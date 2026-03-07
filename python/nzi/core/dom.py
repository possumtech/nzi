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
    VIOLATING THE SCHEMA IS A SHOW-STOPPER.
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
            turn0.set("model", "system")
            # Turn 0 is the start of history
            self.root.insert(0, turn0)
        return turn0

    def _add_preamble(self):
        """Sets up the Constitution and Roadmap in Turn 0 only."""
        turn0 = self._get_turn_zero()
        
        if turn0.find("system") is None:
            sys = etree.SubElement(turn0, "system")
            sys.text = "You are an agent."
            
        if turn0.find("project_roadmap") is None:
            road = etree.SubElement(turn0, "project_roadmap")
            road.set("file", "AGENTS.md")
            road.text = "Initializing roadmap..."

    def dump_xml(self):
        return etree.tostring(self.root, encoding='unicode', pretty_print=True)

    def validate_strictly(self):
        """
        Enforces the XSD and Schematron contracts.
        Failure here stops the program.
        """
        # 1. XSD Validation
        if not self.xsd.validate(self.root):
            errors = "\n".join([f"Line {e.line}: {e.message}" for e in self.xsd.error_log])
            raise ContractViolationError(f"CRITICAL SCHEMA VIOLATION (XSD):\n{errors}", self.dump_xml())
        
        # 2. Schematron Validation
        if not self.sch.validate(self.root):
            errors = "Business Rule Violation"
            if self.sch.error_log:
                errors = "\n".join([e.message for e in self.sch.error_log])
            raise ContractViolationError(f"CRITICAL SCHEMA VIOLATION (Schematron):\n{errors}", self.dump_xml())

    def update_context(self, ctx_list, roadmap_content):
        """
        Synchronizes environment state into the history.
        Roadmap goes in Turn 0 ONLY.
        Files go in a <history> tag in EVERY turn.
        """
        turn0 = self._get_turn_zero()
        
        # 1. Update Roadmap in Turn 0 ONLY
        road = turn0.find("project_roadmap")
        if roadmap_content:
            road.text = roadmap_content

        # 2. Add files to the <history> tag of the CURRENT ACTIVE TURN
        target_turn = self._active_turn if self._active_turn is not None else turn0
        
        hist = target_turn.find("history")
        if hist is None:
            hist = etree.Element("history")
            target_turn.append(hist)
        
        # Purge existing files in the history tag to avoid duplicates on re-sync
        for el in hist.findall("file"):
            hist.remove(el)
            
        for item in ctx_list:
            f = etree.Element("file")
            f.set("name", item["name"])
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
            sys_node = etree.SubElement(turn0, "system")
        sys_node.text = content
        self.validate_strictly()

    def start_turn(self, turn_id, user_data, metadata=None):
        """Creates a new turn."""
        turn = etree.SubElement(self.root, "turn")
        turn.set("id", str(turn_id))
        turn.set("model", (metadata or {}).get("model", "unknown"))
        
        user = etree.SubElement(turn, "user")
        
        if isinstance(user_data, dict):
            # Complex user data with potential selection
            if user_data.get("selection"):
                s = user_data["selection"]
                sel = etree.SubElement(user, "selection")
                sel.set("file", s.get("file", "unknown"))
                sel.set("start", f"{s.get('start_line', 0)}:{s.get('start_col', 0)}")
                sel.set("end", f"{s.get('end_line', 0)}:{s.get('end_col', 0)}")
                # Metadata is in attributes, text is the content
                sel.text = s.get("text", "")
            
            user.text = user_data.get("instruction", "")
        else:
            user.text = str(user_data)
        
        self._active_turn = turn
        # Pre-create content node for streaming
        self._active_content_node = etree.SubElement(turn, "content")
        self._active_content_node.text = ""
        
        self.validate_strictly()
        return turn

    def append_to_turn(self, text):
        if self._active_content_node is not None:
            curr = self._active_content_node.text or ""
            self._active_content_node.text = curr + text

    def finalize_turn(self, full_assistant_content):
        if self._active_turn is None:
            return

        if self._active_content_node is not None:
            self._active_turn.remove(self._active_content_node)
            self._active_content_node = None

        try:
            if "<" in full_assistant_content and ">" in full_assistant_content:
                frag_xml = f'<root>{full_assistant_content}</root>'
                frag = etree.fromstring(frag_xml)
                for child in frag:
                    self._active_turn.append(child)
            else:
                content_node = etree.SubElement(self._active_turn, "content")
                content_node.text = full_assistant_content
        except Exception:
            content_node = etree.SubElement(self._active_turn, "content")
            content_node.text = full_assistant_content

        self._active_turn = None
        self.validate_strictly()

    def add_turn(self, turn_id, user_data, assistant_content=None, metadata=None):
        self.start_turn(turn_id, user_data, metadata)
        self.finalize_turn(assistant_content or "")

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
