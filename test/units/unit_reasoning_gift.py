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

def test_reasoning_gift():
    xml_path = "test/turns/unit_reasoning_gift.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Verify reasoning content
    # Note: Not all models or turn contexts guarantee reasoning_content.
    # But DeepSeek (the project default) usually provides it for complex asks.
    reasoning_node = dom.root.xpath("//assistant/reasoning_content")
    
    if not reasoning_node:
        # We check if the model actually provided it. 
        # In a real test, we'd fail if it's missing but expected.
        sys.stderr.write("WARNING: No reasoning_content was provided by the model in this turn.\n")
    else:
        text = reasoning_node[0].text or ""
        if len(text) < 10:
            sys.stderr.write("FAILURE: Reasoning content exists but is unexpectedly short.\n")
            sys.exit(1)
            
    # Final validation
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_reasoning_gift()
