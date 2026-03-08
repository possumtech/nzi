#!/bin/bash
# Execute a single unit test in the plugin's python environment
export PYTHONPATH=$PYTHONPATH:$(pwd)/python:$(pwd)

# Resolve Python as per NZI logic
if [ -n "$NZI_PYTHON_CMD" ]; then
    PYTHON_CMD=$NZI_PYTHON_CMD
elif [ -x "./.venv/bin/python3" ]; then
    PYTHON_CMD="./.venv/bin/python3"
else
    PYTHON_CMD="python3"
fi

$PYTHON_CMD test/unit.py "$@"
