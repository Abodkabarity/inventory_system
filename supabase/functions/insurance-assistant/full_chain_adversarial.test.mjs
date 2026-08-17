import assert from 'node:assert/strict';
import test from 'node:test';

import {
  advanceConversationContext,
  buildAnswer,
  createSearchPlan,
  filterEvidence,
  parseQuery,
  recoverContextFromMessages,
} from './logic.ts';
import {
  composeVerifiedGroundedAnswer,
  selectSupportingEvidence,
} from './grounded_answer.ts';
import { understandQuery } from './language_understanding.ts';

const GLP_DOCUMENT_ID = '690994d4-5365-4472-99c0-d95110c43391';
const GLP_DOCUMENT_TITLE = 'GLP-1 Receptor Agonists — Adjudication Rule Summary';
const GALCANEZUMAB_DOCUMENT_ID = 'b66b437c-189b-4b4c-b0ca-d8a119ab2cb8';

const glpResolvedEntity = {
  entity_type: 'therapy_class',
  canonical_name: 'GLP-1',
  normalized_entity: 'glp 1',
  document_id: GLP_DOCUMENT_ID,
  document_title: GLP_DOCUMENT_TITLE,
  therapy_topic: 'GLP-1',
  resolution_source: 'entity_registry_exact_alias',
};

const glpEntityMatch = {
  entity_type: 'therapy_class',
  canonical_name: 'GLP-1',
  normalized_entity: 'glp 1',
  matched_alias: 'GLP 1',
  match_kind: 'exact',
  match_score: 1,
  document_ids: [GLP_DOCUMENT_ID],
  metadata: {},
};

function row({
  chunkId,
  documentId,
  documentTitle,
  content,
  combinedScore,
  semanticScore = combinedScore,
  lexicalScore = 0.2,
  intentScore = 1,
  contextScore = 0,
  accepted = true,
  acceptanceReason = 'accepted_fixture_candidate',
  page = 1,
  entityName = null,
  entityNormalized = null,
  queryEntity = null,
  queryEntityNormalized = null,
}) {
  return {
    chunk_id: chunkId,
    document_id: documentId,
    document_title: documentTitle,
    file_name: `${documentId}.pdf`,
    storage_bucket: 'insurance-documents',
    storage_path: `${documentId}.pdf`,
    matched_content: content,
    chunk_metadata: {
      document_topic: documentTitle,
      topic_normalized: documentTitle.toLowerCase(),
      fields: {},
    },
    section_title: 'Adjudication Guideline Summary',
    page_from: page,
    page_to: page,
    sheet_name: null,
    row_from: null,
    row_to: null,
    entity_type: entityName ? 'medication' : null,
    entity_name: entityName,
    entity_name_normalized: entityNormalized,
    query_entity: queryEntity,
    query_entity_normalized: queryEntityNormalized,
    entity_score: entityNormalized && entityNormalized === queryEntityNormalized ? 1 : 0,
    intent_score: intentScore,
    context_score: contextScore,
    accepted,
    acceptance_reason: acceptanceReason,
    lexical_score: lexicalScore,
    semantic_score: semanticScore,
    combined_score: combinedScore,
  };
}

function overridesFromStructuredQuery(structured) {
  const strength = structured.entities.strength;
  return {
    intent: structured.primaryIntent,
    patientAge: structured.patient.age,
    strength: strength ? `${strength.value} ${strength.unit ?? ''}`.trim() : null,
    treatmentMode: structured.therapy.treatmentScope,
    conditionScope: /\bepisodic\b/i.test(structured.normalizedQuestion)
      ? 'episodic'
      : /\bchronic\b/i.test(structured.normalizedQuestion)
        ? 'chronic'
        : null,
    contextualFollowUp: structured.isFollowUp,
    answerMode: structured.answerMode,
    requestedCount: structured.requestedCount,
  };
}

function glpOverviewRows() {
  return [
    row({
      chunkId: 'glp-overview-page-1',
      documentId: GLP_DOCUMENT_ID,
      documentTitle: GLP_DOCUMENT_TITLE,
      combinedScore: 1.3,
      lexicalScore: 0.9,
      queryEntity: 'GLP-1',
      queryEntityNormalized: 'glp 1',
      content:
        'GLP-1 receptor agonists are indicated as an adjunct to diet and exercise for adults with type 2 diabetes mellitus. ' +
        'Initial therapy requires HbA1c ≥ 6.5%, dated within the past 3 months. ' +
        'Ozempic 0.25 mg and Mounjaro 2.5 mg are initial non-therapeutic doses limited to a one-month supply with no refills.',
    }),
    row({
      chunkId: 'glp-overview-page-2',
      documentId: GLP_DOCUMENT_ID,
      documentTitle: GLP_DOCUMENT_TITLE,
      combinedScore: 1.2,
      lexicalScore: 0.8,
      page: 2,
      queryEntity: 'GLP-1',
      queryEntityNormalized: 'glp 1',
      content:
        'Switching between GLP-1 receptor agonists requires a signed and stamped report containing the most recent HbA1c ≥ 6.5%, dated within the past 3 months, and a clear justification for the switch. ' +
        'Eligible specialties include Internal Medicine, Endocrinology, Family Medicine, and Cardiology.',
    }),
  ];
}

function glpReportRow() {
  return row({
    chunkId: 'glp-hba1c-report',
    documentId: GLP_DOCUMENT_ID,
    documentTitle: GLP_DOCUMENT_TITLE,
    combinedScore: 0.72,
    semanticScore: 0.51,
    lexicalScore: 0.91,
    contextScore: 1,
    page: 1,
    queryEntity: 'GLP-1',
    queryEntityNormalized: 'glp 1',
    content:
      'The clinical report must include the most recent HbA1c ≥ 6.5%, dated within the past 3 months. ' +
      'The report must be signed and stamped by the prescribing clinician.',
  });
}

function wrongTopicGalcanezumabRow() {
  return row({
    chunkId: 'galcanezumab-high-semantic-distractor',
    documentId: GALCANEZUMAB_DOCUMENT_ID,
    documentTitle: 'Galcanezumab use for Cluster Headach Summary',
    combinedScore: 9.9,
    semanticScore: 0.99,
    lexicalScore: 0.82,
    intentScore: 1,
    page: 2,
    content:
      'Dosage and administration must be mentioned in the medical report: Galcanezumab 300 mg ' +
      '(3 × 100 mg SC injections) at onset of the cluster period, then monthly until the end.',
  });
}

test('full chain keeps GLP-1 context across a misspelled brief and HbAc1 report follow-up', () => {
  const overviewQuestion = 'give me breif about GLP 1 rule';
  const overviewUnderstanding = understandQuery({
    question: overviewQuestion,
    entityMatches: [glpEntityMatch],
  });

  assert.equal(overviewUnderstanding.primaryIntent, 'document_summary');
  assert.equal(overviewUnderstanding.answerMode, 'overview');

  const overviewPlan = createSearchPlan(
    overviewQuestion,
    {},
    glpResolvedEntity,
    overridesFromStructuredQuery(overviewUnderstanding),
  );
  assert.equal(overviewPlan.documentId, GLP_DOCUMENT_ID);
  assert.equal(overviewPlan.therapyTopic, 'GLP-1');

  const overviewRows = glpOverviewRows();
  const overviewParsed = parseQuery(overviewQuestion, overviewRows, overviewPlan);
  const overviewEvidence = filterEvidence(overviewRows, overviewParsed);
  assert.ok(overviewEvidence.length >= 2, 'An overview must collect multiple supporting facets.');

  const activeContext = {
    schema_version: 1,
    primary_intent: overviewUnderstanding.primaryIntent,
    last_intent: overviewParsed.intent,
    last_entity: 'GLP-1',
    last_entity_normalized: 'glp 1',
    last_document_id: GLP_DOCUMENT_ID,
    last_document_title: GLP_DOCUMENT_TITLE,
    last_therapy_topic: 'GLP-1',
  };

  const reportQuestion = 'what is the result of HbAc1 should be mentined in the report';
  const reportUnderstanding = understandQuery({
    question: reportQuestion,
    previousContext: activeContext,
    entityMatches: [],
  });

  assert.equal(reportUnderstanding.isFollowUp, true);
  assert.match(reportUnderstanding.normalizedQuestion, /hba1c/);
  assert.ok(
    new Set([reportUnderstanding.primaryIntent, ...reportUnderstanding.secondaryIntents])
      .has('report_content'),
    `Expected report_content, got ${reportUnderstanding.primaryIntent} / ${reportUnderstanding.secondaryIntents.join(', ')}`,
  );
  assert.ok(
    new Set([reportUnderstanding.primaryIntent, ...reportUnderstanding.secondaryIntents])
      .has('lab_requirement'),
    `Expected lab_requirement, got ${reportUnderstanding.primaryIntent} / ${reportUnderstanding.secondaryIntents.join(', ')}`,
  );

  const reportPlan = createSearchPlan(
    reportQuestion,
    activeContext,
    null,
    overridesFromStructuredQuery(reportUnderstanding),
  );
  assert.equal(reportPlan.contextualFollowUp, true);
  assert.equal(reportPlan.documentId, GLP_DOCUMENT_ID);
  assert.equal(reportPlan.therapyTopic, 'GLP-1');

  const candidates = [wrongTopicGalcanezumabRow(), glpReportRow()];
  const parsed = parseQuery(reportQuestion, candidates, reportPlan);
  const evidence = filterEvidence(candidates, parsed);
  assert.deepEqual(evidence.map((candidate) => candidate.chunk_id), ['glp-hba1c-report']);

  const result = buildAnswer(reportQuestion, parsed, evidence);
  assert.match(result.answer, /HbA1c/i);
  assert.match(result.answer, /6\.5%/);
  assert.match(result.answer, /past 3 months/i);
  assert.match(result.answer, /signed and stamped/i);
  assert.doesNotMatch(result.answer, /Galcanezumab|cluster|300 mg/i);
});

test('a higher semantic score cannot override a hard GLP-1 document/topic scope', () => {
  const question = 'What HbA1c should be mentioned in the report?';
  const context = {
    last_entity: 'GLP-1',
    last_entity_normalized: 'glp 1',
    last_intent: 'documentation',
    last_document_id: GLP_DOCUMENT_ID,
    last_document_title: GLP_DOCUMENT_TITLE,
    last_therapy_topic: 'GLP-1',
  };
  const plan = createSearchPlan(question, context, null, {
    intent: 'documentation',
    contextualFollowUp: true,
    answerMode: 'multi_requirement',
  });
  const candidates = [wrongTopicGalcanezumabRow(), glpReportRow()];
  const parsed = parseQuery(question, candidates, plan);
  const evidence = filterEvidence(candidates, parsed);

  assert.equal(candidates[0].combined_score, 9.9);
  assert.equal(candidates[1].combined_score, 0.72);
  assert.deepEqual(evidence.map((candidate) => candidate.document_id), [GLP_DOCUMENT_ID]);
  assert.ok(evidence.every((candidate) => !/Galcanezumab/i.test(candidate.document_title)));
});

test('message-based recovery does not let a wrong citation replace established GLP-1 context', () => {
  const stored = {
    last_entity: 'GLP-1',
    last_entity_normalized: 'glp 1',
    last_intent: 'document_summary',
    last_document_id: GLP_DOCUMENT_ID,
    last_document_title: GLP_DOCUMENT_TITLE,
    last_therapy_topic: 'GLP-1',
  };
  const recovered = recoverContextFromMessages(stored, [
    {
      role: 'assistant',
      parsed_data: {
        intent: 'unknown',
        medication: null,
        confidence: 0.14,
      },
      citations: [{
        entity_name: null,
        document_id: GALCANEZUMAB_DOCUMENT_ID,
        document_title: 'Galcanezumab use for Cluster Headach Summary',
      }],
    },
  ]);

  assert.deepEqual(recovered, stored);
});

test('answer composition exposes the exact evidence IDs used for citation derivation', async () => {
  const question = 'What must be in the clinical report?';
  const plan = createSearchPlan(question, {}, null, {
    intent: 'documentation',
    answerMode: 'single_fact',
  });
  const best = glpReportRow();
  const secondary = row({
    chunkId: 'glp-secondary-documentation',
    documentId: GLP_DOCUMENT_ID,
    documentTitle: GLP_DOCUMENT_TITLE,
    combinedScore: 0.6,
    content: 'A separate maintenance confirmation may be requested for another dispensing scenario.',
  });
  const parsed = parseQuery(question, [best, secondary], plan);
  const evidence = filterEvidence([best, secondary], parsed);
  const structuredQuery = understandQuery({ question });
  const result = await composeVerifiedGroundedAnswer({
    query: question,
    parsed,
    structuredQuery,
    rows: evidence,
    // Force the deterministic, locally verifiable path for this regression
    // test. Model behavior is covered separately with a mocked Responses API.
    apiKey: '',
  });

  assert.ok(Array.isArray(result.usedEvidenceIds), 'Composer must return usedEvidenceIds.');
  assert.deepEqual(result.usedEvidenceIds, [best.chunk_id]);

  const citationRows = evidence.filter((candidate) => result.usedEvidenceIds.includes(candidate.chunk_id));
  assert.deepEqual(citationRows.map((candidate) => candidate.chunk_id), [best.chunk_id]);
  assert.deepEqual(
    selectSupportingEvidence(result.answer, evidence).map((candidate) => candidate.chunk_id),
    [best.chunk_id],
  );
});

test('session context advances only from verified evidence and cannot be poisoned by a wrong topic', () => {
  const current = {
    last_entity: 'GLP-1',
    last_entity_normalized: 'glp 1',
    last_intent: 'document_summary',
    last_document_id: GLP_DOCUMENT_ID,
    last_document_title: GLP_DOCUMENT_TITLE,
    last_therapy_topic: 'GLP-1',
    last_evidence_ids: ['glp-overview-page-1'],
  };
  const question = 'What HbA1c should be mentioned in the report?';
  const plan = createSearchPlan(question, current, null, {
    intent: 'lab_requirement',
    contextualFollowUp: true,
    answerMode: 'multi_requirement',
  });
  const correctEvidence = glpReportRow();
  const parsed = parseQuery(question, [correctEvidence], plan);
  const distractor = wrongTopicGalcanezumabRow();

  const unsafeTurns = [
    {
      name: 'wrong-topic evidence despite a high answer confidence',
      input: {
        parsed,
        plan,
        answerStatus: 'answered',
        confidence: 0.99,
        usedEvidence: [distractor],
        evidenceIds: [distractor.chunk_id],
      },
    },
    {
      name: 'low-confidence answer',
      input: {
        parsed,
        plan,
        answerStatus: 'answered',
        confidence: 0.35,
        usedEvidence: [correctEvidence],
        evidenceIds: [correctEvidence.chunk_id],
      },
    },
    {
      name: 'answer without validated evidence',
      input: {
        parsed,
        plan,
        answerStatus: 'answered',
        confidence: 0.99,
        usedEvidence: [],
        evidenceIds: [],
      },
    },
    {
      name: 'unknown intent even if retrieval found a row',
      input: {
        parsed: { ...parsed, intent: 'unknown' },
        plan,
        answerStatus: 'answered',
        confidence: 0.99,
        usedEvidence: [correctEvidence],
        evidenceIds: [correctEvidence.chunk_id],
      },
    },
  ];

  for (const scenario of unsafeTurns) {
    assert.deepEqual(
      advanceConversationContext(current, scenario.input),
      current,
      `Context changed for unsafe scenario: ${scenario.name}`,
    );
  }

  const advanced = advanceConversationContext(current, {
    parsed,
    plan,
    answerStatus: 'answered',
    confidence: 0.97,
    usedEvidence: [correctEvidence],
    evidenceIds: [correctEvidence.chunk_id],
    language: 'en',
  });
  assert.equal(advanced.last_document_id, GLP_DOCUMENT_ID);
  assert.equal(advanced.last_therapy_topic, 'GLP-1');
  assert.equal(advanced.last_intent, 'lab_requirement');
  assert.deepEqual(advanced.last_evidence_ids, [correctEvidence.chunk_id]);
});
