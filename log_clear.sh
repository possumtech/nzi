#!/usr/bin/env bash

# Clear the nzi debug log
LOG_FILE="nzi_debug.log"

if [ -f "$LOG_FILE" ]; then
    echo "" > "$LOG_FILE"
    echo "--- NZI Debug Log Cleared: $(date) ---" >> "$LOG_FILE"
    echo "Log cleared: $LOG_FILE"
else
    echo "Log file not found: $LOG_FILE"
fi
