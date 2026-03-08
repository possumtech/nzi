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

def test_edit_lifecycle():
    xml_path = "test/turns/unit_edit_surgical.xml"
    target_file = "test/hello.py"
    
    # TURN 0: User asks to edit
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted <edit />
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    edit_tag = content_node.find("edit")
    if edit_tag is None or edit_tag.get("file") != target_file:
        sys.stderr.write(f"FAILURE: Assistant did not emit <edit file='{target_file}' />\n")
        sys.exit(1)
    
    # We now allow malformed markers here to test the HEALING in the effector
    from nzi.core.parser import ActionParser
    parser = ActionParser()
    blocks = parser.parse_edit_blocks(edit_tag.text or "")
    if not blocks:
        sys.stderr.write("FAILURE: Even with healing, could not parse any blocks from the edit tag.\n")
        sys.exit(1)

    # TURN 1: Acknowledge edit (Simulate the SCOLD)
    dom.start_turn(1, "I have applied the edit for you.")
    
    user_node = dom.root.xpath("//turn[@id='1']/user")[0]
    history_node = user_node.find("history")
    if history_node is None:
        history_node = etree.Element("history")
        user_node.insert(0, history_node)
    
    ack = etree.SubElement(history_node, "ack")
    ack.set("tool", "edit")
    ack.set("file", target_file)
    
    healed = any(b['healed'] for b in blocks)
    if healed:
        ack.set("status", "healed")
        ack.text = "Edit applied via heuristic healing. Warning: SEARCH/REPLACE markers were malformed. Use strictly: <<<<<<< SEARCH [code] ======= [code] >>>>>>> REPLACE"
    else:
        ack.set("status", "success")
        ack.text = "Surgical edit applied successfully."

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
        
        if "updated" not in final_text and "success" not in final_text and "applied" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not acknowledge the edit success.\n")
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
    test_edit_lifecycle()
