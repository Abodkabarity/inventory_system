import assert from "node:assert/strict";
import test from "node:test";
import {
  additionalRecoveryEvidence,
  hasMeaningfulAdditionalEvidence,
  incompleteExtractiveFallback,
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
    hasMeaningfulAdditionalEvidence([{ id: "old" }], recovered),
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
