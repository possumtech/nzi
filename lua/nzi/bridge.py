#!/usr/bin/env python3
# lua/nzi/bridge.py
import sys
import json
import os
import time
import warnings

# Suppress Pydantic and other library warnings that clutter stdout
warnings.filter_ignore = True
try:
    from pydantic import PydanticDeprecationWarning
    warnings.filterwarnings("ignore", category=PydanticDeprecationWarning)
except ImportError:
    pass

def main():
    # Read request from stdin
    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            # Check mode: just verify dependencies
            import litellm
            print(json.dumps({"status": "ok", "version": getattr(litellm, "__version__", "unknown")}), flush=True)
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
    alias = request.get("alias", "unknown")
    messages = request.get("messages")
    api_base = request.get("api_base")
    api_key = request.get("api_key")
    
    # Extract model options
    options = request.get("model_options", {})
    if not isinstance(options, dict):
        options = {}
    
    # Ensure stream is True for the bridge
    options.pop("stream", None)

    # Advanced options
    extra_body = request.get("extra_body", {})
    extra_headers = request.get("extra_headers", {})
    
    # Aider-inspired metadata mapping: pass the UI alias to the provider
    if "X-Title" not in extra_headers:
        extra_headers["X-Title"] = f"nzi: {alias}"
    if "X-Description" not in extra_headers:
        extra_headers["X-Description"] = f"Neovim-Native Agentic Interface (nzi) using alias: {alias}"

    # LiteLLM configuration
    litellm.drop_params = True 
    
    try:
        # Standardize completion call
        completion_args = {
            "model": model,
            "messages": messages,
            "stream": True,
            **options
        }
        
        if api_base:
            completion_args["api_base"] = api_base
        if api_key:
            completion_args["api_key"] = api_key
        if extra_body:
            completion_args["extra_body"] = extra_body
        if extra_headers:
            completion_args["extra_headers"] = extra_headers

        response = completion(**completion_args)

        for chunk in response:
            try:
                # Use model_dump for Pydantic V2, fallback to dict() for V1 or others
                if hasattr(chunk, "model_dump"):
                    data = chunk.model_dump()
                elif hasattr(chunk, "dict"):
                    data = chunk.dict()
                else:
                    data = chunk
                print(json.dumps(data), flush=True)
            except Exception:
                continue

    except Exception as e:
        error_msg = str(e)
        if "AuthenticationError" in error_msg:
            error_msg = f"Authentication Error: Check your API key for {model}."
        elif "NotFoundError" in error_msg:
            error_msg = f"Model Not Found: '{model}' is invalid or inaccessible."
        
        print(json.dumps({"error": error_msg}), flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
