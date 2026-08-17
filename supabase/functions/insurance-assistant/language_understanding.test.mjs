import assert from 'node:assert/strict';
import test from 'node:test';

import {
  classifyAnswerMode,
  defaultLanguageConfiguration,
  detectLanguage,
  extractRequestedLabNames,
  extractTopicHints,
  normalizeForUnderstanding,
  requestedAnswerCount,
  understandQuery,
} from './language_understanding.ts';

const entity = (name, type = 'medication', documents = ['document-1']) => ({
  entity_type: type,
  canonical_name: name,
  normalized_entity: name.toLowerCase(),
  matched_alias: name,
  match_kind: 'exact',
  match_score: 1,
  document_ids: documents,
  metadata: {},
});

test('answer mode distinguishes overview, complete lists, comparisons and single facts', () => {
  assert.equal(classifyAnswerMode('What are CGRP inhibitors used for?', 'indication'), 'overview');
  assert.equal(classifyAnswerMode('Which medications are classified as Gepants?', 'classification'), 'list');
  assert.equal(classifyAnswerMode('Compare Ubrogepant versus Atogepant', 'comparison'), 'comparison');
  assert.equal(classifyAnswerMode('What is the maximum dose of Ubrogepant?', 'maximum_dose'), 'single_fact');
});

test('explicit list cardinality is extracted from words and digits', () => {
  assert.equal(requestedAnswerCount('What are the two main classes?'), 2);
  assert.equal(requestedAnswerCount('List 4 medications'), 4);
  assert.equal(requestedAnswerCount('Which medications are Gepants?'), null);
});

test('normalization preserves display input separately and normalizes Arabic numerals', () => {
  const raw = 'هل HbA1c ٦٫٥ مقبول؟';
  const parsed = understandQuery({ question: raw });
  assert.equal(parsed.rawQuestion, raw);
  assert.match(normalizeForUnderstanding(raw), /hba1c 6/);
  assert.equal(detectLanguage(raw), 'mixed');
});

test('controlled clinical typo repair normalizes query language without rewriting medicine names', () => {
  assert.equal(normalizeForUnderstanding('HbAc1'), 'hba1c');
  assert.equal(normalizeForUnderstanding('Hb1Ac'), 'hba1c');
  assert.equal(normalizeForUnderstanding('give me a breif'), 'give me a brief');
  assert.equal(normalizeForUnderstanding('should be mentined'), 'should be mentioned');
  assert.equal(normalizeForUnderstanding('Mounjaroo'), 'mounjaroo');
});

test('GLP-1 spelling and separator variants share one topic representation', () => {
  for (const variant of ['GLP-1', 'GLP 1', 'GLP1', 'GLP_1', 'GLP/1', 'GLP–1']) {
    assert.equal(normalizeForUnderstanding(variant), 'glp 1');
    assert.deepEqual(extractTopicHints(variant), ['glp 1']);
  }
});

test('requested lab names are extracted even when the question contains no numeric result', () => {
  assert.deepEqual(
    extractRequestedLabNames('What HbAc1 should be mentined in the report?'),
    ['hba1c'],
  );
});

test('definition question is not reclassified as dispensing merely because source entity exists', () => {
  const parsed = understandQuery({
    question: 'What is Mounjaro?',
    entityMatches: [entity('Mounjaro')],
  });
  assert.equal(parsed.primaryIntent, 'entity_definition');
  assert.equal(parsed.entities.medications[0].canonicalName, 'Mounjaro');
  assert.doesNotMatch(parsed.primaryIntent, /dispens|dose/);
});

test('a bare resolved entity produces an explicit lookup contract', () => {
  const parsed = understandQuery({
    question: 'Mounjaro',
    entityMatches: [entity('Mounjaro')],
  });
  assert.equal(parsed.primaryIntent, 'bare_entity_lookup');
  assert.equal(parsed.answerMode, 'bare_entity_lookup');
  assert.equal(parsed.answerContract.requiresAggregation, true);
  assert.ok(parsed.answerContract.evidenceTargets.includes('definition'));
});

test('brief typo is recognized as an overview with an aggregation contract', () => {
  const parsed = understandQuery({
    question: 'give me a breif about GLP-1 rule',
    entityMatches: [entity('GLP-1 Receptor Agonists', 'therapy_class')],
  });
  assert.equal(parsed.primaryIntent, 'document_summary');
  assert.equal(parsed.answerMode, 'overview');
  assert.deepEqual(parsed.topicHints, ['glp 1']);
  assert.equal(parsed.answerContract.requiresAggregation, true);
  assert.ok(parsed.answerContract.evidenceTargets.includes('indication'));
  assert.ok(parsed.answerContract.evidenceTargets.includes('documentation'));
});

test('an explicit therapy topic overrides stale conversation context', () => {
  const parsed = understandQuery({
    question: 'give me a brief about GLP1 rule',
    previousContext: {
      primary_intent: 'document_summary',
      last_entity: 'CGRP inhibitors',
      last_document_id: 'cgrp-document',
      last_therapy_topic: 'CGRP inhibitors',
    },
  });
  assert.equal(parsed.isFollowUp, false);
  assert.deepEqual(parsed.topicHints, ['glp 1']);
  assert.equal(parsed.primaryIntent, 'document_summary');
  assert.equal(parsed.unresolved.includes('entity'), false);
});

test('a fully worded lab-report question follows the active policy and declares all required fields', () => {
  const parsed = understandQuery({
    question: 'what is the result of HbAc1 should be mentined in the report',
    previousContext: {
      primary_intent: 'document_summary',
      last_entity: 'GLP-1',
      last_entity_normalized: 'glp 1',
      last_document_id: 'glp-document',
      last_therapy_topic: 'GLP-1 Receptor Agonists',
    },
  });
  assert.equal(parsed.isFollowUp, true);
  assert.deepEqual(parsed.patient.requestedLabs, ['hba1c']);
  const intents = new Set([parsed.primaryIntent, ...parsed.secondaryIntents]);
  assert.ok(intents.has('lab_requirement'));
  assert.ok(intents.has('report_content'));
  assert.equal(parsed.answerMode, 'multi_requirement');
  assert.ok(parsed.answerContract.requiredFields.includes('lab_name'));
  assert.ok(parsed.answerContract.requiredFields.includes('lab_threshold'));
  assert.ok(parsed.answerContract.requiredFields.includes('report_content'));
});

test('compound scenario retains all requested criteria and multiple intents', () => {
  const parsed = understandQuery({
    question: 'Patient is 17, HbA1c is 6.8, and the doctor is Family Medicine. Can I dispense this for 3 months without approval?',
    entityMatches: [entity('Family Medicine', 'provider_specialty', [])],
  });
  assert.equal(parsed.patient.age, 17);
  assert.equal(parsed.patient.labs.hba1c.value, 6.8);
  assert.equal(parsed.dispensing.requestedDuration.value, 3);
  assert.equal(parsed.dispensing.requestedDuration.unit, 'month');
  assert.equal(parsed.provider.specialty, 'Family Medicine');
  assert.equal(parsed.modifiers.negated, true);
  const intents = new Set([parsed.primaryIntent, ...parsed.secondaryIntents]);
  assert.ok(intents.has('dispensing_duration'));
  assert.ok(intents.has('prior_authorization'));
  assert.ok(intents.has('age_eligibility'));
  assert.ok(intents.has('lab_requirement'));
});

const intentCases = [
  ['coverage', 'is this med covered'],
  ['coverage', 'هالدواء بيمشي ضمان؟'],
  ['prior_authorization', 'need PA?'],
  ['prior_authorization', 'بدها approval؟'],
  ['dispensing_duration', 'can give 3 months supply?'],
  ['dispensing_duration', 'ممكن اصرف 3 شهور؟'],
  ['maximum_dose', 'max 24 hours?'],
  ['maximum_dose', 'شو أقصى جرعة باليوم؟'],
  ['indication', 'can use chronic prevention?'],
  ['indication', 'ينفع للوقاية المزمنة؟'],
  ['prescriber_specialty', 'family medicine can prescribe?'],
  ['prescriber_specialty', 'Family Medicine ممكن يوصفه؟'],
  ['step_therapy', 'tried one class enough?'],
  ['step_therapy', 'جرب علاج واحد بكفي؟'],
  ['previous_treatment_duration', 'two classes 4 weeks each?'],
  ['refill', 'can give 3 month no refill?'],
  ['lab_requirement', 'HbA1c 6.3 pass?'],
  ['source_request', 'where does it say that?'],
  ['source_request', 'ورجيني المصدر'],
];

for (const [expected, question] of intentCases) {
  test(`classifies ${JSON.stringify(question)} as ${expected}`, () => {
    const parsed = understandQuery({
      question,
      previousContext: { primary_intent: expected, last_entity: 'Current medicine' },
      entityMatches: [],
    });
    assert.ok(
      parsed.primaryIntent === expected || parsed.secondaryIntents.includes(expected),
      `${question}: ${parsed.primaryIntent} / ${parsed.secondaryIntents.join(', ')}`,
    );
  });
}

test('short numeric follow-up inherits intent without inventing a new entity', () => {
  const parsed = understandQuery({
    question: 'طيب لو 19؟',
    previousContext: {
      primary_intent: 'age_eligibility',
      last_intent: 'age_eligibility',
      last_entity: 'Current medication',
    },
  });
  assert.equal(parsed.isFollowUp, true);
  assert.equal(parsed.patient.age, 19);
  assert.equal(parsed.primaryIntent, 'age_eligibility');
});

test('explicit entity is available for context override', () => {
  const parsed = understandQuery({
    question: 'What is NewMedicine?',
    previousContext: {
      primary_intent: 'dosage',
      last_entity: 'OldMedicine',
      last_document_id: 'old-document',
    },
    entityMatches: [entity('NewMedicine', 'medication', ['new-document'])],
  });
  assert.equal(parsed.entities.medications[0].canonicalName, 'NewMedicine');
  assert.deepEqual(parsed.entities.medications[0].documentIds, ['new-document']);
  assert.equal(parsed.primaryIntent, 'entity_definition');
});

test('configuration is extensible without changing classifier code', () => {
  const configuration = defaultLanguageConfiguration();
  configuration.aliases.push({
    phrase: 'green light',
    normalized_concept: 'coverage',
    alias_type: 'intent_phrase',
    language: 'en',
    weight: 1,
  });
  const parsed = understandQuery({ question: 'green light?', configuration });
  assert.equal(parsed.primaryIntent, 'coverage');
});

test('numeric Omega-3 continuation question is a condition evaluation with compatible intents', () => {
  const parsed = understandQuery({
    question: 'patient using omega 3 one year but TG drop only 10%, we continue or stop?',
    entityMatches: [entity('Omega-3 Therapies', 'therapy_class', ['omega-document'])],
  });
  const intents = new Set([parsed.primaryIntent, ...parsed.secondaryIntents]);
  assert.equal(parsed.answerMode, 'condition_evaluation');
  assert.ok(intents.has('stop_therapy'));
  assert.ok(intents.has('response_threshold'));
  assert.equal(parsed.therapy.response.value, 10);
  assert.equal(parsed.therapy.response.unit, '%');
});

test('Botox frequency eligibility is recognized as a clinical condition evaluation', () => {
  const parsed = understandQuery({
    question: 'patient have migraine 14 days every month, can use botox or not?',
    entityMatches: [entity('Botox', 'medication', ['botox-document'])],
  });
  const intents = new Set([parsed.primaryIntent, ...parsed.secondaryIntents]);
  assert.ok(intents.has('coverage') || intents.has('indication'));
  assert.equal(parsed.answerMode, 'condition_evaluation');
});

test('Omega3 topic normalization is independent of punctuation', () => {
  for (const question of ['Omega 3 stop criteria', 'Omega-3 stop criteria', 'Omega3 stop criteria']) {
    const parsed = understandQuery({ question });
    assert.ok(parsed.topicHints.includes('omega 3'), question);
  }
});
