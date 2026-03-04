#!/usr/bin/env bash

# A mock CLI that simulates an LLM response or failure
# Used for unit testing the nzi job wrapper

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --model) MODEL="$2"; shift ;;
    esac
    shift
done

# Read stdin (the prompt)
PROMPT=$(cat)

if [[ "$PROMPT" == *"FAIL_ME"* ]]; then
    echo "Simulated LLM failure message" >&2
    exit 1
fi

echo "MOCK_RESPONSE: Received prompt for model $MODEL: $PROMPT"
