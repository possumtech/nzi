#!/usr/bin/env bash

# Exit on error
set -e

# Load .env variables if file exists
if [ -f .env ]; then
    echo "Loading environment from .env..."
    export $(grep -v '^#' .env | xargs)
fi

# Activate virtual environment for litellm
if [ -d .venv ]; then
    echo "Activating virtual environment..."
    source .venv/bin/activate
fi

TIMEOUT_VAL="120s"
echo "--- Starting nzi Test Suite (Timeout: $TIMEOUT_VAL) ---"

# Check for Neovim
if ! command -v nvim &> /dev/null; then
    echo "Error: nvim not found in PATH."
    exit 1
fi

# Check for Git (needed for cloning plenary in tests/init.lua)
if ! command -v git &> /dev/null; then
    echo "Error: git not found in PATH."
    exit 1
    fi

# Run the tests via Makefile with a timeout
echo "Running unit tests..."
if ! command -v timeout &> /dev/null; then
    echo "Warning: 'timeout' command not found. Running without timeout."
    make test
else
    timeout --foreground "$TIMEOUT_VAL" make test
fi

# Integration tests (if environment is set)
if [[ -n "$NZI_TEST_LOCAL" ]]; then
    echo "Running integration tests against $NZI_TEST_LOCAL..."
    nvim --headless --noplugin -u tests/init.lua \
        -c "lua require('plenary.test_harness').test_directory('tests/integration', { progressive = true, halt_on_error = true })" \
        -c "qa!"
fi

echo "--- Tests Completed Successfully ---"
