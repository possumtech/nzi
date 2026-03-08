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

def test_junk_handling():
    xml_path = "test/turns/unit_junk_handling.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Verify content preservation
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    
    # Check for both structured and unstructured content
    has_lookup = content_node.find("lookup") is not None
    # Text can be in .text (before first child) or in .tail of children
    full_text = etree.tostring(content_node, encoding='unicode', method='text').strip()
    
    if not has_lookup:
        sys.stderr.write("FAILURE: Assistant did not emit the <lookup /> tag.\n")
        sys.exit(1)
        
    if len(full_text) < 50:
        sys.stderr.write("FAILURE: Assistant did not provide enough conversational junk (expected some chatting).\n")
        # We don't exit 1 yet, some models are very concise.
        
    # Final validation
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_junk_handling()
