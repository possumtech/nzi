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
            # No 'model' attribute on Turn itself according to refined theory
            self.root.insert(0, turn0)
        return turn0

    def _get_agent_envelope(self, turn):
        agent = turn.find("agent")
        if agent is None:
            agent = etree.SubElement(turn, "agent")
        return agent

    def _add_preamble(self):
        """Sets up the Constitution in Turn 0/Agent only."""
        turn0 = self._get_turn_zero()
        agent = self._get_agent_envelope(turn0)
        
        if agent.find("system") is None:
            sys = etree.Element("system")
            sys.text = "You are an agent."
            # Ensure it's the first child
            agent.insert(0, sys)
            
        if turn0.find("agent/user") is None:
            user = etree.SubElement(agent, "user")
            user.text = "Initialization"

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
        Roadmap goes in Turn 0/Agent.
        Files go in <agent/history> in EVERY turn.
        """
        turn0 = self._get_turn_zero()
        agent0 = self._get_agent_envelope(turn0)
        
        # 1. Update Roadmap in Turn 0 ONLY
        road = agent0.find("project_roadmap")
        if road is None:
            road = etree.Element("project_roadmap")
            road.set("file", "AGENTS.md")
            # Insert after system if exists
            agent0.insert(1, road)
        
        if roadmap_content:
            road.text = roadmap_content
        elif not road.text:
            road.text = "Roadmap not loaded."

        # 2. Add files to the <history> tag of the CURRENT ACTIVE TURN
        target_turn = self._active_turn if self._active_turn is not None else turn0
        agent = self._get_agent_envelope(target_turn)
        
        hist = agent.find("history")
        if hist is None:
            hist = etree.Element("history")
            # Insert before user
            user = agent.find("user")
            if user is not None:
                user.addprevious(hist)
            else:
                agent.append(hist)
        
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
        """Updates the constitution in Turn 0/Agent."""
        turn0 = self._get_turn_zero()
        agent = self._get_agent_envelope(turn0)
        sys_node = agent.find("system")
        if sys_node is None:
            sys_node = etree.Element("system")
            agent.insert(0, sys_node)
        sys_node.text = content
        self.validate_strictly()

    def start_turn(self, turn_id, user_data, metadata=None):
        """Creates a new turn with agent and assistant envelopes."""
        turn = etree.SubElement(self.root, "turn")
        turn.set("id", str(turn_id))
        
        agent = etree.SubElement(turn, "agent")
        user = etree.SubElement(agent, "user")
        
        if isinstance(user_data, dict):
            if user_data.get("selection"):
                s = user_data["selection"]
                sel = etree.SubElement(agent, "selection")
                sel.set("file", s.get("file", "unknown"))
                sel.set("range", f"{s.get('start_line', 0)}:{s.get('start_col', 0)}-{s.get('end_line', 0)}:{s.get('end_col', 0)}")
                sel.text = s.get("text", "")
                # Ensure selection is before user
                user.addprevious(sel)
            
            user.text = user_data.get("instruction", "")
        else:
            user.text = str(user_data)
        
        self._active_turn = turn
        # Pre-create assistant and content node for streaming
        assistant = etree.SubElement(turn, "assistant")
        assistant.set("model", (metadata or {}).get("model", "unknown"))
        self._active_content_node = etree.SubElement(assistant, "content")
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

        assistant = self._active_turn.find("assistant")
        if assistant is None: return

        # Remove the temporary streaming node
        if self._active_content_node is not None:
            assistant.remove(self._active_content_node)
            self._active_content_node = None

        try:
            if "<" in full_assistant_content and ">" in full_assistant_content:
                frag_xml = f'<root>{full_assistant_content}</root>'
                frag = etree.fromstring(frag_xml)
                for child in frag:
                    assistant.append(child)
            else:
                content_node = etree.SubElement(assistant, "content")
                content_node.text = full_assistant_content
        except Exception:
            content_node = etree.SubElement(assistant, "content")
            content_node.text = full_assistant_content

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
