#!/bin/bash
# NZI: The Brutal Live E2E Runner
# Discards shallow unit tests for live schema-validated interactions.

if [ -z "$NZI_API_KEY" ] && [ -z "$OPENROUTER_API_KEY" ]; then
    echo "Error: NZI_API_KEY or OPENROUTER_API_KEY must be set."
    exit 1
fi

echo "--- Starting NZI Brutal E2E Drill ---"
echo "Project Root: $(pwd)"

# Ensure env is loaded
set -a
[ -f .env ] && source .env
set +a

PYTHON_EXEC="./.venv/bin/python3"
if [ ! -f "$PYTHON_EXEC" ]; then
    PYTHON_EXEC="python3"
fi

FAILED=0
PASSED=0

for sample in samples/*.xml; do
    echo "Testing Sample: $sample"
    $PYTHON_EXEC tests/samples.py "$sample"
    if [ $? -eq 0 ]; then
        echo "RESULT: [PASSED] $sample"
        PASSED=$((PASSED+1))
    else
        echo "RESULT: [FAILED] $sample"
        FAILED=$((FAILED+1))
    fi
    echo "----------------------------------------"
done

echo "--- E2E SUMMARY ---"
echo "PASSED: $PASSED"
echo "FAILED: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
