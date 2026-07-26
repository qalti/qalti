#!/usr/bin/env python3
import os

import requests
from dotenv import load_dotenv


def check_openrouter_usage():
    load_dotenv()
    api_key = os.getenv("OPENROUTER_API_KEY")
    if not api_key:
        print("Error: OPENROUTER_API_KEY environment variable is not set.")
        return

    headers = {"Authorization": f"Bearer {api_key}"}

    # Check current usage
    try:
        response = requests.get(
            "https://openrouter.ai/api/v1/auth/key", headers=headers, timeout=30
        )
        if response.status_code == 200:
            data = response.json()
            print("API Key Info:")
            print(f"  Limit: ${data.get('data', {}).get('limit', 'N/A')}")
            print(f"  Usage: ${data.get('data', {}).get('usage', 'N/A')}")
            print(f"  Rate limit: {data.get('data', {}).get('rate_limit', 'N/A')}")
        else:
            print(f"Error checking usage: {response.text}")
    except requests.RequestException as e:
        print(f"Network error while checking usage: {e}")


if __name__ == "__main__":
    check_openrouter_usage()
