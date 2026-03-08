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

def test_discovery_multi_lifecycle():
    xml_path = "test/turns/unit_discovery_multi.xml"
    
    # TURN 0: User asks for multiple discovery actions
    dom = run_live_unit(xml_path)
    
    # Verify assistant emitted both tags
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    read_tag = content_node.find("read")
    env_tag = content_node.find("env")
    
    if read_tag is None or env_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit both <read /> and <env /> tags in one turn.\n")
        sys.exit(1)

    # TURN 1: Provide combined results
    dom.start_turn(1, "Here are the results for both your requests.")
    
    # Context Update
    # 1. File content
    with open("test/read_sample.txt", 'r') as f:
        file_content = f.read()
    ctx = [{"name": "test/read_sample.txt", "state": "text/plain", "size": len(file_content), "content": file_content}]
    dom.update_context(ctx, None)
    
    # 2. Env result (Update context for env isn't in SessionDOM helper yet, adding manually)
    turn_node = dom.root.xpath("//turn[@id='1']")[0]
    user_node = turn_node.find("user")
    history_node = turn_node.find("history")
    if history_node is None:
        history_node = etree.Element("history")
        user_node.addprevious(history_node)
    
    env_result = etree.SubElement(history_node, "env")
    env_result.set("command", "ls test/fs/")
    env_result.text = "helper.lua\nintegrity_test.py\nuniverse_test.lua\n"

    # Now run the second turn live
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        tmp.write(etree.tostring(dom.root))
        tmp_path = tmp.name

    try:
        final_dom = run_live_unit(tmp_path)
        
        # Verify assistant summarizes both
        final_content = final_dom.root.xpath("//turn[@id='1']/assistant/content")[0]
        final_text = "".join(final_content.xpath(".//text()")).lower()
        
        if "sample" not in final_text or "helper.lua" not in final_text:
            sys.stderr.write("FAILURE: Assistant did not summarize both the file content and the directory list.\n")
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
    test_discovery_multi_lifecycle()
