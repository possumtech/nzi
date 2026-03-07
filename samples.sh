#!/bin/bash
# NZI: Sample Executor
# Usage: ./samples.sh samples/sample01.xml

if [ -z "$1" ]; then
    echo "Usage: ./samples.sh samples/your_sample.xml"
    exit 1
fi

# Load environment variables
set -a
[ -f .env ] && source .env
set +a

# Ensure we have an API key
if [ -z "$NZI_API_KEY" ] && [ -z "$OPENROUTER_API_KEY" ]; then
    echo "Error: NZI_API_KEY or OPENROUTER_API_KEY must be set in .env"
    exit 1
fi

PYTHON_EXEC="./.venv/bin/python3"
if [ ! -f "$PYTHON_EXEC" ]; then
    PYTHON_EXEC="python3"
fi

$PYTHON_EXEC tests/samples.py "$1"
