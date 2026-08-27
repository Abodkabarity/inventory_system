import assert from 'node:assert/strict';
import { groundedExtractiveAnswer, hasStrongVerifiedEvidence } from './fallback.ts';

const chunk = {
  chunk_id: 'c1', document_id: 'd1', document_title: 'Approved Policy', file_name: 'policy.pdf',
  page_from: 4, page_to: 4, sheet_name: null, row_from: 12, row_to: 12, chunk_index: 1,
  section_title: 'Eligibility', chunk_text: 'The approved evidence directly states the requested criterion.',
  metadata: { semantic_table_record: true, entity_specific: true }, score: 10, fts_rank: 0,
  trigram_score: 0, matched_entity_count: 1, matched_dimensions: ['documentation'],
};
const selection = { selected: [chunk], missingDimensions: [], missingSignals: [], requestedCoverage: 0.8, sufficient: true };

assert.equal(hasStrongVerifiedEvidence(selection, [chunk], new Set()), true);
assert.equal(hasStrongVerifiedEvidence({ ...selection, selected: [] }, [chunk], new Set()), false);
assert.equal(hasStrongVerifiedEvidence({ ...selection, sufficient: false }, [chunk], new Set(['c1'])), true);

const fallback = groundedExtractiveAnswer('ما هو الشرط؟', {
  route: 'policy_question', medication: null, generic: null, drug_class: null, indication: null,
  intent: [], requested_dimensions: [], treatment_stage: null, semantic_intent: 'criterion',
  requested_information: 'criterion', information_need: 'criterion', retrieval_queries: [],
  search_concepts: [], search_phrases: [], search_query: null, negation: [], temporal_context: null,
  facts: [], source_requested: false,
}, [chunk]);
assert.match(fallback.answer, /الأدلة المعتمدة/);
assert.match(fallback.answer, /requested criterion/);
assert.deepEqual(fallback.used_evidence_ids, ['E1']);

console.log('insurance-policy-v3 evidence-preserving fallback tests passed');
