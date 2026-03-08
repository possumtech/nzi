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

def test_create_lifecycle():
    xml_path = "test/turns/unit_create_basic.xml"
    target_file = "test/hello.py"
    
    # TURN 0: User asks to create
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted <create />
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    create_tag = content_node.find("create")
    if create_tag is None or create_tag.get("file") != target_file:
        sys.stderr.write(f"FAILURE: Assistant did not emit <create file='{target_file}' />\n")
        sys.exit(1)

    # TURN 1: Acknowledge creation
    dom.start_turn(1, "I have created the file for you.")
    
    user_node = dom.root.xpath("//turn[@id='1']/user")[0]
    turn_node = dom.root.xpath("//turn[@id='1']")[0]
    history_node = turn_node.find("history")
    if history_node is None:
        history_node = etree.Element("history")
        user_node.addprevious(history_node)
    
    ack = etree.SubElement(history_node, "ack")
    ack.set("tool", "create")
    ack.set("file", target_file)
    ack.set("status", "success")
    ack.text = "File written successfully."

    # Now run the second turn live
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        final_dom = run_live_unit(tmp_path)
        
        # Verify assistant finalizes
        final_content = final_dom.root.xpath("//turn[@id='1']/assistant/content")[0]
        final_text = "".join(final_content.xpath(".//text()")).lower()
        
        if "created" not in final_text and "success" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not acknowledge the creation success.\n")
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
    test_create_lifecycle()
