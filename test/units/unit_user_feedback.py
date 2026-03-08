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

def test_user_feedback_lifecycle():
    xml_path = "test/turns/unit_user_feedback.xml"
    
    # TURN 0: User asks to create dir
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted <shell /> or <create />
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    action_tag = content_node.find("shell")
    if action_tag is None:
        action_tag = content_node.find("create")
        
    if action_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit an action tag.\n")
        sys.exit(1)

    # TURN 1: Provide a FAILURE signal via selection
    # We use 'mkdir' which will fail if parents don't exist
    feedback = {
        "type": "shell",
        "status": "fail",
        "command": "mkdir test/fail_dir/sub",
        "content": "mkdir: cannot create directory ‘test/fail_dir/sub’: No such file or directory",
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
        
        # Verify assistant diagnoses and proposes a fix (like -p)
        final_content = final_dom.root.xpath("//turn[@id='1']/assistant/content")[0]
        final_text = "".join(final_content.xpath(".//text()")).lower()
        
        if "-p" not in final_text and "parents" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not propose the correct fix (-p) for the mkdir failure.\n")
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
    test_user_feedback_lifecycle()
