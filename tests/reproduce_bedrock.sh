#!/usr/bin/env bash
# tests/reproduce_bedrock.sh
set -e

if [ -f .env ]; then export $(grep -v '^#' .env | xargs); fi
if [ -z "$OPENROUTER_API_KEY" ]; then echo "Error: OPENROUTER_API_KEY is not set."; exit 1; fi

MODEL="qwen/qwen-2.5-coder-32b-instruct"
API_URL="https://openrouter.ai/api/v1/chat/completions"

run_step() {
    local title=$1
    local mandates_size=$2
    echo "===================================================="
    echo "STEP: $title ($mandates_size chars)"
    echo "===================================================="
    
    MANDATES=$(cat AGENTS.md | head -c "$mandates_size")
    
    local data=$(jq -n \
        --arg model "$MODEL" \
        --arg system_content "You are coder. Adhere to these mandates: $MANDATES" \
        '{
          model: $model,
          messages: [
            {role: "system", content: $system_content},
            {role: "user", content: "<agent:user>Say Hello</agent:user>"}
          ],
          stream: true
        }')

    # Output HTTP code and first few chunks
    RESPONSE=$(curl -s -N -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "HTTP-Referer: https://github.com/possumtech/nzi" \
        -H "X-Title: nzi-repro" \
        -w "\nHTTP_STATUS:%{http_code}" \
        -d "$data")
    
    echo "$RESPONSE" | head -n 5
    echo "$RESPONSE" | grep "HTTP_STATUS"
    echo -e "\n----------------------------------------------------\n"
}

run_step "Minimal" 100
run_step "Medium" 5000
run_step "Large" 15000
run_step "Full" 100000 # Way beyond AGENTS.md size
