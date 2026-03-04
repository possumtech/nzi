#!/usr/bin/env bash

# Exit on error
set -e

# Load .env variables if file exists
if [ -f .env ]; then
    echo "Loading environment from .env..."
    export $(grep -v '^#' .env | xargs)
fi

TIMEOUT_VAL="120s"
echo "--- Starting nzi Test Suite (Timeout: $TIMEOUT_VAL) ---"

# Isolate Neovim environment to avoid loading user config/plugins
export XDG_CONFIG_HOME=$(mktemp -d)
export XDG_DATA_HOME=$(mktemp -d)
export XDG_STATE_HOME=$(mktemp -d)
export XDG_CACHE_HOME=$(mktemp -d)

# Cleanup on exit
trap 'rm -rf "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"' EXIT

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
    nvim --headless -i NONE --noplugin -u tests/init.lua \
        -c "lua require('plenary.test_harness').test_directory('tests/integration', { progressive = true, halt_on_error = true })" \
        -c "qa!"
fi

echo "--- Tests Completed Successfully ---"
