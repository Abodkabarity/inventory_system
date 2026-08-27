import assert from "node:assert/strict";
import test from "node:test";
import {
  preferredAnswerShouldReplace,
  relationSnapshot,
  semanticCachePayload,
  semanticCacheSignature,
  validateDocumentSnapshots,
} from "./validated_cache.ts";

const semantic = (overrides = {}) => ({
  route: "policy_question",
  medication: "Example",
  generic: "Example generic",
  drug_class: null,
  indication: null,
  intent: ["overview"],
  requested_dimensions: ["coverage"],
  treatment_stage: null,
  semantic_intent: "policy overview",
  requested_information: "policy overview",
  information_need: "policy overview",
  retrieval_queries: [],
  search_concepts: [],
  search_phrases: [],
  search_query: null,
  negation: [],
  temporal_context: null,
  facts: [],
  source_requested: false,
  ...overrides,
});
const entity = [{
  id: "e1",
  canonical_name: "Example",
  normalized_name: "example",
  entity_type: "medication_brand",
}];

test("equivalent semantic requests produce the same signature", async () => {
  assert.equal(
    await semanticCacheSignature(semantic(), entity),
    await semanticCacheSignature(
      semantic({ retrieval_queries: ["different wording"] }),
      entity,
    ),
  );
});

test("different intent or patient facts cannot reuse an overview answer", async () => {
  const overview = await semanticCacheSignature(semantic(), entity);
  const dose = await semanticCacheSignature(
    semantic({
      intent: ["dose"],
      requested_dimensions: ["dose"],
      information_need: "dose",
      requested_information: "dose",
      semantic_intent: "dose",
    }),
    entity,
  );
  const patient = await semanticCacheSignature(
    semantic({
      facts: [{
        concept: "age",
        value: 9,
        unit: "years",
        polarity: "present",
        temporal: null,
      }],
    }),
    entity,
  );
  assert.notEqual(overview, dose);
  assert.notEqual(overview, patient);
});

test("entity relation snapshot is stable and limited to relevant entities", () => {
  const relations = [{
    subject_entity_id: "e1",
    relation_type: "brand_of",
    object_entity_id: "e2",
    verified: true,
  }, {
    subject_entity_id: "x",
    relation_type: "member_of",
    object_entity_id: "y",
    verified: true,
  }];
  assert.deepEqual(relationSnapshot(relations, ["e1"]), ["e1|brand_of|e2"]);
  assert.deepEqual(semanticCachePayload(semantic(), entity).entity_ids, ["e1"]);
});

test("accepted Deep Review cannot be replaced by an older normal answer", () => {
  assert.equal(preferredAnswerShouldReplace("deep_review", "normal"), false);
  assert.equal(preferredAnswerShouldReplace("normal", "deep_review"), true);
});

test("document changes and missing citations invalidate cached answers", () => {
  const snapshot = [{ id: "d1", document_hash: "h1", version: "1" }];
  assert.deepEqual(
    validateDocumentSnapshots(snapshot, [{
      id: "d1",
      document_hash: "h2",
      version: "1",
      is_active: true,
      storage_bucket: "b",
      storage_path: "p",
    }]),
    { valid: false, reason: "document_version_changed" },
  );
  assert.deepEqual(
    validateDocumentSnapshots(snapshot, [{
      id: "d1",
      document_hash: "h1",
      version: "1",
      is_active: true,
      storage_bucket: "b",
      storage_path: "",
    }]),
    { valid: false, reason: "citation_unresolvable" },
  );
});
