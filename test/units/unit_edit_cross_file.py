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

def test_edit_cross_file_lifecycle():
    xml_path = "test/turns/unit_edit_cross_file.xml"
    
    # TURN 0: User asks for cross-file edits
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted multiple <edit /> tags
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    edit_tags = content_node.findall("edit")
    if len(edit_tags) < 2:
        sys.stderr.write(f"FAILURE: Assistant only emitted {len(edit_tags)} <edit /> tags, expected 2.\n")
        sys.exit(1)

    # TURN 1: Acknowledge both
    dom.start_turn(1, "I have applied both file edits for you.")
    
    user_node = dom.root.xpath("//turn[@id='1']/user")[0]
    turn_node = dom.root.xpath("//turn[@id='1']")[0]
    history_node = turn_node.find("history")
    if history_node is None:
        history_node = etree.Element("history")
        user_node.addprevious(history_node)
    
    for f in ["test/f1.py", "test/f2.py"]:
        ack = etree.SubElement(history_node, "ack")
        ack.set("tool", "edit")
        ack.set("file", f)
        ack.set("status", "success")
        ack.text = f"Edit applied successfully to {f}."

    # Now run the second turn live
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        final_dom = run_live_unit(tmp_path)
        final_dom.validate_strictly()
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

if __name__ == "__main__":
    test_edit_cross_file_lifecycle()
