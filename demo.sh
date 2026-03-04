#!/usr/bin/env bash

# Launch nvim with the local plugin loaded
# Usage: ./demo.sh [some_file.lua]

echo "--- Launching nzi Demo ---"
echo "Available commands:"
echo "  :Nzi          - Execute directive on current line"
echo "  :NziToggle    - Show/hide the modal"
echo "  :NziBuffers   - Manage buffer context"
echo "  :NziQuestion  - Ask a question from status bar"

nvim -u demo_init.lua "$@"
