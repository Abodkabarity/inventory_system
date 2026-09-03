import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildEvidencePacket,
  buildQueries,
  combineSearchPlans,
  globalLiteralQueries,
  logicalSourceKey,
  mergeCandidates,
  mergeCandidatesWithinAnchors,
  rankingAdjustment,
  relationshipQueryHints,
  restrictToAnchoredDocuments,
} from "./retrieval.ts";

Deno.test("explicit entities get bounded global literal rescue queries", () => {
  assertEquals(
    globalLiteralQueries({
      search_terms: ["coverage criteria"],
      exact_literals: ["Mounjaro", "Crohn's disease", "approval"],
      codes: [],
      important_qualifiers: ["initiation"],
    }),
    ["mounjaro", "crohn AND disease"],
  );
});

Deno.test("relationship hints distinguish lifecycle age and source intents", () => {
  assert(
    relationshipQueryHints("Can Drug A be started?").some((hint) =>
      hint.includes("initiation")
    ),
  );
  assert(
    relationshipQueryHints("What is the minimum age?").some((hint) =>
      hint.includes("age eligibility")
    ),
  );
  assert(
    relationshipQueryHints("Which approved source page says this?").some(
      (hint) => hint.includes("approved source page"),
    ),
  );
});

Deno.test("duplicate representations share one logical source key", () => {
  assertEquals(
    logicalSourceKey("CGRP inhibitors drugs Summary Updated"),
    logicalSourceKey("Antimigraine CGRP inhibitors drugs external AR Aug 2026"),
  );
});

Deno.test("evidence preserves source version and page metadata", () => {
  const item = candidate("source-meta", "doc-source", "Answer-bearing fact");
  item.page_from = 7;
  item.page_to = 7;
  item.metadata = {
    logical_source_key: "family:example",
    source_version: "3.0",
    effective_date: "2026-01-01T00:00:00.000Z",
    source_updated_at: "2026-02-01T00:00:00.000Z",
    document_hash: "hash-1",
  };
  const evidence = buildEvidencePacket([item], "Which source page?", 1)[0];
  assertEquals(evidence.page_from, 7);
  assertEquals(evidence.logical_source_key, "family:example");
  assertEquals(evidence.source_version, "3.0");
  assertEquals(evidence.document_hash, "hash-1");
});
import type { SearchCandidate, SearchPlan } from "./types.ts";

const plan: SearchPlan = {
  search_terms: ["Dexcom price"],
  exact_literals: ["Dexcom"],
  codes: ["K0553"],
  important_qualifiers: ["price"],
};

function candidate(
  id: string,
  document: string,
  text: string,
  score = 1,
): SearchCandidate {
  return {
    search_unit_id: id,
    parent_unit_id: null,
    sibling_order: null,
    document_id: document,
    document_title: `Document ${document}`,
    file_name: `${document}.pdf`,
    unit_type: "table_row",
    page_from: 1,
    page_to: 1,
    row_from: 2,
    row_to: 2,
    section_title: null,
    table_title: "Prices",
    retrieval_text: text,
    source_chunk_ids: [id],
    metadata: {},
    score,
    matched_queries: ["first"],
  };
}

Deno.test("queries retain question, literal, code, and qualifier", () => {
  const queries = buildQueries("Dexcom K0553 price?", plan);
  assertEquals(queries[0], "Dexcom K0553 price?");
  assert(queries.some((query) => query.includes("K0553")));
  assert(queries.some((query) => query.includes("price")));
});

Deno.test("relationship hints cover natural documentation and specialty requests", () => {
  const requestHints = relationshipQueryHints("شو البيانات المطلوبة لطلب CGM؟");
  assert(
    requestHints.some((hint) => hint.includes("requirements for coverage")),
  );
  const specialtyHints = relationshipQueryHints("Who can prescribe Drug A?");
  assert(specialtyHints.some((hint) => hint.includes("eligible specialties")));
});

Deno.test("an explicit entity isolates its owning documents", () => {
  const matching = candidate("a", "d1", "Filgrastim | Specialty: Hematology");
  matching.document_title = "Filgrastim policy";
  const foreign = candidate("b", "d2", "Approved uses | Specialty: Neurology");
  foreign.document_title = "Other medicine";
  const selected = restrictToAnchoredDocuments([foreign, matching], {
    search_terms: ["Filgrastim specialties"],
    exact_literals: ["Filgrastim"],
    codes: [],
    important_qualifiers: ["specialties"],
  });
  assertEquals(selected.map((item) => item.document_id), ["d1"]);
});

Deno.test("hyphenated topics anchor the equivalent spaced document title", () => {
  const matching = candidate(
    "prostate",
    "prostate-doc",
    "Cabazitaxel requires prior Docetaxel treatment",
  );
  matching.document_title = "Prostate Cancer Pharmacological Treatment";
  const foreign = candidate(
    "cgm",
    "cgm-doc",
    "Prior authorization or monitoring evidence may be required",
  );
  foreign.document_title = "Continuous Glucose Monitoring";
  const selected = restrictToAnchoredDocuments([foreign, matching], {
    search_terms: ["prostate cancer", "prior treatment"],
    exact_literals: [
      "prostate-cancer treatment policy",
      "prior treatment or monitoring evidence",
    ],
    codes: [],
    important_qualifiers: ["required"],
  });
  assertEquals(selected.map((item) => item.document_id), ["prostate-doc"]);
});

Deno.test("document-local expansion cannot reintroduce a foreign policy", () => {
  const matching = candidate(
    "initial-prostate",
    "prostate-doc",
    "Prostate cancer medicine requirements",
  );
  matching.document_title = "Prostate Cancer Pharmacological Treatment";
  const foreignExpansion = candidate(
    "expanded-cgm",
    "cgm-doc",
    "Prior treatment or monitoring evidence",
  );
  foreignExpansion.document_title = "Continuous Glucose Monitoring";
  const merged = mergeCandidatesWithinAnchors(
    [matching],
    [foreignExpansion],
    {
      search_terms: ["prostate cancer", "prior treatment"],
      exact_literals: ["prostate-cancer treatment policy"],
      codes: [],
      important_qualifiers: ["monitoring evidence"],
    },
  );
  assertEquals(merged.map((item) => item.document_id), ["prostate-doc"]);
});

Deno.test("a weak relationship literal cannot compete with a stronger title anchor", () => {
  const matching = candidate("pcos", "pcos-doc", "PCOS eligibility branches");
  matching.document_title = "PCOS Management External Instruction";
  const foreign = candidate(
    "revision",
    "foreign-doc",
    "Revision history changes eligibility wording",
  );
  foreign.document_title = "Unrelated Medicine Update";
  const selected = restrictToAnchoredDocuments([foreign, matching], {
    search_terms: ["PCOS clinical qualifier"],
    exact_literals: [
      "PCOS management policy",
      "clinical qualifier changes eligibility for listed medicine",
    ],
    codes: [],
    important_qualifiers: ["eligibility"],
  });
  assertEquals(selected.map((item) => item.document_id), ["pcos-doc"]);
});

Deno.test("multiple explicitly named subjects preserve all owning documents", () => {
  const classDocument = candidate(
    "class",
    "class-doc",
    "Filgrastim and Peg-filgrastim approved uses",
  );
  classDocument.document_title = "Filgrastim Peg filgrastim Indications";
  const productDocument = candidate(
    "product",
    "product-doc",
    "Filgrastim use to clinician specialty mapping",
  );
  productDocument.document_title = "Coverage of Filgrastim under Daman";
  const foreign = candidate("foreign", "foreign-doc", "Other medicine");
  foreign.document_title = "Unrelated Policy";
  const selected = restrictToAnchoredDocuments(
    [foreign, classDocument, productDocument],
    {
      search_terms: ["approved uses", "specialties"],
      exact_literals: ["Filgrastim", "Peg-filgrastim"],
      codes: [],
      important_qualifiers: ["approved", "uses"],
    },
  );
  assertEquals(
    selected.map((item) => item.document_id),
    ["class-doc", "product-doc"],
  );
});

Deno.test("refined search preserves the original subject contract", () => {
  const combined = combineSearchPlans(
    {
      search_terms: ["Omalizumab CSU"],
      exact_literals: ["Omalizumab in CSU"],
      codes: [],
      important_qualifiers: ["continuation"],
    },
    {
      search_terms: ["refill response"],
      exact_literals: [],
      codes: [],
      important_qualifiers: ["initiation versus continuation"],
    },
  );
  assert(combined.exact_literals.includes("Omalizumab in CSU"));
  assert(combined.search_terms.includes("refill response"));
  assert(combined.important_qualifiers.includes("continuation"));
});

Deno.test("revision and denial noise is demoted unless the question asks for it", () => {
  const row = {
    unit_type: "text_chunk",
    section_title: "Revision history and denial rationale",
    table_title: null,
    retrieval_text: "Dexcom K0553 price was revised.",
  };
  const ordinary = rankingAdjustment(row, "What is the Dexcom price?", plan);
  const requested = rankingAdjustment(
    row,
    "What denial or revision applies to Dexcom?",
    plan,
  );
  assert(requested > ordinary);
});

Deno.test("table of contents cannot outrank an answer-bearing policy page", () => {
  const localPlan = {
    search_terms: ["prostate cancer prior treatment"],
    exact_literals: ["prostate cancer"],
    codes: [],
    important_qualifiers: ["prior treatment"],
  };
  const contents = rankingAdjustment(
    {
      unit_type: "page",
      section_title: "Table of Contents",
      retrieval_text: "Table of Contents Eligibility Coverage Criteria",
      document_title: "Prostate cancer policy",
    },
    "What prior treatment evidence is required?",
    localPlan,
  );
  const criteria = rankingAdjustment(
    {
      unit_type: "page",
      section_title: "Eligibility Coverage Criteria",
      retrieval_text:
        "Cabazitaxel is used after prior Docetaxel treatment fails.",
      document_title: "Prostate cancer policy",
    },
    "What prior treatment evidence is required?",
    localPlan,
  );
  assert(criteria > contents);
});

Deno.test("one structured record containing subject and qualifier is preferred", () => {
  const complete = rankingAdjustment(
    {
      unit_type: "table_row",
      section_title: "Pricing",
      table_title: "Device prices",
      retrieval_text: "Dexcom | K0553 | price 10",
    },
    "Dexcom K0553 price?",
    plan,
  );
  const nearby = rankingAdjustment(
    {
      unit_type: "table_row",
      section_title: "Pricing",
      table_title: "Device prices",
      retrieval_text: "Other device | price 10",
    },
    "Dexcom K0553 price?",
    plan,
  );
  assert(complete > nearby);
});

Deno.test("answer-bearing relationship text outranks a nearby table under the same section", () => {
  const continuation = rankingAdjustment(
    {
      unit_type: "page",
      section_title: "Continued Therapy",
      retrieval_text:
        "Document: Drug A Section: Continued Therapy Content: continued therapy requires documented response",
      document_title: "Drug A",
    },
    "What is required for continued Drug A therapy?",
    {
      search_terms: ["Drug A continuation requirement"],
      exact_literals: ["Drug A"],
      codes: [],
      important_qualifiers: ["continued therapy", "requirement"],
    },
  );
  const nearbySpecialty = rankingAdjustment(
    {
      unit_type: "table_row",
      section_title: "Continued Therapy",
      table_title: "Eligible Specialties",
      retrieval_text:
        "Document: Drug A Section: Continued Therapy Content: Eligible Specialty: Neurology",
      document_title: "Drug A",
    },
    "What is required for continued Drug A therapy?",
    {
      search_terms: ["Drug A continuation requirement"],
      exact_literals: ["Drug A"],
      codes: [],
      important_qualifiers: ["continued therapy", "requirement"],
    },
  );
  assert(continuation > nearbySpecialty);
});

Deno.test("sibling table rows are consolidated without losing their mappings", () => {
  const first = candidate("r1", "d1", "Use A | Specialty: Oncology", 1.2);
  first.parent_unit_id = "table-1";
  first.sibling_order = 1;
  const second = candidate("r2", "d1", "Use B | Specialty: Hematology", 1.1);
  second.parent_unit_id = "table-1";
  second.sibling_order = 2;
  const packet = buildEvidencePacket([first, second]);
  assertEquals(packet.length, 1);
  assert(packet[0].text.includes("Use A | Specialty: Oncology"));
  assert(packet[0].text.includes("Use B | Specialty: Hematology"));
  assert(packet[0].text.includes("CLOSED TABLE ROW 1 START"));
  assert(packet[0].text.includes("CLOSED TABLE ROW 2 END"));
});

Deno.test("relationship packets omit silent sibling rows and duplicate narrative", () => {
  const silent = candidate(
    "silent",
    "d1",
    "Chemotherapy Drug: Drug A | Medical Necessity: metastatic disease",
    1.1,
  );
  silent.parent_unit_id = "therapy-table";
  silent.sibling_order = 1;
  const prior = candidate(
    "prior",
    "d1",
    "Chemotherapy Drug: Drug B | previously treated with Drug A | code required to validate administration",
    1,
  );
  prior.parent_unit_id = "therapy-table";
  prior.sibling_order = 2;
  const page = candidate(
    "page-copy",
    "d1",
    "Drug A has no prior text. Drug B was previously treated with Drug A.",
    1.3,
  );
  page.unit_type = "page";
  page.row_from = null;
  page.row_to = null;
  const packet = buildEvidencePacket(
    [page, silent, prior],
    "What prior treatment or monitoring evidence is required?",
  );
  assertEquals(packet.length, 1);
  assert(packet[0].text.includes("Drug B"));
  assertFalse(packet[0].text.includes("Chemotherapy Drug: Drug A |"));
  assertFalse(packet.some((item) => item.search_unit_id === "page-copy"));
});

Deno.test("evidence packet keeps independent approved records with stable IDs", () => {
  const packet = buildEvidencePacket([
    candidate("a", "d1", "Dexcom | K0553 | price 10"),
    candidate("b", "d2", "Unrelated approved rule"),
  ]);
  assertEquals(packet.map((item) => item.evidence_id), ["E1", "E2"]);
  assertEquals(packet[0].text, "Dexcom | K0553 | price 10");
});

Deno.test("administration questions prioritize a structured dose-frequency table", () => {
  const narrative = candidate(
    "page",
    "d1",
    "Medicine is administered by subcutaneous injection.",
    1.2,
  );
  narrative.unit_type = "page";
  narrative.row_from = null;
  narrative.row_to = null;
  const table = candidate(
    "dose-table",
    "d1",
    "Generic: Drug A | Dose Frequency: 10 mg every 2 weeks",
    .8,
  );
  table.unit_type = "table";
  table.table_title = "Generic / Dose Strength / Dose Frequency";
  table.row_from = null;
  table.row_to = null;
  const packet = buildEvidencePacket(
    [narrative, table],
    "How is the medicine administered?",
    1,
  );
  assertEquals(packet[0].search_unit_id, "dose-table");
});

Deno.test("long answer-bearing pages are not clipped before later criteria", () => {
  const longText = `Start ${"x".repeat(3_500)} LATER COVERAGE CRITERION`;
  const packet = buildEvidencePacket([
    candidate("long", "d1", longText),
  ]);
  assert(packet[0].text.includes("LATER COVERAGE CRITERION"));
});

Deno.test("duplicate page narratives collapse while an independent table remains", () => {
  const page = candidate("page", "d1", "Complete continuation page", 1);
  page.unit_type = "page";
  page.row_from = null;
  page.row_to = null;
  const section = candidate(
    "section",
    "d1",
    "Continuation section duplicate",
    1.05,
  );
  section.unit_type = "section";
  section.row_from = null;
  section.row_to = null;
  const table = candidate("table", "d1", "Use A | Specialty A", .9);
  table.unit_type = "table";
  table.row_from = null;
  table.row_to = null;
  const packet = buildEvidencePacket([section, page, table]);
  assertEquals(packet.length, 2);
  assert(packet.some((item) => item.text === "Complete continuation page"));
  assert(packet.some((item) => item.text === "Use A | Specialty A"));
});

Deno.test("candidate merging does not combine different logical rows", () => {
  const merged = mergeCandidates(
    [candidate("a", "d1", "Drug A | dose 5 mg")],
    [candidate("b", "d1", "Drug B | dose 10 mg")],
  );
  assertEquals(merged.length, 2);
  assert(
    merged.every((item) =>
      !item.retrieval_text.includes("Drug A | dose 5 mg\nDrug B")
    ),
  );
});

Deno.test("repeated generic hits cannot accumulate past a stronger entity row", () => {
  const generic = candidate("generic", "d1", "Dose interval", 1);
  const anchored = candidate(
    "anchored",
    "d2",
    "Canakinumab dose interval",
    1.2,
  );
  const merged = mergeCandidates(
    [generic, anchored],
    [generic, generic, generic],
  );
  assertEquals(merged[0].search_unit_id, "anchored");
});
