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

def test_instruct_freedom():
    xml_path = "test/turns/unit_instruct_freedom.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Verify all expected tools were used
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    
    required_tags = ["create", "read", "lookup"]
    found_tags = []
    for tag in required_tags:
        if content_node.find(tag) is not None:
            found_tags.append(tag)
            
    if len(found_tags) < len(required_tags):
        sys.stderr.write(f"FAILURE: Assistant did not use all requested tools. Found: {found_tags}\n")
        sys.exit(1)

    # Final validation
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_instruct_freedom()
