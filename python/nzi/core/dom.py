import os
import logging
from lxml import etree
from lxml.isoschematron import Schematron

class ContractViolationError(Exception):
    def __init__(self, message, xml_dump=None):
        super().__init__(message)
        self.xml_dump = xml_dump

class SessionDOM:
    """
    Single Source of Truth (SSOT) for the interaction session.
    Manages the XML tree and enforces schema validation.
    """
    def __init__(self, xsd_path, sch_path, xml_str=None):
        self.xsd_path = xsd_path
        self.sch_path = sch_path
        try:
            with open(xsd_path, 'rb') as f:
                self.xsd = etree.XMLSchema(etree.parse(f))
            with open(sch_path, 'rb') as f:
                self.sch = Schematron(etree.parse(f))
        except Exception as e:
            raise RuntimeError(f"Schema Load Error: {str(e)}")

        if xml_str:
            self.root = etree.fromstring(xml_str)
        else:
            self.root = etree.Element("session")
            self._active_turn = None
            self._active_content_node = None
            # 1. Initialize structural baseline
            self._add_preamble()

        self._active_turn = None
        self._active_content_node = None

        # 2. MANDATORY VALIDATION
        self.validate_strictly()

    def _get_turn_zero(self):
        turn0 = self.root.find("turn[@id='0']")
        if turn0 is None:
            turn0 = etree.Element("turn")
            turn0.set("id", "0")
            self.root.insert(0, turn0)
        return turn0

    def _add_preamble(self):
        """Sets up the Constitution in Turn 0 directly."""
        turn0 = self._get_turn_zero()
        
        if turn0.find("system") is None:
            sys = etree.Element("system")
            sys.text = "You are an assistant."
            turn0.insert(0, sys)
            
        if turn0.find("user") is None:
            user = etree.SubElement(turn0, "user")
            # Create a compliant interact tag
            instruct = etree.SubElement(user, "instruct")
            instruct.text = "Initialization"

    def dump_xml(self):
        return etree.tostring(self.root, encoding='unicode', pretty_print=True)

    def validate_strictly(self):
        """
        Enforces the XSD and Schematron contracts.
        """
        if not self.xsd.validate(self.root):
            errors = "\n".join([f"Line {e.line}: {e.message}" for e in self.xsd.error_log])
            raise ContractViolationError(f"CRITICAL SCHEMA VIOLATION (XSD):\n{errors}", self.dump_xml())
        
        if not self.sch.validate(self.root):
            errors = "Business Rule Violation"
            if self.sch.error_log:
                errors = "\n".join([e.message for e in self.sch.error_log])
            raise ContractViolationError(f"CRITICAL SCHEMA VIOLATION (Schematron):\n{errors}", self.dump_xml())

    def update_context(self, ctx_list, roadmap_content):
        """
        Synchronizes environment state into the history.
        Roadmap goes in Turn 0.
        Files go in <history> in the CURRENT ACTIVE TURN.
        """
        turn0 = self._get_turn_zero()
        
        # 1. Update Roadmap in Turn 0 ONLY
        road = turn0.find("project_roadmap")
        if road is None:
            road = etree.Element("project_roadmap")
            road.set("file", "AGENTS.md")
            # Insert after system if exists
            turn0.insert(1, road)
        
        if roadmap_content:
            road.text = roadmap_content
        elif not road.text:
            road.text = "Roadmap not loaded."

        # 2. Add files to the <history> tag of the CURRENT ACTIVE TURN
        target_turn = self._active_turn if self._active_turn is not None else turn0
        
        hist = target_turn.find("history")
        if hist is None:
            hist = etree.Element("history")
            # Insert before <user> if possible
            user_node = target_turn.find("user")
            if user_node is not None:
                user_node.addprevious(hist)
            else:
                target_turn.append(hist)
        
        for el in hist.findall("files"):
            hist.remove(el)
        
        files_container = etree.SubElement(hist, "files")
            
        for item in ctx_list:
            f = etree.SubElement(files_container, "file")
            path = item.get("path") or item.get("name")
            if not path:
                continue
            f.set("path", path) # Use 'path' per XSD
            f.set("type", item.get("state", "map"))
            f.set("size", str(item.get("size", "-1")))
            if item.get("content"):
                f.text = item["content"]
        
        self.validate_strictly()

    def set_system_prompt(self, content):
        """Updates the constitution in Turn 0."""
        turn0 = self._get_turn_zero()
        sys_node = turn0.find("system")
        if sys_node is None:
            sys_node = etree.Element("system")
            turn0.insert(0, sys_node)
        sys_node.text = content
        self.validate_strictly()

    def start_turn(self, turn_id, user_data, metadata=None):
        """
        Creates a new turn in the Unified Directive model.
        user_data can be:
        - str: Simple instruction
        - dict: { "type": "shell_pass", "command": "...", "content": "...", "mode": "act" }
        """
        turn = etree.SubElement(self.root, "turn")
        turn.set("id", str(turn_id))
        
        user = etree.SubElement(turn, "user")
        
        # 1. Determine Mode (ask/act)
        mode = "act"
        if isinstance(user_data, dict) and user_data.get("mode") == "ask":
            mode = "ask"
        
        mission = etree.SubElement(user, mode)
        
        # 2. Handle Signals/Feedback
        self._project_user_data(mission, user_data)
        
        self._active_turn = turn
        # Assistant
        assistant = etree.SubElement(turn, "assistant")
        self._active_content_node = etree.SubElement(assistant, "content")
        self._active_content_node.text = ""
        
        self.validate_strictly()
        return turn

    def add_turn(self, user_data, assistant_xml=None, metadata=None, turn_id=None):
        """
        Adds a complete turn manually.
        """
        if turn_id is None:
            # Auto-increment
            turns = self.root.findall("turn")
            ids = []
            for t in turns:
                try:
                    ids.append(int(t.get("id", 0)))
                except ValueError: pass
            turn_id = max(ids) + 1 if ids else 1

        turn = etree.SubElement(self.root, "turn")
        turn.set("id", str(turn_id))
        
        user = etree.SubElement(turn, "user")
        mission = etree.SubElement(user, "act")
        self._project_user_data(mission, user_data)
        
        assistant = etree.SubElement(turn, "assistant")
        
        # 1. Enforce <content> wrapper for Assistant part if needed
        # Assistant must have: reasoning_content?, content, model?, provider?
        content_node = etree.SubElement(assistant, "content")

        if assistant_xml:
            if assistant_xml.startswith("<"):
                try:
                    parser = etree.XMLParser(recover=True)
                    # If it's already wrapped in <content>, we might double wrap, 
                    # but finalizing_turn-like logic is better.
                    if assistant_xml.startswith("<content"):
                        # Unwrap and re-wrap or just append
                        fragment = etree.fromstring(assistant_xml, parser=parser)
                        content_node.text = fragment.text
                        for child in fragment:
                            content_node.append(child)
                    else:
                        fragment = etree.fromstring(f"<root>{assistant_xml}</root>", parser=parser)
                        content_node.text = fragment.text
                        for child in fragment:
                            content_node.append(child)
                except:
                    content_node.text = assistant_xml
            else:
                content_node.text = assistant_xml
        
        self.validate_strictly()
        return turn

    def _project_user_data(self, mission_node, user_data):
        boilerplates = {
            "run:pass": "Command completed successfully. Proceed.",
            "run:fail": "Command error. Diagnose and resolve.",
            "test:pass": "Test passed. Proceed.",
            "test:fail": "Test failed. Diagnose and resolve.",
            "env:pass": "Environment discovery command results.",
            "env:fail": "Environment discovery command failed.",
            "answer": "Your answer to a previous prompt_user."
        }

        if isinstance(user_data, dict) and "type" in user_data:
            s_type = user_data["type"]
            s_status = user_data.get("status", "pass")
            
            # Normalization: handle "run_pass" -> type="run", status="pass"
            if "_" in s_type and s_type.split("_")[1] in ["pass", "fail"]:
                parts = s_type.split("_")
                s_type = parts[0]
                s_status = parts[1]

            sel = etree.SubElement(mission_node, "selection")
            sel.set("type", s_type)
            sel.set("status", s_status)
            
            if user_data.get("command"):
                sel.set("command", user_data["command"])
            if user_data.get("file"):
                sel.set("file", user_data["file"])
            
            sel.text = user_data.get("content", "")
            
            # Append boilerplate
            signal_key = f"{s_type}:{s_status}" if s_type != "answer" else "answer"
            instruct_text = user_data.get("instruction") or boilerplates.get(signal_key, "Proceed.")
            sel.tail = "\n" + instruct_text
        elif isinstance(user_data, dict) and "selection" in user_data:
            # Traditional selection (from UI)
            s = user_data["selection"]
            sel = etree.SubElement(mission_node, "selection")
            sel.set("file", s.get("file", "unknown"))
            sel.set("first_row", str(s.get("start_line", 1)))
            sel.set("first_col", str(s.get("start_col", 1)))
            sel.set("final_row", str(s.get("end_line", 1)))
            sel.set("final_col", str(s.get("end_col", 1)))
            sel.text = s.get("text", "")
            sel.tail = "\n" + (user_data.get("instruction") or "")
        else:
            # Simple text instruction
            if isinstance(user_data, dict):
                mission_node.text = user_data.get("instruction", str(user_data))
            else:
                mission_node.text = str(user_data)

    def append_to_turn(self, text):
        if self._active_content_node is not None:
            curr = self._active_content_node.text or ""
            self._active_content_node.text = curr + text

    def finalize_turn(self, llm_result):
        """
        Zero-Unwrap Fidelity: Direct projection of LLM data into the DOM.
        Ensures strict XSD sequence: reasoning_content?, content, model?, provider?
        """
        if self._active_turn is None:
            return

        assistant = self._active_turn.find("assistant")
        if assistant is None:
            assistant = etree.SubElement(self._active_turn, "assistant")

        # Remove the temporary streaming node BEFORE validation
        if self._active_content_node is not None:
            try:
                assistant.remove(self._active_content_node)
            except ValueError: pass
            self._active_content_node = None

        def get_insertion_point(parent, before_tags):
            # Finds the first existing tag from before_tags to insert before, or returns None.
            for tag in before_tags:
                node = parent.find(tag)
                if node is not None:
                    return node
            return None

        # 1. Integrate Reasoning (The Gift)
        reasoning = llm_result.get("reasoning_content")
        if reasoning:
            rc_node = assistant.find("reasoning_content")
            if rc_node is None:
                rc_node = etree.Element("reasoning_content")
                # Insert before everything
                point = get_insertion_point(assistant, ["content", "model", "provider"])
                if point is not None:
                    point.addprevious(rc_node)
                else:
                    assistant.append(rc_node)
            rc_node.text = reasoning

        # 2. Integrate Content (The Protocol + Conversational Body)
        content_str = llm_result.get("content", "").strip()
        content_node = assistant.find("content")
        if content_node is None:
            content_node = etree.Element("content")
            # Insert before metadata
            point = get_insertion_point(assistant, ["model", "provider"])
            if point is not None:
                point.addprevious(content_node)
            else:
                assistant.append(content_node)
        
        # Clear any existing content
        content_node.text = None
        for child in list(content_node):
            content_node.remove(child)

        try:
            parser = etree.XMLParser(recover=True)
            wrapped_content = f"<root>{content_str}</root>"
            fragment = etree.fromstring(wrapped_content, parser=parser)
            
            # UNWRAP NESTED <content> (De-slop)
            # If we find a <content> tag anywhere inside, and it seems redundant
            # (e.g. the model is trying to use it as a tool), we unwrap it.
            nested_content = fragment.find(".//content")
            if nested_content is not None:
                # If there's a nested content, we take its content and append it
                # to any existing text in fragment.
                if fragment.text:
                    fragment.text = fragment.text.strip() + "\n" + (nested_content.text or "")
                else:
                    fragment.text = nested_content.text
                
                for child in nested_content:
                    fragment.append(child)
                fragment.remove(nested_content)
            
            content_node.text = fragment.text
            for child in fragment:
                content_node.append(child)
        except Exception as e:
            logging.error(f"Failed to domify content: {e}")
            content_node.text = content_str

        # 3. Add Metadata
        if llm_result.get("model"):
            m_node = assistant.find("model")
            if m_node is None:
                m_node = etree.Element("model")
                point = get_insertion_point(assistant, ["provider"])
                if point is not None:
                    point.addprevious(m_node)
                else:
                    assistant.append(m_node)
            m_node.text = llm_result["model"]

        if llm_result.get("provider"):
            p_node = assistant.find("provider")
            if p_node is None:
                p_node = etree.SubElement(assistant, "provider")
            p_node.text = llm_result["provider"]

        self._active_turn = None
        self.validate_strictly()

    def delete_after(self, turn_id):
        """Removes the turn with the given ID and all subsequent turns."""
        turns = self.root.xpath(f"//turn[@id >= {turn_id}]")
        for t in turns:
            self.root.remove(t)
        self.validate_strictly()

    def xpath(self, expression):
        results = self.root.xpath(expression)
        if not isinstance(results, list):
            results = [results]
        output = []
        for r in results:
            if isinstance(r, etree._Element):
                output.append(etree.tostring(r, encoding='unicode', with_tail=False).strip())
            else:
                output.append(str(r).strip())
        return output

    def clear(self):
        self.root = etree.Element("session")
        self._active_turn = None
        self._active_content_node = None
        self._add_preamble()
        self.validate_strictly()
