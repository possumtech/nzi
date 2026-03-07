import sys
import os
import json
# Add the module path so we can import nzi
script_dir = os.path.dirname(os.path.abspath(__file__))
python_path = os.path.abspath(os.path.join(script_dir, "../python"))
if python_path not in sys.path:
    sys.path.insert(0, python_path)

from nzi.core.dom import SessionDOM
from nzi.service.prompt.projector import project_dom_to_messages

def test_engine():
    base_dir = os.getcwd()
    xsd_path = os.path.join(base_dir, "nzi.xsd")
    sch_path = os.path.join(base_dir, "nzi.sch")
    
    print("--- 1. Initialization ---")
    dom = SessionDOM(xsd_path, sch_path, debug_mode=True)
    print("Init Success")
    print(dom.dump_xml())

    print("\n--- 2. Setting Global State ---")
    dom.set_system_prompt("Be a good agent.")
    dom.update_context([{"name": "test.py", "state": "active", "content": "print('hello')"}], "# ROADMAP\n- [ ] Task 1")
    print("State Update Success")
    print(dom.dump_xml())

    print("\n--- 3. Adding Turns ---")
    # Turn 1
    dom.add_turn(1, "Fix the bug", "I will fix it.", {"model": "test-model"})
    # Turn 2 with nested selection
    user_data = {
        "instruction": "Refactor this",
        "selection": {"file": "test.py", "start_line": 1, "start_col": 1, "end_line": 1, "end_col": 5, "text": "print"}
    }
    valid_edit = """<model:edit file='test.py'>
<<<<<<< SEARCH
print('hello')
=======
print('goodbye')
>>>>>>> REPLACE
</model:edit>"""
    dom.add_turn(2, user_data, valid_edit, {"model": "test-model"})
    print("Turns Added Success")
    
    xml = dom.dump_xml()
    print(xml)

    print("\n--- 4. Message Projection ---")
    messages = project_dom_to_messages(dom)
    print(json.dumps(messages, indent=2))

    print("\n--- 5. XPath Verification ---")
    turns = dom.xpath("//agent:turn")
    print(f"Turns Found: {len(turns)}")
    assert len(turns) == 2, f"Expected 2 turns, found {len(turns)}"
    
    ids = dom.xpath("//agent:turn/@id")
    print(f"IDs: {ids}")
    assert ids == ["1", "2"], f"Expected ['1', '2'], found {ids}"

    print("\n--- ALL ENGINE ISOLATION TESTS PASSED ---")

if __name__ == "__main__":
    try:
        test_engine()
    except Exception as e:
        print(f"\n!!! TEST FAILED: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
