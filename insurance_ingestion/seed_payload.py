from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

from worker import chunk_blocks, content_hash, extract_pdf, sha256_bytes, token_estimate


def serialize_document(path: Path, *, title: str, category: str, version: str) -> dict:
    raw = path.read_bytes()
    chunks = chunk_blocks(extract_pdf(path))
    return {
        "file_name": path.name,
        "title": title,
        "category": category,
        "version": version,
        "mime_type": "application/pdf",
        "checksum": sha256_bytes(raw),
        "file_base64": base64.b64encode(raw).decode("ascii"),
        "chunks": [
            {
                "chunk_index": index,
                "page_from": chunk.page_from,
                "page_to": chunk.page_to,
                "sheet_name": chunk.sheet_name,
                "row_from": chunk.row_from,
                "row_to": chunk.row_to,
                "section_title": chunk.section_title,
                "subsection_title": None,
                "content_text": chunk.text,
                "raw_content": chunk.raw,
                "content_type": chunk.content_type,
                "extraction_method": chunk.extraction_method,
                "token_count": token_estimate(chunk.text),
                "content_hash": content_hash(chunk.text),
                "metadata": chunk.metadata,
            }
            for index, chunk in enumerate(chunks)
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Build an offline seed payload for trusted ingestion.")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cgrp", type=Path, required=True)
    parser.add_argument("--glp1", type=Path, required=True)
    args = parser.parse_args()

    documents = [
        serialize_document(
            args.cgrp,
            title="CGRP Inhibitors — Adjudication Rule Summary",
            category="migraine_cgrp",
            version="latest",
        ),
        serialize_document(
            args.glp1,
            title="GLP-1 Receptor Agonists — Adjudication Rule Summary",
            category="diabetes_glp1",
            version="2025-12-04",
        ),
    ]
    args.output.write_text(json.dumps({"documents": documents}, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({
        "output": str(args.output),
        "documents": len(documents),
        "chunks": sum(len(item["chunks"]) for item in documents),
        "bytes": args.output.stat().st_size,
    }))


if __name__ == "__main__":
    main()
