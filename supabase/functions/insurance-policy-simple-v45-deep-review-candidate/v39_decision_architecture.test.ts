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
  buildDecisionObject,
  classifyRequestModality,
  deterministicFallback,
  nextRequiredStep,
  parseStepTherapy,
  renderDeterministicDecision,
} from "./decision.ts";
import {
  anchorRecoveryPlan,
  buildEvidencePacket,
  compatibleEvidenceOnly,
  inferPolicyScopeFromCandidates,
  isEvidenceCompatible,
  matchEntityAliases,
  rankPolicyScopeDocuments,
} from "./retrieval.ts";
import {
  appendRequestedSourceMetadata,
  detectDeterministicNumericConflict,
  evaluateBooleanExpression,
  evaluateBoundNumericFacts,
  hasUsableDoseSchedule,
} from "./structural.ts";
import type { EvidenceBlock, SearchCandidate, SearchPlan } from "./types.ts";

function candidate(
  id: string,
  documentId: string,
  title: string,
  text: string,
  options: Partial<SearchCandidate> = {},
): SearchCandidate {
  return {
    search_unit_id: id,
    document_id: documentId,
    document_title: title,
    file_name: `${title}.pdf`,
    unit_type: "text_chunk",
    page_from: 2,
    page_to: 2,
    row_from: null,
    row_to: null,
    section_title: "Policy rule",
    table_title: null,
    parent_unit_id: null,
    sibling_order: null,
    retrieval_text: text,
    source_chunk_ids: [id],
    metadata: {
      logical_source_key: `family:${documentId}`,
      source_version: "1",
      is_active: true,
    },
    score: 1,
    matched_queries: [title],
    ...options,
  };
}

function evidence(
  id: string,
  doc: string,
  text: string,
  options: Partial<EvidenceBlock> = {},
): EvidenceBlock {
  return {
    evidence_id: id,
    search_unit_id: id,
    document_id: doc,
    document_title: `${doc} Guideline`,
    file_name: `${doc}.pdf`,
    page_from: 4,
    page_to: 4,
    row_from: null,
    row_to: null,
    section_title: "Rule",
    table_title: null,
    logical_source_key: `family:${doc}`,
    source_version: "1",
    text,
    ...options,
  };
}

const plan: SearchPlan = {
  search_terms: [],
  exact_literals: [],
  codes: [],
  important_qualifiers: [],
  requested_relationships: [],
  ambiguity: "clear",
  missing_slots: [],
};

Deno.test("01 exact alias resolves its canonical policy family", () => {
  const alias = matchEntityAliases("ZetaBrand refill", [
    {
      alias: "ZetaBrand",
      normalized_alias: "zetabrand",
      canonical_name: "zetamab",
      entity_type: "medication",
      status: "active",
    },
  ]);
  assertEquals(alias.canonical_names, ["zetamab"]);
  const contract = buildDeterministicContract("ZetaBrand refill");
  contract.strong_anchor_terms.push(...alias.canonical_names);
  const scope = rankPolicyScopeDocuments("ZetaBrand zetamab refill", [
    { id: "z", title: "Zetamab Policy", file_name: "z.pdf", is_active: true },
    {
      id: "x",
      title: "General Refill Policy",
      file_name: "x.pdf",
      is_active: true,
    },
  ], contract);
  assertEquals(scope.document_ids, ["z"]);
});

Deno.test("02 strong entity rejects unrelated high score evidence", () => {
  const q = "Arbolex approval";
  const contract = buildDeterministicContract(q);
  const scope = {
    confident: true,
    document_ids: ["arb"],
    anchors: ["Arbolex"],
    logical_source_keys: ["family:arb"],
    reason: "test",
  };
  const kept = compatibleEvidenceOnly(
    q,
    [
      candidate("a", "arb", "Arbolex Policy", "Approval rule"),
      candidate("b", "other", "General Approval", "Arbolex words", {
        score: 99,
      }),
    ],
    scope,
    contract,
  );
  assertEquals(kept.map((row) => row.document_id), ["arb"]);
});

Deno.test("03 anchor recovery repairs a bad semantic search plan", () => {
  const q = "Arbolex pediatric dose";
  const recovery = anchorRecoveryPlan(q, {
    ...plan,
    search_terms: ["unrelated"],
  }, {
    confident: true,
    document_ids: ["arb"],
    anchors: ["Arbolex Policy"],
    logical_source_keys: [],
    reason: "test",
  }, buildDeterministicContract(q));
  assert(recovery.search_terms.some((term) => /arbolex/iu.test(term)));
  assert(recovery.requested_relationships?.some((term) => /dose/iu.test(term)));
});

Deno.test("04 pediatric age and weight rules combine across same-policy sections", () => {
  const q = "Novafer age 8 years weight 24 kg eligible?";
  const decision = buildDecisionObject(q, [
    evidence("E1", "nova", "Age must be >= 6 years."),
    evidence("E2", "nova", "Weight must be >= 20 kg."),
  ], buildDeterministicContract(q));
  assertEquals(decision.components.map((item) => item.result), [true, true]);
  assertEquals(decision.overall_result, "pass");
});

Deno.test("05 infant maintenance schedule remains valid without loading", () => {
  assert(
    hasUsableDoseSchedule(
      "Infant maintenance dose 8 mg every 4 weeks. No loading dose.",
    ),
  );
});

Deno.test("06 two thresholds split into mixed component result", () => {
  const q = "duration 20 days frequency 9 times: pass?";
  const result = buildDecisionObject(q, [
    evidence(
      "E1",
      "cluster",
      "Duration must be >= 14 days. Frequency must be <= 8 times.",
    ),
  ], buildDeterministicContract(q));
  assertEquals(result.overall_result, "mixed");
});

Deno.test("07 mixed renderer never starts with global yes", () => {
  const q = "score 12 and weight 40 kg pass?";
  const decision = buildDecisionObject(q, [
    evidence("E1", "mix", "Score must be >= 10. Weight must be >= 50 kg."),
  ], buildDeterministicContract(q));
  assertFalse(
    /^(?:yes|no)\b/iu.test(renderDeterministicDecision(q, decision) ?? ""),
  );
});

Deno.test("08 exact 299 does not meet minimum 300", () =>
  assertEquals(
    evaluateBoundNumericFacts("score 299", "Score must be >= 300.")[0].result,
    false,
  ));
Deno.test("09 exact 10 does not meet greater than 10", () =>
  assertEquals(
    evaluateBoundNumericFacts("score 10", "Score must be > 10.")[0].result,
    false,
  ));
Deno.test("10 exact 10.6 exceeds maximum 10.5", () =>
  assertEquals(
    evaluateBoundNumericFacts("score 10.6", "Score must be <= 10.5.")[0].result,
    false,
  ));

Deno.test("11 class-level reassessment scope needs no medicine", () => {
  const scope = rankPolicyScopeDocuments("LUMA-class reassessment interval", [
    {
      id: "l",
      title: "LUMA-class Policy",
      file_name: "l.pdf",
      is_active: true,
    },
    { id: "g", title: "General Policy", file_name: "g.pdf", is_active: true },
  ], buildDeterministicContract("LUMA-class reassessment interval"));
  assertEquals(scope.document_ids, ["l"]);
});

Deno.test("12 equal member rules return shared rule", () =>
  assertEquals(
    resolveMaterialAmbiguity([
      { id: "a", confidence: .9, requested_rule_signature: "reassess:6months" },
      { id: "b", confidence: .9, requested_rule_signature: "reassess:6months" },
    ]).action,
    "shared_rule",
  ));

Deno.test("13 different member rules require clarification", () =>
  assertEquals(
    resolveMaterialAmbiguity([
      { id: "a", confidence: .9, requested_rule_signature: "reassess:6months" },
      {
        id: "b",
        confidence: .9,
        requested_rule_signature: "reassess:12months",
      },
    ]).action,
    "clarify",
  ));

Deno.test("14 distinctive relationship selects one policy scope", () => {
  const q = "Does continuation require current non-smoker status?";
  const inferred = inferPolicyScopeFromCandidates(q, [
    candidate(
      "a",
      "alpha",
      "Alpha",
      "Continuation requires current non-smoker status.",
    ),
    candidate(
      "b",
      "beta",
      "Beta",
      "Continuation requires response documentation.",
    ),
  ], buildDeterministicContract(q));
  assertEquals(inferred?.document_ids, ["alpha"]);
});

Deno.test("15 form signature identifies approved prerequisite form", () => {
  const q = "HBV HCV HIV history and drug from to duration fields";
  const inferred = inferPolicyScopeFromCandidates(q, [
    candidate(
      "a",
      "bio-form",
      "Prerequisite Form",
      "HBV HCV HIV history; current treatment; laboratory reports; drug from to duration.",
    ),
    candidate("b", "hep-policy", "Hepatitis Policy", "Treatment criteria."),
  ], buildDeterministicContract(q));
  assertEquals(inferred?.document_ids, ["bio-form"]);
});

Deno.test("16 yes form field enforces dependent treatment and lab fields", () => {
  const q =
    "Infection history marked yes; current treatment blank; laboratory reports attached. Is this section complete?";
  const decision = buildDecisionObject(q, [
    evidence(
      "E1",
      "form",
      "Infection history = Yes -> current treatment, laboratory reports.",
    ),
  ], buildDeterministicContract(q));
  assertEquals(decision.decision_type, "form_completeness");
  assertEquals(decision.overall_result, "fail");
});

Deno.test("17 OR accepts the single satisfied branch", () =>
  assertEquals(
    evaluateBooleanExpression("A OR B", { A: true, B: false }),
    true,
  ));
Deno.test("18 AND rejects one missing branch", () =>
  assertEquals(
    evaluateBooleanExpression("A AND B", { A: true, B: false }),
    false,
  ));

Deno.test("19 consideration and automatic approval are distinct modalities", () => {
  assertEquals(
    classifyRequestModality("Can this be considered?"),
    "can_be_considered",
  );
  assertEquals(
    classifyRequestModality("Is this automatically approved?"),
    "automatic_approval",
  );
});

Deno.test("20 ordered therapy returns the first incomplete step", () => {
  const sequence = parseStepTherapy(
    "Step 1: Therapy A. Step 2: Therapy B. Step 3: Therapy C.",
  );
  assertEquals(nextRequiredStep(sequence, ["Therapy A"]), "Therapy B");
});

Deno.test("21 explicit antiemetic-like entity rejects unrelated policy", () => {
  const q = "Nauselex pregnancy next step";
  const contract = buildDeterministicContract(q);
  const scope = {
    confident: true,
    document_ids: ["nauselex"],
    anchors: ["Nauselex"],
    logical_source_keys: [],
    reason: "test",
  };
  assertFalse(
    isEvidenceCompatible(
      q,
      candidate(
        "x",
        "migraine",
        "Migraine Biologic Policy",
        "Pregnancy next step",
      ),
      scope,
      contract,
    ),
  );
});

Deno.test("22 dose and monitoring survive as separate same-family sections", () => {
  const packet = buildEvidencePacket([
    candidate(
      "d",
      "acid",
      "Acid Class Policy",
      "Dose escalation follows standard-dose failure.",
    ),
    candidate(
      "m",
      "acid",
      "Acid Class Policy",
      "Safety monitoring is required after escalation.",
      { page_from: 7, page_to: 7 },
    ),
  ], "Acid class dose escalation and monitoring");
  assertEquals(packet.length, 2);
});

Deno.test("23 no-evidence response waits for anchor recovery", () => {
  const recovery = anchorRecoveryPlan("Vireximab lab requirement", plan, {
    confident: true,
    document_ids: ["v"],
    anchors: ["Vireximab"],
    logical_source_keys: [],
    reason: "test",
  }, buildDeterministicContract("Vireximab lab requirement"));
  assert(recovery.exact_literals.includes("vireximab"));
});

Deno.test("24 compact brand indication age remains strongly scoped", () => {
  const contract = buildDeterministicContract("Noviq asthma age 9");
  assert(contract.strong_anchor_terms.includes("noviq"));
  assert(contract.strong_anchor_terms.includes("asthma"));
});

Deno.test("25 compact drug lab months preserves numeric relation", () => {
  const contract = buildDeterministicContract(
    "Zetamab IgE 35 atopy age 13 months",
  );
  assert(contract.strong_anchor_terms.includes("zetamab"));
  assert(contract.numeric_comparisons.length === 0);
});

Deno.test("26 engine rule refuses to assume missing entity", () => {
  const q = "Should the system assume an unstated medicine?";
  const rule = classifySystemRuleQuestion(q)!;
  assertEquals(rule, "missing_entity");
  assert(/does not assume/iu.test(systemRuleAnswer(q, rule)));
});

Deno.test("27 engine alias tie requires confirmation", () =>
  assertEquals(
    resolveMaterialAmbiguity([
      { id: "x", confidence: .8, requested_rule_signature: "dose-x" },
      { id: "y", confidence: .8, requested_rule_signature: "dose-y" },
    ]).action,
    "clarify",
  ));

Deno.test("28 generic alias behavior bypasses clinical facts", () =>
  assertEquals(
    classifySystemRuleQuestion(
      "What should the engine do when two aliases tie?",
    ),
    "alias_ambiguity",
  ));
Deno.test("29 duplicate PDF and DOCX invoke dedup engine rule", () =>
  assertEquals(
    classifySystemRuleQuestion(
      "Should the system count duplicate PDF and DOCX copies separately?",
    ),
    "logical_source_deduplication",
  ));

Deno.test("30 unresolved active conflict is deterministic", () => {
  const ids = detectDeterministicNumericConflict([
    evidence("E1", "a", "Score must be >= 7."),
    evidence("E2", "b", "Score must be >= 8."),
  ]);
  assertEquals(ids, ["E1", "E2"]);
});

Deno.test("31 generic conflict behavior is answered directly", () =>
  assertEquals(
    classifySystemRuleQuestion(
      "Should the engine choose a higher scoring chunk when active sources conflict?",
    ),
    "active_source_conflict",
  ));

Deno.test("32 invalid model citation falls back to decision citations", () => {
  const q = "score 9 pass?";
  const packet = [evidence("E1", "score", "Score must be >= 10.")];
  const fallback = deterministicFallback(
    q,
    buildDecisionObject(q, packet, buildDeterministicContract(q)),
    packet,
  )!;
  assertEquals(fallback.evidence_ids, ["E1"]);
  assertFalse(fallback.answer.includes("E99"));
});

Deno.test("33 invalid model polarity cannot alter deterministic lead", () => {
  const q = "score 9 pass?";
  const packet = [evidence("E1", "score", "Score must be >= 10.")];
  const fallback = deterministicFallback(
    q,
    buildDecisionObject(q, packet, buildDeterministicContract(q)),
    packet,
  )!;
  assert(/^No\./u.test(fallback.answer));
});

Deno.test("34 malformed model response still has deterministic fallback", () => {
  const q = "score 11 pass?";
  const packet = [evidence("E1", "score", "Score must be >= 10.")];
  assert(
    deterministicFallback(
      q,
      buildDecisionObject(q, packet, buildDeterministicContract(q)),
      packet,
    )?.answer,
  );
});

Deno.test("35 deterministic validation failure never maps to unavailable", () => {
  const q = "score 11 pass?";
  const packet = [evidence("E1", "score", "Score must be >= 10.")];
  const fallback = deterministicFallback(
    q,
    buildDecisionObject(q, packet, buildDeterministicContract(q)),
    packet,
  );
  assert(fallback && fallback.evidence_ids.length === 1);
});

Deno.test("36 explicit source page is appended deterministically", () => {
  const packet = [
    evidence("E1", "alpha", "Rule applies.", { page_from: 8, page_to: 8 }),
  ];
  const answer = appendRequestedSourceMetadata(
    "Give source and page",
    "The rule applies.",
    ["E1"],
    packet,
  );
  assert(answer.includes("alpha Guideline"));
  assert(answer.includes("page 8"));
});

Deno.test("37 inherited conflict remains distinct-source aware", () => {
  assertEquals(
    detectDeterministicNumericConflict([
      evidence("E1", "one", "HbA1c must be >= 7%."),
      evidence("E2", "two", "HbA1c must be >= 8%."),
    ]).length,
    2,
  );
});

Deno.test("38 inherited biomarker OR branch remains correct", () =>
  assertEquals(
    evaluateBooleanExpression("(EOS AND ATOPY) OR IGE", {
      EOS: true,
      ATOPY: false,
      IGE: true,
    }),
    true,
  ));
Deno.test("39 inherited negative criterion remains independent", () =>
  assertEquals(
    evaluateBooleanExpression("BIOMARKER AND NONSMOKER", {
      BIOMARKER: true,
      NONSMOKER: false,
    }),
    false,
  ));

Deno.test("40 inherited duration frequency result stays mixed", () => {
  const q = "duration 20 days and frequency 9 times pass?";
  const evaluations = evaluateBoundNumericFacts(
    q,
    "Duration must be >= 14 days. Frequency must be <= 8 times.",
  );
  assertEquals(evaluations.map((item) => item.result), [true, false]);
});
