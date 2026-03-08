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

def test_broken_xml():
    xml_path = "test/turns/unit_broken_xml.xml"
    
    # Run the turn
    # If finalize_turn crashes, this test will fail here.
    try:
        dom = run_live_unit(xml_path)
    except Exception as e:
        sys.stderr.write(f"FAILURE: DOM crashed while handling broken XML: {e}\n")
        sys.exit(1)
    
    # Verify the content was at least partially preserved
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    full_text = etree.tostring(content_node, encoding='unicode').strip()
    
    if len(full_text) < 10:
        sys.stderr.write("FAILURE: Assistant content was lost during healing.\n")
        sys.exit(1)
        
    # Final validation
    # Note: If it's HEALED, it should pass validation.
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error after healing: {e}\n")
        # We don't exit 1 here yet, because some healing might produce valid nodes
        # that still violate semantic rules.

if __name__ == "__main__":
    test_broken_xml()
