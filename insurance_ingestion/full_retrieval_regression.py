from __future__ import annotations

import json

from .retrieval_qa import invoke


# One evidence-level regression for every policy family plus high-risk traps.
# Expected terms are facts/titles, never generated answers.
CASES = [
    ("CGRP atomic dose", "What is the maximum Ubrogepant dose in 24 hours?", "Ubrogepant", "dose", "CGRP Inhibitors — Adjudication", ["200 mg"]),
    ("Omega-3 dose", "What is the recommended dose of Icosapent Ethyl?", "Icosapent Ethyl", "dose", "Omega 3 Therapies", ["4 grams/day", "twice daily"]),
    ("GLP current dispensing", "How is Mounjaro 2.5 mg dispensed initially?", "Mounjaro", "initial_dispensing", "GLP-1 Receptor Agonists", ["one-month", "no refills"]),
    ("Botox indication", "When is botulinum toxin covered for urinary incontinence?", "BOTOX", "coverage", "Botulinum Toxin", ["medically necessary indications"]),
    ("CGRP class aggregation", "What are the two main classes of CGRP inhibitors?", "CGRP", "coverage", "CGRP", ["Monoclonal", "Gepants"]),
    ("Filgrastim specialty", "Which specialties cover Filgrastim for non-myeloid malignancies?", "Filgrastim", "prescriber", "Filgrastim", ["Oncology", "Hematology"]),
    ("Dupilumab type", "What type of medicine is Dupilumab?", "Dupilumab", "definition", "Dupilumab", ["monoclonal antibody", "IL-4"]),
    ("Biologic request form", "What patient details are required on the Daman biologic therapy form?", "Biologic Therapy", "documentation", "Pre requisite Form", ["Patient", "Date of Birth"]),
    ("Galcanezumab cluster dose", "What is the Galcanezumab dose for cluster headache?", "Galcanezumab", "dose", "Galcanezumab", ["300 mg", "monthly"]),
    ("JAK overview", "What diseases are JAK inhibitors approved to treat?", "JAK", "coverage", "JAKi summary", ["autoimmune", "Janus kinase"]),
    ("JAK detailed guideline", "What documentation is required for JAK inhibitor coverage?", "JAK", "documentation", "JAKi summary", ["Documentation"]),
    ("Mepolizumab asthma dose", "What is the Mepolizumab dose for severe eosinophilic asthma?", "Mepolizumab", "dose", "Mepolizumab", ["100 mg", "4 weeks"]),
    ("Omalizumab CSU", "What is the Omalizumab dose for chronic spontaneous urticaria?", "Omalizumab", "dose", "Omalizumab", ["150", "300 mg"]),
    ("Ondansetron pregnancy", "When is Ondansetron covered during pregnancy?", "Ondansetron", "coverage", "Ondansetron", ["10 to 20 Weeks", "rehydration"]),
    ("Tralokinumab continuation", "What is required for Tralokinumab refill after 16 weeks?", "Tralokinumab", "coverage", "Tralokinumab", ["IGA", "EASI"]),
    ("PCSK9 definition", "What are PCSK9 inhibitors?", "PCSK9", "definition", "PCSK9", ["lipid-lowering", "subcutaneous"]),
    ("PPI ICD", "What is the PPI ICD-10 code for eosinophilic esophagitis?", "PPI", "coverage", "PPI Dx CODES", ["K20.0"]),
    ("GLP MASH safety", "What GLP-1 contraindications apply for MASH?", "MASH", "coverage", "GLP 1 R.A. for MASH", ["MEN-2", "pancreatitis"]),
    ("GLP T2DM initiation", "What supply is allowed when GLP-1 treatment is initiated for T2DM?", "T2DM", "initial_dispensing", "GLP 1 R.A. for T2DM", ["One month", "new prescription"]),
    ("PPI administration", "When should PPIs be taken?", "PPI", "dose", "PPI coverage", ["30 minutes", "meals"]),
]


def main() -> None:
    reports = []
    for name, query, entity, intent, title_hint, content_hints in CASES:
        rows = invoke(query, entity, intent)
        accepted = [row for row in rows if row.get("accepted") is True]
        combined = "\n".join(str(row.get("matched_content", "")) for row in accepted)
        titles = [str(row.get("document_title", "")) for row in accepted]
        passed = (
            any(title_hint.casefold() in title.casefold() for title in titles)
            and all(term.casefold() in combined.casefold() for term in content_hints)
        )
        reports.append({
            "name": name,
            "pass": passed,
            "accepted_documents": titles[:3],
            "top_reason": accepted[0].get("acceptance_reason") if accepted else None,
            "top_score": accepted[0].get("combined_score") if accepted else None,
            "sample": combined[:260],
        })
    result = {"passed": sum(item["pass"] for item in reports), "total": len(reports), "reports": reports}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not all(item["pass"] for item in reports):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
