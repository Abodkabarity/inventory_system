import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  administrationAnswerShape,
  citationsFor,
  continuationAnswerShape,
  coverageHierarchyAnswerShape,
  decisionStructure,
  isInitiationContinuationComparison,
  listedEntityEvidenceShape,
  multiRelationshipAnswerShape,
  partialEvidenceAnswerShape,
  qualifierAnswerShape,
  recoverOptionalCitationFormatting,
  relationshipAnswerShape,
} from "./structural.ts";
import type { EvidenceBlock, ModelDecision } from "./types.ts";

const packet: EvidenceBlock[] = [{
  evidence_id: "E1",
  search_unit_id: "u1",
  document_id: "d1",
  document_title: "Approved document",
  file_name: "approved.pdf",
  page_from: 2,
  page_to: 2,
  row_from: null,
  row_to: null,
  section_title: "Criteria",
  table_title: null,
  text: "Approved evidence.",
}];

function decision(answer: string, evidenceIds: string[]): ModelDecision {
  return {
    action: "answer",
    answer,
    evidence_ids: evidenceIds,
    continuation_clinical: "NOT_APPLICABLE",
    continuation_documentation: "NOT_APPLICABLE",
    refined_search: null,
  };
}

Deno.test("known evidence IDs pass without semantic rewriting", () => {
  const result = decisionStructure(
    decision("Natural answer [E1]", ["E1"]),
    packet,
    true,
  );
  assert(result.valid);
  assertEquals(result.citedEvidenceIds, ["E1"]);
  assertEquals(
    citationsFor(packet, result.citedEvidenceIds)[0].document_id,
    "d1",
  );
});

Deno.test("unknown evidence IDs fail the only citation safety check", () => {
  const result = decisionStructure(
    decision("Wrong reference [E99]", ["E99"]),
    packet,
    true,
  );
  assertFalse(result.valid);
  assertEquals(result.reason, "unknown_evidence_id");
});

Deno.test("optional inline citation typo is removed when declared evidence is valid", () => {
  const recovered = recoverOptionalCitationFormatting(
    decision("Supported answer [E1] [E99]", ["E1"]),
    packet,
  );
  assert(recovered.recovered);
  assertEquals(recovered.decision.answer, "Supported answer [E1]");
  assert(decisionStructure(recovered.decision, packet, false).valid);
});

Deno.test("invalid declared evidence cannot be recovered as formatting", () => {
  const recovered = recoverOptionalCitationFormatting(
    decision("Unsupported answer [E99]", ["E99"]),
    packet,
  );
  assertFalse(recovered.recovered);
  assertFalse(decisionStructure(recovered.decision, packet, false).valid);
});

Deno.test("factual answer without evidence remains blocked", () => {
  assertFalse(
    decisionStructure(
      decision("Yes, it is covered.", []),
      packet,
      false,
    ).valid,
  );
});

Deno.test("explicit evidence absence is insufficiency rather than malformed output", () => {
  const decision: ModelDecision = {
    action: "answer",
    answer:
      "The provided evidence does not contain the requested relationship, so it cannot be determined.",
    evidence_ids: [],
    refined_search: null,
    continuation_clinical: "NOT_APPLICABLE",
    continuation_documentation: "NOT_APPLICABLE",
  };
  assertEquals(decisionStructure(decision, packet, false), {
    valid: true,
    invalidEvidenceIds: [],
    citedEvidenceIds: [],
    reason: null,
  });
});

Deno.test("stated criteria questions cannot imply complete approval", () => {
  assert(
    partialEvidenceAnswerShape(
      "Do these stated criteria pass for initiation?",
    ).includes("complete initiation"),
  );
});

Deno.test("uncited insufficiency response remains structurally valid", () => {
  const result = decisionStructure(
    decision("The approved evidence does not establish this information.", []),
    [],
    true,
  );
  assert(result.valid);
  assertEquals(result.citedEvidenceIds, []);
});

Deno.test("use-to-specialty questions request a relationship mapping", () => {
  assert(
    relationshipAnswerShape(
      "Which specialties are listed for the approved uses?",
    ).includes("one bullet per distinct use"),
  );
  assertEquals(
    relationshipAnswerShape("Which specialties may prescribe it?"),
    "",
  );
});

Deno.test("eligibility qualifier questions request every independent branch", () => {
  assert(
    qualifierAnswerShape(
      "Which clinical qualifier changes eligibility for the medicine?",
    ).includes("every such qualifier"),
  );
  assertEquals(
    qualifierAnswerShape("Which dose is documented?"),
    "",
  );
});

Deno.test("unnamed listed-medicine evidence questions enumerate all mappings", () => {
  const shape = listedEntityEvidenceShape(
    "What prior treatment or monitoring evidence is required for the listed medicine?",
  );
  assert(shape.includes("Do not guess one"));
  assert(shape.includes("Completely omit silent rows"));
  assert(shape.includes("Output positive source statements only"));
  assertEquals(
    listedEntityEvidenceShape(
      "What monitoring evidence is required for Ribociclib?",
    ),
    "",
  );
});

Deno.test("prior-treatment or monitoring asks for both evidence categories", () => {
  const shape = multiRelationshipAnswerShape(
    "What prior treatment or monitoring evidence is required?",
  );
  assert(shape.includes("BOTH sides"));
  assert(shape.includes("must never replace or hide"));
  assertEquals(
    multiRelationshipAnswerShape("What monitoring evidence is required?"),
    "",
  );
});

Deno.test("administration questions require explicit table schedules", () => {
  const shape = administrationAnswerShape("How is the medicine administered?");
  assert(shape.includes("explicit dose-and-frequency table"));
  assert(shape.includes("does not establish recurring administration"));
  assert(shape.includes("never move a strength"));
  assertEquals(administrationAnswerShape("Is it covered?"), "");
});

Deno.test("initiation-versus-continuation comparison preserves the full answer", () => {
  assert(
    isInitiationContinuationComparison(
      "What evidence distinguishes continuation from initiation?",
    ),
  );
  assertFalse(
    isInitiationContinuationComparison(
      "What evidence is required for continuation?",
    ),
  );
});

Deno.test("coverage questions include general and narrower relevant rules", () => {
  assert(
    coverageHierarchyAnswerShape(
      "متى الفيتامينات تكون مغطاة لثقة؟",
    ).includes("general coverage rule"),
  );
  assertEquals(
    coverageHierarchyAnswerShape("What dose is documented?"),
    "",
  );
});

Deno.test("continuation questions require both clinical and documentation facets", () => {
  const shape = continuationAnswerShape(
    "For continued Drug A therapy, what documented requirement applies?",
  );
  assert(shape.includes("continuation_clinical"));
  assert(shape.includes("continuation_documentation"));
  assert(shape.includes("Do not return NOT_APPLICABLE"));
  assertEquals(continuationAnswerShape("Who can prescribe Drug A?"), "");
});
