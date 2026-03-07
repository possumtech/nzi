import html
from lxml import etree

def project_dom_to_messages(dom, system_prompt_raw=None):
    """
    Projects the XML DOM state into an array of LLM messages.
    """
    messages = []
    
    # 1. System Prompt
    sys_node = dom.root.find("system")
    # CRITICAL: We project the system prompt content RAW and UNESCAPED
    sys_content = None
    if sys_node is not None and sys_node.text:
        sys_content = html.unescape(sys_node.text)
    
    if not sys_content and system_prompt_raw:
        sys_content = system_prompt_raw
        
    if sys_content:
        messages.append({"role": "system", "content": sys_content})
    
    # 2. Workspace Context
    env_parts = []
    road = dom.root.find("project_roadmap")
    if road is not None and road.text:
        env_parts.append(etree.tostring(road, encoding='unicode').strip())
        
    files = dom.root.findall("file")
    for f in files:
        env_parts.append(etree.tostring(f, encoding='unicode').strip())
        
    if env_parts:
        messages.append({"role": "system", "content": "WORKSPACE CONTEXT:\n" + "\n".join(env_parts)})
        
    # 3. History
    turns = dom.root.findall("turn")
    for t in turns:
        user_node = t.find("user")
        if user_node is not None:
            u_xml = etree.tostring(user_node, encoding='unicode').strip()
            messages.append({"role": "user", "content": u_xml})
        
        asst_parts = []
        for child in t:
            if child.tag != "user":
                asst_parts.append(etree.tostring(child, encoding='unicode', with_tail=False).strip())
        if asst_parts:
            messages.append({"role": "assistant", "content": "\n".join(asst_parts)})
            
    return messages
