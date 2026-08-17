import assert from 'node:assert/strict';
import test from 'node:test';

import { composeVerifiedGroundedAnswer } from './grounded_answer.ts';

const row = {
  chunk_id: 'glp-evidence',
  document_id: 'glp-document',
  document_title: 'GLP-1 Adjudication Rule',
  file_name: 'glp.pdf',
  storage_bucket: 'insurance-documents',
  storage_path: 'glp.pdf',
  matched_content: 'The report should include the most recent HbA1c result >= 6.5%, dated within the past 3 months. The report must be signed and stamped by the prescribing clinician.',
  chunk_metadata: { fields: {} },
  section_title: 'Documentation',
  page_from: 1,
  entity_type: 'therapy_class',
  entity_name: 'GLP-1',
  entity_name_normalized: 'glp 1',
  query_entity: 'GLP-1',
  query_entity_normalized: 'glp 1',
  entity_score: 1,
  intent_score: 1,
  context_score: 1,
  accepted: true,
  acceptance_reason: 'accepted_current_document_scope_and_intent',
  lexical_score: 0.9,
  semantic_score: 0.8,
  combined_score: 1.2,
  topic: 'GLP-1',
  topic_normalized: 'glp 1',
  document_family: 'glp-1-adjudication',
};

const parsed = {
  intent: 'lab_requirement',
  entity: 'GLP-1',
  entityNormalized: 'glp 1',
  patientAge: null,
  strength: null,
  treatmentMode: null,
  conditionScope: null,
  timePeriodHours: null,
  documentId: 'glp-document',
  documentTitle: row.document_title,
  therapyTopic: 'GLP-1',
  documentFamily: 'glp-1-adjudication',
  topicHint: 'GLP-1',
  explicitEntity: false,
  inheritedContext: true,
  needsClarification: false,
  answerMode: 'multi_requirement',
  requestedCount: null,
};

const structured = {
  normalizedQuestion: 'what is the hba1c result mentioned in the report',
  language: 'en',
  answerContract: {
    requiredFields: ['lab_name', 'lab_threshold', 'report_content'],
    evidenceTargets: ['lab_name', 'lab_threshold', 'report_content'],
    expectedCount: null,
    requiresCompleteEvidence: true,
  },
};

test('local composer uses only the accepted evidence and never calls an external model', async () => {
  let externalCallAttempted = false;
  const result = await composeVerifiedGroundedAnswer({
    query: 'what is the result of HbAc1 should be mentined in the report',
    parsed,
    structuredQuery: structured,
    rows: [row],
    // These legacy-looking values deliberately prove that the local composer
    // ignores all external model configuration.
    apiKey: 'must-not-be-used',
    fetchImpl: async () => {
      externalCallAttempted = true;
      throw new Error('external calls are forbidden');
    },
  });

  assert.equal(externalCallAttempted, false);
  assert.equal(result.generation.provider, 'deterministic');
  assert.equal(result.generation.model, null);
  assert.deepEqual(result.usedEvidenceIds, ['glp-evidence']);
  assert.match(result.answer, /6\.5%/);
  assert.match(result.answer, /past 3 months/i);
  assert.doesNotMatch(result.answer, /Galcanezumab|300 mg/i);
});

test('the local composer cannot invent a numeric fact absent from evidence', async () => {
  const result = await composeVerifiedGroundedAnswer({
    query: 'what HbA1c is required?',
    parsed,
    structuredQuery: structured,
    rows: [row],
  });

  assert.doesNotMatch(result.answer, /6\.3/);
  assert.match(result.answer, /6\.5/);
  assert.equal(result.answerStatus, 'answered');
});

test('no matching evidence produces no claims and no citation IDs', async () => {
  const result = await composeVerifiedGroundedAnswer({
    query: 'what HbA1c is required?',
    parsed,
    structuredQuery: structured,
    rows: [],
  });

  assert.equal(result.answerStatus, 'insufficient_evidence');
  assert.deepEqual(result.claims, []);
  assert.deepEqual(result.usedEvidenceIds, []);
  assert.equal(result.confidence, null);
  assert.deepEqual(result.completeness, {
    complete: false,
    expected: null,
    found: 0,
    required_facets: ['lab_name', 'lab_threshold', 'report_content'],
    covered_facets: [],
    missing_information: ['lab_name', 'lab_threshold', 'report_content'],
  });
});
