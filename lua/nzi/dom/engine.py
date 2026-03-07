#!/usr/bin/env python3
import sys
import json
import os
from lxml import etree
from lxml.isoschematron import Schematron

NS = {"nzi": "nzi", "agent": "nzi", "model": "nzi"}
NS_MAP = {None: "nzi", "nzi": "nzi", "agent": "nzi", "model": "nzi"}

class ContractViolationError(Exception):
    def __init__(self, message, xml_dump=None):
        super().__init__(message)
        self.xml_dump = xml_dump

class SessionDOM:
    def __init__(self, xsd_path, sch_path, debug_mode=False):
        self.xsd_path = xsd_path
        self.sch_path = sch_path
        self.debug_mode = debug_mode
        self.xsd = etree.XMLSchema(etree.parse(xsd_path))
        with open(sch_path, 'rb') as f:
            self.sch = Schematron(etree.parse(f))
            
        self.root = etree.Element("{nzi}session", nsmap=NS_MAP)
        self.root.set("model", "unknown")
        self.root.set("yolo", "false")
        self.root.set("roadmap", "AGENTS.md")
        
        # Turn 0 is the Preamble and also the container for global workspace state (context)
        self._add_preamble()
        
        if self.debug_mode: self.validate_strictly()

    def _add_preamble(self):
        # 1. System Prompt (Constitution)
        sys = etree.SubElement(self.root, "{nzi}system", nsmap=NS_MAP)
        sys.text = ""
        # 2. Roadmap
        etree.SubElement(self.root, "{nzi}project_roadmap", nsmap=NS_MAP)

    def _dump_xml(self):
        return etree.tostring(self.root, encoding='unicode', pretty_print=True)

    def validate_strictly(self):
        if not self.xsd.validate(self.root):
            error = self.xsd.error_log.last_error
            raise ContractViolationError(f"XSD Violation: {error.message}", self._dump_xml())
        if not self.sch.validate(self.root):
            raise ContractViolationError("Schematron Business Rule Violation", self._dump_xml())

    def guard(func):
        def wrapper(self, *args, **kwargs):
            try:
                result = func(self, *args, **kwargs)
                if self.debug_mode: self.validate_strictly()
                return result
            except ContractViolationError: raise
            except Exception as e:
                raise ContractViolationError(f"Logic Error in {func.__name__}: {str(e)}", self._dump_xml())
        return wrapper

    @guard
    def set_global_attr(self, key, value):
        self.root.set(key, str(value).lower() if isinstance(value, bool) else str(value))

    @guard
    def add_turn(self, turn_id, user_data, assistant_content=None, metadata=None):
        turn = etree.SubElement(self.root, "{nzi}turn", nsmap=NS_MAP)
        turn.set("id", str(turn_id))
        turn.set("model", (metadata or {}).get("model", "unknown"))
        turn.set("duration", str((metadata or {}).get("duration", 0)))
        turn.set("acts", str((metadata or {}).get("changes", 0)))

        user = etree.SubElement(turn, "{nzi}user", nsmap=NS_MAP)

        if isinstance(user_data, dict):
            if user_data.get("selection"):
                s = user_data["selection"]
                sel = etree.SubElement(user, "{nzi}selection", nsmap=NS_MAP)
                sel.set("file", s.get("file", "unknown"))
                sel.set("start", f"{s.get('start_line', 0)}:{s.get('start_col', 0)}")
                sel.set("end", f"{s.get('end_line', 0)}:{s.get('end_col', 0)}")
                sel.text = s.get("text", "")

            instr_text = user_data.get("instruction", "")
            if user_data.get("roadmap_hint"):
                hint = etree.SubElement(user, "{nzi}next_task_suggest", nsmap=NS_MAP)
                hint.set("file", self.root.get("roadmap", "AGENTS.md"))
                hint.text = user_data["roadmap_hint"]
        else:
            instr_text = str(user_data)

        # Add line numbers to instruction text for better model reasoning
        # But ONLY if it's not already XML tags (like <agent:status>)
        if not (instr_text.strip().startswith("<") and instr_text.strip().endswith(">")):
            lines = instr_text.split("\n")
            numbered_lines = []
            for i, line in enumerate(lines):
                if not line.strip().startswith(f"{i+1}:"):
                    numbered_lines.append(f"{i+1}: {line}")
                else:
                    numbered_lines.append(line)
            instr_text = "\n".join(numbered_lines)

        if user.text:
            user.text += f"\nInstruction: {instr_text}"
        else:
            # If instr_text is XML, parse it into the user node
            if instr_text.strip().startswith("<") and instr_text.strip().endswith(">"):
                try:
                    frag_xml = f'<root xmlns:agent="nzi" xmlns:model="nzi">{instr_text}</root>'
                    frag = etree.fromstring(frag_xml)
                    for child in frag:
                        user.append(child)
                except Exception:
                    user.text = instr_text
            else:
                user.text = instr_text

        if assistant_content:

            try:
                frag_xml = f'<root xmlns:agent="nzi" xmlns:model="nzi">{assistant_content}</root>'
                frag = etree.fromstring(frag_xml)
                for child in frag:
                    turn.append(child)
            except Exception:
                content_node = turn.find("{nzi}content", namespaces=NS)
                if content_node is None:
                    content_node = etree.SubElement(turn, "{nzi}content", nsmap=NS_MAP)
                content_node.text = (content_node.text or "") + assistant_content

    @guard
    def update_context(self, ctx_list, roadmap_content):
        """
        Workspace state is stored at the root.
        """
        # Purge existing files
        for el in self.root.findall("{nzi}file", namespaces=NS):
            self.root.remove(el)
        
        # Update Roadmap
        road = self.root.find("{nzi}project_roadmap", namespaces=NS)
        if road is None:
            road = etree.SubElement(self.root, "{nzi}project_roadmap", nsmap=NS_MAP)
        
        if roadmap_content:
            road.set("file", self.root.get("roadmap", "AGENTS.md"))
            road.text = roadmap_content
            
        # Add Files
        # We insert before the first turn to keep the DOM organized: Knowledge then History
        insertion_point = self.root.find("{nzi}turn", namespaces=NS)
        
        for item in ctx_list:
            f = etree.Element("{nzi}file", nsmap=NS_MAP)
            f.set("name", item["name"])
            f.set("type", item["state"])
            if item.get("content"):
                f.text = item["content"]
            
            if insertion_point is not None:
                insertion_point.addprevious(f)
            else:
                self.root.append(f)

    @guard
    def set_system_prompt(self, content):
        """
        Rules of behavior are stored in the <system> tag at root.
        """
        sys_node = self.root.find("{nzi}system", namespaces=NS)
        if sys_node is None:
            sys_node = etree.SubElement(self.root, "{nzi}system", nsmap=NS_MAP)
        sys_node.text = content

    def build_messages(self, system_prompt_raw=None):
        """
        Projects the DOM state into the LLM message array.
        """
        messages = []
        
        # 1. System Prompt
        sys_node = self.root.find("{nzi}system", namespaces=NS)
        sys_content = sys_node.text if sys_node is not None else None
        
        if not sys_content and system_prompt_raw:
            sys_content = system_prompt_raw
            
        if sys_content:
            messages.append({"role": "system", "content": sys_content})
        
        # 2. Workspace Context (Roadmap + Files)
        env_parts = []
        road = self.root.find("{nzi}project_roadmap", namespaces=NS)
        if road is not None and road.text:
            env_parts.append(etree.tostring(road, encoding='unicode').strip())
            
        files = self.root.findall("{nzi}file", namespaces=NS)
        for f in files:
            env_parts.append(etree.tostring(f, encoding='unicode').strip())
            
        if env_parts:
            messages.append({"role": "system", "content": "WORKSPACE CONTEXT:\n" + "\n".join(env_parts)})
            
        # 3. History
        turns = self.root.findall("{nzi}turn", namespaces=NS)
        for t in turns:
            user_node = t.find("{nzi}user", namespaces=NS)
            if user_node is not None:
                # We send the full XML of the user node to preserve structural tags
                u_xml = etree.tostring(user_node, encoding='unicode').strip()
                messages.append({"role": "user", "content": u_xml})
            
            asst_parts = []
            for child in t:
                if child.tag != "{nzi}user":
                    asst_parts.append(etree.tostring(child, encoding='unicode').strip())
            if asst_parts:
                messages.append({"role": "assistant", "content": "\n".join(asst_parts)})
                
        return messages

    def xpath(self, expression):
        results = self.root.xpath(expression, namespaces=NS)
        output = []
        for r in results:
            if isinstance(r, etree._Element):
                output.append(etree.tostring(r, encoding='unicode', with_tail=False).strip())
            else:
                output.append(str(r).strip())
        return output

    def get_full_xml(self):
        return self._dump_xml()

    @guard
    def clear(self):
        # Preserve Preamble (System/Roadmap) but clear History (Turns) and Files
        for el in self.root.findall("{nzi}turn", namespaces=NS):
            self.root.remove(el)
        for el in self.root.findall("{nzi}file", namespaces=NS):
            self.root.remove(el)
        
        # Reset roadmap text
        road = self.root.find("{nzi}project_roadmap", namespaces=NS)
        if road is not None: road.text = ""

def main():
    base_dir = os.getcwd()
    xsd_path = os.path.join(base_dir, "nzi.xsd")
    sch_path = os.path.join(base_dir, "nzi.sch")
    debug_mode = os.environ.get("NZI_DEBUG") == "1"
    
    try:
        dom = SessionDOM(xsd_path, sch_path, debug_mode=debug_mode)
    except Exception as e:
        print(json.dumps({"success": False, "error": f"Init Error: {str(e)}"}))
        sys.exit(1)

    for line in sys.stdin:
        try:
            line_strip = line.strip()
            if not line_strip: continue
            req = json.loads(line_strip)
            m = req.get("method")
            p = req.get("params", {})
            if isinstance(p, list) and not p:
                p = {}
            rid = req.get("id")

            if m == "add_turn":
                dom.add_turn(p["id"], p["user_data"], p.get("assistant"), p.get("metadata"))
                res = {"success": True}
            elif m == "update_context":
                dom.update_context(p["ctx_list"], p.get("roadmap_content"))
                res = {"success": True}
            elif m == "build_messages":
                msgs = dom.build_messages(p.get("system_prompt"))
                res = {"success": True, "messages": msgs}
            elif m == "xpath":
                res = {"success": True, "results": dom.xpath(p["query"])}
            elif m == "format":
                res = {"success": True, "xml": dom.get_full_xml()}
            elif m == "clear":
                dom.clear()
                res = {"success": True}
            elif m == "set_system_prompt":
                dom.set_system_prompt(p["content"])
                res = {"success": True}
            elif m == "set_attr":
                dom.set_global_attr(p["key"], p["value"])
                res = {"success": True}
            else:
                res = {"success": False, "error": f"Unknown: {m}"}

            res["id"] = rid
            print(json.dumps(res), flush=True)

        except ContractViolationError as e:
            print(json.dumps({"success": False, "error": str(e), "xml_dump": e.xml_dump, "id": rid}), flush=True)
        except Exception as e:
            print(json.dumps({"success": False, "error": f"Internal Error: {str(e)}", "id": rid}), flush=True)

if __name__ == "__main__": main()
