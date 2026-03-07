import html
from lxml import etree

def project_dom_to_messages(dom, system_prompt_raw=None):
    """
    Projects the XML DOM state into an array of LLM messages.
    Follows history-based model:
    - system and roadmap from Turn 0.
    - files from Turn history.
    Strictly follows the protocol defined in nzi.prompt.
    """
    messages = []
    
    turns = dom.root.findall("turn")
    for t in turns:
        tid = t.get("id")
        
        # 1. Handle System/Roadmap from Turn 0 (The Constitution)
        if tid == "0":
            sys_node = t.find("system")
            sys_content = ""
            if sys_node is not None and sys_node.text:
                sys_content = html.unescape(sys_node.text)
            else:
                sys_content = "You are an agent."

            road_node = t.find("project_roadmap")
            road_content = ""
            if road_node is not None and road_node.text:
                road_content = f"\n\n<project_roadmap file=\"{road_node.get('file', 'AGENTS.md')}\">{road_node.text}</project_roadmap>"

            # Initial history in Turn 0 (Initial context)
            hist_node = t.find("history")
            hist_content = ""
            if hist_node is not None:
                parts = []
                for f in hist_node.findall("file"):
                    f_xml = f"<file name=\"{f.get('name')}\" type=\"{f.get('type')}\">{f.text or ''}</file>"
                    parts.append(f_xml)
                if parts:
                    hist_content = "\n\n" + "\n".join(parts)

            messages.append({
                "role": "system",
                "content": sys_content + road_content + hist_content
            })
            continue

        # 2. Sequential Interaction (Turns > 0)
        user_node = t.find("user")
        if user_node is not None:
            user_text = ""
            if user_node.text:
                user_text += user_node.text
            
            for child in user_node:
                if child.tag == "selection":
                    sel_xml = f"<selection file=\"{child.get('file')}\" start=\"{child.get('start')}\" end=\"{child.get('end')}\">{child.text or ''}</selection>"
                    user_text += sel_xml
                else:
                    user_text += etree.tostring(child, encoding='unicode').strip()
                
                if child.tail:
                    user_text += child.tail
            
            # Append this turn's specific context RAW
            hist_node = t.find("history")
            if hist_node is not None:
                parts = []
                for f in hist_node.findall("file"):
                    f_xml = f"<file name=\"{f.get('name')}\" type=\"{f.get('type')}\">{f.text or ''}</file>"
                    parts.append(f_xml)
                if parts:
                    user_text += "\n\n" + "\n".join(parts)

            if user_text.strip():
                messages.append({"role": "user", "content": user_text.strip()})
        
        # 3. Assistant parts (RAW protocol)
        asst_parts = []
        for child in t:
            if child.tag not in ["user", "system", "project_roadmap", "history"]:
                raw_xml = etree.tostring(child, encoding='unicode', with_tail=False).strip()
                # DO NOT project empty content tags that haven't been filled yet
                if raw_xml != "<content/>" and raw_xml != "<content></content>":
                    asst_parts.append(html.unescape(raw_xml))
        
        if asst_parts:
            messages.append({"role": "assistant", "content": "\n".join(asst_parts)})
            
    return messages
