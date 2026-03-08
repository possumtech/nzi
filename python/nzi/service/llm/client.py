import litellm
import json
import logging
import os

class LLMClient:
    """
    Cognitive Bridge: Handles network requests to the LLM.
    Uses LiteLLM for universal provider support.
    """
    def __init__(self, model_alias="deepseek"):
        self.model_alias = model_alias

    def stream_complete(self, messages, config, on_chunk):
        """
        Executes a streaming completion.
        """
        litellm.set_verbose = False
        litellm.suppress_debug_info = True
        try:
            model_options = config.get("model_options", {}).copy()
            if "stream" in model_options:
                del model_options["stream"]

            model_name = config.get("model")
            api_base = config.get("api_base")
            api_key = config.get("api_key")

            # Fallback key loading if missing
            if not api_key:
                if "openrouter" in str(api_base).lower():
                    api_key = os.environ.get("OPENROUTER_API_KEY")
                else:
                    api_key = os.environ.get("OPENAI_API_KEY")

            # Provider Normalization for LiteLLM
            # 1. If it already has a provider prefix, trust it
            if "/" in str(model_name) and not str(model_name).startswith("deepseek/"):
                pass
            # 2. If it's OpenRouter, ensure the prefix
            elif "openrouter.ai" in str(api_base).lower():
                # OpenRouter models MUST be prefixed
                if not str(model_name).startswith("openrouter/"):
                    model_name = f"openrouter/{model_name}"
            # 3. If it's a local/OpenAI compatible base without a slash, LiteLLM usually assumes openai/
            # but we'll leave it as is for broad compatibility.

            response = litellm.completion(
                model=model_name,
                messages=messages,
                api_base=api_base,
                api_key=api_key,
                stream=True,
                timeout=15, # Hardware Enforcement: 15s absolute limit
                **model_options
            )

            full_content = ""
            full_reasoning = ""
            for chunk in response:
                delta = chunk.choices[0].delta
                content = getattr(delta, "content", None)
                reasoning = getattr(delta, "reasoning_content", None) or getattr(delta, "thought", None)

                if reasoning:
                    full_reasoning += reasoning
                    on_chunk(reasoning, "reasoning")
                if content:
                    full_content += content
                    on_chunk(content, "content")
            
            # Return full data object for "Zero-Unwrap" fidelity
            result = {
                "content": full_content,
                "reasoning_content": full_reasoning,
                "model": model_name,
                "provider": config.get("api_base") # or similar source
            }
            return True, result
        except Exception as e:
            logging.error(f"LLM Error: {str(e)}", exc_info=True)
            return False, str(e)
