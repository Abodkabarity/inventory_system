from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.request import Request, urlopen


def post(url: str, token: str, payload: dict) -> dict:
    request = Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"content-type": "application/json", "x-seed-token": token},
        method="POST",
    )
    with urlopen(request, timeout=90) as response:
        return json.loads(response.read())


def main() -> None:
    parser = argparse.ArgumentParser(description="Resumable trusted live seed client.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--payload", type=Path, required=True)
    args = parser.parse_args()

    documents = json.loads(args.payload.read_text(encoding="utf-8"))["documents"]
    summaries = []
    for item in documents:
        descriptor = {key: value for key, value in item.items() if key != "chunks"}
        document = post(args.url, args.token, {"mode": "document", "document": descriptor})
        document_id = document["id"]
        inserted = 0
        for chunk in item["chunks"]:
            result = post(args.url, args.token, {"mode": "chunk", "document_id": document_id, "chunk": chunk})
            inserted += int(not result.get("duplicate", False))
        post(args.url, args.token, {"mode": "finalize", "document_id": document_id, "chunk_count": len(item["chunks"])})
        summaries.append({"id": document_id, "file": item["file_name"], "chunks": len(item["chunks"]), "inserted": inserted})
    print(json.dumps({"documents": summaries}, ensure_ascii=False))


if __name__ == "__main__":
    main()
