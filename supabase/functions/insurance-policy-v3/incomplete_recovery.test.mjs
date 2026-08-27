import assert from "node:assert/strict";
import test from "node:test";
import {
  additionalRecoveryEvidence,
  answerIncorporatesMissingEvidenceFacts,
  hasMeaningfulAdditionalEvidence,
  incompleteExtractiveFallback,
  recoveryEvidenceWithMissingFacts,
  removeBroadAbsenceClaimsAfterRecovery,
  substantiallyEquivalentAnswer,
} from "./incomplete_recovery.ts";

const chunk = (id, text) => ({
  chunk_id: id,
  document_id: "d1",
  document_title: "Policy",
  file_name: "p.pdf",
  page_from: 1,
  page_to: 1,
  sheet_name: null,
  row_from: null,
  row_to: null,
  section_title: null,
  chunk_text: text,
  metadata: {},
  score: 1,
  fts_rank: 1,
  trigram_score: 1,
  matched_entity_count: 1,
  matched_dimensions: [],
});

test("detects substantially equivalent answers despite cosmetic wording", () => {
  assert.equal(
    substantiallyEquivalentAnswer(
      "Covered for adults with diagnosis.",
      "The diagnosis is covered for adult patients.",
    ),
    true,
  );
  assert.equal(
    substantiallyEquivalentAnswer(
      "Covered for adults.",
      "Dose is 5 mg once weekly.",
    ),
    false,
  );
});

test("identifies only meaningful newly recovered evidence", () => {
  const recovered = [
    chunk("old", "Already seen evidence with sufficient detail for this test."),
    chunk(
      "new",
      "New verified continuation requirements with additional supported details.",
    ),
  ];
  assert.deepEqual(
    additionalRecoveryEvidence([{ id: "old" }], recovered).map((item) =>
      item.chunk_id
    ),
    ["new"],
  );
  assert.equal(
    hasMeaningfulAdditionalEvidence(
      "Existing summary.",
      [{ id: "old" }],
      recovered,
    ),
    true,
  );
});

test("same evidence ID is meaningful when its supported facts were omitted", () => {
  const completeRow = chunk(
    "same",
    "Medicine: Example\nIndications: Condition A; Condition B\nInitial Dose: 2.5 mg once weekly for 4 weeks\nMaximum Quantity: 1 box monthly",
  );
  const originalEvidence = [{ id: "same", text: completeRow.chunk_text }];
  const originalAnswer =
    "Example is indicated for Condition A and Condition B.";
  assert.deepEqual(
    recoveryEvidenceWithMissingFacts(
      originalAnswer,
      originalEvidence,
      [completeRow],
    ).map((item) => item.chunk_id),
    ["same"],
  );
  assert.equal(
    hasMeaningfulAdditionalEvidence(originalAnswer, originalEvidence, [
      completeRow,
    ]),
    true,
  );
  assert.equal(
    answerIncorporatesMissingEvidenceFacts(
      originalAnswer,
      `${originalAnswer} No broader information is available in the evidence.`,
      [completeRow],
    ),
    false,
  );
  assert.equal(
    answerIncorporatesMissingEvidenceFacts(
      originalAnswer,
      `${originalAnswer} Initial dose is 2.5 mg once weekly for 4 weeks.`,
      [completeRow],
    ),
    true,
  );
});

test("extractive guard preserves original and appends new grounded facts", () => {
  const answer = incompleteExtractiveFallback(
    "Existing supported fact.\n\nSource: Old — Page 1",
    [{ id: "old" }],
    [chunk("new", "New approved evidence fact.")],
  );
  assert.match(answer, /Existing supported fact/);
  assert.match(answer, /New approved evidence fact/);
  assert.doesNotMatch(answer, /Source: Old/);
});

test("removes broad absence claims after missing facts were recovered", () => {
  assert.equal(
    removeBroadAbsenceClaimsAfterRecovery(
      "The verified dose is 5 mg weekly. No additional policy details are available in the supplied evidence.",
    ),
    "The verified dose is 5 mg weekly.",
  );
});
