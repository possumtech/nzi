import os
import sys
from lxml import etree
from nzi.core.dom import SessionDOM
from nzi.service.llm.client import LLMClient
from nzi.service.prompt.projector import project_dom_to_messages

def get_effective_xml(xml_path, prompt_path="nzi.prompt"):
    """
    Reads an XML session file and injects the nzi.prompt into Turn 0's 
    <system> tag if it is missing.
    """
    with open(xml_path, 'rb') as f:
        xml_doc = etree.XML(f.read())
    
    turn0 = xml_doc.xpath("//turn[@id='0']")
    if turn0 and turn0[0].find("system") is None:
        if os.path.exists(prompt_path):
            with open(prompt_path, 'r') as f:
                prompt_content = f.read()
                sys_el = etree.Element("system")
                sys_el.text = etree.CDATA(prompt_content)
                turn0[0].insert(0, sys_el)
    
    return xml_doc

def run_live_unit(xml_path, xsd_path="nzi.xsd", sch_path="nzi.sch"):
    """
    Standard runner for a live unit test.
    Loads XML, injects prompt, calls LLM, integrates response, and prints session.
    """
    # 1. Load and Inject Prompt
    xml_doc = get_effective_xml(xml_path)
    
    # 2. Configuration
    api_key = os.environ.get("OPENROUTER_API_KEY") or os.environ.get("NZI_API_KEY")
    if not api_key:
        sys.stderr.write("Error: API Key not set.\n")
        sys.exit(1)
        
    config = {
        "model": os.environ.get("NZI_MODEL", "deepseek/deepseek-chat"),
        "api_base": "https://openrouter.ai/api/v1",
        "api_key": api_key,
        "model_options": {"temperature": 0.0}
    }
    
    # 3. Project to Messages
    class MockDOM:
        def __init__(self, root): self.root = root
    
    messages = project_dom_to_messages(MockDOM(xml_doc))
    
    # 4. Call LLM
    client = LLMClient()
    success, full_response = client.stream_complete(messages, config, lambda x, y: None)
    
    if not success:
        sys.stderr.write(f"LLM Error: {full_response}\n")
        sys.exit(1)
        
    # 5. Integrate Response
    # We pass the XML string to SessionDOM to maintain the full history
    xml_str = etree.tostring(xml_doc, encoding='unicode')
    dom = SessionDOM(xsd_path, sch_path, xml_str=xml_str)
    
    # SessionDOM.__init__ might have set active_turn to None or added a preamble
    # if it didn't recognize the structure. We explicitly point to the last turn.
    last_turn_id = xml_doc.xpath("//turn")[-1].get("id")
    dom._active_turn = dom.root.xpath(f"//turn[@id='{last_turn_id}']")[0]
    
    dom.finalize_turn(full_response)
    
    # 6. FAITHFUL OUTPUT
    print(etree.tostring(dom.root, encoding='unicode', pretty_print=True))
    
    return dom
