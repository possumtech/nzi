#!/usr/bin/env bash

# Exit on error
set -e

TIMEOUT_VAL="60s"
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
echo "Running tests..."
if ! command -v timeout &> /dev/null; then
    echo "Warning: 'timeout' command not found. Running without timeout."
    make test
else
    timeout --foreground "$TIMEOUT_VAL" make test
fi

echo "--- Tests Completed Successfully ---"
