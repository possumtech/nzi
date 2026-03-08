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

def test_answer_flow_lifecycle():
    xml_path = "test/turns/unit_answer_flow.xml"
    
    # TURN 0: User asks for a choice
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted <choice />
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    choice_tag = content_node.find("choice")
    if choice_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit a <choice /> tag.\n")
        sys.exit(1)

    # TURN 1: Provide the ANSWER via Unified Directive
    # We choose "Python"
    feedback = {
        "type": "answer",
        "content": "Python",
        "mode": "act",
        "instruction": "I have chosen Python. Please proceed with setting up a Python project structure."
    }
    dom.start_turn(1, feedback)
    
    # Now run the second turn live
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        final_dom = run_live_unit(tmp_path)
        
        # Verify assistant acknowledges the choice and proceeds
        final_content = final_dom.root.xpath("//turn[@id='1']/assistant/content")[0]
        final_text = "".join(final_content.xpath(".//text()")).lower()
        
        if "python" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not acknowledge the chosen answer (Python).\n")
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
    test_answer_flow_lifecycle()
