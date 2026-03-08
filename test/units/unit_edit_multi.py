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

def test_edit_multi_lifecycle():
    xml_path = "test/turns/unit_edit_multi.xml"
    target_file = "test/multi.py"
    
    # TURN 0: User asks for multiple blocks
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted <edit />
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    edit_tag = content_node.find("edit")
    if edit_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit <edit />\n")
        sys.exit(1)
    
    # Verify parser finds MULTIPLE blocks
    from nzi.core.parser import ActionParser
    parser = ActionParser()
    blocks = parser.parse_edit_blocks(edit_tag.text or "")
    
    if len(blocks) < 2:
        sys.stderr.write(f"FAILURE: Assistant only emitted {len(blocks)} blocks, expected at least 2.\n")
        sys.exit(1)

    # TURN 1: Acknowledge
    dom.start_turn(1, "I have applied both edits for you.")
    
    user_node = dom.root.xpath("//turn[@id='1']/user")[0]
    history_node = user_node.find("history")
    if history_node is None:
        history_node = etree.Element("history")
        user_node.insert(0, history_node)
    
    ack = etree.SubElement(history_node, "ack")
    ack.set("tool", "edit")
    ack.set("file", target_file)
    ack.set("status", "success")
    ack.text = f"Applied {len(blocks)} surgical blocks successfully."

    # Now run the second turn live
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        final_dom = run_live_unit(tmp_path)
        # Final validation
        final_dom.validate_strictly()
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

if __name__ == "__main__":
    test_edit_multi_lifecycle()
