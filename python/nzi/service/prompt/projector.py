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
            sys_node = t.find("agent/system")
            sys_content = ""
            if sys_node is not None and sys_node.text:
                sys_content = html.unescape(sys_node.text)
            else:
                sys_content = "You are an agent."
            
            messages.append({"role": "system", "content": sys_content})

            # B. Everything else in Agent 0 -> role: user (First Prompt)
            agent_node = t.find("agent")
            if agent_node is not None:
                primordial_text = ""
                for child in agent_node:
                    if child.tag == "system": continue
                    
                    if child.tag == "user":
                        primordial_text += (child.text or "")
                    elif child.tag == "project_roadmap":
                        primordial_text += f"\n\nPROJECT_ROADMAP:\n{etree.tostring(child, encoding='unicode').strip()}"
                    elif child.tag == "history":
                        parts = []
                        for f in child.findall("file"):
                            # Strip internal metadata for protocol
                            pf = etree.Element("file")
                            pf.set("name", f.get("name"))
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
        agent_node = t.find("agent")
        if agent_node is not None:
            user_text = ""
            user_node = agent_node.find("user")
            if user_node is not None:
                user_text += (user_node.text or "")
            
            for child in agent_node:
                if child.tag == "user": continue
                if child.tag == "history":
                    parts = []
                    for f in child.findall("file"):
                        pf = etree.Element("file")
                        pf.set("name", f.get("name"))
                        pf.set("type", f.get("type"))
                        pf.text = f.text
                        parts.append(etree.tostring(pf, encoding='unicode').strip())
                    if parts:
                        user_text += "\n\nCONTEXT:\n" + "\n".join(parts)
                else:
                    user_text += f"\n\n{etree.tostring(child, encoding='unicode').strip()}"
            
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
