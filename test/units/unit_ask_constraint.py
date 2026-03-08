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

def test_ask_constraint():
    xml_path = "test/turns/unit_ask_constraint.xml"
    
    # Run the turn
    dom = run_live_unit(xml_path)
    
    # Check assistant content for prohibited tags
    # <ask> turns cannot have edit, create, delete, run, or choice
    prohibited = ["edit", "create", "delete", "run", "choice"]
    content_node = dom.root.xpath("//turn[@id='0']/assistant/content")[0]
    
    found_prohibited = []
    for tag in prohibited:
        if content_node.find(tag) is not None:
            found_prohibited.append(tag)
            
    if found_prohibited:
        sys.stderr.write(f"FAILURE: Assistant used prohibited tags in an <ask> turn: {found_prohibited}\n")
        sys.exit(1)

    # Verify Schematron also catches this (double check)
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Schematron Correctly caught violation (if any): {e}\n")
        # In this test, we WANT it to pass validation because the model SHOULD follow the rules.
        # If it fails validation here, it means the model drifted and Schematron worked.
        sys.exit(1)

if __name__ == "__main__":
    test_ask_constraint()
