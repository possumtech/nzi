import os
import sys
import json
from lxml import etree

# Ensure we can import the nzi package
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(project_root, "python"))

from nzi.core.dom import SessionDOM, ContractViolationError
from nzi.service.prompt.projector import project_dom_to_messages
from nzi.service.llm.client import LLMClient

def run_sample(sample_path):
    xsd = os.path.join(project_root, "nzi.xsd")
    sch = os.path.join(project_root, "nzi.sch")
    
    if not os.path.exists(sample_path):
        print(f"Error: Sample not found at {sample_path}")
        sys.exit(1)

    # 1. Initialize DOM
    dom = SessionDOM(xsd, sch)
    dom.clear()
    
    # 2. Load the <agent> block from sample
    with open(sample_path, 'r') as f:
        agent_xml = f.read().strip()

    try:
        new_agent_node = etree.fromstring(agent_xml)
        turn0 = dom._get_turn_zero()
        old_agent = turn0.find("agent")
        if old_agent is not None:
            turn0.replace(old_agent, new_agent_node)
        else:
            turn0.append(new_agent_node)
        
        dom.validate_strictly()
    except Exception as e:
        print(f"Input Validation Failed: {e}")
        sys.exit(1)

    # 3. Config model
    model_alias = os.environ.get("NZI_MODEL", "deepseek")
    
    # Correct config structure for LLMClient.stream_complete
    llm_config = {
        "model": "deepseek/deepseek-chat",
        "api_base": "https://openrouter.ai/api/v1",
        "api_key": os.environ.get("NZI_API_KEY") or os.environ.get("OPENROUTER_API_KEY")
    }
    
    # 4. Project to messages and call LLM
    messages = project_dom_to_messages(dom)
    client = LLMClient(model_alias)
    
    print(f"--- Sending to Model ({model_alias}) ---")
    
    def on_chunk(text, chunk_type):
        print(text, end="", flush=True)

    success, full_result = client.stream_complete(messages, llm_config, on_chunk)
    print(f"\n--- End Response ---\n")

    if not success:
        print(f"LLM Error: {full_result}")
        sys.exit(1)

    # 5. Final Validation
    try:
        dom._active_turn = turn0
        if turn0.find("assistant") is None:
            etree.SubElement(turn0, "assistant")
        
        assistant = turn0.find("assistant")
        dom._active_content_node = etree.SubElement(assistant, "content")
        
        dom.finalize_turn(full_result)
        print("Final DOM State is SCHEMA VALID.")
        print("\n--- FINAL XML ---")
        print(dom.dump_xml())
    except ContractViolationError as e:
        print(f"CRITICAL: Model response violated the schema!")
        print(e)
        sys.exit(1)
    except Exception as e:
        print(f"Finalization Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 tests/samples.py samples/sampleXX.xml")
        sys.exit(1)
    run_sample(sys.argv[1])
