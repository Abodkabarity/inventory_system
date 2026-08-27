from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
import uuid
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

import pdfplumber

from insurance_ingestion.worker import (
    ExtractedBlock,
    extract_csv,
    extract_docx,
    extract_pdf,
    extract_xls,
    extract_xlsb,
    extract_xlsx,
    normalize_text,
    token_estimate,
)

SUPPORTED = {".pdf", ".docx", ".xlsx", ".xls", ".xlsb", ".txt", ".csv"}
NAMESPACE = uuid.UUID("877ac73f-a0cc-4aca-86c5-d8e772647992")


ENTITY_SEED: dict[str, dict[str, list[str]]] = {
    "medication_brand": {
        "Dupixent": ["Dupixent"],
        "Aimovig": ["Aimovig"],
        "Nurtec": ["Nurtec", "Nurtec ODT"],
        "Repatha": ["Repatha"],
        "Praluent": ["Praluent"],
        "Leqvio": ["Leqvio"],
        "Mounjaro": ["Mounjaro"],
        "Ozempic": ["Ozempic"],
        "Wegovy": ["Wegovy"],
        "Trulicity": ["Trulicity"],
        "Zarzio": ["Zarzio"],
        "Botox": ["Botox"],
    },
    "medication_generic": {
        "Erenumab": ["Erenumab"],
        "Rimegepant": ["Rimegepant"],
        "Evolocumab": ["Evolocumab"],
        "Alirocumab": ["Alirocumab"],
        "Inclisiran": ["Inclisiran"],
        "Tirzepatide": ["Tirzepatide"],
        "Semaglutide": ["Semaglutide"],
        "Dulaglutide": ["Dulaglutide"],
        "Liraglutide": ["Liraglutide"],
        "Filgrastim": ["Filgrastim"],
        "Botulinum toxin": ["Botulinum toxin"],
        "Fremanezumab": ["Fremanezumab"],
        "Galcanezumab": ["Galcanezumab"],
        "Eptinezumab": ["Eptinezumab"],
        "Ubrogepant": ["Ubrogepant"],
        "Atogepant": ["Atogepant"],
        "Zavegepant": ["Zavegepant"],
        "Dupilumab": ["Dupilumab"],
        "Mepolizumab": ["Mepolizumab"],
        "Omalizumab": ["Omalizumab"],
        "Tralokinumab": ["Tralokinumab"],
        "Ondansetron": ["Ondansetron"],
        "Abrocitinib": ["Abrocitinib"],
        "Baricitinib": ["Baricitinib"],
        "Delgocitinib": ["Delgocitinib"],
        "Filgotinib": ["Filgotinib"],
        "Ruxolitinib": ["Ruxolitinib"],
        "Tofacitinib": ["Tofacitinib"],
        "Upadacitinib": ["Upadacitinib"],
        "Icosapent ethyl": ["Icosapent ethyl", "Icosapent"],
        "Reslizumab": ["Reslizumab"],
        "Benralizumab": ["Benralizumab"],
    },
    "indication": {
        "Homozygous Familial Hypercholesterolaemia": [
            "Homozygous Familial Hypercholesterolaemia", "HoFH"
        ],
        "Heterozygous Familial Hypercholesterolaemia": [
            "Heterozygous Familial Hypercholesterolaemia", "HeFH"
        ],
        "Eosinophilic esophagitis": ["Eosinophilic esophagitis", "EoE"],
        "Metabolic dysfunction-associated steatohepatitis": [
            "Metabolic dysfunction-associated steatohepatitis",
            "Metabolic Dysfunction-Associated Steatohepatitis",
            "MASH", "NASH",
        ],
        "Migraine": ["Migraine", "episodic migraine", "chronic migraine"],
        "Type 2 diabetes mellitus": ["Type 2 diabetes mellitus", "T2DM"],
        "Atopic dermatitis": ["Atopic dermatitis", "AD"],
        "Chronic spontaneous urticaria": ["Chronic spontaneous urticaria", "CSU"],
        "Chronic rhinosinusitis with nasal polyps": [
            "Chronic rhinosinusitis with nasal polyps", "CRSwNP"
        ],
        "Severe asthma": ["Severe asthma", "asthma"],
        "Gastroesophageal reflux disease": ["Gastroesophageal reflux disease", "GERD"],
    },
    "drug_class": {
        "CGRP inhibitors": ["CGRP inhibitors", "CGRP"],
        "GLP-1 receptor agonists": ["GLP-1 receptor agonists", "GLP-1 R.A.", "GLP-1"],
        "PCSK9 inhibitors": ["PCSK9 inhibitors", "PCSK9"],
        "Omega-3 therapies": ["Omega-3 therapies", "Omega-3", "Omega 3", "Omega-3-Acid Ethyl Esters"],
        "Proton pump inhibitors": ["Proton pump inhibitors", "PPI", "PPIs"],
        "Janus kinase inhibitors": ["Janus kinase inhibitors", "JAKi", "JAK inhibitors"],
    },
    "insurer": {"Daman": ["Daman"]},
}

BRAND_RELATIONS = {
    "Dupixent": "Dupilumab",
    "Aimovig": "Erenumab",
    "Nurtec": "Rimegepant",
    "Repatha": "Evolocumab",
    "Praluent": "Alirocumab",
    "Leqvio": "Inclisiran",
    "Mounjaro": "Tirzepatide",
    "Ozempic": "Semaglutide",
    "Wegovy": "Semaglutide",
    "Trulicity": "Dulaglutide",
    "Zarzio": "Filgrastim",
    "Botox": "Botulinum toxin",
}

TOPIC_PATTERNS = {
    "dose": r"\b(dose|dosage|mg|mcg|gram|ml|جرعة)\b",
    "age": r"\b(age|aged|years? old|\d+\s*years?|adult|paediatric|pediatric|children|عمر|سنة)\b",
    "weight": r"\b(weight|kg|kilogram|وزن)\b",
    "labs": r"\b(lab|laboratory|hba1c|a1c|eosinophil|ige|alt|ast|ldl|elf|vcte|mre|تحليل)\b",
    "time_window": r"\b(within|months?|weeks?|days?|hours?|year|annually|monthly|مدة|خلال)\b",
    "initiation": r"\b(initiat\w*|start|starting|first prescription|بدء|ابتداء)\b",
    "continuation": r"\b(continu\w*|maintenance|reassessment|switch\w*|change in therapy|استمرار|تبديل)\b",
    "refill": r"\b(refill|repeat prescription|إعادة صرف|اعادة صرف)\b",
    "documentation": r"\b(document|report|signed|stamped|prescriber|physician|تقرير|توثيق)\b",
    "indication": r"\b(indication|treatment of|prevention|diagnosis|دواعي|تشخيص)\b",
    "coverage": r"\b(coverage|covered|criteria|authorization|eligible|تغطية|مغط)\b",
}


def normalized(value: str | None) -> str:
    value = unicodedata.normalize("NFKC", value or "").casefold()
    value = re.sub(r"(?<=\d)(?=[^\W\d_])|(?<=[^\W\d_])(?=\d)", " ", value, flags=re.UNICODE)
    value = re.sub(r"[^\w\u0600-\u06ff]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def stable_id(*parts: str) -> str:
    return str(uuid.uuid5(NAMESPACE, "|".join(parts)))


def sha256(value: bytes | str) -> str:
    if isinstance(value, str):
        value = value.encode("utf-8")
    return hashlib.sha256(value).hexdigest()


def source_files(root: Path) -> tuple[list[Path], list[dict[str, str]]]:
    supported: list[Path] = []
    ignored: list[dict[str, str]] = []
    for path in sorted(root.rglob("*"), key=lambda item: str(item).casefold()):
        if not path.is_file():
            continue
        if path.name.startswith(("~$", ".~lock.")) or path.suffix.casefold() == ".tmp":
            ignored.append({"file": str(path), "reason": "temporary_or_lock_file"})
        elif path.suffix.casefold() in SUPPORTED:
            supported.append(path)
        else:
            ignored.append({"file": str(path), "reason": "unsupported_extension"})
    return supported, ignored


def extract(path: Path) -> list[ExtractedBlock]:
    extractors = {
        ".pdf": extract_pdf,
        ".docx": extract_docx,
        ".xlsx": extract_xlsx,
        ".xls": extract_xls,
        ".xlsb": extract_xlsb,
        ".csv": extract_csv,
    }
    if path.suffix.casefold() == ".txt":
        value = path.read_text(encoding="utf-8-sig")
        return [ExtractedBlock(text=normalize_text(value), raw=value, page_from=1, page_to=1)]
    return extractors[path.suffix.casefold()](path)


def build_pages(path: Path, blocks: list[ExtractedBlock]) -> list[dict[str, Any]]:
    pages: list[dict[str, Any]] = []
    if path.suffix.casefold() == ".pdf":
        with pdfplumber.open(path) as pdf:
            for number, page in enumerate(pdf.pages, start=1):
                raw = page.extract_text(x_tolerance=2, y_tolerance=3) or ""
                pages.append({"page_number": number, "raw_text": raw, "normalized_text": normalize_text(raw), "metadata": {"provenance_type": "physical_page"}})
        return pages
    if path.suffix.casefold() in {".xlsx", ".xls", ".xlsb", ".csv"}:
        by_sheet: dict[str, list[ExtractedBlock]] = defaultdict(list)
        for block in blocks:
            by_sheet[block.sheet_name or path.stem].append(block)
        for number, (sheet, values) in enumerate(by_sheet.items(), start=1):
            raw = "\n\n".join(block.raw or block.text for block in values)
            rows = [row for block in values for row in (block.row_from, block.row_to) if row is not None]
            pages.append({
                "page_number": number, "sheet_name": sheet,
                "row_from": min(rows) if rows else None, "row_to": max(rows) if rows else None,
                "raw_text": raw, "normalized_text": normalize_text(raw),
                "metadata": {"provenance_type": "worksheet"},
            })
        return pages
    raw = "\n\n".join(block.raw or block.text for block in blocks)
    return [{
        "page_number": 1, "raw_text": raw, "normalized_text": normalize_text(raw),
        "metadata": {"provenance_type": "logical_document", "physical_pagination_available": False},
    }]


def is_table_record_start(block: ExtractedBlock) -> bool:
    if block.metadata.get("entity_name"):
        return True
    fields = block.metadata.get("fields") or {}
    table_key = re.sub(r"[^a-z0-9]+", "_", str(block.metadata.get("table_title") or "").casefold()).strip("_")
    if table_key and fields.get(table_key):
        return True
    return any(value and key not in {"text"} and not key.startswith("column_") for key, value in fields.items())


def pack_text(parts: list[str], maximum: int = 700) -> list[str]:
    output: list[str] = []
    current: list[str] = []
    current_tokens = 0
    for raw_part in parts:
        part = normalize_text(raw_part)
        if not part:
            continue
        tokens = token_estimate(part)
        if tokens > maximum:
            words = part.split()
            for offset in range(0, len(words), 620):
                if current:
                    output.append("\n\n".join(current))
                    current, current_tokens = [], 0
                output.append(" ".join(words[offset:offset + 660]))
            continue
        if current and current_tokens + tokens > maximum:
            output.append("\n\n".join(current))
            current, current_tokens = [], 0
        current.append(part)
        current_tokens += tokens
    if current:
        output.append("\n\n".join(current))
    return output


def semantic_chunks(blocks: list[ExtractedBlock], pages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    sheet_pages = {page.get("sheet_name"): page["page_number"] for page in pages if page.get("sheet_name")}
    prepared: list[dict[str, Any]] = []
    table_buffer: list[ExtractedBlock] = []
    table_key: tuple[Any, ...] | None = None

    def page_number(block: ExtractedBlock) -> int:
        return int(block.page_from or sheet_pages.get(block.sheet_name) or 1)

    def flush_table() -> None:
        nonlocal table_buffer, table_key
        if not table_buffer:
            return
        first, last = table_buffer[0], table_buffer[-1]
        text = "\n".join(item.text for item in table_buffer)
        metadata = dict(first.metadata)
        metadata["semantic_table_record"] = True
        metadata["merged_source_rows"] = len(table_buffer)
        prepared.append({
            "page_from": page_number(first), "page_to": page_number(last),
            "sheet_name": first.sheet_name,
            "row_from": min((item.row_from for item in table_buffer if item.row_from is not None), default=None),
            "row_to": max((item.row_to for item in table_buffer if item.row_to is not None), default=None),
            "section_title": first.section_title or str(first.metadata.get("section_path") or "") or None,
            "text": text, "metadata": metadata,
        })
        table_buffer, table_key = [], None

    prose: list[ExtractedBlock] = []

    def flush_prose() -> None:
        nonlocal prose
        if not prose:
            return
        first, last = prose[0], prose[-1]
        for text in pack_text([item.text for item in prose]):
            prepared.append({
                "page_from": page_number(first), "page_to": page_number(last),
                "sheet_name": first.sheet_name,
                "row_from": first.row_from, "row_to": last.row_to,
                "section_title": first.section_title or str(first.metadata.get("section_path") or "") or None,
                "text": text, "metadata": dict(first.metadata),
            })
        prose = []

    for block in blocks:
        if not normalize_text(block.text):
            continue
        if block.content_type == "table_row":
            flush_prose()
            key = (page_number(block), block.sheet_name, block.metadata.get("table_index"))
            if table_buffer and (key != table_key or is_table_record_start(block)):
                flush_table()
            table_key = key
            table_buffer.append(block)
        else:
            flush_table()
            if prose:
                previous = prose[-1]
                same_group = (
                    page_number(previous) == page_number(block)
                    and previous.sheet_name == block.sheet_name
                    and (previous.section_title or previous.metadata.get("section_path"))
                        == (block.section_title or block.metadata.get("section_path"))
                )
                if not same_group:
                    flush_prose()
            prose.append(block)
    flush_table()
    flush_prose()

    deduped: list[dict[str, Any]] = []
    seen: set[tuple[int, str]] = set()
    for item in prepared:
        key = (item["page_from"], sha256(item["text"]))
        if key not in seen:
            seen.add(key)
            deduped.append(item)
    return deduped


def found_entities(text: str) -> list[dict[str, str]]:
    value = f" {normalized(text)} "
    output: list[dict[str, str]] = []
    for entity_type, entities in ENTITY_SEED.items():
        for canonical, aliases in entities.items():
            if any(f" {normalized(alias)} " in value for alias in aliases):
                output.append({"entity_type": entity_type, "canonical_name": canonical})
    return output


def retrieval_metadata(text: str, entities: list[dict[str, str]]) -> dict[str, Any]:
    topics = [name for name, pattern in TOPIC_PATTERNS.items() if re.search(pattern, text, re.IGNORECASE)]
    stage_topics = [name for name in ("initiation", "continuation", "refill") if name in topics]
    # A page/chunk can legitimately contain initiation and continuation sections.
    # Never collapse mixed evidence to one stage merely because a later sentence
    # contains words such as "maintenance" or "refill".
    stage = stage_topics[0] if len(stage_topics) == 1 else None
    section_type = "mixed_stage" if len(stage_topics) > 1 else stage or next((name for name in (
        "dose", "age", "weight", "labs", "documentation", "indication", "coverage",
    ) if name in topics), "general")
    return {
        "medications": [item["canonical_name"] for item in entities if item["entity_type"].startswith("medication_")],
        "indications": [item["canonical_name"] for item in entities if item["entity_type"] == "indication"],
        "section_type": section_type,
        "topics": topics,
        "treatment_stage": stage,
        "treatment_stages": stage_topics,
        "entity_specific": any(item["entity_type"].startswith("medication_") for item in entities),
        "metadata_is_retrieval_hint_only": True,
    }


def title_for(path: Path) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[-_]+", " ", path.stem)).strip()


def version_for(path: Path) -> str | None:
    name = path.name
    match = re.search(r"(?<!\d)(\d{1,2})-(\d{1,2})-(20\d{2})(?!\d)", name)
    if match:
        day, month, year = match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"
    return "old" if "old" in name.casefold() else None


def sql_value(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (dict, list)):
        return "'" + json.dumps(value, ensure_ascii=False).replace("'", "''") + "'::jsonb"
    return "'" + str(value).replace("'", "''") + "'"


def insert_sql(table: str, columns: list[str], rows: Iterable[list[Any]], conflict: str) -> str:
    values = list(rows)
    if not values:
        return ""
    rendered = ",\n".join("(" + ",".join(sql_value(value) for value in row) + ")" for row in values)
    return f"insert into public.{table} ({','.join(columns)}) values\n{rendered}\n{conflict};\n"


def build(source_root: Path, output_root: Path) -> dict[str, Any]:
    files, ignored = source_files(source_root)
    manifest: dict[str, Any] = {"source_root": str(source_root.resolve()), "documents": [], "ignored": ignored}
    all_entities: dict[tuple[str, str], dict[str, Any]] = {}
    document_text: dict[str, str] = {}

    for path in files:
        payload = path.read_bytes()
        document_id = stable_id("document", sha256(payload))
        report: dict[str, Any] = {
            "id": document_id, "file": path.name, "type": path.suffix.casefold().lstrip("."),
            "source_path": str(path.resolve()), "document_hash": sha256(payload), "title": title_for(path),
            "version": version_for(path), "errors": [], "warnings": [],
        }
        try:
            blocks = extract(path)
            pages = build_pages(path, blocks)
            chunks = semantic_chunks(blocks, pages)
            if not chunks:
                raise RuntimeError("extraction produced no searchable chunks")
            for page in pages:
                page["id"] = stable_id("page", document_id, str(page["page_number"]))
                page["content_hash"] = sha256(page["normalized_text"])
            for index, chunk in enumerate(chunks):
                # A document dedicated to one medicine may omit its name in a
                # continuation paragraph. The approved filename/title is valid
                # routing metadata, so link that verified entity to every chunk
                # without copying any clinical fact into metadata.
                entities = found_entities(f"{report['title']}\n{chunk['text']}")
                metadata = {**chunk.pop("metadata"), **retrieval_metadata(chunk["text"], entities)}
                chunk.update({
                    "id": stable_id("chunk", document_id, str(index)), "chunk_index": index,
                    "normalized_text": normalized(chunk["text"]), "token_count": token_estimate(chunk["text"]),
                    "content_hash": sha256(chunk["text"]), "metadata": metadata, "entities": entities,
                })
                for entity in entities:
                    key = (entity["entity_type"], normalized(entity["canonical_name"]))
                    all_entities[key] = entity
            document_medications = {
                (item["entity_type"], item["canonical_name"])
                for chunk in chunks for item in chunk["entities"]
                if item["entity_type"].startswith("medication_")
            }
            document_indications = {
                (item["entity_type"], item["canonical_name"])
                for chunk in chunks for item in chunk["entities"]
                if item["entity_type"] == "indication"
            }
            # Propagate a single medication family/indication through a
            # dedicated document so continuation pages remain reachable even
            # when they use pronouns. Never do this for mixed catalogs.
            inherited = set()
            if len(document_medications) <= 2:
                inherited.update(document_medications)
            if len(document_indications) == 1:
                inherited.update(document_indications)
            for chunk in chunks:
                present = {(item["entity_type"], item["canonical_name"]) for item in chunk["entities"]}
                chunk["entities"].extend({"entity_type": kind, "canonical_name": name} for kind, name in inherited - present)
                chunk["metadata"] = {**chunk["metadata"], **retrieval_metadata(chunk["text"], chunk["entities"])}
            document_text[document_id] = "\n".join(chunk["text"] for chunk in chunks)
            report.update({
                "status": "ready", "is_active": "old" not in path.name.casefold(),
                "pages_or_sheets": len(pages), "characters_extracted": sum(len(page["raw_text"]) for page in pages),
                "chunks_created": len(chunks),
                "entities_found": sorted({item["canonical_name"] for chunk in chunks for item in chunk["entities"]}),
                "medications": sorted({item["canonical_name"] for chunk in chunks for item in chunk["entities"] if item["entity_type"].startswith("medication_")}),
                "generics": sorted({item["canonical_name"] for chunk in chunks for item in chunk["entities"] if item["entity_type"] == "medication_generic"}),
                "indications": sorted({item["canonical_name"] for chunk in chunks for item in chunk["entities"] if item["entity_type"] == "indication"}),
                "pages": pages, "chunks": chunks,
            })
            if path.suffix.casefold() == ".docx":
                report["warnings"].append("DOCX has logical-document provenance because physical pagination is not intrinsic and LibreOffice is unavailable.")
        except Exception as error:
            report.update({"status": "failed", "is_active": False, "pages_or_sheets": 0, "characters_extracted": 0, "chunks_created": 0, "entities_found": [], "pages": [], "chunks": []})
            report["errors"].append(f"{type(error).__name__}: {error}")
        manifest["documents"].append(report)

    by_stem: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for document in manifest["documents"]:
        logical = normalized(re.sub(r"\b(updated|old|summary)\b", " ", Path(document["file"]).stem, flags=re.IGNORECASE))
        by_stem[logical].append(document)
    for documents in by_stem.values():
        if len(documents) > 1:
            preferred = next((item for item in documents if item["type"] == "pdf" and "old" not in item["file"].casefold()), documents[0])
            for item in documents:
                if item is not preferred and item["status"] == "ready":
                    item["is_active"] = False
                    item["status"] = "superseded"
                    item["warnings"].append(f"Inactive duplicate representation; active source is {preferred['file']}.")

    for entity_type, entities in ENTITY_SEED.items():
        for canonical in entities:
            if any(normalized(alias) in normalized(text) for alias in entities[canonical] for text in document_text.values()):
                all_entities[(entity_type, normalized(canonical))] = {"entity_type": entity_type, "canonical_name": canonical}
    # These pairs were explicitly supplied as already-verified knowledge for
    # V3 brand/generic expansion. Keep them even when an approved source uses
    # only the generic name and never prints the brand.
    for brand, generic in BRAND_RELATIONS.items():
        all_entities[("medication_brand", normalized(brand))] = {"entity_type": "medication_brand", "canonical_name": brand}
        all_entities[("medication_generic", normalized(generic))] = {"entity_type": "medication_generic", "canonical_name": generic}

    entities = []
    for (entity_type, norm), item in sorted(all_entities.items()):
        aliases = ENTITY_SEED[entity_type][item["canonical_name"]]
        unique_aliases = {
            normalized(alias): alias for alias in aliases if normalized(alias)
        }
        entities.append({
            "id": stable_id("entity", entity_type, norm), "canonical_name": item["canonical_name"],
            "normalized_name": norm, "entity_type": entity_type,
            "aliases": [{"alias": alias, "normalized_alias": alias_norm, "alias_type": "canonical" if alias_norm == norm else "verified_synonym"} for alias_norm, alias in unique_aliases.items()],
        })
    manifest["entities"] = entities
    entity_by_name = {(item["entity_type"], item["canonical_name"]): item for item in entities}
    relations = []
    for brand, generic in BRAND_RELATIONS.items():
        subject = entity_by_name.get(("medication_brand", brand))
        obj = entity_by_name.get(("medication_generic", generic))
        if subject and obj:
            source_document_id = next((doc_id for doc_id, text in document_text.items() if normalized(brand) in normalized(text) and normalized(generic) in normalized(text)), None)
            relations.append({"subject_entity_id": subject["id"], "relation_type": "brand_of", "object_entity_id": obj["id"], "verified": True, "source_document_id": source_document_id})
    manifest["relations"] = relations

    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "corpus_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    write_reports(manifest, output_root)
    (output_root / "ingestion.sql").write_text(build_sql(manifest), encoding="utf-8")
    return manifest


def build_sql(manifest: dict[str, Any]) -> str:
    sql = ["""begin;

-- V3 is rebuilt as an isolated corpus. These deletes never touch V2 or legacy tables.
delete from public.insurance_v3_chunk_entities;
delete from public.insurance_v3_entity_relations;
delete from public.insurance_v3_aliases;
delete from public.insurance_v3_chunks;
delete from public.insurance_v3_pages;
delete from public.insurance_v3_entities;
delete from public.insurance_v3_documents;
"""]
    documents = manifest["documents"]
    sql.append(insert_sql("insurance_v3_documents", [
        "id", "file_name", "title", "file_type", "source_path", "document_hash", "status", "is_active", "version", "total_pages", "metadata"
    ], ([doc["id"], doc["file"], doc["title"], doc["type"], doc["source_path"], doc["document_hash"], doc["status"], doc["is_active"], doc["version"], doc["pages_or_sheets"], {"warnings": doc["warnings"], "errors": doc["errors"]}] for doc in documents),
        "on conflict (document_hash) do update set status=excluded.status,is_active=excluded.is_active,updated_at=now(),metadata=excluded.metadata"))
    for doc in documents:
        sql.append(insert_sql("insurance_v3_pages", [
            "id", "document_id", "page_number", "sheet_name", "row_from", "row_to", "raw_text", "normalized_text", "content_hash", "metadata"
        ], ([page["id"], doc["id"], page["page_number"], page.get("sheet_name"), page.get("row_from"), page.get("row_to"), page["raw_text"], normalized(page["raw_text"]), page["content_hash"], page["metadata"]] for page in doc["pages"]),
            "on conflict (document_id,page_number) do update set raw_text=excluded.raw_text,normalized_text=excluded.normalized_text,content_hash=excluded.content_hash,metadata=excluded.metadata"))
        sql.append(insert_sql("insurance_v3_chunks", [
            "id", "document_id", "page_from", "page_to", "sheet_name", "row_from", "row_to", "chunk_index", "section_title", "chunk_text", "normalized_text", "token_count", "content_hash", "metadata"
        ], ([chunk["id"], doc["id"], chunk["page_from"], chunk["page_to"], chunk.get("sheet_name"), chunk.get("row_from"), chunk.get("row_to"), chunk["chunk_index"], chunk.get("section_title"), chunk["text"], chunk["normalized_text"], chunk["token_count"], chunk["content_hash"], chunk["metadata"]] for chunk in doc["chunks"]),
            "on conflict (document_id,chunk_index) do update set chunk_text=excluded.chunk_text,normalized_text=excluded.normalized_text,token_count=excluded.token_count,content_hash=excluded.content_hash,metadata=excluded.metadata"))
    sql.append(insert_sql("insurance_v3_entities", ["id", "canonical_name", "normalized_name", "entity_type", "active"],
        ([entity["id"], entity["canonical_name"], entity["normalized_name"], entity["entity_type"], True] for entity in manifest["entities"]),
        "on conflict (entity_type,normalized_name) do update set canonical_name=excluded.canonical_name,active=true"))
    alias_rows = []
    for entity in manifest["entities"]:
        for alias in entity["aliases"]:
            alias_rows.append([stable_id("alias", entity["id"], alias["normalized_alias"]), entity["id"], alias["alias"], alias["normalized_alias"], alias["alias_type"], True, None])
    sql.append(insert_sql("insurance_v3_aliases", ["id", "entity_id", "alias", "normalized_alias", "alias_type", "verified", "source_document_id"], alias_rows,
        "on conflict (entity_id,normalized_alias) do update set alias=excluded.alias,verified=true,alias_type=excluded.alias_type"))
    sql.append(insert_sql("insurance_v3_entity_relations", ["id", "subject_entity_id", "relation_type", "object_entity_id", "verified", "source_document_id"],
        ([stable_id("relation", relation["subject_entity_id"], relation["relation_type"], relation["object_entity_id"]), relation["subject_entity_id"], relation["relation_type"], relation["object_entity_id"], relation["verified"], relation["source_document_id"]] for relation in manifest["relations"]),
        "on conflict (subject_entity_id,relation_type,object_entity_id) do update set verified=excluded.verified,source_document_id=excluded.source_document_id"))
    entity_ids = {(entity["entity_type"], entity["canonical_name"]): entity["id"] for entity in manifest["entities"]}
    links = []
    for doc in documents:
        for chunk in doc["chunks"]:
            for entity in chunk["entities"]:
                entity_id = entity_ids.get((entity["entity_type"], entity["canonical_name"]))
                if entity_id:
                    links.append([chunk["id"], entity_id, "mentions", 1.0])
    sql.append(insert_sql("insurance_v3_chunk_entities", ["chunk_id", "entity_id", "relation_type", "confidence"], links,
        "on conflict (chunk_id,entity_id) do update set relation_type=excluded.relation_type,confidence=excluded.confidence"))
    # Refresh the additive, derived multi-granular index in the same ingestion
    # transaction. The scheduled embedding worker then processes only units
    # whose content hash changed; no per-document embedding step is required.
    sql.append("select * from public.insurance_v3_refresh_search_units();")
    sql.append("commit;\n")
    return "\n".join(part for part in sql if part)


def write_reports(manifest: dict[str, Any], output_root: Path) -> None:
    rows = []
    for doc in manifest["documents"]:
        rows.append({key: doc[key] for key in (
            "file", "type", "status", "is_active", "pages_or_sheets", "characters_extracted", "chunks_created", "medications", "generics", "indications", "errors", "warnings"
        )})
    summary = {
        "files_scanned": len(manifest["documents"]),
        "successful": sum(doc["status"] in {"ready", "superseded"} for doc in manifest["documents"]),
        "failed": sum(doc["status"] == "failed" for doc in manifest["documents"]),
        "pages_or_sheets": sum(doc["pages_or_sheets"] for doc in manifest["documents"]),
        "chunks": sum(doc["chunks_created"] for doc in manifest["documents"]),
        "characters": sum(doc["characters_extracted"] for doc in manifest["documents"]),
        "ignored": manifest["ignored"], "documents": rows,
    }
    (output_root / "ingestion_report.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# Insurance V3 ingestion report", "", f"- Files: {summary['files_scanned']}", f"- Successful: {summary['successful']}", f"- Failed: {summary['failed']}", f"- Pages/sheets: {summary['pages_or_sheets']}", f"- Chunks: {summary['chunks']}", f"- Characters: {summary['characters']}", "", "| File | Type | Status | Active | Pages/sheets | Characters | Chunks | Errors/warnings |", "|---|---:|---|---:|---:|---:|---:|---|"]
    for row in rows:
        issues = "; ".join(row["errors"] + row["warnings"]).replace("|", "\\|")
        lines.append(f"| {row['file']} | {row['type']} | {row['status']} | {row['is_active']} | {row['pages_or_sheets']} | {row['characters_extracted']} | {row['chunks_created']} | {issues} |")
    (output_root / "ingestion_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    audit = {"entities": manifest["entities"], "relations": manifest["relations"], "counts": {"entities": len(manifest["entities"]), "aliases": sum(len(item["aliases"]) for item in manifest["entities"]), "relations": len(manifest["relations"])}}
    (output_root / "entity_audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
    type_counts = Counter(entity["entity_type"] for entity in manifest["entities"])
    audit_lines = ["# Insurance V3 entity audit", "", f"- Entities: {audit['counts']['entities']}", f"- Verified aliases: {audit['counts']['aliases']}", f"- Verified relations: {audit['counts']['relations']}", "", "## Entity types", ""]
    audit_lines.extend(f"- {entity_type}: {count}" for entity_type, count in sorted(type_counts.items()))
    audit_lines.extend(["", "## Verified brand to generic relations", "", "| Brand | Generic | Source document |", "|---|---|---|"])
    by_id = {entity["id"]: entity["canonical_name"] for entity in manifest["entities"]}
    by_doc = {document["id"]: document["file"] for document in manifest["documents"]}
    for relation in manifest["relations"]:
        audit_lines.append(f"| {by_id[relation['subject_entity_id']]} | {by_id[relation['object_entity_id']]} | {by_doc.get(relation['source_document_id'], 'explicit verified mapping')} |")
    (output_root / "entity_audit.md").write_text("\n".join(audit_lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the source-first insurance V3 corpus and SQL payload.")
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, default=Path("insurance_v3/generated"))
    args = parser.parse_args()
    manifest = build(args.source.resolve(), args.output.resolve())
    print(json.dumps({"documents": len(manifest["documents"]), "chunks": sum(item["chunks_created"] for item in manifest["documents"]), "entities": len(manifest["entities"]), "relations": len(manifest["relations"]), "output": str(args.output.resolve())}, ensure_ascii=False))


if __name__ == "__main__":
    main()
