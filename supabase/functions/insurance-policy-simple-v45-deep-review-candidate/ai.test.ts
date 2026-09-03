import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeDecision,
  normalizeEvidenceAssessment,
  normalizeSearchPlan,
  parseJsonObject,
} from "./ai.ts";

Deno.test("planner preserves relationship while suppressing needless ambiguity", () => {
  assertEquals(
    normalizeSearchPlan({
      search_terms: ["refill criteria"],
      exact_literals: ["Drug A"],
      codes: [],
      important_qualifiers: ["refill"],
      requested_relationships: ["refill eligibility"],
      ambiguity: "clarify",
      missing_slots: [],
      ambiguity_reason: "The wording is short.",
      clarification_question: "Which indication do you mean?",
    }, "Can Drug A be refilled?"),
    {
      search_terms: ["refill criteria"],
      exact_literals: ["Drug A"],
      codes: [],
      important_qualifiers: ["refill"],
      requested_relationships: ["refill eligibility"],
      ambiguity: "clear",
      missing_slots: [],
      ambiguity_reason: null,
      clarification_question: null,
    },
  );
});

Deno.test("explicit entity plus requested relationship cannot be over-clarified", () => {
  const plan = normalizeSearchPlan({
    search_terms: ["continuation evidence"],
    exact_literals: ["Crizanlizumab"],
    codes: [],
    important_qualifiers: ["continuation"],
    requested_relationships: ["continuation"],
    ambiguity: "clarify",
    missing_slots: [],
    ambiguity_reason: "Could be refill.",
    clarification_question: "Do you mean continuation or refill?",
  }, "What continuation evidence is required for Crizanlizumab?");
  assertEquals(plan.ambiguity, "clear");
});

Deno.test("evidence assessment normalizes one bounded refinement", () => {
  assertEquals(
    normalizeEvidenceAssessment({
      action: "search_again",
      refined_search: {
        search_terms: ["continuation response criteria"],
        exact_literals: ["Drug A"],
        codes: [],
        important_qualifiers: ["continuation"],
        requested_relationships: ["continuation clinical response"],
        ambiguity: "clear",
        missing_slots: [],
        ambiguity_reason: null,
        clarification_question: null,
      },
      clarification_question: null,
      missing_slots: [],
      ambiguity_reason: null,
      conflict_evidence_ids: [],
      reason: "The packet is topical but lacks response criteria.",
    }, "What supports continuation of Drug A?"),
    {
      action: "search_again",
      refined_search: {
        search_terms: ["continuation response criteria"],
        exact_literals: ["Drug A"],
        codes: [],
        important_qualifiers: ["continuation"],
        requested_relationships: ["continuation clinical response"],
        ambiguity: "clear",
        missing_slots: [],
        ambiguity_reason: null,
        clarification_question: null,
      },
      clarification_question: null,
      missing_slots: [],
      ambiguity_reason: "",
      conflict_evidence_ids: [],
      reason: "The packet is topical but lacks response criteria.",
    },
  );
});

Deno.test("clear short schedule question proceeds without restatement", () => {
  const plan = normalizeSearchPlan({
    search_terms: ["Omalizumab schedule"],
    exact_literals: ["Omalizumab", "asthma"],
    codes: [],
    important_qualifiers: ["asthma", "schedule"],
    requested_relationships: ["allowed schedule"],
    ambiguity: "clarify",
    missing_slots: ["relationship"],
    ambiguity_reason: "The question is short.",
    clarification_question: "Which schedule do you mean?",
  }, "Omalizumab for asthma — which schedule?");
  assertEquals(plan.ambiguity, "clear");
  assertEquals(plan.missing_slots, []);
  assertEquals(plan.clarification_question, null);
});

Deno.test("bare lab value still requires a real missing slot", () => {
  const plan = normalizeSearchPlan({
    search_terms: ["HbA1c threshold"],
    exact_literals: ["HbA1c"],
    codes: [],
    important_qualifiers: ["6.5%"],
    requested_relationships: [],
    ambiguity: "clarify",
    missing_slots: ["entity", "relationship"],
    ambiguity_reason:
      "No medication, disease, or requested policy relationship.",
    clarification_question: "Which medication or policy question is this for?",
  }, "HbA1c 6.5%");
  assertEquals(plan.ambiguity, "clarify");
  assertEquals(plan.missing_slots, ["relationship"]);
});

Deno.test("materially missing indication remains clarifiable", () => {
  const plan = normalizeSearchPlan({
    search_terms: ["Drug A dose"],
    exact_literals: ["Drug A"],
    codes: [],
    important_qualifiers: ["dose"],
    requested_relationships: ["dose"],
    ambiguity: "clarify",
    missing_slots: ["indication"],
    ambiguity_reason: "The approved dose differs by indication.",
    clarification_question: "Which indication is Drug A being used for?",
  }, "Drug A dose?");
  assertEquals(plan.ambiguity, "clarify");
  assertEquals(plan.missing_slots, ["indication"]);
});

Deno.test("uncertain entity resolution remains clarifiable", () => {
  const plan = normalizeSearchPlan({
    search_terms: ["Omali medicine"],
    exact_literals: ["Omali"],
    codes: [],
    important_qualifiers: ["covered"],
    requested_relationships: ["coverage"],
    ambiguity: "clarify",
    missing_slots: ["entity_resolution"],
    ambiguity_reason: "The spelling matches multiple products.",
    clarification_question: "Which medicine do you mean by Omali?",
  }, "Is Omali covered?");
  assertEquals(plan.ambiguity, "clarify");
  assertEquals(plan.missing_slots, ["entity_resolution"]);
});

Deno.test("evidence controller cannot re-clarify a complete intent without a missing slot", () => {
  const original = normalizeSearchPlan({
    search_terms: ["PPI specialty"],
    exact_literals: ["PPI"],
    codes: [],
    important_qualifiers: ["specialty"],
    requested_relationships: ["specialty eligibility"],
    ambiguity: "clear",
    missing_slots: [],
    ambiguity_reason: null,
    clarification_question: null,
  }, "PPI: who can prescribe it?");
  const assessment = normalizeEvidenceAssessment(
    {
      action: "clarify",
      refined_search: null,
      clarification_question: "Which prescribing rule do you mean?",
      missing_slots: [],
      ambiguity_reason: "The wording is short.",
      conflict_evidence_ids: [],
      reason: "The wording is short.",
    },
    "PPI: who can prescribe it?",
    original,
  );
  assertEquals(assessment.action, "answer");
  assertEquals(assessment.missing_slots, []);
});

Deno.test("search plan preserves only literals and codes present in the question", () => {
  assertEquals(
    normalizeSearchPlan({
      search_terms: ["Tepotinib", "MET exon 14 skipping"],
      exact_literals: ["Tepotinib", "Tepotinib"],
      codes: ["K0553"],
      important_qualifiers: ["continuation", "age 12"],
      ignored: "value",
    }, "Tepotinib age 12"),
    {
      search_terms: ["Tepotinib", "MET exon 14 skipping"],
      exact_literals: ["Tepotinib"],
      codes: [],
      important_qualifiers: ["continuation", "age 12"],
    },
  );
});

Deno.test("planner hallucinations cannot become exact retrieval anchors", () => {
  assertEquals(
    normalizeSearchPlan({
      search_terms: ["Bulevirtide continuation"],
      exact_literals: ["Bulevirtide", "Hepcludex"],
      codes: ["J05AX13"],
      important_qualifiers: ["continued therapy"],
    }, "What is required for continued Bulevirtide therapy?"),
    {
      search_terms: ["Bulevirtide continuation"],
      exact_literals: ["Bulevirtide"],
      codes: [],
      important_qualifiers: ["continued therapy"],
    },
  );
});

Deno.test("generic relationship words cannot become entity anchors", () => {
  assertEquals(
    normalizeSearchPlan({
      search_terms: ["Filgrastim specialties"],
      exact_literals: ["Filgrastim", "approved", "uses", "specialties"],
      codes: [],
      important_qualifiers: ["approved uses", "specialties"],
    }, "Which specialties are listed for the approved Filgrastim uses?"),
    {
      search_terms: ["Filgrastim specialties"],
      exact_literals: ["Filgrastim"],
      codes: [],
      important_qualifiers: ["approved uses", "specialties"],
    },
  );
});

Deno.test("restriction and exception remain qualifiers, not entity anchors", () => {
  assertEquals(
    normalizeSearchPlan({
      search_terms: ["eye lubricant coverage restriction"],
      exact_literals: ["restriction", "exception", "eye-lubricant"],
      codes: [],
      important_qualifiers: ["restriction", "exception"],
    }, "What restriction or exception applies to eye-lubricant coverage?"),
    {
      search_terms: ["eye lubricant coverage restriction"],
      exact_literals: ["eye-lubricant"],
      codes: [],
      important_qualifiers: ["restriction", "exception"],
    },
  );
});

Deno.test("semantic relationship phrases do not compete with an explicit topic anchor", () => {
  assertEquals(
    normalizeSearchPlan(
      {
        search_terms: ["PCOS management policy", "clinical qualifier"],
        exact_literals: [
          "PCOS management policy",
          "clinical qualifier",
          "eligibility",
          "medicine",
        ],
        codes: [],
        important_qualifiers: ["clinical qualifier that changes eligibility"],
      },
      "Under the PCOS management policy, which clinical qualifier changes eligibility for the listed medicine?",
    ),
    {
      search_terms: ["PCOS management policy", "clinical qualifier"],
      exact_literals: ["PCOS management policy"],
      codes: [],
      important_qualifiers: ["clinical qualifier that changes eligibility"],
    },
  );
});

Deno.test("prior-treatment wording does not become a cross-document anchor", () => {
  assertEquals(
    normalizeSearchPlan(
      {
        search_terms: ["prostate-cancer treatment policy", "prior treatment"],
        exact_literals: ["prostate-cancer treatment policy", "prior treatment"],
        codes: [],
        important_qualifiers: ["required evidence"],
      },
      "Under the prostate-cancer treatment policy, what prior treatment evidence is required?",
    ),
    {
      search_terms: ["prostate-cancer treatment policy", "prior treatment"],
      exact_literals: ["prostate-cancer treatment policy"],
      codes: [],
      important_qualifiers: ["required evidence"],
    },
  );
});

Deno.test("entity inside a natural phrase remains the only exact anchor", () => {
  assertEquals(
    normalizeSearchPlan(
      {
        search_terms: ["Dupilumab continuation"],
        exact_literals: ["initial Dupilumab period"],
        codes: [],
        important_qualifiers: ["required"],
      },
      "What continuation evidence is required after the initial Dupilumab period?",
    ),
    {
      search_terms: ["Dupilumab continuation"],
      exact_literals: ["initial Dupilumab period"],
      codes: [],
      important_qualifiers: ["required"],
    },
  );
});

Deno.test("generic Arabic question words cannot anchor unrelated documents", () => {
  assertEquals(
    normalizeSearchPlan({
      search_terms: ["تغطية الفيتامينات"],
      exact_literals: ["متى", "الفيتامينات", "مغطاة", "ثقة"],
      codes: [],
      important_qualifiers: ["coverage criteria"],
    }, "متى الفيتامينات تكون مغطاة لثقة؟"),
    {
      search_terms: ["تغطية الفيتامينات"],
      exact_literals: ["الفيتامينات", "ثقة"],
      codes: [],
      important_qualifiers: ["coverage criteria"],
    },
  );
});

Deno.test("provider fenced JSON is parsed", () => {
  assertEquals(parseJsonObject('```json\n{"action":"answer"}\n```'), {
    action: "answer",
  });
});

Deno.test("decision normalization is structural only", () => {
  const decision = normalizeDecision({
    action: "answer",
    answer: "Yes [E1]",
    evidence_ids: ["E1", "E1"],
    continuation_clinical: "NOT_APPLICABLE",
    continuation_documentation: "NOT_APPLICABLE",
    refined_search: null,
  });
  assertStrictEquals(decision.action, "answer");
  assertEquals(decision.evidence_ids, ["E1"]);
  assertStrictEquals(decision.answer, "Yes [E1]");
  assertStrictEquals(decision.continuation_clinical, "NOT_APPLICABLE");
  assertStrictEquals(decision.continuation_documentation, "NOT_APPLICABLE");
});
