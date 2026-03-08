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

def test_choice_basic():
    xml_path = "test/turns/unit_choice_basic.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Verify choice or prompt_user tag presence and format
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    choice_tag = content_node.find("choice") or content_node.find("prompt_user")
    if choice_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit a <choice /> or <prompt_user /> tag.\n")
        sys.exit(1)

        
    choice_text = choice_tag.text or ""
    if "- [ ]" not in choice_text:
        sys.stderr.write("FAILURE: Choice tag is missing the expected checkbox format '- [ ]'.\n")
        sys.exit(1)
        
    # Final validation
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_choice_basic()
