#!/usr/bin/env python3
import sys
import os
import subprocess

def get_python_cmd():
    # NZI logic for resolving python: NZI_PYTHON_CMD or ./.venv/bin/python3 or python3
    nzi_cmd = os.environ.get("NZI_PYTHON_CMD")
    if nzi_cmd:
        return nzi_cmd.split()
    
    venv_path = os.path.join(os.getcwd(), ".venv", "bin", "python3")
    if os.path.exists(venv_path):
        return [venv_path]
    
    return [sys.executable] # fallback to current runner's python

def run_test(test_path):
    print(f"Running unit test {test_path}...")
    try:
        # Run test in a subprocess for isolation
        env = os.environ.copy()
        # Ensure project's python path and project root (for test.helpers) are available
        project_root = os.getcwd()
        python_dir = os.path.join(project_root, "python")
        if 'PYTHONPATH' in env:
            env['PYTHONPATH'] = f"{python_dir}:{project_root}:{env['PYTHONPATH']}"
        else:
            env['PYTHONPATH'] = f"{python_dir}:{project_root}"

        cmd = get_python_cmd() + [test_path]
        result = subprocess.run(cmd, 
                                env=env, 
                                capture_output=True, 
                                text=True)
        
        if result.returncode == 0:
            print(f"  [PASS] {test_path}")
            return True
        else:
            print(f"  [FAIL] {test_path}")
            print(f"--- STDOUT --- \n{result.stdout}")
            print(f"--- STDERR --- \n{result.stderr}")
            return False
            
    except Exception as e:
        print(f"ERROR: Failed to run test {test_path}: {e}")
        return False

def main():
    units_dir = "test/units"
    if not os.path.exists(units_dir):
        print(f"Error: Directory {units_dir} not found.")
        sys.exit(1)
        
    tests = sorted([os.path.join(units_dir, f) for f in os.listdir(units_dir) if f.endswith(".py")])
    
    if not tests:
        print("No unit tests found.")
        return

    success_count = 0
    for test in tests:
        if run_test(test):
            success_count += 1
            
    print(f"\n{success_count}/{len(tests)} tests passed.")
    if success_count < len(tests):
        sys.exit(1)

if __name__ == "__main__":
    main()
