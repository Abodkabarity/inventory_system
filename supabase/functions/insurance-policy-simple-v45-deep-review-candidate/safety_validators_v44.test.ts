import { assert, assertEquals } from "jsr:@std/assert@1";
import { validateAgenticResult } from "./safety_validators.ts";
import type { AgenticFinal, EvidenceBlock } from "./types.ts";

const evidence: EvidenceBlock[] = [{
  evidence_id: "E1",
  search_unit_id: "u1",
  document_id: "d1",
  document_title: "Nucala approved policy",
  file_name: "nucala.pdf",
  page_from: 2,
  page_to: 2,
  row_from: null,
  row_to: null,
  section_title: "Eligibility",
  table_title: null,
  text:
    "Nucala requires an eosinophil count greater than or equal to 300 cells/mcL.",
}];

function result(answer: string): AgenticFinal {
  return {
    action: "answer",
    interpretation: {
      language: "en",
      turn_kind: "standalone",
      canonical_entities: ["Nucala"],
      indication: null,
      requested_relationships: ["eligibility threshold"],
      numeric_qualifiers: ["300"],
      formulation: null,
      resolved_question: "Does 300 pass?",
      genuinely_ambiguous: false,
      ambiguity_reason: null,
      clarification_question: null,
    },
    answer,
    evidence_ids: ["E1"],
    evidence_judgements: [{
      evidence_id: "E1",
      disposition: "accepted",
      reason: "answers_requested_relationship",
    }],
    unresolved_facets: [],
  };
}

Deno.test("V44 permits exact grounded numeric boundary", () => {
  assert(
    validateAgenticResult(
      "For Nucala, does 300 cells/mcL pass?",
      result("Yes. 300 cells/mcL meets the threshold. [E1]"),
      evidence,
    ).valid,
  );
});

Deno.test("V44 blocks a number absent from question and selected evidence", () => {
  assertEquals(
    validateAgenticResult(
      "For Nucala, does the threshold pass?",
      result("Yes. The threshold is 500 cells/mcL. [E1]"),
      evidence,
    ).failures.includes("unsupported_numeric_value"),
    true,
  );
});

Deno.test("V44 blocks an answer that cites rejected evidence", () => {
  const value = result("Yes. [E1]");
  value.evidence_judgements[0].disposition = "rejected";
  assertEquals(
    validateAgenticResult("Nucala eligible?", value, evidence).failures
      .includes("answer_uses_unaccepted_evidence"),
    true,
  );
});

Deno.test("V44 accepts a brand evidence match for a brand-generic canonical label", () => {
  const value = result("Yes. 300 cells/mcL meets the threshold. [E1]");
  value.interpretation.canonical_entities = ["Nucala (mepolizumab)"];
  assert(validateAgenticResult("Nucala threshold?", value, evidence).valid);
});
