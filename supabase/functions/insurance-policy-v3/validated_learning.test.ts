import { extractVerifiedSearchStrategy, validatedLearningGate } from './validated_learning.ts';

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

const verifiedAudit = (overrides: Record<string, unknown> = {}) => ({
  answer_status: 'grounded', answer_generator: 'grounded_ai', fallback_used: null,
  retrieval_plan: { question_contract: { answer_cardinality: 'singular', ambiguities: [] } },
  completeness: {
    evidence_ledger: { status: 'complete', aggregation_complete: true },
    answer_verifier: { answer_usable: true, answer_rejected_before_display: false },
  },
  provider_diagnostics: {
    shared_reasoning_engine: {
      semantic_hypotheses_generated: [
        { kind: 'literal', query: 'synthetic request', mode: 'all', concepts: ['synthetic'], relationship_direction: 'unknown' },
        { kind: 'canonical', query: 'formal synthetic concept', mode: 'semantic', concepts: ['formal concept'], relationship_direction: 'reverse' },
        { kind: 'reverse_relation', query: 'owners with formal concept', mode: 'tables', concepts: ['owners'], relationship_direction: 'reverse' },
      ],
      canonical_terms_discovered: ['formal concept'], relation_direction: 'reverse',
      provider_failure_stage: null, raw_json_blocked: false, raw_evidence_dump_blocked: false,
    },
    reasoning_agent: { question_contract: { requested_relationships: [], required_answer_facets: [] }, search_hypotheses: [] },
  },
  ...overrides,
});

const citations = [{ document_id: 'd1', chunk_id: 'e1' }];

Deno.test('Useful learns only a complete grounded answer that passed verification', () => {
  const decision = validatedLearningGate(verifiedAudit(), citations, 'Verified answer');
  assert(decision.eligible, `unexpected learning rejection: ${decision.reasons.join(',')}`);
});

Deno.test('fallback, partial evidence, and failed verifier cannot poison validated learning', () => {
  const fallback = validatedLearningGate(verifiedAudit({ answer_status: 'grounded_fallback', answer_generator: 'shared_grounded_synthesis_fallback', fallback_used: 'deterministic_grounded_synthesis' }), citations, 'Fallback');
  const partial = validatedLearningGate(verifiedAudit({ completeness: { evidence_ledger: { status: 'partial' }, answer_verifier: { answer_usable: true, answer_rejected_before_display: false } } }), citations, 'Partial');
  const rejected = validatedLearningGate(verifiedAudit({ completeness: { evidence_ledger: { status: 'complete' }, answer_verifier: { answer_usable: false, answer_rejected_before_display: true } } }), citations, 'Rejected');
  assert(!fallback.eligible && !partial.eligible && !rejected.eligible, 'unsafe answer became learnable');
});

Deno.test('a verifier-corrected final answer can learn while the rejected draft cannot', () => {
  const corrected = verifiedAudit({ completeness: {
    evidence_ledger: { status: 'complete', aggregation_complete: true },
    answer_verifier: { answer_usable: true, final_answer_verified: true, draft_answer_usable: false, answer_rejected_before_display: true },
  } });
  assert(validatedLearningGate(corrected, citations, 'Corrected verified answer').eligible, 'verified corrected final answer was not learnable');
});

Deno.test('aggregate answer is learnable only after collection completeness', () => {
  const audit = verifiedAudit({
    retrieval_plan: { question_contract: { answer_cardinality: 'aggregate', ambiguities: [] } },
    completeness: { evidence_ledger: { status: 'complete', aggregation_complete: false }, answer_verifier: { answer_usable: true, answer_rejected_before_display: false } },
  });
  assert(!validatedLearningGate(audit, citations, 'One match').eligible, 'incomplete aggregate was learned');
});

Deno.test('provider failure or blocked structured output prevents learning', () => {
  const base = verifiedAudit();
  const diagnostics = base.provider_diagnostics as Record<string, unknown>;
  const shared = diagnostics.shared_reasoning_engine as Record<string, unknown>;
  assert(!validatedLearningGate({ ...base, provider_diagnostics: { ...diagnostics, shared_reasoning_engine: { ...shared, provider_failure_stage: 'answer_generation' } } }, citations, 'Answer').eligible, 'provider-failed request was learned');
  assert(!validatedLearningGate({ ...base, provider_diagnostics: { ...diagnostics, shared_reasoning_engine: { ...shared, raw_json_blocked: true } } }, citations, 'Answer').eligible, 'blocked JSON was learned');
});

Deno.test('successful sandbox strategy is extracted as search knowledge, not policy facts', () => {
  const strategy = extractVerifiedSearchStrategy(verifiedAudit().provider_diagnostics);
  assert(strategy.hypotheses.length === 3, 'search hypotheses were not preserved');
  assert(strategy.expansionConcepts.includes('formal concept'), 'canonical search clue was not preserved');
  assert(strategy.relationshipDirection === 'reverse', 'verified relation direction was not preserved');
  assert(!JSON.stringify(strategy).includes('Verified answer'), 'answer facts leaked into semantic memory strategy');
});

Deno.test('negative feedback invalidates the matching validated cache before recovery', async () => {
  const pipeline = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(pipeline.includes('invalidateValidatedAnswerAfterNegativeFeedback'), 'negative cache invalidation is absent');
  assert(pipeline.includes("invalidation_reason: 'negative_feedback_requires_reverification'"), 'negative feedback reason is not recorded');
  assert(pipeline.includes('storeVerifiedSemanticRecovery(memoryDb'), 'Useful does not promote the verified search strategy');
});
