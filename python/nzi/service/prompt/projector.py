import html
from lxml import etree

def project_dom_to_messages(dom, system_prompt_raw=None):
    """
    Projects the XML DOM state into an array of LLM messages.
    Follows history-based model:
    - system from Turn 0 -> role: system
    - everything else in Turn 0 (roadmap, history, user) -> role: user (Primordial)
    - everything else -> sequential user/assistant roles
    """
    messages = []
    
    turns = dom.root.findall("turn")
    for t in turns:
        tid = t.get("id")
        
        # 1. Handle Turn 0 (Primordial)
        if tid == "0":
            # A. System Constitution -> role: system
            # Check for system directly under turn OR under agent
            sys_node = t.find("system") or t.find("agent/system")
            sys_content = ""
            if sys_node is not None and sys_node.text:
                sys_content = html.unescape(sys_node.text)
            else:
                sys_content = "You are an agent."
            
            messages.append({"role": "system", "content": sys_content})

            # B. Everything else in Turn 0 -> role: user (First Prompt)
            # We look for children directly under turn or under agent
            primordial_nodes = []
            agent_node = t.find("agent")
            if agent_node is not None:
                primordial_nodes.extend(list(agent_node))
            
            # Also add direct children of turn that aren't system or agent
            for child in t:
                if child.tag not in ["system", "agent", "assistant"]:
                    primordial_nodes.append(child)
            
            primordial_text = ""
            for child in primordial_nodes:
                if child.tag == "system": continue
                
                if child.tag == "user":
                    # For user tags, we want their inner interaction content (ask, instruct, etc.)
                    # If it has children (like <ask>), tounicode them.
                    if len(child):
                        for subchild in child:
                            primordial_text += etree.tostring(subchild, encoding='unicode').strip() + "\n"
                    else:
                        primordial_text += (child.text or "") + "\n"
                elif child.tag == "project_roadmap":
                    primordial_text += f"\n\nPROJECT_ROADMAP:\n{etree.tostring(child, encoding='unicode').strip()}"
                elif child.tag == "history":
                    parts = []
                    for f in child.findall("file"):
                        pf = etree.Element("file")
                        pf.set("name", f.get("name") or f.get("path"))
                        pf.set("type", f.get("type"))
                        pf.text = f.text
                        parts.append(etree.tostring(pf, encoding='unicode').strip())
                    if parts:
                        primordial_text += "\n\nINITIAL_CONTEXT:\n" + "\n".join(parts)
                else:
                    primordial_text += f"\n\n{etree.tostring(child, encoding='unicode').strip()}"
            
            if primordial_text.strip():
                messages.append({"role": "user", "content": primordial_text.strip()})
            
            # Assistant part of Turn 0
            asst_node = t.find("assistant")
            if asst_node is not None:
                asst_parts = []
                for child in asst_node:
                    content = etree.tostring(child, encoding='unicode', with_tail=False).strip()
                    if content != "<content/>" and content != "<content></content>":
                        asst_parts.append(html.unescape(content))
                if asst_parts:
                    messages.append({"role": "assistant", "content": "\n".join(asst_parts)})
            
            continue

        # 2. Subsequent Turns (N > 0)
        # Look for user directly or under agent
        user_node = t.find("user") or t.find("agent/user")
        user_text = ""
        if user_node is not None:
            if len(user_node):
                for subchild in user_node:
                    user_text += etree.tostring(subchild, encoding='unicode').strip() + "\n"
            else:
                user_text += (user_node.text or "") + "\n"
        
        # Context from history or other nodes
        history_nodes = t.xpath(".//history")
        for h in history_nodes:
            parts = []
            for f in h.findall("file"):
                pf = etree.Element("file")
                pf.set("name", f.get("name") or f.get("path"))
                pf.set("type", f.get("type"))
                pf.text = f.text
                parts.append(etree.tostring(pf, encoding='unicode').strip())
            if parts:
                user_text += "\n\nCONTEXT:\n" + "\n".join(parts)
        
        if user_text.strip():
            messages.append({"role": "user", "content": user_text.strip()})

        assistant_node = t.find("assistant")
        if assistant_node is not None:
            asst_parts = []
            for child in assistant_node:
                content = etree.tostring(child, encoding='unicode', with_tail=False).strip()
                if content != "<content/>" and content != "<content></content>":
                    asst_parts.append(html.unescape(content))
            if asst_parts:
                messages.append({"role": "assistant", "content": "\n".join(asst_parts)})
            
    return messages
