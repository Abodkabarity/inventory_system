from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

try:
    from .worker import InsuranceIngestionWorker, SUPPORTED, build_client, sha256_bytes
except ImportError:
    from worker import InsuranceIngestionWorker, SUPPORTED, build_client, sha256_bytes


def infer_category(name: str) -> str:
    # The document's extracted content creates its entity/topic profile. File
    # names must not require code changes when future policies are uploaded.
    del name
    return "insurance_policy"


def infer_version(name: str) -> str:
    matches = re.findall(r"(?<!\d)(20\d{2})[-_ ](0?[1-9]|1[0-2])[-_ ](0?[1-9]|[12]\d|3[01])(?!\d)", name)
    if matches:
        year, month, day = matches[-1]
        return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
    matches = re.findall(r"(?<!\d)(0?[1-9]|[12]\d|3[01])[-_ ](0?[1-9]|1[0-2])[-_ ](20\d{2})(?!\d)", name)
    if matches:
        day, month, year = matches[-1]
        return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
    return "old" if re.search(r"(?:^|[\s_.-])old(?:$|[\s_.-])", name, flags=re.IGNORECASE) else "current"


def title_from_path(path: Path) -> str:
    title = re.sub(r"[-_]+", " ", path.stem)
    return re.sub(r"\s+", " ", title).strip()


def is_old_version(path: Path) -> bool:
    return bool(re.search(r"(?:^|[\s_.-])old(?:$|[\s_.-])", path.name, flags=re.IGNORECASE))


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Ingest every supported insurance document in a folder.")
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-extract existing documents with the current chunking and metadata contract.",
    )
    args = parser.parse_args()
    directory = args.directory.expanduser().resolve()
    if not directory.is_dir():
        raise NotADirectoryError(directory)

    client = build_client()
    worker = InsuranceIngestionWorker(client)
    results: list[dict] = []
    for path in sorted(directory.rglob("*"), key=lambda item: str(item.relative_to(directory)).casefold()):
        if not path.is_file() or path.suffix.casefold() not in SUPPORTED:
            continue
        checksum = sha256_bytes(path.read_bytes())
        inactive = is_old_version(path)
        existing = client.table("insurance_documents").select("id,processing_status,metadata,is_active").eq("checksum", checksum).execute().data
        if existing and existing[0]["processing_status"] == "ready" and not args.force:
            if bool(existing[0].get("is_active")) == inactive:
                client.table("insurance_documents").update({"is_active": not inactive}).eq("id", existing[0]["id"]).execute()
            results.append({"file": path.name, "id": existing[0]["id"], "status": "already_ready"})
            continue

        document_id = worker.register(
            path,
            title_from_path(path),
            infer_version(path.name),
            infer_category(path.name),
        )
        for attempt in range(3):
            try:
                worker.process(document_id, path)
                break
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(2 ** attempt)
        if inactive:
            client.table("insurance_documents").update({"is_active": False}).eq("id", document_id).execute()
        results.append({
            "file": path.name,
            "id": document_id,
            "status": "ready",
            "active": not inactive,
        })
        print(json.dumps(results[-1], ensure_ascii=False), flush=True)

    print(json.dumps({
        "documents": len(results),
        "already_ready": sum(item["status"] == "already_ready" for item in results),
        "results": results,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
