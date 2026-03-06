#!/usr/bin/env python3
# lua/nzi/protocol/bridge.py
import sys
import json
import os
import time
import warnings
import logging

# Suppress all library logging and warnings
os.environ["LITELLM_LOG"] = "ERROR"
logging.getLogger("litellm").setLevel(logging.ERROR)
warnings.filterwarnings("ignore")

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

    # Advanced options - Ensure they are dicts (Lua empty tables can become lists)
    extra_body = request.get("extra_body", {})
    if not isinstance(extra_body, dict):
        extra_body = {}
        
    extra_headers = request.get("extra_headers", {})
    if not isinstance(extra_headers, dict):
        extra_headers = {}
    
    # Metadata mapping: pass the UI alias to the provider
    if "X-Title" not in extra_headers:
        extra_headers["X-Title"] = f"nzi: {alias}"
    if "X-Description" not in extra_headers:
        extra_headers["X-Description"] = f"Neovim-Native Agentic Interface (nzi) using alias: {alias}"

    # LiteLLM configuration
    litellm.drop_params = True 
    
    max_retries = 3
    retry_delay = 1
    
    for attempt in range(max_retries):
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
            
            # If we reach here, the stream finished successfully
            return

        except Exception as e:
            error_msg = str(e)
            
            # Check if it's a retryable error (500, 502, 503, 504 or rate limit)
            is_retryable = any(err in error_msg for err in ["500", "502", "503", "504", "RateLimitError", "rate_limit"])
            
            if is_retryable and attempt < max_retries - 1:
                time.sleep(retry_delay)
                retry_delay *= 2 # Exponential backoff
                continue

            # Provider-specific guidance
            if "500" in error_msg and "openrouter" in str(api_base).lower():
                error_msg = (
                    f"OpenRouter Provider Error (500): The upstream host interrupted the stream. "
                    f"Try switching to a different model like 'deepseek/deepseek-chat' or 'google/gemini-2.0-flash-001'."
                )
            elif "AuthenticationError" in error_msg:
                error_msg = f"Authentication Error: Check your API key for {model}."
            elif "NotFoundError" in error_msg:
                error_msg = f"Model Not Found: '{model}' is invalid or inaccessible."
            
            print(json.dumps({"error": error_msg}), flush=True)
            sys.exit(1)

if __name__ == "__main__":
    main()
