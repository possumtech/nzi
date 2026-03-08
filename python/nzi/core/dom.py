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
    def __init__(self, xsd_path, sch_path, debug_mode=False):
        try:
            with open(xsd_path, 'rb') as f:
                self.xsd = etree.XMLSchema(etree.parse(f))
            with open(sch_path, 'rb') as f:
                self.sch = Schematron(etree.parse(f))
        except Exception as e:
            raise RuntimeError(f"Schema Load Error: {str(e)}")

        self.root = etree.Element("session")
        self._active_turn = None
        self._active_content_node = None
        
        # 1. Initialize structural baseline
        self._add_preamble()
        
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
            sys.text = "You are an agent."
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
            # Insert before user
            user = target_turn.find("user")
            if user is not None:
                user.addprevious(hist)
            else:
                target_turn.append(hist)
        
        for el in hist.findall("file"):
            hist.remove(el)
            
        for item in ctx_list:
            f = etree.Element("file")
            f.set("path", item["name"]) # Use 'path' per XSD
            f.set("type", item.get("state", "map"))
            f.set("size", str(item.get("size", "-1")))
            if item.get("content"):
                f.text = item["content"]
            hist.append(f)
        
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
        """Creates a new turn."""
        turn = etree.SubElement(self.root, "turn")
        turn.set("id", str(turn_id))
        
        user = etree.SubElement(turn, "user")
        
        if isinstance(user_data, dict):
            if user_data.get("selection"):
                s = user_data["selection"]
                sel = etree.SubElement(turn, "selection")
                sel.set("file", s.get("file", "unknown"))
                # Note: XSD uses separate row/col attributes, not a range string
                sel.set("first_row", str(s.get("start_line", 1)))
                sel.set("first_col", str(s.get("start_col", 1)))
                sel.set("final_row", str(s.get("end_line", 1)))
                sel.set("final_col", str(s.get("end_col", 1)))
                sel.text = s.get("text", "")
                # Ensure selection is before user interaction choice
                # Handled by choice in XSD
            
            # User must contain a CHOICE of interaction
            instruct = etree.SubElement(user, "instruct")
            instruct.text = user_data.get("instruction", "")
        else:
            instruct = etree.SubElement(user, "instruct")
            instruct.text = str(user_data)
        
        self._active_turn = turn
        # Assistant
        assistant = etree.SubElement(turn, "assistant")
        self._active_content_node = etree.SubElement(assistant, "content")
        self._active_content_node.text = ""
        
        self.validate_strictly()
        return turn

    def append_to_turn(self, text):
        if self._active_content_node is not None:
            curr = self._active_content_node.text or ""
            self._active_content_node.text = curr + text

    def finalize_turn(self, llm_result):
        """
        Zero-Unwrap Fidelity: Direct projection of LLM data into the DOM.
        llm_result: { "content": "...", "reasoning_content": "...", "model": "...", "provider": "..." }
        """
        if self._active_turn is None:
            return

        assistant = self._active_turn.find("assistant")
        if assistant is None: return

        # Remove the temporary streaming node
        if self._active_content_node is not None:
            try:
                assistant.remove(self._active_content_node)
            except ValueError: pass
            self._active_content_node = None

        # 1. Integrate Reasoning (The Gift)
        reasoning = llm_result.get("reasoning_content")
        if reasoning:
            rc_node = etree.SubElement(assistant, "reasoning_content")
            rc_node.text = reasoning

        # 2. Integrate Content (The Protocol + Conversational Body)
        # We domify this directly into a <content> element.
        content_str = llm_result.get("content", "").strip()
        content_node = etree.SubElement(assistant, "content")
        
        try:
            # We parse the content string as an XML fragment to handle mixed content
            # and protocol tags (edit, summary, etc.) without losing filler text.
            # We wrap in a dummy root to parse multiple top-level tags + text.
            parser = etree.XMLParser(recover=True)
            wrapped_content = f"<root>{content_str}</root>"
            fragment = etree.fromstring(wrapped_content, parser=parser)
            
            # UNWRAP REDUNDANT <content> TAGS
            # If the model itself wrapped its response in <content>, we unwrap it
            # to avoid <content><content>...</content></content> which violates XSD.
            actual_content = fragment
            first_child = fragment.find("content")
            if first_child is not None and len(fragment) == 1 and not (fragment.text and fragment.text.strip()):
                actual_content = first_child
            
            # Transfer all text and child nodes to the content_node
            content_node.text = actual_content.text
            for child in actual_content:
                content_node.append(child)
        except Exception as e:
            # Fallback to raw text if parsing fails completely
            logging.error(f"Failed to domify content: {e}")
            content_node.text = content_str

        # 3. Add Metadata
        if llm_result.get("model"):
            m_node = etree.SubElement(assistant, "model")
            m_node.text = llm_result["model"]
        if llm_result.get("provider"):
            p_node = etree.SubElement(assistant, "provider")
            p_node.text = llm_result["provider"]

        self._active_turn = None
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
