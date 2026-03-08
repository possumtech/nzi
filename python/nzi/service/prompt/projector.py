import html
from lxml import etree

def project_dom_to_messages(dom, system_prompt_raw=None):
    """
    Projects the XML DOM state into an array of LLM messages.
    Follows history-based model:
    - system from Turn 0 -> role: system
    - everything else in Turn 0 (roadmap, history, mission) -> role: user (Primordial)
    - everything else -> sequential user/assistant roles
    """
    messages = []
    
    turns = dom.root.findall("turn")
    for t in turns:
        tid = t.get("id")
        
        # 1. Handle Turn 0 (Primordial)
        if tid == "0":
            # A. System Constitution -> role: system
            sys_node = t.find("system")
            sys_content = ""
            if sys_node is not None and sys_node.text:
                sys_content = sys_node.text
            else:
                sys_content = "You are an assistant."
            
            messages.append({"role": "system", "content": sys_content})

            # B. Everything else in Turn 0 -> role: user (First Prompt)
            primordial_nodes = list(t)
            primordial_text = ""
            
            # Context First (History and Roadmap)
            for child in primordial_nodes:
                if child.tag == "history":
                    parts = []
                    for f in child.xpath(".//file"):
                        pf = etree.Element("file")
                        pf.set("name", f.get("name") or f.get("path"))
                        pf.set("type", f.get("type"))
                        pf.text = f.text
                        parts.append(etree.tostring(pf, encoding='unicode').strip())
                    if parts:
                        primordial_text += "INITIAL_CONTEXT:\n" + "\n".join(parts) + "\n\n"
                elif child.tag == "project_roadmap":
                    primordial_text += f"PROJECT_ROADMAP:\n{etree.tostring(child, encoding='unicode').strip()}\n\n"

            # Mission Second
            for child in primordial_nodes:
                if child.tag in ["system", "history", "project_roadmap", "assistant"]: 
                    continue
                
                if child.tag == "user":
                    for mission in child:
                        # Selections then instructions
                        for sel in mission.findall("selection"):
                            primordial_text += etree.tostring(sel, encoding='unicode').strip() + "\n"
                        if mission.text:
                            primordial_text += mission.text.strip() + "\n"
                else:
                    # In the new structure, history might be here if it's not handled above
                    # but we already handled history, roadmap and system.
                    primordial_text += f"{etree.tostring(child, encoding='unicode').strip()}\n"
            
            if primordial_text.strip():
                messages.append({"role": "user", "content": primordial_text.strip()})
            
            # Assistant part of Turn 0
            asst_node = t.find("assistant")
            if asst_node is not None:
                asst_parts = []
                content_node = asst_node.find("content")
                if content_node is not None:
                    if content_node.text:
                        asst_parts.append(content_node.text.strip())
                    for sc in content_node:
                        asst_parts.append(etree.tostring(sc, encoding='unicode', with_tail=True).strip())
                if asst_parts:
                    messages.append({"role": "assistant", "content": "\n".join(asst_parts)})
            
            continue

        # 2. Subsequent Turns (N > 0)
        user_node = t.find("user")
        user_text = ""
        
        # A. Context First (Inside Turn)
        history_node = t.find("history")
        if history_node is not None:
            parts = []
            for f in history_node.xpath(".//file"):
                pf = etree.Element("file")
                pf.set("name", f.get("name") or f.get("path"))
                pf.set("type", f.get("type"))
                pf.text = f.text
                parts.append(etree.tostring(pf, encoding='unicode').strip())
            if parts:
                user_text += "CONTEXT:\n" + "\n".join(parts) + "\n\n"
        
        if user_node is not None:
            # B. Directive Second (Selection then Instruction)
            for mission in user_node:
                for sel in mission.findall("selection"):
                    user_text += etree.tostring(sel, encoding='unicode').strip() + "\n"
                if mission.text:
                    user_text += mission.text.strip() + "\n"
        
        if user_text.strip():
            messages.append({"role": "user", "content": user_text.strip()})

        assistant_node = t.find("assistant")
        if assistant_node is not None:
            asst_parts = []
            content_node = assistant_node.find("content")
            if content_node is not None:
                if content_node.text:
                    asst_parts.append(content_node.text.strip())
                for sc in content_node:
                    asst_parts.append(etree.tostring(sc, encoding='unicode', with_tail=True).strip())
            
            if asst_parts:
                messages.append({"role": "assistant", "content": "\n".join(asst_parts)})
            
    return messages
