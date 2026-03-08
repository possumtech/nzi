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

def test_summary_strict():
    xml_path = "test/turns/unit_summary_strict.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Verify summary tag constraints
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    summary_tag = content_node.find("summary")
    
    if summary_tag is None:
        sys.stderr.write("FAILURE: Assistant did not emit a <summary /> tag.\n")
        sys.exit(1)
        
    summary_text = summary_tag.text or ""
    
    # Check for single line
    if "\n" in summary_text.strip():
        sys.stderr.write("FAILURE: Summary contains multiple lines.\n")
        sys.exit(1)
        
    # Check for length (using 80 as defined in prompt, though XSD says 120)
    if len(summary_text) > 80:
        sys.stderr.write(f"FAILURE: Summary is too long ({len(summary_text)} chars). Limit is 80.\n")
        sys.exit(1)
        
    # Final validation (XSD enforces 120)
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_summary_strict()
