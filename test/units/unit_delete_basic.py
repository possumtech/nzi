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

def test_delete_lifecycle():
    xml_path = "test/turns/unit_delete_basic.xml"
    target_file = "test/read_sample.txt"
    
    # Ensure file exists for the test
    if not os.path.exists(target_file):
        with open(target_file, "w") as f: f.write("temp")

    # TURN 0: User asks to delete
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted <delete />
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    delete_tag = content_node.find("delete")
    if delete_tag is None or delete_tag.get("file") != target_file:
        sys.stderr.write(f"FAILURE: Assistant did not emit <delete file='{target_file}' />\n")
        sys.exit(1)

    # TURN 1: Acknowledge deletion via Unified Directive
    feedback = {
        "type": "shell",
        "status": "pass",
        "command": f"rm {target_file}",
        "content": "File deleted successfully.",
        "mode": "act"
    }
    dom.start_turn(1, feedback)
    
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
    test_delete_lifecycle()
