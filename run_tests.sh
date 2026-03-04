#!/usr/bin/env bash

# Exit on error
set -e

echo "--- Starting nzi Test Suite ---"

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

# Run the tests via Makefile
echo "Running tests..."
make test

echo "--- Tests Completed Successfully ---"
