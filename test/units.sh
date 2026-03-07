#!/bin/bash
# Execute unit tests in the plugin's python environment
export PYTHONPATH=$PYTHONPATH:$(pwd)/python
python3 test/units.py "$@"
