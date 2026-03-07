#!/usr/bin/env python3
import sys
import os
import subprocess

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 test/unit.py <test_path>")
        sys.exit(1)
        
    test_path = sys.argv[1]
    # Ensure project's python path is available
    env = os.environ.copy()
    project_root = os.getcwd()
    python_dir = os.path.join(project_root, "python")
    if 'PYTHONPATH' in env:
        env['PYTHONPATH'] = f"{python_dir}:{env['PYTHONPATH']}"
    else:
        env['PYTHONPATH'] = python_dir

    result = subprocess.run([sys.executable, test_path], 
                            env=env, 
                            capture_output=True, 
                            text=True)
    
    if result.returncode == 0:
        print(f"  [PASS] {test_path}")
        print(result.stdout)
    else:
        print(f"  [FAIL] {test_path}")
        print(f"--- STDOUT --- \n{result.stdout}")
        print(f"--- STDERR --- \n{result.stderr}")
        sys.exit(1)

if __name__ == "__main__":
    main()
