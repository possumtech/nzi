#!/bin/bash
# Execute a single unit test in the plugin's python environment
export PYTHONPATH=$PYTHONPATH:$(pwd)/python
python3 test/unit.py "$@"
