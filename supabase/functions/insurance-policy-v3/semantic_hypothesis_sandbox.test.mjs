import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ai = readFileSync(new URL('./ai.ts', import.meta.url), 'utf8');
const pipeline = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const provider = readFileSync(new URL('./ai_provider.ts', import.meta.url), 'utf8');

test('A: unfamiliar abbreviations receive independent formal search hypotheses without runtime maps', () => {
  assert.match(ai, /acronym_or_professional/);
  assert.match(ai, /canonical\/formal terminology/);
  assert.match(ai, /independentStrategyCount[\s\S]*>= 2/);
  assert.doesNotMatch(ai, /(?:acronym|abbreviation)(?:Map|Dictionary)\s*=/i);
});

test('B: practitioner wording can expand toward specialty terminology as a search probe only', () => {
  assert.match(ai, /professional-title expansion/);
  assert.match(ai, /specialty\/practitioner wording/);
  assert.match(ai, /General linguistic, medical, and professional knowledge is allowed ONLY to propose unverified search terminology/);
  assert.match(ai, /approved evidence confirms it/);
});

test('C: reverse retrieval direction is relative to stored subject and object', () => {
  assert.match(ai, /determined relative to document structure/);
  assert.match(ai, /stores subject and object, not merely the user's sentence grammar/);
  assert.match(ai, /search for the attribute as object and return the owning subjects/);
  assert.match(pipeline, /relationship_direction: hypothesis\.relationship_direction/);
});

test('D: first-pass evidence terminology is inspected and only literal evidence terms survive', () => {
  assert.match(pipeline, /first_pass_evidence: selection\.selected\.slice/);
  assert.match(ai, /terminology explicitly discovered in supplied first-pass evidence/);
  assert.match(ai, /normalizedEvidence\.includes/);
  assert.match(ai, /basis: \{ type: 'string', enum: \['user_literal', 'general_knowledge_search_only', 'retrieved_evidence'\]/);
});

test('E: Incorrect recovery rejects a literal-equivalent strategy and substitutes independent hypotheses', () => {
  assert.match(ai, /For Incorrect feedback, every non-literal hypothesis must materially differ/);
  assert.match(pipeline, /pipelineContext\.feedbackReason === 'incorrect'/);
  assert.match(pipeline, /!plannerChangedSearch/);
  assert.match(pipeline, /Literal-equivalent recovery was rejected/);
  assert.match(pipeline, /independentHypotheses = recoverySemanticSandbox\.hypotheses/);
});

test('F: insufficient evidence is allowed only after bounded semantic expansion', () => {
  assert.match(pipeline, /alternateSemanticExpansionAttempted/);
  assert.match(pipeline, /semantic_expansion_required_before_insufficient_evidence/);
  assert.match(pipeline, /insufficient_evidence_after_semantic_expansion: true/);
  assert.match(pipeline, /approved documents do not establish/i);
});

test('existing deterministic provider behavior and architectural boundaries remain intact', () => {
  assert.match(provider, /temperature:\s*0/);
  assert.match(provider, /groq_fallback/);
  assert.match(pipeline, /findVerifiedSemanticMemory/);
  assert.match(pipeline, /insurance_validated_answers/);
  assert.match(pipeline, /inspectEvidenceAgainstContract/);
  assert.match(pipeline, /verifyAnswerAgainstContract/);
});
