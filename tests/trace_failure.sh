#!/usr/bin/env bash
# tests/trace_failure.sh
set -e

if [ -f .env ]; then export $(grep -v '^#' .env | xargs); fi
if [ -z "$OPENROUTER_API_KEY" ]; then echo "Error: OPENROUTER_API_KEY is not set."; exit 1; fi

MODEL="qwen/qwen-2.5-coder-32b-instruct"
API_URL="https://openrouter.ai/api/v1/chat/completions"
REFERER="https://github.com/possumtech/nzi"

run_trace() {
    local step=$1
    local data=$2
    echo "===================================================="
    echo "STEP $step"
    echo "===================================================="
    
    # Capture full output to check for stalls or errors
    RESPONSE=$(echo "$data" | curl -s -N -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "HTTP-Referer: $REFERER" \
        -H "X-Title: nzi-trace" \
        -w "\nHTTP_STATUS:%{http_code}" \
        -d @-)
    
    # Show first few chunks
    echo "$RESPONSE" | grep "data: {" | head -n 10
    echo "$RESPONSE" | grep "HTTP_STATUS"
    
    # Check if it actually finished and synthesized correctly
    if echo "$RESPONSE" | grep -q "1234" && echo "$RESPONSE" | grep -q "5678"; then
        echo "RESULT: Synthesis Successful (Found both codes)."
    elif echo "$RESPONSE" | grep -q "data: \[DONE\]"; then
        echo "RESULT: Stream Finished but Synthesis Failed (Missing codes)."
    else
        echo "RESULT: Stream Stalled or Failed."
    fi
    echo -e "\n----------------------------------------------------\n"
}

MANDATES=$(cat AGENTS.md)

# 10. Exact App Synthesis Emulation
run_trace "10: Exact App Synthesis" "$(jq -n --arg m "$MODEL" --arg c "$MANDATES" '{
  model: $m, 
  stream: true, 
  messages: [
    {role: "developer", content: $c}, 
    {role: "user", content: "<agent:context>\n<agent:file name=\"vault_a.txt\" state=\"active\">\nTEST_KEY_A = 1234\n</agent:file>\n<agent:file name=\"vault_b.txt\" state=\"active\">\nTEST_KEY_B = 5678\n</agent:file>\n</agent:context>\n\n<agent:user>What are the values of TEST_KEY_A and TEST_KEY_B? Answer with the keys and values.</agent:user>"}
  ]
}')"
