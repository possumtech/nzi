#!/usr/bin/env python3
import sys
import os
from lxml import etree

# Ensure project paths are set
PROJECT_ROOT = os.getcwd()
sys.path.insert(0, os.path.join(PROJECT_ROOT, "python"))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "test"))

from test_helpers import get_effective_xml
from nzi.core.dom import SessionDOM
from nzi.service.llm.client import LLMClient
from nzi.service.prompt.projector import project_dom_to_messages

def run_live_turn():
    xml_path = "test/turns/turn001.xml"
    xsd_path = "nzi.xsd"
    sch_path = "nzi.sch"
    
    # 1. Load and Inject Prompt
    xml_doc = get_effective_xml(xml_path)
    
    # Configuration
    api_key = os.environ.get("OPENROUTER_API_KEY") or os.environ.get("NZI_API_KEY")
    if not api_key:
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
    def on_chunk(text, chunk_type):
        pass
        
    success, full_response = client.stream_complete(messages, config, on_chunk)
    
    if not success:
        sys.exit(1)
        
    # 5. Integrate Response
    dom = SessionDOM(xsd_path, sch_path)
    dom.root = xml_doc
    last_turn = xml_doc.xpath("//turn")[-1]
    dom._active_turn = last_turn
    
    # Ensure assistant envelope exists
    if last_turn.find("assistant") is None:
        etree.SubElement(last_turn, "assistant")
    
    dom.finalize_turn(full_response)
    
    # 6. FAITHFUL OUTPUT
    print(etree.tostring(dom.root, encoding='unicode', pretty_print=True))
    
    # Final check for exit code and error reporting
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    run_live_turn()
