#!/usr/bin/env python3
# lua/nzi/bridge.py
import sys
import json
import os
import time

def main():
    # Read request from stdin
    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            # Check mode: just verify dependencies
            import litellm
            print(json.dumps({"status": "ok", "version": litellm.__version__}), flush=True)
            return
        request = json.loads(raw_input)
    except Exception as e:
        print(json.dumps({"error": f"Failed to parse input: {str(e)}"}), flush=True)
        sys.exit(1)

    # Late import to catch ImportError and return as JSON
    try:
        import litellm
        from litellm import completion
    except ImportError:
        print(json.dumps({"error": "Dependency missing: LiteLLM not found. Run 'pip install litellm'."}), flush=True)
        sys.exit(1)

    model = request.get("model")
    messages = request.get("messages")
    api_base = request.get("api_base")
    api_key = request.get("api_key")
    
    # Extract model options (flattened in config.options.model_options)
    options = request.get("model_options", {})
    
    # Aider-inspired additions: extra_body and extra_headers
    extra_body = request.get("extra_body", {})
    extra_headers = request.get("extra_headers", {})
    
    # Environment validation (Aider pattern)
    try:
        litellm.validate_environment(model)
    except Exception as e:
        # We don't exit here, as the user might have provided keys in the request
        pass

    # LiteLLM configuration
    litellm.drop_params = True # Drop unsupported params gracefully
    
    try:
        response = completion(
            model=model,
            messages=messages,
            api_base=api_base,
            api_key=api_key,
            stream=True,
            extra_body=extra_body,
            extra_headers=extra_headers,
            **options
        )

        for chunk in response:
            # LiteLLM chunks follow OpenAI format
            # We print each chunk as a single line of JSON for Lua to parse
            try:
                # Handle both dict and object responses
                if hasattr(chunk, "dict"):
                    data = chunk.dict()
                else:
                    data = chunk
                print(json.dumps(data), flush=True)
            except Exception as e:
                # Skip chunks that fail to serialize
                continue

    except Exception as e:
        # Provide clean JSON error for Lua
        # Map LiteLLM exceptions to readable messages
        error_msg = str(e)
        if "AuthenticationError" in error_msg:
            error_msg = f"Authentication Error: Check your API key for {model}."
        elif "NotFoundError" in error_msg:
            error_msg = f"Model Not Found: '{model}' is invalid or inaccessible."
        
        print(json.dumps({"error": error_msg}), flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
