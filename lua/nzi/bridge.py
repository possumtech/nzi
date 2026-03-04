#!/usr/bin/env python3
# lua/nzi/bridge.py
import sys
import json
import os
from litellm import completion

def main():
    # Read request from stdin
    try:
        raw_input = sys.stdin.read()
        request = json.loads(raw_input)
    except Exception as e:
        print(json.dumps({"error": f"Failed to parse input: {str(e)}"}), flush=True)
        sys.exit(1)

    model = request.get("model")
    messages = request.get("messages")
    api_base = request.get("api_base")
    api_key = request.get("api_key")
    
    # Extract model options (flattened in config.options.model_options)
    options = request.get("model_options", {})
    
    try:
        response = completion(
            model=model,
            messages=messages,
            api_base=api_base,
            api_key=api_key,
            stream=True,
            **options
        )

        for chunk in response:
            # LiteLLM chunks follow OpenAI format
            # We print each chunk as a single line of JSON for Lua to parse
            print(json.dumps(chunk.dict()), flush=True)

    except Exception as e:
        # Provide clean JSON error for Lua
        print(json.dumps({"error": str(e)}), flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
