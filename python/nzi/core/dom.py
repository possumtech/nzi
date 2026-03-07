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
        self.debug_mode = debug_mode
        try:
            with open(xsd_path, 'rb') as f:
                self.xsd = etree.XMLSchema(etree.parse(f))
            with open(sch_path, 'rb') as f:
                self.sch = Schematron(etree.parse(f))
        except Exception as e:
            raise RuntimeError(f"Init Error: {str(e)}")

        self.root = etree.Element("session")
        self._active_turn = None
        self._active_content_node = None
        self._add_preamble()
        
        if self.debug_mode: self.validate_strictly()

    def _add_preamble(self):
        # 1. System Prompt (Constitution)
        sys = etree.SubElement(self.root, "system")
        sys.text = "Initializing..."
        # 2. Roadmap
        road = etree.SubElement(self.root, "project_roadmap")
        road.set("file", "AGENTS.md")

    def dump_xml(self):
        return etree.tostring(self.root, encoding='unicode', pretty_print=True)

    def validate_strictly(self):
        # 1. XSD Validation
        if not self.xsd.validate(self.root):
            errors = "\n".join([f"Line {e.line}: {e.message}" for e in self.xsd.error_log])
            raise ContractViolationError(f"XSD Violation: {errors}", self.dump_xml())
        
        # 2. Schematron Validation
        if not self.sch.validate(self.root):
            errors = "Business Rule Violation"
            if self.sch.error_log:
                errors = "\n".join([e.message for e in self.sch.error_log])
            raise ContractViolationError(f"Schematron Violation: {errors}", self.dump_xml())

    def update_context(self, ctx_list, roadmap_content):
        # Purge existing files
        for el in self.root.findall("file"):
            self.root.remove(el)
        
        # Update Roadmap
        road = self.root.find("project_roadmap")
        if road is None:
            road = etree.SubElement(self.root, "project_roadmap")
        
        if roadmap_content:
            road.set("file", self.root.get("roadmap", "AGENTS.md"))
            road.text = roadmap_content
            
        insertion_point = self.root.find("turn")
        
        for item in ctx_list:
            f = etree.Element("file")
            f.set("name", item["name"])
            f.set("type", item["state"])
            if item.get("content"):
                f.text = item["content"]
            
            if insertion_point is not None:
                insertion_point.addprevious(f)
            else:
                self.root.append(f)

    def set_system_prompt(self, content):
        sys_node = self.root.find("system")
        if sys_node is None:
            sys_node = etree.SubElement(self.root, "system")
        sys_node.text = content

    def start_turn(self, turn_id, user_data, metadata=None):
        """Creates a new turn and prepares it for streaming output."""
        turn = etree.SubElement(self.root, "turn")
        turn.set("id", str(turn_id))
        turn.set("model", (metadata or {}).get("model", "unknown"))
        
        user = etree.SubElement(turn, "user")

        if isinstance(user_data, dict):
            if user_data.get("selection"):
                s = user_data["selection"]
                sel = etree.SubElement(user, "selection")
                sel.set("file", s.get("file", "unknown"))
                sel.set("start", f"{s.get('start_line', 0)}:{s.get('start_col', 0)}")
                sel.set("end", f"{s.get('end_line', 0)}:{s.get('end_col', 0)}")
                sel.text = s.get("text", "")
            instr_text = user_data.get("instruction", "")
        else:
            instr_text = str(user_data)

        user.text = instr_text
        
        self._active_turn = turn
        # Pre-create content node for streaming
        self._active_content_node = etree.SubElement(turn, "content")
        self._active_content_node.text = ""
        return turn

    def append_to_turn(self, text):
        """Appends streaming text to the active turn's content node."""
        if self._active_content_node is not None:
            curr = self._active_content_node.text or ""
            self._active_content_node.text = curr + text

    def finalize_turn(self, full_assistant_content):
        """Replaces the temporary streaming node with the final parsed structure."""
        if self._active_turn is None:
            return

        # Remove the temporary streaming node
        if self._active_content_node is not None:
            self._active_turn.remove(self._active_content_node)
            self._active_content_node = None

        # Parse and append the final content (which may contain multiple tags)
        try:
            if "<" in full_assistant_content and ">" in full_assistant_content:
                # Wrap in root to handle multiple siblings
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
        if self.debug_mode: self.validate_strictly()

    def add_turn(self, turn_id, user_data, assistant_content=None, metadata=None):
        """Legacy helper for non-streaming turn addition."""
        self.start_turn(turn_id, user_data, metadata)
        if assistant_content:
            self.finalize_turn(assistant_content)
        else:
            self._active_turn = None
            self._active_content_node = None

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
        for el in self.root.findall("turn"):
            self.root.remove(el)
        for el in self.root.findall("file"):
            self.root.remove(el)
        road = self.root.find("project_roadmap")
        if road is not None: road.text = ""
        self._active_turn = None
        self._active_content_node = None
