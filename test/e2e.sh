#!/bin/bash
# Run Neovim headless e2e tests
set -e

# Isolate Neovim environment
export XDG_CONFIG_HOME=$(mktemp -d)
export XDG_DATA_HOME=$(mktemp -d)
export XDG_STATE_HOME=$(mktemp -d)
export XDG_CACHE_HOME=$(mktemp -d)

# Cleanup on exit
trap 'rm -rf "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"' EXIT

# Run tests
if [ $# -eq 1 ]; then
    echo "Running E2E test $1..."
    nvim --headless --clean -u test/e2e/init.lua -l "$1"
else
    echo "Running all E2E tests in test/e2e/..."
    for testfile in test/e2e/*.lua; do
        if [[ "$testfile" != "test/e2e/init.lua" ]]; then
            echo "Running E2E test $testfile..."
            nvim --headless --clean -u test/e2e/init.lua -l "$testfile"
        fi
    done
fi
