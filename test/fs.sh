#!/bin/bash
# Category 3: Filesystem & Universe Tests
set -e

# Resolve Python as per NZI logic
if [ -n "$NZI_PYTHON_CMD" ]; then
    PYTHON_CMD=$NZI_PYTHON_CMD
elif [ -x "./.venv/bin/python3" ]; then
    PYTHON_CMD="./.venv/bin/python3"
else
    PYTHON_CMD="python3"
fi

# Isolate Neovim environment
export XDG_CONFIG_HOME=$(mktemp -d)
export XDG_DATA_HOME=$(mktemp -d)
export XDG_STATE_HOME=$(mktemp -d)
export XDG_CACHE_HOME=$(mktemp -d)

# Cleanup on exit
trap 'rm -rf "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"' EXIT

echo "Running Python Filesystem Integrity Tests..."
export PYTHONPATH=$PYTHONPATH:$(pwd)/python:$(pwd)
$PYTHON_CMD test/fs/integrity_test.py

echo "Running Lua Universe Tests..."
nvim --headless --clean -u test/e2e/init.lua -l test/fs/universe_test.lua

echo "--- FILESYSTEM TESTS PASSED ---"
