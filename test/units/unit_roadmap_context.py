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

def test_roadmap_context():
    xml_path = "test/turns/unit_roadmap_context.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Verify assistant identifies the roadmap content
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    final_text = "".join(content_node.xpath(".//text()")).lower()
    
    if "finalize" not in final_text and "e2e" not in final_text:
        sys.stderr.write("FAILURE: Assistant did not correctly identify the next steps from the roadmap.\n")
        sys.exit(1)

    # Final validation
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_roadmap_context()
