from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

try:
    from .worker import InsuranceIngestionWorker, SUPPORTED, build_client, sha256_bytes
except ImportError:
    from worker import InsuranceIngestionWorker, SUPPORTED, build_client, sha256_bytes


CATEGORY_RULES = [
    (r"cgrp|galcanezumab", "migraine_cgrp"),
    (r"glp-?1.*mash|mash", "glp1_mash"),
    (r"glp-?1", "diabetes_glp1"),
    (r"omega-?3", "omega3_therapy"),
    (r"botox|botulinum", "botulinum_toxin"),
    (r"filgrastim|zarzio", "filgrastim"),
    (r"dupilumab", "dupilumab"),
    (r"biologic therapy|f-6030", "biologic_prerequisite"),
    (r"janus|jaki", "jak_inhibitors"),
    (r"mepolizumab", "mepolizumab"),
    (r"omalizumab", "omalizumab"),
    (r"ondansetron", "ondansetron"),
    (r"tralokinumab", "tralokinumab"),
    (r"pcsk9", "pcsk9_inhibitors"),
    (r"ppi", "ppi_coverage"),
]


def infer_category(name: str) -> str:
    normalized = name.casefold()
    return next((category for pattern, category in CATEGORY_RULES if re.search(pattern, normalized)), "insurance_policy")


def infer_version(name: str) -> str:
    matches = re.findall(r"(?<!\d)(20\d{2})[-_ ](0?[1-9]|1[0-2])[-_ ](0?[1-9]|[12]\d|3[01])(?!\d)", name)
    if matches:
        year, month, day = matches[-1]
        return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
    matches = re.findall(r"(?<!\d)(0?[1-9]|[12]\d|3[01])[-_ ](0?[1-9]|1[0-2])[-_ ](20\d{2})(?!\d)", name)
    if matches:
        day, month, year = matches[-1]
        return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
    return "old" if "old" in name.casefold() else "current"


def title_from_path(path: Path) -> str:
    title = re.sub(r"[-_]+", " ", path.stem)
    return re.sub(r"\s+", " ", title).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest every supported insurance document in a folder.")
    parser.add_argument("directory", type=Path)
    parser.add_argument("--skip-embeddings", action="store_true")
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
    worker = InsuranceIngestionWorker(client, skip_embeddings=args.skip_embeddings)
    results: list[dict] = []
    for path in sorted(directory.iterdir(), key=lambda item: item.name.casefold()):
        if not path.is_file() or path.suffix.casefold() not in SUPPORTED:
            continue
        checksum = sha256_bytes(path.read_bytes())
        existing = client.table("insurance_documents").select("id,processing_status,metadata").eq("checksum", checksum).execute().data
        if existing and existing[0]["processing_status"] == "ready" and not args.force:
            results.append({"file": path.name, "id": existing[0]["id"], "status": "already_ready"})
            continue
        if (
            args.skip_embeddings
            and existing
            and not args.force
            and existing[0]["processing_status"] == "embedding"
            and int((existing[0].get("metadata") or {}).get("chunk_count") or 0) > 0
        ):
            results.append({"file": path.name, "id": existing[0]["id"], "status": "already_extracted"})
            continue

        document_id = worker.register(
            path,
            title_from_path(path),
            infer_version(path.name),
            infer_category(path.name),
        )
        worker.process(document_id, path)
        inactive = "old" in path.name.casefold()
        if inactive:
            client.table("insurance_documents").update({"is_active": False}).eq("id", document_id).execute()
        results.append({
            "file": path.name,
            "id": document_id,
            "status": "awaiting_embeddings" if args.skip_embeddings else "ready",
            "active": not inactive,
        })
        print(json.dumps(results[-1], ensure_ascii=False), flush=True)

    print(json.dumps({
        "documents": len(results),
        "already_ready": sum(item["status"] == "already_ready" for item in results),
        "awaiting_embeddings": sum(item["status"] == "awaiting_embeddings" for item in results),
        "results": results,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
