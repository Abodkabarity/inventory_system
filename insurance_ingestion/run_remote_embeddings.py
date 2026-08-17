from __future__ import annotations

import argparse
import json
import os
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def invoke(url: str, service_role: str, payload: dict) -> dict:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {service_role}",
            "apikey": service_role,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=150) as response:
            return json.loads(response.read())
    except HTTPError as error:
        raise RuntimeError(error.read().decode("utf-8", errors="replace")) from error


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate matching gte-small embeddings inside Supabase.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()
    service_role = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not service_role:
        raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY is required on the server process only.")

    total = 0
    while True:
        result = invoke(args.url, service_role, {"limit": args.limit})
        processed = int(result.get("processed", 0))
        remaining = int(result.get("remaining", 0))
        total += processed
        print(json.dumps({
            "processed_now": processed,
            "processed_total": total,
            "remaining": remaining,
            "completed_documents": len(result.get("completed", [])),
        }), flush=True)
        if processed == 0 or remaining == 0:
            break
        time.sleep(0.15)


if __name__ == "__main__":
    main()
