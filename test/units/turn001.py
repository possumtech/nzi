#!/usr/bin/env python3
import sys
import os
import json
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
    
    print(f"--- STARTING LIVE TURN: {xml_path} ---")
    
    # 1. Load and Inject Prompt
    xml_doc = get_effective_xml(xml_path)
    
    # 2. Setup DOM (We'll use the raw lxml doc since SessionDOM is currently 
    # being stubborn about its internal state/agent tags)
    # For a real test, we want to see what the LLM does with our protocol.
    
    # Configuration (Using environment variables)
    api_key = os.environ.get("OPENROUTER_API_KEY") or os.environ.get("NZI_API_KEY")
    if not api_key:
        print("Error: OPENROUTER_API_KEY or NZI_API_KEY not set.")
        sys.exit(1)
        
    config = {
        "model": os.environ.get("NZI_MODEL", "deepseek/deepseek-chat"),
        "api_base": "https://openrouter.ai/api/v1",
        "api_key": api_key,
        "model_options": {"temperature": 0.0}
    }
    
    # 3. Project to Messages
    # Mocking a DOM object for the projector
    class MockDOM:
        def __init__(self, root): self.root = root
    
    messages = project_dom_to_messages(MockDOM(xml_doc))
    
    print("\n--- MESSAGES SENT TO MODEL ---")
    for m in messages:
        content_preview = m['content'][:100].replace('\n', ' ') + "..."
        print(f"[{m['role'].upper()}]: {content_preview}")
        
    # 4. Call LLM
    client = LLMClient()
    print("\n--- MODEL RESPONSE ---")
    
    def on_chunk(text, chunk_type):
        print(text, end="", flush=True)
        
    success, full_response = client.stream_complete(messages, config, on_chunk)
    print("\n\n--- END MODEL RESPONSE ---")
    
    if not success:
        print(f"Error during LLM call: {full_response}")
        sys.exit(1)
        
    # 5. Integrate Response into DOM for review
    # Find the last turn and append the assistant response
    last_turn = xml_doc.xpath("//turn")[-1]
    assistant = last_turn.find("assistant")
    if assistant is None:
        assistant = etree.SubElement(last_turn, "assistant")
    
    # Create a wrapper for the raw response to see it in context
    response_node = etree.SubElement(assistant, "raw_response")
    response_node.text = full_response
    
    # 6. Final Dump
    print("\n--- COMPLETE SESSION TRANSACTION ---")
    print(etree.tostring(xml_doc, encoding='unicode', pretty_print=True))
    
    # 7. Final Sanity Check (Schema validation on the effective XML)
    with open(xsd_path, 'rb') as f:
        schema = etree.XMLSchema(etree.parse(f))
        # Note: raw_response will fail XSD if not removed, but we want it for review
        # We'll validate a clone without it.
        valid_doc = etree.fromstring(etree.tostring(xml_doc))
        for rr in valid_doc.xpath("//raw_response"):
            rr.getparent().remove(rr)
            
        if schema.validate(valid_doc):
            print("\n[RESULT] Final transaction is SCHEMA VALID.")
        else:
            print("\n[RESULT] Final transaction VIOLATES SCHEMA.")
            for error in schema.error_log:
                print(f"  Line {error.line}: {error.message}")

if __name__ == "__main__":
    run_live_turn()
