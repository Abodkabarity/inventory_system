import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildDeterministicContract,
  classifySystemRuleQuestion,
  resolveMaterialAmbiguity,
  systemRuleAnswer,
} from "./contract.ts";
import {
  ageWeightBandPriority,
  buildEvidencePacket,
  entityPolicyCompatibilityScore,
  findDelegatedDocumentIds,
  inferPolicyScopeFromCandidates,
  rankPolicyScopeDocuments,
} from "./retrieval.ts";
import {
  appendRequestedSourceMetadata,
  detectDeterministicNumericConflict,
  deterministicComponentLead,
  deterministicReasoningSummary,
  evaluateBooleanExpression,
  evaluateBoundNumericFacts,
  extractFormDependencies,
  hasUsableDoseSchedule,
  sharedNumericRuleAcrossEvidence,
  validateAnswerSemantics,
} from "./structural.ts";
import type { EvidenceBlock, SearchCandidate } from "./types.ts";

function row(
  id: string,
  doc: string,
  title: string,
  text: string,
  score = 1,
): SearchCandidate {
  return {
    search_unit_id: id,
    document_id: doc,
    document_title: title,
    file_name: `${title}.pdf`,
    unit_type: "table_row",
    page_from: 2,
    page_to: 2,
    row_from: 1,
    row_to: 1,
    section_title: "Criteria",
    table_title: "Rules",
    parent_unit_id: null,
    sibling_order: 1,
    retrieval_text: text,
    source_chunk_ids: [id],
    metadata: { logical_source_key: `logical:${doc}`, source_version: "1" },
    score,
    matched_queries: [title],
  };
}

function ev(id: string, doc: string, text: string): EvidenceBlock {
  return {
    evidence_id: id,
    search_unit_id: id,
    document_id: doc,
    document_title: `${doc} Policy`,
    file_name: `${doc}.pdf`,
    page_from: 3,
    page_to: 3,
    row_from: null,
    row_to: null,
    section_title: "Criteria",
    table_title: null,
    logical_source_key: `logical:${doc}`,
    source_version: "1",
    text,
  };
}

Deno.test("01 explicit medicine dominates unrelated generic policy", () => {
  const q = "Aureximab refill requirement?";
  const c = buildDeterministicContract(q);
  const named = row("a", "a", "Aureximab", "Refill evidence required");
  const generic = row(
    "b",
    "b",
    "Wheelchair Approval Form",
    "Patient approval requirement",
  );
  assert(
    entityPolicyCompatibilityScore(q, named, c) >
      entityPolicyCompatibilityScore(q, generic, c),
  );
});

Deno.test("02 class-level policy binding", () => {
  const q = "GLP-1 refill?";
  const scope = rankPolicyScopeDocuments(q, [
    {
      id: "g",
      title: "GLP-1 Class Policy",
      file_name: "glp.pdf",
      is_active: true,
    },
    {
      id: "x",
      title: "General Approval Policy",
      file_name: "general.pdf",
      is_active: true,
    },
  ], buildDeterministicContract(q));
  assertEquals(scope.document_ids, ["g"]);
});

Deno.test("03 only strong entity candidate survives generic overlap", () => {
  const q = "Velunimab current treatment approval";
  const scope = rankPolicyScopeDocuments(q, [
    { id: "v", title: "Velunimab Policy", file_name: "v.pdf", is_active: true },
    {
      id: "p",
      title: "Current Treatment Approval",
      file_name: "p.pdf",
      is_active: true,
    },
  ], buildDeterministicContract(q));
  assertEquals(scope.document_ids, ["v"]);
});

Deno.test("04 genuine equal interpretations with different rules clarify", () => {
  assertEquals(
    resolveMaterialAmbiguity([
      { id: "a", confidence: .9, requested_rule_signature: ">=10" },
      { id: "b", confidence: .9, requested_rule_signature: ">=12" },
    ]).action,
    "clarify",
  );
});

Deno.test("05 equal interpretations with common class rule answer shared rule", () => {
  assertEquals(
    resolveMaterialAmbiguity([
      { id: "a", confidence: .9, requested_rule_signature: "reassess:6months" },
      { id: "b", confidence: .9, requested_rule_signature: "reassess:6months" },
    ]).action,
    "shared_rule",
  );
});

Deno.test("06 unique distinctive rule identifies policy without medicine", () => {
  const q =
    "Is current non-smoker status required for continuation eligibility?";
  const contract = buildDeterministicContract(q);
  const scope = inferPolicyScopeFromCandidates(q, [
    row(
      "a",
      "alpha",
      "Alpha",
      "Continuation requires current non-smoker status and review.",
    ),
    row("b", "beta", "Beta", "Continuation requires response documentation."),
  ], contract);
  assertEquals(scope?.document_ids, ["alpha"]);
});

Deno.test("07 form signature identifies one form", () => {
  const q =
    "HBV HCV HIV history, current treatment, laboratory reports, drug from to duration fields?";
  const scope = inferPolicyScopeFromCandidates(q, [
    row(
      "a",
      "viral-form",
      "Viral History Form",
      "HBV HCV HIV history. If Yes: current treatment and laboratory reports. Drug from to duration.",
    ),
    row("b", "other-form", "Mobility Form", "Wheelchair dimensions."),
  ], buildDeterministicContract(q));
  assertEquals(scope?.document_ids, ["viral-form"]);
});

Deno.test("08 dependent form fields remain grouped", () => {
  assertEquals(
    extractFormDependencies(
      "Infection history = Yes -> current treatment, current laboratory reports.",
    ),
    [{
      trigger: "Infection history",
      required: ["current treatment", "current laboratory reports"],
    }],
  );
});

Deno.test("09 mixed duration and frequency results", () => {
  const out = evaluateBoundNumericFacts(
    "duration 20 days and frequency 9 times: do both pass?",
    "Duration must be >= 14 days. Frequency must be <= 8 times.",
  );
  assertEquals(out.map((x) => x.result), [true, false]);
});

Deno.test("10 age and weight bind separately", () => {
  const out = evaluateBoundNumericFacts(
    "age 11 years weight 45 kg",
    "Age must be >= 10 years. Weight must be >= 50 kg.",
  );
  assertEquals(out.map((x) => x.metric), ["age", "weight"]);
  assertEquals(out.map((x) => x.result), [true, false]);
});

Deno.test("11 two biomarker branches evaluate without cross-binding", () => {
  assertEquals(
    evaluateBooleanExpression("(EOS AND ATOPY) OR IGE", {
      EOS: true,
      ATOPY: false,
      IGE: true,
    }),
    true,
  );
});

Deno.test("12 A OR B accepts A alone", () =>
  assertEquals(
    evaluateBooleanExpression("A OR B", { A: true, B: false }),
    true,
  ));
Deno.test("13 A AND B rejects A alone", () =>
  assertEquals(
    evaluateBooleanExpression("A AND B", { A: true, B: false }),
    false,
  ));
Deno.test("14 nested boolean condition", () =>
  assertEquals(
    evaluateBooleanExpression("(A AND B) OR (C AND D)", {
      A: true,
      B: false,
      C: true,
      D: true,
    }),
    true,
  ));

Deno.test("15 pediatric row outranks adult row", () => {
  assert(
    ageWeightBandPriority(
      "age 8 years weight 24 kg",
      "Pediatric age 6-11 years weight 20-29 kg",
    ) >
      ageWeightBandPriority(
        "age 8 years weight 24 kg",
        "Adult age >= 18 years",
      ),
  );
});

Deno.test("16 maintenance schedule is usable without loading dose", () => {
  assert(
    hasUsableDoseSchedule(
      "No loading dose. Maintenance dose 20 mg every 4 weeks.",
    ),
  );
});

Deno.test("17 dose overview follows delegated safety monitoring source", () => {
  const overview = row(
    "a",
    "ppi",
    "Acid Suppression Overview",
    "For double-dose safety monitoring, consult the Acid Suppression Safety appendix.",
  );
  assertEquals(
    findDelegatedDocumentIds([overview], [
      {
        id: "s",
        title: "Acid Suppression Safety Appendix",
        file_name: "s.xlsx",
      },
      { id: "x", title: "Migraine Monitoring", file_name: "x.pdf" },
    ]),
    ["s"],
  );
});

Deno.test("18 strong PPI anchor rejects CGRP", () => {
  const q = "PPI double dose monitoring?";
  const c = buildDeterministicContract(q);
  assert(
    entityPolicyCompatibilityScore(
      q,
      row("p", "p", "PPI Policy", "Double dose monitoring"),
      c,
    ) >
      entityPolicyCompatibilityScore(
        q,
        row("c", "c", "CGRP Policy", "Dose monitoring"),
        c,
      ),
  );
});

Deno.test("19 class reassessment interval shared across members", () => {
  assertEquals(
    sharedNumericRuleAcrossEvidence([
      ev("E1", "member-a", "Reassessment interval must be >= 6 months."),
      ev("E2", "member-b", "Reassessment interval must be >= 6 months."),
    ]),
    "duration:>=:6:months",
  );
});

Deno.test("20 negative criterion remains independent", () => {
  assertEquals(
    evaluateBooleanExpression("BIOMARKER AND NONSMOKER", {
      BIOMARKER: true,
      NONSMOKER: false,
    }),
    false,
  );
});

Deno.test("21 alias tie rule requires confirmation", () => {
  assertEquals(
    resolveMaterialAmbiguity([
      { id: "entity-a", confidence: .88, requested_rule_signature: "dose-a" },
      { id: "entity-b", confidence: .88, requested_rule_signature: "dose-b" },
    ]).action,
    "clarify",
  );
});

Deno.test("22 generic alias behavior question uses engine contract", () => {
  const q = "What should the engine do when a typo ties between two aliases?";
  const rule = classifySystemRuleQuestion(q);
  assertEquals(rule, "alias_ambiguity");
  assert(systemRuleAnswer(q, rule!).includes("asks the user"));
});

Deno.test("23 PDF DOCX logical duplicates count once", () => {
  const a = row("pdf", "a", "Alpha Guideline", "Age >= 10 years");
  const b = row("docx", "b", "Alpha Guideline", "Age >= 10 years");
  b.metadata = { ...a.metadata };
  assertEquals(buildEvidencePacket([a, b], "Alpha age").length, 1);
});

Deno.test("24 unresolved active-source conflict detected", () => {
  assertEquals(
    detectDeterministicNumericConflict([
      ev("E1", "authority-a", "HbA1c must be >= 7%."),
      ev("E2", "authority-b", "HbA1c must be >= 8%."),
    ]),
    ["E1", "E2"],
  );
});

Deno.test("25 source precedence engine rule", () => {
  const q =
    "How should the engine handle current and superseded source precedence?";
  assertEquals(classifySystemRuleQuestion(q), "source_precedence");
});

Deno.test("26 generic conflict behavior question", () => {
  const q = "What should the system do when two active sources conflict?";
  assert(
    systemRuleAnswer(q, classifySystemRuleQuestion(q)!).includes("CONFLICT"),
  );
});

Deno.test("27 exact boundary 299 does not satisfy >=300", () => {
  assertEquals(
    evaluateBoundNumericFacts("score 299", "Score must be >= 300.")[0].result,
    false,
  );
});

Deno.test("28 exact boundary 10 does not satisfy >10", () => {
  assertEquals(
    evaluateBoundNumericFacts("score 10", "Score must be > 10.")[0].result,
    false,
  );
});

Deno.test("29 exact boundary 10.6 does not satisfy <=10.5", () => {
  assertEquals(
    evaluateBoundNumericFacts("score 10.6", "Score must be <= 10.5.")[0].result,
    false,
  );
});

Deno.test("30 semantic validator rejects Yes followed by failed threshold", () => {
  const packet = [ev("E1", "alpha", "Age must be >= 10 years.")];
  const result = validateAnswerSemantics({
    question: "Age 9 years okay?",
    answer: "Yes. Minimum age is 10 years; age 9 does not meet it [E1].",
    evidenceIds: ["E1"],
    packet,
    contract: buildDeterministicContract("Age 9 years okay?"),
    scope: null,
  });
  assertFalse(result.valid);
});

Deno.test("31 mixed components cannot render global Yes or No", () => {
  const summary = deterministicReasoningSummary("age 11 years weight 45 kg", [
    ev("E1", "alpha", "Age must be >= 10 years. Weight must be >= 50 kg."),
  ]);
  assertEquals(summary.global_polarity, "MIXED");
  assertEquals(
    deterministicComponentLead(summary.numeric_comparisons),
    "age: passes; weight: fails.",
  );
});

Deno.test("32 source page request leads with exact metadata", () => {
  const answer = appendRequestedSourceMetadata(
    "Give source and page",
    "The rule applies [E1].",
    ["E1"],
    [ev("E1", "alpha", "Rule")],
  );
  assert(answer.includes("alpha Policy"));
  assert(answer.includes("page 3"));
});
