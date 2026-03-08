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

def test_shell_lifecycle():
    xml_path = "test/turns/unit_shell_basic.xml"
    
    # TURN 0: User asks for shell
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted <shell />
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    shell_tag = content_node.find("shell")
    if shell_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit <shell /> tag\n")
        sys.exit(1)

    # TURN 1: Provide results via UNIFIED DIRECTIVE (selection in instruct)
    # We use the new start_turn helper logic
    feedback = {
        "type": "shell_pass",
        "command": shell_tag.get("command", "mkdir test/tmp_shell_test && rmdir test/tmp_shell_test"),
        "content": "Directory created and removed successfully.",
        "mode": "instruct"
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
    test_shell_lifecycle()
