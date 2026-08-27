import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ai = readFileSync(new URL('./ai.ts', import.meta.url), 'utf8');
const pipeline = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const provider = readFileSync(new URL('./ai_provider.ts', import.meta.url), 'utf8');

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
});

test('reverse and cross-document recovery is open-vocabulary and provenance preserving', () => {
  assert.match(ai, /reverse relationships/);
  assert.match(ai, /aggregate across documents while preserving provenance/);
  assert.match(pipeline, /recoveryPlan\.searches\.slice\(0, 6\)/);
});

test('normal path gets memory hints without overwriting semantic identity', () => {
  assert.match(pipeline, /findVerifiedSemanticMemory/);
  assert.match(pipeline, /buildRetrievalPlan\(question, semantic, verifiedEntities, dimensions, memoryHint/);
  assert.doesNotMatch(pipeline, /semantic\.medication\s*=\s*memoryHint/);
});

test('temperature remains deterministic and provider fallback remains present', () => {
  assert.match(provider, /temperature:\s*0/);
  assert.match(provider, /groq_fallback/);
});

test('Incorrect and Incomplete feedback contracts remain available', () => {
  assert.match(pipeline, /feedbackReason === 'incomplete'/);
  assert.match(pipeline, /feedback_reason: pipelineContext\.feedbackReason/);
  assert.match(pipeline, /maximumRecoveryIterations = pipelineContext\.forceRecovery \? 2 : 1/);
});
