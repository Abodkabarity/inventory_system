import { strict as assert } from 'node:assert';
import test from 'node:test';
import type { EvidenceBlock, ResolvedEntity, SemanticRequest } from './types.ts';
import { validateAnswer } from './validation.ts';

const semantic: SemanticRequest = {
  route: 'policy', language: 'en', entities: ['ExampleMed'], concepts: [], user_goal: 'overview',
  relationship_direction: 'entity_to_policy', answer_cardinality: 'single', search_queries: ['ExampleMed'],
  direct_response: null, ambiguity_question: null,
};
const entities: ResolvedEntity[] = [{
  entity_id: '1', canonical_name: 'ExampleMed', entity_type: 'medication_brand', matched_term: 'examplemed', match_kind: 'canonical',
}];
const packet: EvidenceBlock[] = [{
  id: 'E1', search_unit_id: 'u1', chunk_id: 'c1', document_id: 'd1', document_title: 'Approved policy',
  file_name: 'policy.xlsx', storage_bucket: 'insurance-documents', storage_path: 'x/policy.xlsx', page_from: 3,
  page_to: 3, sheet_name: null, row_from: 4, row_to: 4, section: 'Medication table',
  evidence_type: 'structured_table_row', text: 'ExampleMed initial dose is 2.5 mg once weekly for 4 weeks. Maximum boxes per month: 1.',
  gold: true, score: 100,
}];

test('accepts a grounded answer that preserves direct structured-row numbers', () => {
  const result = validateAnswer({
    answer: 'ExampleMed starts at 2.5 mg once weekly for 4 weeks, with 1 box per month.', usedEvidenceIds: ['E1'],
    question: 'ExampleMed', semantic, entities, packet, medicationCatalog: ['ExampleMed', 'OtherMed'],
  });
  assert.equal(result.valid, true);
});

test('gold evidence cannot be erased by an insufficient-evidence claim', () => {
  const result = validateAnswer({
    answer: 'The approved documents do not establish the requested information.', usedEvidenceIds: ['E1'],
    question: 'ExampleMed', semantic, entities, packet,
  });
  assert.equal(result.valid, false);
  assert.ok(result.errors.includes('denies_existing_gold_evidence'));
});

test('detects wrong medication contamination for an anchored medication request', () => {
  const result = validateAnswer({
    answer: 'OtherMed starts at 2.5 mg.', usedEvidenceIds: ['E1'], question: 'ExampleMed', semantic, entities, packet,
    medicationCatalog: ['ExampleMed', 'OtherMed'],
  });
  assert.ok(result.errors.some((error) => error.startsWith('wrong_medication_contamination:')));
});

test('rejects unsupported exhaustive language for aggregate retrieval', () => {
  const result = validateAnswer({
    answer: 'These are the only supported policies: Approved policy.', usedEvidenceIds: ['E1'], question: 'Which policies?',
    semantic: { ...semantic, answer_cardinality: 'aggregate' }, entities: [], packet,
  });
  assert.ok(result.errors.includes('unsupported_exhaustive_claim'));
});

test('requires multi-document coverage for a multiple-result answer', () => {
  const second = { ...packet[0], id: 'E2', search_unit_id: 'u2', chunk_id: 'c2', document_id: 'd2', document_title: 'Second policy' };
  const result = validateAnswer({
    answer: 'Approved policy supports the result.', usedEvidenceIds: ['E1'], question: 'Which policies?',
    semantic: { ...semantic, answer_cardinality: 'multiple' }, entities: [], packet: [...packet, second],
  });
  assert.ok(result.errors.some((error) => error.startsWith('multi_document_omission:')));
});

test('entity overview cannot omit verified identity or major gold-row fields', () => {
  const generic = { ...entities[0], entity_id: '2', canonical_name: 'ExampleGeneric', entity_type: 'medication_generic' };
  const overviewPacket = [{ ...packet[0], text: `${packet[0].text}\nIndications: Condition A; Condition B` }];
  const result = validateAnswer({
    answer: 'ExampleMed starts at 2.5 mg for Condition A.', usedEvidenceIds: ['E1'], question: 'ExampleMed',
    semantic, entities: [...entities, generic], packet: overviewPacket,
  });
  assert.ok(result.errors.some((error) => error.includes('verified_identity_omission:ExampleGeneric')));
  assert.ok(result.errors.some((error) => error.startsWith('gold_numeric_omission:')));
  assert.ok(result.errors.some((error) => error.includes('gold_indication_omission:Condition B')));
});

test('complete entity overview passes gold-row completeness checks', () => {
  const generic = { ...entities[0], entity_id: '2', canonical_name: 'ExampleGeneric', entity_type: 'medication_generic' };
  const overviewPacket = [{ ...packet[0], text: `${packet[0].text}\nIndications: Condition A; Condition B` }];
  const result = validateAnswer({
    answer: 'ExampleMed (ExampleGeneric) is indicated for Condition A and Condition B. It starts at 2.5 mg once weekly for 4 weeks, with a maximum of 1 box per month.',
    usedEvidenceIds: ['E1'], question: 'ExampleMed', semantic, entities: [...entities, generic], packet: overviewPacket,
  });
  assert.equal(result.valid, true);
});

test('document summary does not inherit medication-profile completeness checks', () => {
  const result = validateAnswer({
    answer: 'The policy lists the supported clinician specialties.',
    usedEvidenceIds: ['E1'],
    question: 'Summarize the policy and its supported specialties.',
    semantic: { ...semantic, entities: [], user_goal: 'summary of a policy document' },
    entities: [],
    packet,
  });
  assert.equal(result.valid, true);
  assert.equal(result.errors.some((error) => error.startsWith('gold_numeric_omission:')), false);
});

test('direct policy wording containing only is not mistaken for an exhaustive search claim', () => {
  const result = validateAnswer({
    answer: 'The cited policy says coverage applies to specific indications only.',
    usedEvidenceIds: ['E1'], question: 'Summarize the criteria.',
    semantic: { ...semantic, answer_cardinality: 'multiple' }, entities: [], packet,
  });
  assert.equal(result.errors.includes('unsupported_exhaustive_claim'), false);
});

test('denial cannot erase direct supported multi-document evidence', () => {
  const result = validateAnswer({
    answer: 'No approved evidence identifies a supported policy owner.',
    usedEvidenceIds: ['E1'], question: 'Which policy owners?', semantic, entities, packet,
  });
  assert.ok(result.errors.includes('denies_existing_gold_evidence'));
});

test('numeric determination requires its threshold and evidence in the answer', () => {
  const result = validateAnswer({
    answer: 'The patient does not qualify.', usedEvidenceIds: ['E1'], question: 'Age 11: does it pass?', semantic, entities, packet,
    criteria: [{ subject: 'age', patient_value: 11, operator: '>=', threshold: 12, result: false, evidence_id: 'E1', explanation: '11 >= 12 is false' }],
  });
  assert.ok(result.errors.includes('numeric_criterion_threshold_omission:12'));
});
