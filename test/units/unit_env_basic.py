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

def test_env_lifecycle():
    xml_path = "test/turns/unit_env_basic.xml"
    
    # TURN 0: User asks to list files
    dom = run_live_unit(xml_path)
    
    # Verify assistant asked for env info
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    env_tag = content_node.find("env")
    if env_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit <env /> tag\n")
        sys.exit(1)

    # TURN 1: Provide the directory list
    dom.start_turn(1, "Here is the result of the environment command.")
    
    user_node = dom.root.xpath("//turn[@id='1']/user")[0]
    turn_node = dom.root.xpath("//turn[@id='1']")[0]
    history_node = turn_node.find("history")
    if history_node is None:
        history_node = etree.Element("history")
        user_node.addprevious(history_node)
    
    env_result = etree.SubElement(history_node, "env")
    env_result.set("command", env_tag.get("command", "ls test/"))
    env_result.text = "e2e/\nfs/\nturns/\nunits/\nUNITS.md\ntest.sh\n"

    # Now run the second turn live
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        final_dom = run_live_unit(tmp_path)
        
        # Verify assistant acknowledges the file structure
        final_content = final_dom.root.xpath("//turn[@id='1']/assistant/content")[0]
        final_text = "".join(final_content.xpath(".//text()")).lower()
        
        if "units.md" not in final_text and "test.sh" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not acknowledge the directory structure results.\n")
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
    test_env_lifecycle()
