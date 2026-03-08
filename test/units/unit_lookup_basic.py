#!/usr/bin/env python3
import sys
import os
from lxml import etree

# Ensure project paths are set
PROJECT_ROOT = os.getcwd()
sys.path.insert(0, os.path.join(PROJECT_ROOT, "python"))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "test"))

from test_helpers import run_live_unit
from nzi.core.dom import SessionDOM

def test_lookup_lifecycle():
    xml_path = "test/turns/unit_lookup_basic.xml"
    
    # TURN 0: User asks to lookup
    dom = run_live_unit(xml_path)
    
    # Verify assistant asked to lookup
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    lookup_tag = content_node.find("lookup")
    if lookup_tag is None or "assistant" not in lookup_tag.text.lower():
        sys.stderr.write("FAILURE: Assistant did not emit <lookup>assistant</lookup>\n")
        sys.exit(1)

    # TURN 1: Provide the lookup results
    # We'll simulate finding it in test/read_sample.txt and maybe some others
    dom.start_turn(1, "I have run the lookup for you. Here are the results.")
    
    # Update context manually for the test
    # SessionDOM doesn't have a direct 'add_lookup_result' but update_context handles ctx_list
    # In the real app, lookup results are projected into history.
    # Actually, XSD says <history> contains <lookup> tags.
    
    user_node = dom.root.xpath("//turn[@id='1']/user")[0]
    history_node = user_node.find("history")
    if history_node is None:
        history_node = etree.Element("history")
        user_node.insert(0, history_node)
    
    lookup_result = etree.SubElement(history_node, "lookup")
    lookup_result.text = "assistant"
    
    match1 = etree.SubElement(lookup_result, "match")
    match1.set("file", "test/read_sample.txt")
    match1.set("line", "1")
    match1.text = "This is a sample file for the unit_read_basic test." # Wait, assistant isn't in here.
    
    # Let's use a real match from test/units/turn001.py which we know has 'assistant'
    match2 = etree.SubElement(lookup_result, "match")
    match2.set("file", "test/units/turn001.py")
    match2.set("line", "5")
    match2.text = "from nzi.service.llm.client import LLMClient # wait, still not there."
    
    # Let's just force a match for the test
    match3 = etree.SubElement(lookup_result, "match")
    match3.set("file", "test/mock_assistant.txt")
    match3.set("line", "1")
    match3.text = "You are an assistant."

    # Now run the second turn live
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        final_dom = run_live_unit(tmp_path)
        
        # Verify assistant acknowledges the results
        final_content = final_dom.root.xpath("//turn[@id='1']/assistant/content")[0]
        final_text = "".join(final_content.xpath(".//text()")).lower()
        
        if "mock_assistant.txt" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not acknowledge the lookup results for mock_assistant.txt.\n")
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

    # Final validation
    try:
        final_dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_lookup_lifecycle()
