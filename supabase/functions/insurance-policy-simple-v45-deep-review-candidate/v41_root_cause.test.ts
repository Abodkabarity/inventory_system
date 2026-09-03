import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildDeterministicContract,
  extractNumericComparisons,
} from "./contract.ts";
import {
  ageWeightBandPriority,
  matchEntityAliases,
  relationshipTextPriority,
} from "./retrieval.ts";
import {
  evaluateReassessmentIntervalFacts,
  evaluateWindowedThresholdFacts,
  validateAnswerSemantics,
} from "./structural.ts";
import type { EvidenceBlock } from "./types.ts";

function block(text: string): EvidenceBlock {
  return {
    evidence_id: "E1",
    search_unit_id: "u1",
    document_id: "d1",
    document_title: "Approved biologic policy",
    file_name: "policy.pdf",
    page_from: 1,
    page_to: 1,
    row_from: null,
    row_to: null,
    section_title: "Criteria",
    table_title: null,
    logical_source_key: "policy:biologic",
    source_version: "1",
    effective_date: null,
    source_updated_at: null,
    document_hash: "hash",
    retrieval_channel: "deterministic_scope",
    text,
  };
}

Deno.test("V41 self-named alias and its single expansion are one identity", () => {
  const resolved = matchEntityAliases("ACR therapy", [
    {
      alias: "ACR",
      normalized_alias: "acr",
      canonical_name: "Acr",
      entity_type: "therapy_class",
      status: "active",
    },
    {
      alias: "ACR",
      normalized_alias: "acr",
      canonical_name: "Advanced Class Replacement",
      entity_type: "medication",
      status: "active",
    },
  ]);
  assertEquals(resolved.canonical_names, ["Advanced Class Replacement"]);
  assertEquals(resolved.ambiguous, false);
});

Deno.test("V41 two distinct non-self entities remain ambiguous", () => {
  const resolved = matchEntityAliases("ambiguous-name", [
    {
      alias: "ambiguous-name",
      normalized_alias: "ambiguous name",
      canonical_name: "Medicine One",
      entity_type: "medication",
      status: "active",
    },
    {
      alias: "ambiguous-name",
      normalized_alias: "ambiguous name",
      canonical_name: "Medicine Two",
      entity_type: "medication",
      status: "active",
    },
  ]);
  assertEquals(resolved.ambiguous, true);
});

Deno.test("V41 temporal words do not steal a repeated biomarker threshold", () => {
  const rules = extractNumericComparisons(
    "Eosinophils >=150 cells/uL within 6 months OR >=300 cells/uL within 12 months. Children >=2 years.",
  );
  assertEquals(
    rules.filter((rule) => rule.value === 150 || rule.value === 300).map((
      rule,
    ) => rule.metric),
    ["eosinophils", "eosinophils"],
  );
});

Deno.test("V41 adjacent clinical scales do not become extra BSA thresholds", () => {
  const rules = extractNumericComparisons(
    "DLQI ≥10; BSA >10%; SCORAD ≥25; EASI ≥7; IGA ≥3.",
  );
  assertEquals(
    rules.map((rule) => rule.metric),
    ["dlqi", "bsa", "scorad", "easi", "iga"],
  );
});

Deno.test("V41 event-count thresholds do not bind to a nearby biomarker", () => {
  const rules = extractNumericComparisons(
    "Eosinophils >=150 cells/uL. Uncontrolled disease means >=2 exacerbations.",
  );
  assertEquals(rules.find((rule) => rule.value === 2)?.metric, "exacerbation");
});

Deno.test("V41 requested time-window branch is evaluated as a joint rule", () => {
  const evaluations = evaluateWindowedThresholdFacts(
    "Biologic eos 249 from 11 months ago — enough through the 12-month branch?",
    "Eosinophils >=150 cells/uL within 6 months OR >=250 cells/uL within 12 months.",
  );
  assertEquals(evaluations.length, 1);
  assertEquals(evaluations[0].policy_threshold, 250);
  assertEquals(evaluations[0].result, false);
});

Deno.test("V41 preserves Unicode PDF threshold operators", () => {
  const evaluations = evaluateWindowedThresholdFacts(
    "Nucala eos 299 from 11 months ago — enough through the 12-month eosinophil branch?",
    "Eosinophils ≥150 cells/μL within 6 months OR ≥300 cells/μL within 12 months.",
  );
  assertEquals(evaluations.length, 1);
  assertEquals(evaluations[0].policy_threshold, 300);
  assertEquals(evaluations[0].result, false);
});

Deno.test("V41 ranks a less-than weight band only when the patient is inside it", () => {
  assert(
    ageWeightBandPriority(
      "8-month-old weighing 10 kg",
      "5 to less than 15 kg: 200 mg every 4 weeks",
    ) > ageWeightBandPriority(
      "8-month-old weighing 10 kg",
      "15 to less than 30 kg: 300 mg every 4 weeks",
    ),
  );
});

Deno.test("V41 accepts a negative override answer with a passing component", () => {
  const question =
    "Current smoker with eos 400 — can the high eosinophil value override the smoking criterion?";
  const packet = [block(
    "Initiation requires eosinophils ≥300 cells/μL within 12 months and current non-smoker.",
  )];
  const validation = validateAnswerSemantics({
    question,
    answer:
      "No. The eosinophil value meets its threshold, but it does not override the separate current non-smoker criterion. [E1]",
    evidenceIds: ["E1"],
    packet,
    contract: buildDeterministicContract(question),
    scope: {
      confident: true,
      document_ids: ["d1"],
      anchors: ["Approved policy"],
      logical_source_keys: ["policy:test"],
      reason: "synthetic",
    },
  });
  assert(validation.valid);
});

Deno.test("V41 accepts No when not every requested component passes", () => {
  const question =
    "DLQI is exactly 10 and BSA is exactly 10%. Does each threshold pass?";
  const packet = [block("DLQI ≥10. BSA >10%.")];
  const validation = validateAnswerSemantics({
    question,
    answer:
      "No. DLQI 10 passes the ≥10 threshold, but BSA 10% does not pass the >10% threshold. [E1]",
    evidenceIds: ["E1"],
    packet,
    contract: buildDeterministicContract(question),
    scope: {
      confident: true,
      document_ids: ["d1"],
      anchors: ["Approved policy"],
      logical_source_keys: ["policy:test"],
      reason: "synthetic",
    },
  });
  assert(validation.valid);
});

Deno.test("V41 ordinary language cannot become an entity through a bad alias row", () => {
  const result = matchEntityAliases("Does each threshold pass?", [{
    alias: "each",
    normalized_alias: "each",
    canonical_name: "Unrelated Drug",
    entity_type: "drug",
    status: "active",
  }]);
  assertEquals(result.canonical_names, []);
});

Deno.test("V41 exact continuation interval text outranks generic same-policy text", () => {
  assert(
    relationshipTextPriority(
      "Refill was last reassessed 7 months ago — is it overdue?",
      "Re-evaluate for refills every 6 months.",
    ) > relationshipTextPriority(
      "Refill was last reassessed 7 months ago — is it overdue?",
      "Maintenance dose table and eligible clinicians.",
    ),
  );
});

Deno.test("V41 reassessment overdue comparison is deterministic", () => {
  const evaluations = evaluateReassessmentIntervalFacts(
    "JAK refill was last reassessed 7 months ago — is the policy reassessment timing overdue?",
    "Re-evaluate for JAKi refills every 6 months.",
  );
  assertEquals(evaluations.length, 1);
  assertEquals(evaluations[0].result, true);
});

Deno.test("V41 rejects positive opening for a failed windowed threshold", () => {
  const question =
    "Biologic eos 249 from 11 months ago — enough through the 12-month branch?";
  const packet = [block(
    "Eosinophils >=150 cells/uL within 6 months OR >=250 cells/uL within 12 months.",
  )];
  const validation = validateAnswerSemantics({
    question,
    answer:
      "Yes. However, 249 does not meet the required >=250 cells/uL within 12 months. [E1]",
    evidenceIds: ["E1"],
    packet,
    contract: buildDeterministicContract(question),
    scope: {
      confident: true,
      document_ids: ["d1"],
      anchors: ["Approved biologic policy"],
      logical_source_keys: ["policy:biologic"],
      reason: "synthetic",
    },
  });
  assert(!validation.valid);
});
