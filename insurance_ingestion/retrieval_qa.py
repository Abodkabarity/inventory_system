from __future__ import annotations

import json
import os
from urllib.error import HTTPError
from urllib.request import Request, urlopen


CASES = [
    ("What is the maximum Ubrogepant dose in 24 hours?", "Ubrogepant", "dose", "CGRP", ["Ubrogepant", "200 mg"]),
    ("What are the coverage requirements for Dupilumab?", "Dupilumab", "coverage", "Dupilumab", ["Dupilumab"]),
    ("What are the coverage criteria for Tralokinumab?", "Tralokinumab", "coverage", "Tralokinumab", ["Tralokinumab"]),
    ("When is Ondansetron covered during pregnancy?", "Ondansetron", "coverage", "Ondansetron", ["Ondansetron"]),
    ("What are the PPI diagnosis codes?", "PPI", "coverage", "PPI", ["Diagnosis", "ICD"]),
    ("What are the PCSK9 inhibitor coverage requirements?", "PCSK9", "coverage", "PCSK9", ["Coverage Criteria"]),
    ("What are the JAK inhibitor coverage requirements?", "JAK", "coverage", "JAK", ["JAK"]),
    ("What is Mepolizumab coverage for?", "Mepolizumab", "coverage", "Mepolizumab", ["Mepolizumab"]),
]


def invoke(query: str, entity: str, intent: str) -> list[dict]:
    service_role = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    context_request = Request(
        "https://rzvxjkbraufqbfhvftcy.supabase.co/rest/v1/rpc/resolve_insurance_query_context_v2",
        data=json.dumps({"query_text": query}).encode(),
        headers={
            "Authorization": f"Bearer {service_role}",
            "apikey": service_role,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(context_request, timeout=60) as response:
        contexts = json.loads(response.read())
    context = contexts[0] if contexts else {}
    request = Request(
        "https://rzvxjkbraufqbfhvftcy.supabase.co/functions/v1/insurance-embedding-worker",
        data=json.dumps({
            "mode": "search",
            "query": query,
            "entity_hint": entity,
            "intent_hint": intent,
            "document_hint": context.get("document_id"),
            "limit": 8,
        }).encode(),
        headers={
            "Authorization": f"Bearer {service_role}",
            "apikey": service_role,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=120) as response:
            return json.loads(response.read()).get("results", [])
    except HTTPError as error:
        raise RuntimeError(error.read().decode(errors="replace")) from error


def main() -> None:
    reports = []
    for query, entity, intent, title_hint, content_hints in CASES:
        results = invoke(query, entity, intent)
        top = results[:5]
        combined = "\n".join(str(row.get("matched_content", "")) for row in top)
        titles = [str(row.get("document_title", "")) for row in top]
        reports.append({
            "query": query,
            "pass": any(title_hint.casefold() in title.casefold() for title in titles)
            and any(hint.casefold() in combined.casefold() for hint in content_hints),
            "top_documents": titles[:3],
            "top_score": top[0].get("combined_score") if top else None,
            "sample": combined[:220],
        })
    print(json.dumps({
        "passed": sum(item["pass"] for item in reports),
        "total": len(reports),
        "reports": reports,
    }, ensure_ascii=False, indent=2))
    if not all(item["pass"] for item in reports):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
