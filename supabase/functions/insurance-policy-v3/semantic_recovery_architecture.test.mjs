import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ai = readFileSync(new URL('./ai.ts', import.meta.url), 'utf8');
const pipeline = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const provider = readFileSync(new URL('./ai_provider.ts', import.meta.url), 'utf8');
const engine = readFileSync(new URL('./reasoning_engine.ts', import.meta.url), 'utf8');

test('recovery performs one independent dynamic semantic expansion with 3-6 hypotheses', () => {
  assert.match(ai, /independently reinterpret/i);
  assert.match(ai, /value\.searches\.length >= 3/);
  assert.match(ai, /value\.searches\.length <= 6/);
  assert.match(ai, /relationship_direction/);
  assert.match(ai, /Arabic\/English\/mixed wording/);
});

test('first-pass candidates and verified evidence remain inputs to recovery', () => {
  assert.match(pipeline, /retrieved_candidates: units\.slice/);
  assert.match(pipeline, /selected_evidence: selection\.selected\.slice/);
  assert.match(pipeline, /first_pass_clues_reused/);
  assert.match(pipeline, /Build and inspect the normal evidence baseline for every request/);
  assert.doesNotMatch(pipeline, /if \(!pipelineContext\.forceRecovery\) \{\s+if \(retrievalMode/);
});

test('reverse and cross-document recovery is open-vocabulary and provenance preserving', () => {
  assert.match(ai, /reverse relationships/);
  assert.match(ai, /aggregate across documents while preserving provenance/);
  assert.match(pipeline, /recoveryPlan\.searches\.slice\(0, 6\)/);
});

test('normal path gets memory hints without overwriting semantic identity', () => {
  assert.match(pipeline, /findVerifiedSemanticMemory/);
  assert.match(pipeline, /rememberedQueries/);
  assert.match(pipeline, /rememberedConcepts/);
  assert.match(pipeline, /buildRetrievalPlan\(question, semantic, verifiedEntities, dimensions/);
  assert.doesNotMatch(pipeline, /semantic\.medication\s*=\s*memoryHint/);
});

test('temperature remains deterministic and provider fallback remains present', () => {
  assert.match(provider, /temperature:\s*0/);
  assert.match(provider, /groq_fallback/);
});

test('Incorrect and Incomplete feedback contracts remain available', () => {
  assert.match(pipeline, /const objective = feedbackObjective\(pipelineContext\.feedbackReason\)/);
  assert.match(pipeline, /preserve_supported_previous_facts: objective\.preserve_supported_previous_facts/);
  assert.match(engine, /require_alternative_semantic_hypotheses/);
  assert.match(pipeline, /feedback_reason: pipelineContext\.feedbackReason/);
  assert.match(pipeline, /maximumRecoveryIterations = aggregateRequested \? maximumAggregateRecoveryIterations : pipelineContext\.forceRecovery \? 2 : 1/);
  assert.match(pipeline, /semanticRequestedRecovery \|\| pipelineContext\.forceRecovery/);
  assert.match(pipeline, /pipelineContext\.forceRecovery && recoveryPlan\.decision !== 'search'/);
});

test('Question Contract remains attached through planning, evidence inspection, answer, and diagnostics', () => {
  assert.match(ai, /createQuestionContract/);
  assert.match(ai, /original_question: question/);
  assert.match(pipeline, /question_contract: questionContract/);
  assert.match(pipeline, /inspectEvidenceAgainstContract\(question, semantic, questionContract/);
  assert.match(pipeline, /answerFromEvidence\([\s\S]*question, semantic, answerEvidence[\s\S]*questionContract, evidenceLedger, sharedAnswerContext/);
});

test('facet ledger and final verifier reject nearby relationship answers before display', () => {
  assert.match(ai, /A facet is supported only when the evidence answers that exact requested relationship\/direction/);
  assert.match(ai, /intent drift/i);
  assert.match(ai, /answer_rejected_before_display/);
  assert.match(pipeline, /trace\.answer_verifier = answerResult\.verifier/);
  assert.match(pipeline, /\['reverse', 'bidirectional', 'comparison'\]\.includes/);
});

test('table evidence retains headers, rows, footnotes, and table title', () => {
  assert.match(ai, /table_title: chunk\.metadata/);
  assert.match(ai, /headers: chunk\.metadata/);
  assert.match(ai, /row_text: chunk\.metadata/);
  assert.match(ai, /footnotes: chunk\.metadata/);
});

test('clarification is blocked when retrieval is difficult but material ambiguity is absent', () => {
  assert.match(pipeline, /clarificationGate\(questionContract, semantic\)/);
  assert.match(pipeline, /!currentClarificationGate\.allow_clarification/);
  assert.match(pipeline, /Retrieval difficulty is not material user ambiguity/);
});

test('numeric hypothesis sanitation cannot invalidate an otherwise valid AI contract', () => {
  assert.match(ai, /modelHypotheses\.length > 0 \? modelHypotheses/);
  assert.match(ai, /query: question\.slice\(0, 500\)/);
  assert.doesNotMatch(ai, /facets\.length === 0 \|\| hypotheses\.length === 0/);
});

test('bounded search ends in clarification for two or more material contract interpretations', () => {
  assert.match(ai, /interpretations: \{ type: 'array', minItems: 2, maxItems: 4/);
  assert.match(pipeline, /materialInterpretations\.length >= 2/);
  assert.match(pipeline, /material_contract_ambiguity_after_bounded_search/);
  assert.match(pipeline, /answer_status: 'clarification_required'/);
});

test('automatic semantic learning records every conservative eligibility gate', () => {
  assert.match(pipeline, /learning_eligibility: semanticLearningChecks/);
  assert.match(pipeline, /answer_verifier_passed/);
  assert.match(pipeline, /all_source_snapshots_resolved/);
  assert.match(pipeline, /Object\.values\(semanticLearningChecks\)\.every\(Boolean\)/);
});
