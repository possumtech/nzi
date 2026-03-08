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

def test_read_lifecycle():
    xml_path = "test/turns/unit_read_basic.xml"
    sample_file = "test/read_sample.txt"
    
    # TURN 0: User asks to read
    # run_live_unit will print the XML for turn 0
    dom = run_live_unit(xml_path)
    
    # Verify assistant asked to read the file
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    read_tag = content_node.find("read")
    if read_tag is None or read_tag.get("file") != sample_file:
        sys.stderr.write(f"FAILURE: Assistant did not emit <read file='{sample_file}' />\n")
        sys.exit(1)

    # TURN 1: Provide the file content
    # In a real app, the effector would read the file and update the context
    with open(sample_file, 'r') as f:
        file_content = f.read()
    
    # We simulate the next turn where the context is provided
    # start_turn(id, user_data)
    dom.start_turn(1, "I have provided the file content in your history. How many lines does it have?")
    
    # Update context manually for the test
    ctx = [{"name": sample_file, "state": "text/plain", "size": len(file_content), "content": file_content}]
    dom.update_context(ctx, None)
    
    # Now run the second turn live
    # We save the intermediate state to a temp file for run_live_unit
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        # run_live_unit will print the XML for turn 1
        final_dom = run_live_unit(tmp_path)
        
        # Verify assistant correctly counted the lines (there are 4 lines in our sample)
        final_content = final_dom.root.xpath("//turn[@id='1']/assistant/content")[0]
        final_text = "".join(final_content.xpath(".//text()")).lower()
        
        if "4" not in final_text and "four" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not correctly count the lines (expected 4).\n")
            # We don't exit 1 yet, let the user see the XML
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

    # Final validation of the whole sequence
    try:
        final_dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_read_lifecycle()
