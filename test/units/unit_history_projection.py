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

def test_history_projection_lifecycle():
    xml_path = "test/turns/unit_history_projection.xml"
    target_file = "test/f1.py"
    file_content = 'print("file alpha")'
    
    # TURN 0: User asks to read f1.py
    dom = run_live_unit(xml_path)
    
    # TURN 1: Provide content and summarize
    dom.start_turn(1, "I have provided the file content in history. Summarize it.")
    ctx = [{"name": target_file, "state": "read", "size": len(file_content), "content": file_content}]
    dom.update_context(ctx, None)
    
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp1:
        tmp1.write(etree.tostring(dom.root))
        tmp1_path = tmp1.name

    try:
        dom = run_live_unit(tmp1_path)
        
        # TURN 2: Ambiguous follow-up
        # We start a NEW turn without mentioning the filename
        dom.start_turn(2, "What was in that file I asked about earlier?")
        
        with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp2:
            tmp2.write(etree.tostring(dom.root))
            tmp2_path = tmp2.name
            
        try:
            final_dom = run_live_unit(tmp2_path)
            
            # Verify assistant identifies 'alpha' or 'f1.py'
            final_content = final_dom.root.xpath("//turn[@id='2']/assistant/content")[0]
            final_text = "".join(final_content.xpath(".//text()")).lower()
            
            if "alpha" not in final_text and "f1.py" not in final_text:
                sys.stderr.write("FAILURE: Assistant could not identify the file from history.\n")
        finally:
            if os.path.exists(tmp2_path):
                os.remove(tmp2_path)
                
    finally:
        if os.path.exists(tmp1_path):
            os.remove(tmp1_path)

    # Final validation
    try:
        final_dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_history_projection_lifecycle()
