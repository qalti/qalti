#!/usr/bin/env python3
"""
Script to check availability of OpenRouter models by making test requests.
"""

import json
import os
import time
from datetime import datetime
from typing import Any

import requests
from dotenv import load_dotenv


def load_environment():
    """Load environment variables from .env file."""
    # Look for .env file in current directory or parent directory
    env_paths = [".env", "../.env"]
    for env_path in env_paths:
        if os.path.exists(env_path):
            load_dotenv(env_path)
            print(f"Loaded environment from: {env_path}")
            break


def load_suitable_models(file_path: str) -> list[dict[str, Any]]:
    """Load suitable models from JSON file."""
    try:
        with open(file_path) as f:
            data = json.load(f)
            return data.get("suitable_models", [])
    except FileNotFoundError:
        print(f"File not found: {file_path}")
        return []
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON: {e}")
        return []


def get_openrouter_key() -> str:
    """Get OpenRouter API key from environment."""
    api_key = os.environ.get(
        "OPENROUTER_API_KEY"
    )  # Prefer the public/CI standard variable name

    if not api_key:
        print("\u274c No OpenRouter API key found!")
        print("Make sure your .env file contains: OPENROUTER_API_KEY=your_key_here")
        print("Or set OPENROUTER_API_KEY environment variable")
        return ""

    # Mask the key for display
    masked_key = api_key[:8] + "..." + api_key[-8:] if len(api_key) > 16 else "***"
    print(f"\u2705 Using API key: {masked_key}")
    return api_key


def get_http_referer() -> str:
    """Get HTTP-Referer header value from environment or use default."""
    return os.environ.get("OPENROUTER_REFERER", "https://github.com/qalti/qalti")


def test_model_availability(
    model_id: str, api_key: str, timeout: int = 30
) -> dict[str, Any]:
    """Test if a model is available by making a minimal request."""
    url = "https://openrouter.ai/api/v1/chat/completions"

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": get_http_referer(),
        "X-Title": "AIQA Model Availability Checker",
    }

    # Minimal test payload
    payload = {
        "model": model_id,
        "messages": [{"role": "user", "content": "Hi"}],
        "max_tokens": 1,
        "temperature": 0,
    }

    start_time = time.time()
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=timeout)
        elapsed = time.time() - start_time

        result = {
            "model_id": model_id,
            "status_code": response.status_code,
            "available": False,
            "response_time_ms": round(elapsed * 1000, 2),
            "error": None,
            "response_data": None,
        }

        if response.status_code == 200:
            result["available"] = True
            try:
                result["response_data"] = response.json()
            except Exception:
                pass
        elif response.status_code == 401:
            result["error"] = "Authentication failed"
        elif response.status_code == 402:
            result["error"] = "Insufficient balance"
        elif response.status_code == 404:
            result["error"] = "Model not found"
        elif response.status_code == 422:
            result["error"] = "Invalid request (model might not support this format)"
        elif response.status_code == 429:
            result["error"] = "Rate limited"
        elif response.status_code == 503:
            result["error"] = "Service unavailable"
        else:
            try:
                error_data = response.json()
                result["error"] = error_data.get("error", {}).get(
                    "message", f"HTTP {response.status_code}"
                )
            except Exception:
                result["error"] = f"HTTP {response.status_code}"

        return result

    except requests.exceptions.Timeout:
        return {
            "model_id": model_id,
            "status_code": None,
            "available": False,
            "response_time_ms": timeout * 1000,
            "error": "Request timeout",
            "response_data": None,
        }
    except requests.exceptions.RequestException as e:
        return {
            "model_id": model_id,
            "status_code": None,
            "available": False,
            "response_time_ms": None,
            "error": f"Request failed: {str(e)}",
            "response_data": None,
        }


def test_vision_capability(
    model_id: str, api_key: str, timeout: int = 30
) -> dict[str, Any]:
    """Test if a model actually supports vision by sending an image."""
    url = "https://openrouter.ai/api/v1/chat/completions"

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": get_http_referer(),
        "X-Title": "AIQA Vision Capability Checker",
    }

    # Test with a simple image (1x1 pixel PNG base64)
    tiny_image_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAGA6dx7HAAAAABJRU5ErkJggg=="

    payload = {
        "model": model_id,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "What do you see?"},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{tiny_image_base64}"
                        },
                    },
                ],
            }
        ],
        "max_tokens": 10,
        "temperature": 0,
    }

    start_time = time.time()
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=timeout)
        elapsed = time.time() - start_time

        result = {
            "model_id": model_id,
            "vision_capable": False,
            "response_time_ms": round(elapsed * 1000, 2),
            "error": None,
        }

        if response.status_code == 200:
            result["vision_capable"] = True
        else:
            try:
                error_data = response.json()
                error_message = error_data.get("error", {}).get(
                    "message", f"HTTP {response.status_code}"
                )
                result["error"] = error_message
            except Exception:
                result["error"] = f"HTTP {response.status_code}"

        return result

    except requests.exceptions.Timeout:
        return {
            "model_id": model_id,
            "vision_capable": False,
            "response_time_ms": timeout * 1000,
            "error": "Request timeout",
        }
    except requests.exceptions.RequestException as e:
        return {
            "model_id": model_id,
            "vision_capable": False,
            "response_time_ms": None,
            "error": f"Request failed: {str(e)}",
        }


def save_results(results: list[dict[str, Any]], output_dir: str):
    """Save test results to JSON file."""
    os.makedirs(output_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = os.path.join(output_dir, f"model_availability_test_{timestamp}.json")

    # Calculate summary stats
    total_models = len(results)
    available_models = sum(1 for r in results if r.get("available", False))
    vision_capable = sum(1 for r in results if r.get("vision_capable", False))

    output_data = {
        "tested_at": datetime.now().isoformat(),
        "summary": {
            "total_models_tested": total_models,
            "available_models": available_models,
            "vision_capable_models": vision_capable,
            "availability_rate": (
                round(available_models / total_models * 100, 1)
                if total_models > 0
                else 0
            ),
        },
        "results": results,
    }

    with open(filename, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"Results saved to: {filename}")
    return filename


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Check OpenRouter model availability")
    parser.add_argument("json_file", help="Path to suitable models JSON file")
    parser.add_argument(
        "--test-vision", action="store_true", help="Also test vision capabilities"
    )
    parser.add_argument(
        "--delay", type=float, default=1.0, help="Delay between requests in seconds"
    )
    parser.add_argument(
        "--timeout", type=int, default=30, help="Request timeout in seconds"
    )
    parser.add_argument("--max-models", type=int, help="Limit number of models to test")

    args = parser.parse_args()

    # Load environment variables
    load_environment()

    # Load models
    models = load_suitable_models(args.json_file)
    if not models:
        print("No models to test")
        return

    # Limit models if requested
    if args.max_models and args.max_models < len(models):
        models = models[: args.max_models]
        print(f"Limited to first {args.max_models} models")

    # Get API key
    api_key = get_openrouter_key()
    if not api_key:
        return

    print(f"Testing {len(models)} models...")
    print(f"Delay between requests: {args.delay}s")
    print(f"Request timeout: {args.timeout}s")
    print(f"Vision testing: {'enabled' if args.test_vision else 'disabled'}")
    print("-" * 50)

    results = []

    for i, model in enumerate(models, 1):
        model_id = model["id"]
        model_name = model.get("name", model_id)
        cost = model.get("prompt_cost", 0) + model.get("completion_cost", 0)
        cost_str = "FREE" if cost == 0 else f"${cost * 1000:.4f}/1K"

        print(f"{i}/{len(models)}: Testing {model_id}")
        print(f"  Name: {model_name}")
        print(f"  Cost: {cost_str}")

        # Test basic availability
        availability_result = test_model_availability(model_id, api_key, args.timeout)

        result = {**model, **availability_result}

        if availability_result["available"]:
            print(f"  ✅ Available ({availability_result['response_time_ms']}ms)")

            # Test vision capability if requested and model is available
            if args.test_vision:
                print("    Testing vision capability...")
                vision_result = test_vision_capability(model_id, api_key, args.timeout)
                result.update(vision_result)

                if vision_result.get("vision_capable"):
                    print(
                        f"    ✅ Vision capable ({vision_result['response_time_ms']}ms)"
                    )
                else:
                    print(
                        f"    ❌ Vision failed: {vision_result.get('error', 'Unknown')}"
                    )
        else:
            print(f"  ❌ Not available: {availability_result.get('error', 'Unknown')}")

        results.append(result)

        # Delay between requests to be nice to the API
        if i < len(models):
            time.sleep(args.delay)

    # Save results
    output_dir = "scripts/output"
    results_file = save_results(results, output_dir)

    # Print summary
    print("\n" + "=" * 50)
    print("SUMMARY")
    print("=" * 50)

    available = [r for r in results if r.get("available", False)]
    vision_capable = [r for r in results if r.get("vision_capable", False)]
    free_available = [r for r in available if r.get("prompt_cost", 0) == 0]

    print(f"Total models tested: {len(results)}")
    print(f"Available models: {len(available)}")
    print(f"Free available models: {len(free_available)}")
    if args.test_vision:
        print(f"Vision capable models: {len(vision_capable)}")
        print(
            f"Free + vision capable: {len([r for r in vision_capable if r.get('prompt_cost', 0) == 0])}"
        )

    if free_available:
        print("\n🆓 Free available models:")
        for model in free_available:
            vision_str = " [VISION ✅]" if model.get("vision_capable") else ""
            print(f"  - {model['id']}{vision_str}")

    if available:
        print("\n💰 All available models:")
        for model in sorted(
            available,
            key=lambda x: x.get("prompt_cost", 0) + x.get("completion_cost", 0),
        ):
            cost = model.get("prompt_cost", 0) + model.get("completion_cost", 0)
            cost_str = "FREE" if cost == 0 else f"${cost * 1000:.4f}/1K"
            vision_str = " [VISION ✅]" if model.get("vision_capable") else ""
            print(f"  - {model['id']} ({cost_str}){vision_str}")

    print(f"\nDetailed results saved to: {results_file}")


if __name__ == "__main__":
    main()
