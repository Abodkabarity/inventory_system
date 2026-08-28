import { strict as assert } from 'node:assert';
import test from 'node:test';
import { applyPolicyEntityRouteGuard, applyVerifiedEntityAmbiguityGuard } from './semantic.ts';
import type { ResolvedEntity, SemanticRequest } from './types.ts';

const ambiguous: SemanticRequest = {
  route: 'ambiguous', language: 'en', entities: ['ExampleMed'], concepts: [], user_goal: 'clarify the medicine',
  relationship_direction: 'entity', answer_cardinality: 'single', search_queries: ['ExampleMed'], direct_response: null,
  ambiguity_question: 'What would you like to know?',
};
const verified: ResolvedEntity = {
  entity_id: 'm1', canonical_name: 'ExampleMed', entity_type: 'medication_brand', matched_term: 'examplemed', match_kind: 'canonical',
};

test('verified entity prevents a false ambiguity response without adding requested dimensions', () => {
  const result = applyVerifiedEntityAmbiguityGuard(ambiguous, [verified]);
  assert.equal(result.route, 'policy');
  assert.equal(result.ambiguity_question, null);
  assert.deepEqual(result.concepts, []);
  assert.deepEqual(result.search_queries, ['ExampleMed']);
});

test('true ambiguity remains when no entity resolves', () => {
  assert.deepEqual(applyVerifiedEntityAmbiguityGuard(ambiguous, []), ambiguous);
});

test('named policy shorthand cannot bypass evidence retrieval as conversation', () => {
  const result = applyPolicyEntityRouteGuard({ ...ambiguous, route: 'conversation', direct_response: 'general model answer' });
  assert.equal(result.route, 'policy');
  assert.equal(result.direct_response, null);
});
