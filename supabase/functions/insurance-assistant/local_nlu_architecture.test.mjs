import assert from 'node:assert/strict';
import test from 'node:test';

import { buildTurnContext, filterEvidence } from './logic.ts';
import { applyLocalNluInterpretation } from './local_nlu.ts';

const baseQuery = {
  schemaVersion: 1,
  rawQuestion: 'ondansetron 8 weeks pregnant ok?',
  normalizedQuestion: 'ondansetron 8 weeks pregnant ok',
  language: 'en', isFollowUp: false, conversational: false,
  answerMode: 'single_fact', requestedCount: null, topicHints: [],
  primaryIntent: 'unknown', secondaryIntents: [], intentCandidates: [],
  answerContract: { mode: 'single_fact', requiredFields: [], requestedLabNames: [], evidenceTargets: [], expectedCount: null, requiresAggregation: false, requiresCompleteEvidence: false, directAnswerPreferred: true },
  canonicalPlan: { primaryEntity: null, entityType: null, indication: null, intent: 'unknown', secondaryIntents: [], answerMode: 'single_fact', requestedFields: [], conditions: [], missingSlots: [], inheritedContext: false, canonicalSearchTerms: [], canonicalSearchText: '' },
  entities: { medications: [], ingredients: [], therapyClasses: [], insuranceCompany: null, insurancePlan: null, diagnoses: [], documents: [], denialCodes: [], strength: null, dosageForm: null, route: null },
  patient: { age: null, sex: null, pregnancy: null, breastfeeding: null, diagnoses: [], comorbidities: [], requestedLabs: [], labs: {}, scores: {}, clinicalValues: {} },
  therapy: { treatmentScope: null, treatmentStage: null, previousTreatments: [], previousTreatmentCount: null, trialDuration: null, response: null, reasonForSwitch: null },
  dispensing: { requestedQuantity: null, requestedDuration: null, refills: null, frequency: null },
  provider: { specialty: null }, modifiers: { negated: false, comparison: false, hypothetical: false, askingException: false },
  confidence: { intent: 0, entity: 0, values: 0, slots: 0, context: 0, overall: 0 }, unresolved: [],
};

test('new explicit entity clears every stale clinical slot before the turn', () => {
  const old = {
    last_entity: 'Mepolizumab', last_document_id: 'mepo-doc', last_therapy_topic: 'asthma',
    patient: { clinicalValues: { eosinophil: { value: 160 } } },
    therapy: { treatmentStage: 'continuation' }, dispensing: { requestedDuration: { value: 6 } },
  };
  const turn = buildTurnContext(old, { explicitNewEntity: true, isFollowUp: false });
  assert.equal(turn.context.last_entity, undefined);
  assert.equal(turn.context.patient, undefined);
  assert.equal(turn.context.therapy, undefined);
  assert.ok(turn.clearedKeys.includes('patient'));
});

test('schema-validated local semantics require a catalog-confirmed entity', () => {
  const semantic = {
    raw_query: 'ondansetron 8 weeks pregnant ok?', normalized_query: 'ondansetron 8 weeks pregnant ok', language: 'en',
    entity: 'Ondansetron', canonical_entity: 'Ondansetron', entity_confidence: .95,
    topic: 'pregnancy', diagnosis: null, primary_intent: 'eligibility_check', secondary_intents: [], intent_confidence: .92,
    answer_mode: 'condition_evaluation', requested_fields: ['pregnancy_week'],
    criteria: [{ field: 'pregnancy_week', value: 8, unit: 'weeks', operator: '=' }],
    missing_information: [], is_followup: false, explicit_new_entity: true,
  };
  const confirmed = [{ entity_type: 'medication', canonical_name: 'Ondansetron', normalized_entity: 'ondansetron', matched_alias: 'Ondansetron', match_kind: 'exact', match_score: 1, document_ids: ['ond-doc'], metadata: {} }];
  const query = applyLocalNluInterpretation(baseQuery, semantic, confirmed);
  assert.equal(query.canonicalPlan.primaryEntity, 'Ondansetron');
  assert.equal(query.canonicalPlan.intent, 'eligibility_check');
  assert.equal(query.canonicalPlan.conditions[0].value, 8);
  assert.equal(query.patient.clinicalValues.eosinophil, undefined);
});

test('hard entity gate rejects a high-scoring different medication', () => {
  const shared = { accepted: true, document_title: 'Policy', file_name: 'p.pdf', storage_bucket: 'b', storage_path: 'x', entity_score: 1, intent_score: 1, context_score: 1, lexical_score: .9, semantic_score: .9, combined_score: .9, acceptance_reason: 'test' };
  const rows = [
    { ...shared, chunk_id: 'wrong', document_id: 'mepo', matched_content: 'Mepolizumab eosinophil 160', entity_name_normalized: 'mepolizumab', query_entity_normalized: 'mepolizumab' },
    { ...shared, chunk_id: 'right', document_id: 'wegovy', matched_content: 'Wegovy fibrosis stage F2 or F3', entity_name_normalized: 'wegovy', query_entity_normalized: 'wegovy' },
  ];
  const parsed = { intent: 'coverage', entity: 'Wegovy', entityNormalized: 'wegovy', patientAge: null, strength: null, treatmentMode: null, conditionScope: null, timePeriodHours: null, documentId: null, documentTitle: null, therapyTopic: null, documentFamily: null, topicHint: null, explicitEntity: true, inheritedContext: false, needsClarification: false, answerMode: 'condition_evaluation', requestedCount: null };
  assert.deepEqual(filterEvidence(rows, parsed).map((row) => row.chunk_id), ['right']);
});
