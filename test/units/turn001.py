#!/usr/bin/env python3
import sys
import os
from lxml import etree
# Add test directory to path for helpers
sys.path.insert(0, os.path.join(os.getcwd(), "test"))
from test_helpers import get_effective_xml

def test_turn001_content():
    xml_path = "test/turns/turn001.xml"
    # Load with injection
    xml_doc = get_effective_xml(xml_path)

    # Check session alias
    assert xml_doc.get("alias") == "test-session", "Session alias mismatch"

    # Check Turn 0 system message (now from nzi.prompt)
    turn0 = xml_doc.xpath("//turn[@id='0']")[0]
    system_msg = turn0.find("system").text
    assert "USER INTERACTION PROTOCOL" in system_msg, "Turn 0 system message missing prompt content"

    # Check Turn 1 interaction
    turn1 = xml_doc.xpath("//turn[@id='1']")[0]
    user_ask = turn1.xpath("./user/ask")[0]
    assert "status" in user_ask.text, "Turn 1 user ask text mismatch"

    # Check Turn 1 assistant action
    assistant = turn1.find("assistant")
    read_action = assistant.find("read")
    assert read_action.get("file") == "README.md", "Assistant read action file mismatch"

    print("turn001.py: All assertions passed.")

if __name__ == "__main__":
    try:
        test_turn001_content()
    except AssertionError as e:
        print(f"Assertion failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
