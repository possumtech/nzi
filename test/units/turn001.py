#!/usr/bin/env python3
import sys
import os

# Ensure project paths are set
PROJECT_ROOT = os.getcwd()
sys.path.insert(0, os.path.join(PROJECT_ROOT, "python"))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "test"))

from test_helpers import run_live_unit

def test_turn001():
    dom = run_live_unit("test/turns/turn001.xml")
    
    # Final check for exit code and error reporting
    try:
        dom.validate_strictly()
    except Exception as e:
        sys.stderr.write(f"Validation Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    test_turn001()
