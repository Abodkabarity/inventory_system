import assert from 'node:assert/strict';
import { buildRetrievalPlan, enforceRouteSafety, evidenceForAnswer, groundEntityOnlySemantic, isolateMedicationCandidates, requestedDimensions, rerankChunks, resolveVerifiedEntities, selectEvidence, strictRetrievalEntityIds } from './retrieval.ts';

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
assert.deepEqual(strictRetrievalEntityIds(resolved), ['brand', 'generic']);
assert.deepEqual(strictRetrievalEntityIds([entities[2]]), []);

const classInflection = resolveVerifiedEntities(
  'Is a double dose of a sample pump inhibitor allowed?',
  { ...semantic, medication: 'sample pump inhibitor', generic: null, drug_class: 'sample pump inhibitor' },
  [{ id: 'sample-class', canonical_name: 'Sample pump inhibitors', normalized_name: 'sample pump inhibitors', entity_type: 'drug_class' }],
  [{ entity_id: 'sample-class', alias: 'Sample pump inhibitors', normalized_alias: 'sample pump inhibitors', verified: true }],
  [],
);
assert.deepEqual(classInflection.map((item) => item.id), ['sample-class']);

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

const unknownBrandResolved = resolveVerifiedEntities(
  'UnknownBrand asthma eos 200?',
  { ...semantic, medication: 'UnknownBrand', generic: 'Other Generic', indication: 'HoFH' },
  conflictingEntities,
  conflictingAliases,
  relations,
);
assert.deepEqual(new Set(unknownBrandResolved.map((item) => item.id)), new Set(['hofh']));
assert.equal(
  enforceRouteSafety(
    { ...semantic, route: 'policy_question', medication: 'UnknownBrand', generic: 'Other Generic' },
    unknownBrandResolved,
    ['labs'],
  ).route,
  'clarification_required',
);
const dimensions = requestedDimensions('Repatha HoFH age9?', semantic);
assert.ok(dimensions.includes('age'));
assert.equal(enforceRouteSafety(semantic, resolved, dimensions).route, 'policy_question');

const groundedBareMedication = groundEntityOnlySemantic('Mounjaro?', {
  ...semantic,
  route: 'policy_question',
  medication: 'Mounjaro',
  generic: 'Tirzepatide',
  indication: 'Obesity',
  intent: ['coverage'],
  requested_dimensions: ['prior authorization'],
  treatment_stage: 'initiation',
  semantic_intent: 'invented scope',
  requested_information: 'invented scope',
  information_need: 'invented scope',
  retrieval_queries: ['invented scope'],
  search_concepts: ['invented scope'],
  search_phrases: ['invented scope'],
  search_query: 'invented scope',
  negation: [], temporal_context: null,
}, [
  { id: 'mounjaro', canonical_name: 'Mounjaro', normalized_name: 'mounjaro', entity_type: 'medication_brand' },
  { id: 'tirzepatide', canonical_name: 'Tirzepatide', normalized_name: 'tirzepatide', entity_type: 'medication_generic' },
], [
  { entity_id: 'mounjaro', alias: 'Mounjaro', normalized_alias: 'mounjaro', verified: true },
]);
assert.equal(groundedBareMedication.route, 'catalog_discovery');
assert.equal(groundedBareMedication.indication, null);
assert.equal(groundedBareMedication.treatment_stage, null);
assert.deepEqual(groundedBareMedication.intent, ['overview']);
assert.ok(groundedBareMedication.information_need.includes('Mounjaro (Tirzepatide)'));
assert.equal(groundEntityOnlySemantic('Mounjaro dose?', groundedBareMedication, resolved, aliases), groundedBareMedication);

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

const eosDimensions = requestedDimensions(
  'Brand asthma eos was 150 seven months ago, latest 290 from 2 months ago. ينفع للموافقة؟',
  { ...semantic, requested_dimensions: [], intent: ['approval'], facts: [
    { concept: 'eosinophil count', value: '150', unit: 'cells/uL', polarity: 'past', temporal: '7 months ago' },
    { concept: 'eosinophil count', value: '290', unit: 'cells/uL', polarity: 'current', temporal: '2 months ago' },
  ] },
);
assert.ok(eosDimensions.includes('labs'));
assert.ok(eosDimensions.includes('time_window'));
assert.ok(eosDimensions.includes('coverage'));

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
assert.deepEqual(
  new Set(evidenceForAnswer(selected.selected, ['E1'], ['dose', 'age']).map((item) => item.chunk_id)),
  new Set(['dose', 'age']),
);

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

const indicationScopedNumeric = rerankChunks([
  { ...base, chunk_id: 'right-indication', chunk_text: 'Severe eosinophilic asthma: eosinophils at least 150 within 6 months or at least 300 within 12 months', metadata: { medications: ['Generic A'], topics: ['labs', 'time_window'] }, score: 5 },
  { ...base, chunk_id: 'wrong-indication', chunk_text: 'COPD: eosinophils at least 150; reassess after 2 months', metadata: { medications: ['Generic A'], topics: ['labs', 'time_window'] }, score: 8 },
], [
  { id: 'generic-a', canonical_name: 'Generic A', normalized_name: 'generic a', entity_type: 'medication_generic' },
  { id: 'severe-asthma', canonical_name: 'Severe asthma', normalized_name: 'severe asthma', entity_type: 'indication' },
], ['labs', 'time_window'], null, 'Generic A severe asthma eos 150 two months ago');
assert.equal(indicationScopedNumeric[0].chunk_id, 'right-indication');
const indicationScopedSelection = selectEvidence(indicationScopedNumeric, ['labs', 'time_window']);
assert.deepEqual(indicationScopedSelection.selected.map((chunk) => chunk.chunk_id), ['right-indication']);

const openVocabularySemantic = {
  ...semantic,
  semantic_intent: 'identify which clinician specialties may prescribe the treatment',
  requested_information: 'eligible clinician specialties and documentation responsibility',
  search_concepts: ['prescriber specialty', 'eligible clinician', 'medical records'],
  search_phrases: ['eligible clinician specialty', 'document in medical records'],
  search_query: 'eligible clinician specialties prescribing documentation medical records',
  negation: [], temporal_context: null, drug_class: null,
};
const openPlan = buildRetrievalPlan('Who may prescribe and what goes in the record?', openVocabularySemantic, [], []);
assert.equal(enforceRouteSafety({ ...openVocabularySemantic, route: 'clarification_required', medication: null }, [], []).route, 'policy_question');
assert.ok(openPlan.query.includes('eligible clinician'));
assert.ok(openPlan.phrases.includes('eligible clinician specialty'));
const openRanked = rerankChunks([
  { ...base, chunk_id: 'generic-dose', chunk_text: 'Recommended dose once daily', score: 8 },
  { ...base, chunk_id: 'specialty-table', document_title: 'Policy table', section_title: 'Eligible clinicians', chunk_text: 'Column 1: Specialty\nColumn 2: Internal Medicine\nColumn 3: Document the schedule in medical records', metadata: { semantic_table_record: true, fields: { specialty: 'Internal Medicine' } }, row_from: 8, row_to: 9, score: 2 },
], [], [], null, 'Who may prescribe and what goes in the record?', openVocabularySemantic);
assert.equal(openRanked[0].chunk_id, 'specialty-table');
const openSelection = selectEvidence(openRanked, [], 6, openVocabularySemantic);
assert.equal(openSelection.selected[0].chunk_id, 'specialty-table');
assert.equal(openSelection.sufficient, true);
assert.ok(openSelection.requestedCoverage > 0);

const indicationIsolationSemantic = {
  ...openVocabularySemantic,
  indication: 'Condition Alpha',
  requested_dimensions: ['dose'],
  requested_information: 'dose for Condition Alpha',
};
const indicationIsolated = selectEvidence([
  { ...base, chunk_id: 'alpha-rule', section_title: 'Shared criteria', chunk_text: 'Condition Alpha: maintenance dose 25 mg weekly', metadata: { entity_specific: true }, indication_context_matches: 1, deterministic_score: 12 },
  { ...base, chunk_id: 'shared-documentation', section_title: 'Shared criteria', chunk_text: 'All requests require a signed clinical report', metadata: { entity_specific: false }, indication_context_matches: 0, deterministic_score: 11.5 },
  { ...base, chunk_id: 'beta-loading', section_title: 'Shared criteria', chunk_text: 'Condition Beta: loading dose 100 mg', metadata: { entity_specific: true }, indication_context_matches: 0, deterministic_score: 11 },
], ['dose'], 6, indicationIsolationSemantic);
assert.deepEqual(indicationIsolated.selected.map((chunk) => chunk.chunk_id), ['alpha-rule', 'shared-documentation']);
assert.ok(requestedDimensions('What documentation is required?', { ...openVocabularySemantic, requested_dimensions: [] }).includes('documentation'));
console.log('insurance-policy-v3 retrieval tests passed');
