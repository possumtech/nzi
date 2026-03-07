#!/usr/bin/env python3
import sys
import os
from lxml import etree

def test_turn001_content():
    xml_path = "test/turns/turn001.xml"
    with open(xml_path, 'rb') as f:
        xml_doc = etree.XML(f.read())

    # Check session alias
    assert xml_doc.get("alias") == "test-session", "Session alias mismatch"

    # Check Turn 0 system message
    turn0 = xml_doc.xpath("//turn[@id='0']")[0]
    system_msg = turn0.find("system").text
    assert "NZI" in system_msg, "Turn 0 system message missing 'NZI'"

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
