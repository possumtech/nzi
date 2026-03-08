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

def test_nested_content_unwrapping():
    xml_path = "test/turns/unit_nested_content.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Verify unnesting
    # The XSD defines assistant/content as a sequence of children.
    # If the model wrapped its output in <content>, we should have UNWRAPPED it
    # so we don't have <content><content>...
    
    content_nodes = dom.root.xpath("//assistant/content")
    for node in content_nodes:
        if node.find("content") is not None:
            sys.stderr.write("FAILURE: Redundant nested <content> tag was NOT unwrapped.\n")
            sys.exit(1)
            
    # Final validation
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_nested_content_unwrapping()
