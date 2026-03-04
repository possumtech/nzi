import sys
import os
import argparse
from litellm import completion

def main():
    parser = argparse.ArgumentParser(description="nzi model bridge")
    parser.add_argument("--model", required=True)
    parser.add_argument("--api_base", help="API base URL")
    parser.add_argument("--api_key", help="API Key")
    args = parser.parse_args()

    # Read prompt from stdin
    prompt = sys.stdin.read()

    try:
        # Use litellm completion with streaming
        response = completion(
            model=args.model,
            messages=[{"role": "user", "content": prompt}],
            api_base=args.api_base,
            api_key=args.api_key,
            stream=True
        )

        for chunk in response:
            delta = chunk['choices'][0]['delta']
            
            # Capture neurotic ramblings (internal reasoning)
            # Some providers use 'reasoning_content', others use 'thought'
            reasoning = delta.get('reasoning_content') or delta.get('thought')
            if reasoning:
                sys.stdout.write(f"<NZ_THOUGHT>{reasoning}")
                sys.stdout.flush()
                continue

            # Capture standard content
            content = delta.get('content', '')
            if content:
                sys.stdout.write(f"<NZ_CONTENT>{content}")
                sys.stdout.flush()
                
    except Exception as e:
        sys.stderr.write(f"Error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
