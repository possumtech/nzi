#!/bin/bash
# Execute lint.py in the plugin's python environment
# Ensure PYTHONPATH includes the python directory of the project
export PYTHONPATH=$PYTHONPATH:$(pwd)/python
python3 test/lint.py "$@"
