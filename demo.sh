#!/usr/bin/env bash

# Launch nvim with the local plugin loaded
# Usage: ./demo.sh [some_file.lua]

echo "--- Launching nzi Demo ---"

# Load .env variables if file exists
if [ -f .env ]; then
    echo "Loading environment from .env..."
    export $(grep -v '^#' .env | xargs)
fi

# Activate virtual environment
if [ -d .venv ]; then
    source .venv/bin/activate
fi
echo "Available commands:"
echo "  :Nzi          - Execute directive on current line"
echo "  :NziToggle    - Show/hide the modal"
echo "  :NziBuffers   - Manage buffer context"
echo "  :NziQuestion  - Ask a question from status bar"

export NZI_DEBUG=1
nvim -u demo_init.lua "$@"
