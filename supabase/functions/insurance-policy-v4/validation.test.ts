import { strict as assert } from 'node:assert';
import test from 'node:test';
import type { EvidenceBlock, ResolvedEntity, SemanticRequest } from './types.ts';
import { buildFactManifest } from './fact_binding.ts';
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

test('reverse specialty answer cannot hide one treatment in document prose', () => {
  const reversePacket = [
    { ...packet[0], id: 'E1', document_id: 'ppi', document_title: 'What you should know about the PPI coverage', text: 'Eligible Clinician Specialty: Otolaryngology' },
    { ...packet[0], id: 'E2', document_id: 'oma', document_title: 'Omalizumab Overview', text: 'Eligible clinical specialties for Omalizumab: Otolaryngology' },
  ];
  const reverseSemantic: SemanticRequest = {
    ...semantic, entities: ['Otolaryngology'], relationship_direction: 'specialty_to_treatment', answer_cardinality: 'multiple',
  };
  const result = validateAnswer({
    answer: 'Omalizumab is supported. The PPI coverage document also mentions Otolaryngology.',
    usedEvidenceIds: ['E1', 'E2'], question: 'Which treatments can an ENT doctor prescribe?',
    semantic: reverseSemantic, entities: [], packet: reversePacket,
  });
  assert.ok(result.errors.includes('relationship_endpoint_not_enumerated:PPI'));
  assert.ok(result.errors.includes('relationship_endpoint_not_enumerated:Omalizumab'));
});

test('reverse specialty answer passes when every endpoint is an explicit result', () => {
  const reversePacket = [
    { ...packet[0], id: 'E1', document_id: 'ppi', document_title: 'What you should know about the PPI coverage', text: 'Eligible Clinician Specialty: Otolaryngology' },
    { ...packet[0], id: 'E2', document_id: 'oma', document_title: 'Omalizumab Overview', text: 'Eligible clinical specialties for Omalizumab: Otolaryngology' },
  ];
  const result = validateAnswer({
    answer: 'The retrieved evidence supports:\n1. PPI — Otolaryngology is eligible.\n2. Omalizumab — Otolaryngology is eligible.',
    usedEvidenceIds: ['E1', 'E2'], question: 'Which treatments can an ENT doctor prescribe?',
    semantic: { ...semantic, entities: ['Otolaryngology'], relationship_direction: 'specialty_to_policy', answer_cardinality: 'multiple' },
    entities: [], packet: reversePacket,
  });
  assert.equal(result.valid, true);
});

test('rejects a number that exists in the packet but is not bound to the requested medication', () => {
  const mounjaroEntities: ResolvedEntity[] = [
    { ...entities[0], entity_id: 'mounjaro', canonical_name: 'Mounjaro', matched_term: 'Mounjaro' },
    { ...entities[0], entity_id: 'tirzepatide', canonical_name: 'Tirzepatide', entity_type: 'medication_generic', matched_term: 'Mounjaro' },
  ];
  const mixedPacket: EvidenceBlock[] = [
    {
      ...packet[0], id: 'E1', evidence_type: 'structured_table_row',
      text: 'Content:\nDrug Name: Tirzepatide (Mounjaro)\nInitial Dose: 2.5 mg once weekly for 4 weeks\nMaximum Allowed boxes per Month: 1',
    },
    { ...packet[0], id: 'E2', gold: false, evidence_type: 'page', row_from: null, row_to: null, text: 'OZEMPIC 0.25 MG, and MOUNJARO 2.5 MG are initial doses. The 0.25 mg dose may sometimes be therapeutic.' },
  ];
  const factManifest = buildFactManifest(mixedPacket, mounjaroEntities, ['Mounjaro', 'Tirzepatide', 'Ozempic'], 'Mounjaro');
  const result = validateAnswer({
    answer: 'Mounjaro starts at 2.5 mg. In sensitive patients, 0.25 mg may be therapeutic.',
    usedEvidenceIds: ['E1', 'E2'], question: 'Mounjaro', semantic, entities: mounjaroEntities,
    packet: mixedPacket, medicationCatalog: ['Mounjaro', 'Tirzepatide', 'Ozempic'], factManifest,
  });
  assert.ok(result.errors.includes('unbound_entity_numbers:0.25'));
});

test('accepts numbers bound to the requested medication structured row', () => {
  const mounjaroEntities: ResolvedEntity[] = [
    { ...entities[0], entity_id: 'mounjaro', canonical_name: 'Mounjaro', matched_term: 'Mounjaro' },
    { ...entities[0], entity_id: 'tirzepatide', canonical_name: 'Tirzepatide', entity_type: 'medication_generic', matched_term: 'Mounjaro' },
  ];
  const directPacket = [{
    ...packet[0], evidence_type: 'structured_table_row',
    text: 'Content:\nDrug Name: Tirzepatide (Mounjaro)\nInitial Dose: 2.5 mg once weekly for 4 weeks\nMaximum Allowed boxes per Month: 1',
  }];
  const factManifest = buildFactManifest(directPacket, mounjaroEntities, ['Mounjaro', 'Tirzepatide', 'Ozempic'], 'Mounjaro');
  const result = validateAnswer({
    answer: 'Mounjaro (Tirzepatide) starts at 2.5 mg once weekly for 4 weeks, with 1 box per month.',
    usedEvidenceIds: ['E1'], question: 'Mounjaro', semantic, entities: mounjaroEntities,
    packet: directPacket, medicationCatalog: ['Mounjaro', 'Tirzepatide', 'Ozempic'], factManifest,
  });
  assert.equal(result.valid, true);
});

test('evidence IDs are not treated as unsupported medical numbers', () => {
  const result = validateAnswer({
    answer: 'ExampleMed starts at 2.5 mg (E3, E4).', usedEvidenceIds: ['E1'],
    question: 'ExampleMed', semantic, entities, packet,
  });
  assert.equal(result.errors.some((error) => error.startsWith('unsupported_numbers:3,4')), false);
});

test('a number suggested by the user cannot become a medication fact without entity binding', () => {
  const mounjaroEntities: ResolvedEntity[] = [
    { ...entities[0], entity_id: 'mounjaro', canonical_name: 'Mounjaro', matched_term: 'Mounjaro' },
    { ...entities[0], entity_id: 'tirzepatide', canonical_name: 'Tirzepatide', entity_type: 'medication_generic', matched_term: 'Mounjaro' },
  ];
  const mixedPacket: EvidenceBlock[] = [
    { ...packet[0], text: 'Content:\nDrug Name: Tirzepatide (Mounjaro)\nInitial Dose: 2.5 mg once weekly for 4 weeks' },
    { ...packet[0], id: 'E2', gold: false, evidence_type: 'page', row_from: null, row_to: null, text: 'OZEMPIC 0.25 MG, and MOUNJARO 2.5 MG are initial doses.' },
  ];
  const factManifest = buildFactManifest(mixedPacket, mounjaroEntities, ['Mounjaro', 'Tirzepatide', 'Ozempic'], 'Can Mounjaro 0.25 mg be therapeutic?');
  const affirmed = validateAnswer({
    answer: 'Yes, Mounjaro 0.25 mg can be therapeutic.', usedEvidenceIds: ['E1', 'E2'],
    question: 'Can Mounjaro 0.25 mg be therapeutic?', semantic, entities: mounjaroEntities,
    packet: mixedPacket, factManifest,
  });
  assert.ok(affirmed.errors.includes('unbound_entity_numbers:0.25'));

  const rejected = validateAnswer({
    answer: 'No. The approved evidence does not support 0.25 mg for Mounjaro; it directly lists 2.5 mg.',
    usedEvidenceIds: ['E1'], question: 'Can Mounjaro 0.25 mg be therapeutic?', semantic, entities: mounjaroEntities,
    packet: mixedPacket, factManifest,
  });
  assert.equal(rejected.errors.includes('unbound_entity_numbers:0.25'), false);
});
