import assert from 'node:assert/strict';
import { enforceRouteSafety, isolateMedicationCandidates, requestedDimensions, rerankChunks, resolveVerifiedEntities, selectEvidence } from './retrieval.ts';

const semantic = { route: 'catalog_discovery', medication: 'Repatha', generic: null, indication: 'HoFH', intent: [], requested_dimensions: ['age'], treatment_stage: null, facts: [], source_requested: false };
const entities = [
  { id: 'brand', canonical_name: 'Repatha', normalized_name: 'repatha', entity_type: 'medication_brand' },
  { id: 'generic', canonical_name: 'Evolocumab', normalized_name: 'evolocumab', entity_type: 'medication_generic' },
  { id: 'hofh', canonical_name: 'Homozygous Familial Hypercholesterolaemia', normalized_name: 'homozygous familial hypercholesterolaemia', entity_type: 'indication' },
];
const aliases = [{ entity_id: 'brand', alias: 'Repatha', normalized_alias: 'repatha', verified: true }, { entity_id: 'hofh', alias: 'HoFH', normalized_alias: 'hofh', verified: true }];
const relations = [{ subject_entity_id: 'brand', relation_type: 'brand_of', object_entity_id: 'generic', verified: true }];
const resolved = resolveVerifiedEntities('Repatha HoFH age9?', semantic, entities, aliases, relations);
assert.deepEqual(new Set(resolved.map((item) => item.id)), new Set(['brand', 'generic', 'hofh']));

const conflictingEntities = [
  ...entities,
  { id: 'other-generic', canonical_name: 'Other Generic', normalized_name: 'other generic', entity_type: 'medication_generic' },
];
const conflictingAliases = [
  ...aliases,
  { entity_id: 'other-generic', alias: 'Other Generic', normalized_alias: 'other generic', verified: true },
];
const conflictResolved = resolveVerifiedEntities(
  'Repatha HoFH age9?',
  { ...semantic, generic: 'Other Generic' },
  conflictingEntities,
  conflictingAliases,
  relations,
);
assert.deepEqual(new Set(conflictResolved.map((item) => item.id)), new Set(['brand', 'generic', 'hofh']));
const dimensions = requestedDimensions('Repatha HoFH age9?', semantic);
assert.ok(dimensions.includes('age'));
assert.equal(enforceRouteSafety(semantic, resolved, dimensions).route, 'policy_question');

const shortQuestionSemantic = {
  ...semantic,
  route: 'clarification_required',
  requested_dimensions: [],
  intent: ['treatment'],
  facts: [{ concept: 'age', value: '8', unit: 'months', polarity: 'positive', temporal: 'present' }],
};
const shortDimensions = requestedDimensions('Dupixent at 8 months old?', shortQuestionSemantic);
assert.ok(shortDimensions.includes('age'));
assert.ok(!shortDimensions.includes('treatment'));
assert.equal(enforceRouteSafety(shortQuestionSemantic, resolved, shortDimensions).route, 'policy_question');

const timeWindowSemantic = {
  ...semantic,
  medication: 'GLP-1',
  requested_dimensions: ['HbA1c timeframe'],
  intent: ['clarify policy requirement'],
  treatment_stage: 'initiation',
  facts: [{ concept: 'HbA1c', value: 'last 3 months', unit: 'months', polarity: 'required', temporal: 'current' }],
};
const timeDimensions = requestedDimensions('For GLP-1 initiation, must HbA1c be from the last 3 months?', timeWindowSemantic);
assert.deepEqual(new Set(timeDimensions), new Set(['labs', 'time_window', 'initiation']));

const classOnly = [{ id: 'class', canonical_name: 'GLP-1 receptor agonists', normalized_name: 'glp 1 receptor agonists', entity_type: 'drug_class' }];
const classChunk = {
  document_id: 'd', document_title: 'GLP-1', file_name: 'glp.pdf', page_from: 1, page_to: 1,
  sheet_name: null, row_from: null, row_to: null, section_title: null, chunk_id: 'class-chunk',
  chunk_text: 'GLP-1 initiation criteria with HbA1c dated within the past 3 months',
  metadata: { medications: ['Ozempic', 'Mounjaro'], topics: ['labs', 'time_window', 'initiation'], treatment_stage: null },
  score: 10, fts_rank: 0, trigram_score: 0, matched_entity_count: 1, matched_dimensions: [],
};
const rerankedClass = rerankChunks([classChunk], classOnly, ['labs', 'time_window', 'initiation'], 'initiation', 'GLP-1 HbA1c last 3 months');
assert.equal(rerankedClass[0].deterministic_score, 20.5);
assert.equal(enforceRouteSafety({ ...timeWindowSemantic, route: 'clarification_required' }, classOnly, timeDimensions).route, 'policy_question');
assert.equal(enforceRouteSafety({ ...timeWindowSemantic, route: 'policy_question', medication: 'unknown medicine' }, [], timeDimensions).route, 'clarification_required');

const base = { document_id: 'd', document_title: 'x', file_name: 'x.pdf', page_from: 1, page_to: 1, sheet_name: null, row_from: null, row_to: null, section_title: null, metadata: {}, score: 1, fts_rank: 0, trigram_score: 0, matched_entity_count: 1, matched_dimensions: [] };
const isolated = isolateMedicationCandidates([
  { ...base, chunk_id: 'right-drug', chunk_text: 'Minimum age is 10 years', metadata: { medications: ['Repatha', 'Evolocumab'] } },
  { ...base, chunk_id: 'class-wide', chunk_text: 'Not covered below the class minimum age', metadata: { medications: [], entity_specific: false } },
  { ...base, chunk_id: 'wrong-class-member', chunk_text: 'Minimum age is 8 years', metadata: { medications: ['Other Brand', 'Other Generic'] } },
], resolved);
assert.deepEqual(isolated.map((item) => item.chunk_id), ['right-drug', 'class-wide']);
const selected = selectEvidence([
  { ...base, chunk_id: 'dose', chunk_text: 'Dose is 140 mg monthly', deterministic_score: 10 },
  { ...base, chunk_id: 'age', chunk_text: 'Minimum age is 18 years', deterministic_score: 9 },
], ['dose', 'age']);
assert.deepEqual(new Set(selected.selected.map((item) => item.chunk_id)), new Set(['dose', 'age']));
assert.deepEqual(selected.missingDimensions, []);

const temporalSelection = selectEvidence([
  { ...base, chunk_id: 'context-1', chunk_text: 'Policy context', deterministic_score: 10 },
  { ...base, chunk_id: 'context-2', chunk_text: 'Continuation context', metadata: { topics: ['continuation'] }, deterministic_score: 9 },
  { ...base, chunk_id: 'context-3', chunk_text: 'Additional context', deterministic_score: 8 },
  { ...base, chunk_id: 'criterion', chunk_text: 'Lack of response after at least 6 months', metadata: { topics: ['time_window', 'continuation'] }, deterministic_score: 7 },
], ['time_window', 'continuation'], 6);
assert.equal(temporalSelection.selected.length, 4);
assert.ok(temporalSelection.selected.some((chunk) => chunk.chunk_id === 'criterion'));

const numericBoundary = rerankChunks([
  { ...base, chunk_id: 'decimal', chunk_text: 'HbA1c is 6.5 percent', metadata: { topics: ['labs'] } },
  { ...base, chunk_id: 'duration', chunk_text: 'Switch after 6 months', metadata: { topics: ['time_window', 'continuation'], treatment_stage: 'continuation' } },
], [], ['time_window'], 'continuation', 'switch after 6 months');
assert.equal(numericBoundary[0].chunk_id, 'duration');
assert.equal(numericBoundary.find((chunk) => chunk.chunk_id === 'decimal').deterministic_score, 1);
console.log('insurance-policy-v3 retrieval tests passed');
