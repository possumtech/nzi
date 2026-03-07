#!/usr/bin/env bash
# tests/trace_failure.sh
set -e

if [ -f .env ]; then export $(grep -v '^#' .env | xargs); fi
if [ -z "$OPENROUTER_API_KEY" ]; then echo "Error: OPENROUTER_API_KEY is not set."; exit 1; fi

MODEL="deepseek/deepseek-chat"
API_URL="https://openrouter.ai/api/v1/chat/completions"

run_trace() {
    local step=$1
    local data=$2
    echo "===================================================="
    echo "STEP $step"
    echo "===================================================="
    
    RESPONSE=$(echo "$data" | curl -s -N --no-buffer -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "HTTP-Referer: https://github.com/possumtech/nzi" \
        -H "X-Title: nzi" \
        -w "\nHTTP_STATUS:%{http_code}" \
        -d @-)
    
    echo "$RESPONSE" | grep "data: {" | head -n 3
    echo "$RESPONSE" | grep "HTTP_STATUS"
    
    if echo "$RESPONSE" | grep -q "1234" && echo "$RESPONSE" | grep -q "5678"; then
        echo "RESULT: Synthesis Successful (Found both codes)."
    elif echo "$RESPONSE" | grep -q "data: \[DONE\]"; then
        echo "RESULT: Stream Finished but Synthesis Failed (Missing codes)."
    else
        echo "RESULT: Stream Stalled or Failed."
    fi
    echo -e "\n----------------------------------------------------\n"
}

IDENTITY="You are deepseek."
CONSTRAINTS="## CONSTRAINTS\n* NEVER output structured XML tags like <turn>, <user>, <file> etc unless as a model action.\n* NEVER repeat prompt, history, or context content.\n* Provide only new information or requested changes."
GLOBAL_RULES="### GLOBAL RULES\nBe concise."
PROJECT_RULES="### PROJECT RULES\n$(cat AGENTS.md)"

USER_PROMPT="I have added these files to the context:\nvault_a.txt\nvault_b.txt\n\nvault_a.txt\n\`\`\`\nTEST_KEY_A = ABC-123\n\`\`\`\n\nvault_b.txt\n\`\`\`\nTEST_KEY_B = DEF-456\n\`\`\`\n\nWhat are the values of TEST_KEY_A and TEST_KEY_B? Answer with the keys and values."

run_trace "Markdown Context Framing" "$(jq -n --arg m "$MODEL" --arg s "$IDENTITY\n\n$CONSTRAINTS\n\n$GLOBAL_RULES\n\n$PROJECT_RULES" --arg u "$USER_PROMPT" '{model: $m, stream: true, messages: [{role: "system", content: $s}, {role: "user", content: $u}]}')"
