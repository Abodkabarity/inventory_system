import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildDeterministicContract,
  expandCompactPolicyQuestion,
  extractPatientNumericFacts,
} from "./contract.ts";
import { parseStepTherapy } from "./decision.ts";
import {
  anchorRecoveryPlan,
  findDelegatedDocumentIds,
  matchEntityAliases,
} from "./retrieval.ts";
import {
  evaluateBoundNumericFacts,
  validateAnswerSemantics,
} from "./structural.ts";
import type { EvidenceBlock, SearchPlan } from "./types.ts";

const clearPlan: SearchPlan = {
  search_terms: [],
  exact_literals: ["KnownDrug"],
  codes: [],
  important_qualifiers: [],
  requested_relationships: ["dose_schedule"],
  ambiguity: "clear",
  missing_slots: [],
  ambiguity_reason: null,
  clarification_question: null,
};

Deno.test("V40 generic relationship words do not become entity anchors", () => {
  const contract = buildDeterministicContract(
    "KnownDrug refill start date and initiation requirement",
  );
  assert(contract.strong_anchor_terms.includes("knowndrug"));
  assert(!contract.strong_anchor_terms.includes("start"));
  assert(!contract.strong_anchor_terms.includes("date"));
});

Deno.test("V40 collapses acronym, brand, and generic aliases by canonical identity", () => {
  const same = matchEntityAliases("AlphaBrand and alpha generic", [
    {
      alias: "AlphaBrand",
      normalized_alias: "alphabrand",
      canonical_name: "alpha-generic",
      entity_type: "medication",
      status: "active",
    },
    {
      alias: "alpha generic",
      normalized_alias: "alpha generic",
      canonical_name: "alpha-generic",
      entity_type: "medication",
      status: "active",
    },
  ]);
  assertEquals(same.canonical_names, ["alpha-generic"]);
  assertEquals(same.ambiguous, false);
  const distinct = matchEntityAliases("SharedAlias", [
    {
      alias: "SharedAlias",
      normalized_alias: "sharedalias",
      canonical_name: "alpha-generic",
      entity_type: "medication",
      status: "active",
    },
    {
      alias: "SharedAlias",
      normalized_alias: "sharedalias",
      canonical_name: "beta-generic",
      entity_type: "medication",
      status: "active",
    },
  ]);
  assertEquals(distinct.ambiguous, true);
});

Deno.test("V40 compact patient shorthand preserves recognized subjects and age", () => {
  assertEquals(
    expandCompactPolicyQuestion("BrandX syndrome kid9 ok"),
    "BrandX syndrome age 9 ok",
  );
  assertEquals(extractPatientNumericFacts("BrandX syndrome kid9 ok"), [
    { metric: "age", value: 9, unit: null },
  ]);
});

Deno.test("V40 recovery plan retains a named entity and every relationship anchor", () => {
  const recovery = anchorRecoveryPlan(
    "KnownDrug age and weight schedule",
    clearPlan,
    {
      confident: true,
      document_ids: ["doc-a"],
      anchors: ["Known policy"],
      logical_source_keys: ["family:known"],
      reason: "exact_alias_anchor:KnownDrug",
    },
    buildDeterministicContract("KnownDrug age and weight schedule"),
  );
  assert(recovery.exact_literals.some((item) => /knowndrug/iu.test(item)));
  assert(recovery.search_terms.some((item) => /dose schedule/iu.test(item)));
});

Deno.test("V40 evaluates multiple metrics independently with strict boundaries", () => {
  const results = evaluateBoundNumericFacts(
    "DLQI is 10 and BSA is 10%",
    "DLQI at least 10. BSA greater than 10%.",
  );
  assertEquals(
    results.sort((left, right) => left.metric.localeCompare(right.metric)).map(
      (item) => item.result,
    ),
    [false, true],
  );
});

Deno.test("V40 preserves ordered algorithms with an unfinished intermediate step", () => {
  const steps = parseStepTherapy(
    "1. support\n2. first therapy\n3. intermediate therapy\n4. final therapy",
  );
  assertEquals(steps, [
    "support",
    "first therapy",
    "intermediate therapy",
    "final therapy",
  ]);
});

Deno.test("V40 follows an explicit overview-to-spreadsheet delegation", () => {
  const ids = findDelegatedDocumentIds([{
    document_id: "overview",
    retrieval_text:
      "For condition-specific duration, check the Dx-code spreadsheet.",
  } as never], [
    {
      id: "overview",
      title: "Overview",
      file_name: "overview.pdf",
      is_active: true,
    },
    {
      id: "sheet",
      title: "Dx-code spreadsheet",
      file_name: "dx-code.xlsx",
      is_active: true,
    },
  ]);
  assertEquals(ids, ["sheet"]);
});

Deno.test("V40 rejects a negative contrast opening that contradicts its own broader answer", () => {
  const packet: EvidenceBlock[] = [{
    evidence_id: "E1",
    search_unit_id: "u",
    document_id: "d",
    document_title: "Form",
    file_name: "form.pdf",
    page_from: 1,
    page_to: 1,
    row_from: null,
    row_to: null,
    section_title: null,
    table_title: null,
    text: "History and current diagnosis are both required.",
  }];
  const result = validateAnswerSemantics({
    question:
      "Does the form include historical diagnostic information, or only the current diagnosis?",
    answer:
      "No. The form includes historical diagnostic information in addition to the current diagnosis. [E1]",
    evidenceIds: ["E1"],
    packet,
    contract: buildDeterministicContract(
      "Does the form include historical diagnostic information, or only the current diagnosis?",
    ),
    scope: null,
  });
  assertEquals(
    result.reason,
    "contrast_question_negative_opening_conflicts_with_answer",
  );
});
