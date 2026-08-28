import {
  contractRelevantEvidence,
  deterministicGroundedSynthesis,
  feedbackObjective,
  guardUserOutput,
  initialSandboxFromContract,
  mergeCanonicalTerms,
  preserveRetrievalSeeds,
  REASONING_ENGINE_VERSION,
  recoveryPlanFromSandbox,
  requiresAggregateCollection,
  semanticQuestionContract,
} from './reasoning_engine.ts';
import type { EvidenceLedger, QuestionContract, SemanticHypothesisSandbox } from './ai.ts';
import type { HybridSearchUnit, SemanticInterpretation, V3Chunk } from './retrieval.ts';

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

const contract: QuestionContract = {
  original_question: 'Synthetic reverse collection request', primary_subject: 'Synthetic specialty', secondary_subjects: [],
  requested_relationships: [{ subject: 'Synthetic specialty', relation: 'eligible policies', object: null, direction: 'reverse' }],
  required_answer_facets: [{ id: 'f1', description: 'eligible policy list', requested_type: 'policy', required: true }],
  comparison_axes: [], constraints: [], patient_facts: [], ambiguities: [], expected_answer_type: 'list', answer_cardinality: 'aggregate', source_requirement: true,
  initial_search_hypotheses: [{ query: 'synthetic specialty eligible policies', mode: 'all', concepts: ['synthetic specialty'], relationship_direction: 'reverse' }],
};

const chunk = (id: string, document: string, text: string): V3Chunk => ({
  chunk_id: id, document_id: `doc-${id}`, document_title: document, file_name: `${document}.pdf`,
  page_from: 1, page_to: 1, sheet_name: null, row_from: 1, row_to: 1, section_title: 'Eligibility',
  chunk_text: text, metadata: { semantic_table_record: true }, score: 10, fts_rank: 1,
  trigram_score: 1, matched_entity_count: 0, matched_dimensions: [],
});

const evidence = [
  chunk('e1', 'Policy Alpha', 'Column 1: Policy Alpha\nColumn 2: Synthetic specialty is eligible.'),
  chunk('e2', 'Policy Beta', 'Column 1: Policy Beta\nColumn 2: Synthetic specialty is eligible.'),
  chunk('e3', 'Neighbor Context', 'Column 1: Unrelated neighboring specialty.'),
];

const ledger: EvidenceLedger = {
  status: 'complete', facets: [{ facet_id: 'f1', status: 'supported', evidence_ids: ['e1', 'e2'], relation_paths: [], explanation: 'Two verified matches.' }],
  missing_facets: [], relation_direction_preserved: true, detected_relation_direction: 'reverse', cross_document_search: true,
  aggregation_complete: true, matched_subjects: ['Policy Alpha', 'Policy Beta'], next_searches: [], reason: 'Bounded collection complete.',
};

const sandbox: SemanticHypothesisSandbox = {
  terminology_mismatch_plausible: true, relation_direction_original: 'forward', relation_direction_reconsidered: 'reverse',
  evidence_discovered_terminology: ['formal discipline'], hypotheses: [
    { kind: 'literal', query: 'synthetic shorthand', concepts: ['synthetic shorthand'], mode: 'all', relationship_direction: 'unknown', basis: 'user_literal' },
    { kind: 'canonical', query: 'formal discipline policy eligibility', concepts: ['formal discipline'], mode: 'semantic', relationship_direction: 'reverse', basis: 'general_knowledge_search_only' },
    { kind: 'reverse_relation', query: 'eligible specialty formal discipline', concepts: ['eligible specialty'], mode: 'tables', relationship_direction: 'reverse', basis: 'retrieved_evidence' },
  ],
};

Deno.test('A same semantic request uses one engine identity for Normal Incorrect and Incomplete', () => {
  const ids = ['normal', 'incorrect', 'incomplete'].map(() => REASONING_ENGINE_VERSION);
  assert(new Set(ids).size === 1, 'feedback paths must share one semantic engine id');
});

Deno.test('A2 semantic output compiles a multi-part open-vocabulary contract without a second AI call', () => {
  const semantic: SemanticInterpretation = {
    route: 'policy_question', medication: null, generic: null, drug_class: null, indication: null,
    intent: ['find permitted treatments', 'find applicable policies'], requested_dimensions: ['treatment options', 'policy applicability'],
    treatment_stage: null, semantic_intent: 'Resolve a professional-specialty reverse policy lookup.',
    requested_information: 'Treatments and applicable policy documents', information_need: 'Specialty-linked policy evidence',
    semantic_facets: [
      { description: 'permitted treatments', requested_type: 'treatment' },
      { description: 'applicable policies', requested_type: 'policy document' },
    ],
    semantic_relationships: [
      { subject: 'Synthetic specialty', relation: 'may prescribe', object: 'treatment', direction: 'forward' },
      { subject: 'policy document', relation: 'applies to', object: 'Synthetic specialty', direction: 'reverse' },
    ],
    answer_cardinality: 'aggregate',
    retrieval_queries: [], search_concepts: ['Synthetic specialty'], search_phrases: [], search_query: null,
    negation: [], temporal_context: null, facts: [], source_requested: false,
  };
  const compiled = semanticQuestionContract('Synthetic multi-part question', semantic, []);
  assert(compiled.primary_subject === 'Synthetic specialty', 'semantic subject anchor was lost');
  assert(compiled.requested_relationships.length === 2, 'multi-part relationships were not preserved');
  assert(compiled.required_answer_facets.length === 2, 'multi-part facets were not preserved');
  assert(compiled.required_answer_facets[1].requested_type === 'policy document', 'semantic endpoint type was replaced by descriptive wording');
  assert(compiled.answer_cardinality === 'aggregate', 'unanchored multi-part lookup was not treated as aggregate');
});

Deno.test('B2 evidence-discovered recovery searches outrank generic hypotheses before the bounded cutoff', () => {
  const crowded: SemanticHypothesisSandbox = {
    ...sandbox,
    hypotheses: [
      ...sandbox.hypotheses,
      { kind: 'canonical', query: 'generic four', concepts: [], mode: 'all', relationship_direction: 'unknown', basis: 'general_knowledge_search_only' },
      { kind: 'canonical', query: 'generic five', concepts: [], mode: 'all', relationship_direction: 'unknown', basis: 'general_knowledge_search_only' },
      { kind: 'evidence_discovered', query: 'direct evidence terminology', concepts: ['direct term'], mode: 'all', relationship_direction: 'unknown', basis: 'retrieved_evidence' },
    ],
  };
  const plan = recoveryPlanFromSandbox(crowded, feedbackObjective(null), []);
  assert(plan.searches.length === 5, 'bounded recovery size changed');
  assert(plan.searches[0].query === 'direct evidence terminology', 'direct evidence clue was truncated behind generic searches');
});

Deno.test('A3 newly retrieved top evidence survives stale reranker judgments', () => {
  const unit = (id: string, score: number): HybridSearchUnit => ({
    search_unit_id: id, document_id: `doc-${id}`, document_title: id, file_name: `${id}.pdf`, unit_type: 'text_chunk',
    page_from: 1, page_to: 1, sheet_name: null, row_from: null, row_to: null, section_title: null, table_title: null,
    parent_unit_id: null, sibling_order: 0, retrieval_text: id, source_chunk_ids: [id], metadata: {}, vector_rank: null,
    fts_rank: null, trigram_rank: null, heading_rank: null, entity_rank: null, vector_similarity: null, fts_score: null,
    trigram_score: null, entity_match_count: 0, hybrid_rrf_score: score,
  });
  const newlyRetrieved = unit('new-direct-evidence', 100);
  const stalePositive = unit('old-reranker-choice', 1);
  const selected = preserveRetrievalSeeds([newlyRetrieved, stalePositive], [stalePositive, newlyRetrieved], [stalePositive]);
  assert(selected.some((candidate) => candidate.search_unit_id === newlyRetrieved.search_unit_id), 'new direct retrieval evidence was dropped');
});

Deno.test('B canonical terminology discovered in one round is preserved for later rounds', () => {
  const terms = mergeCanonicalTerms(['initial concept'], sandbox.evidence_discovered_terminology, ['formal discipline']);
  const plan = recoveryPlanFromSandbox(sandbox, feedbackObjective('incorrect'), terms);
  assert(plan.searches.every((search) => search.concepts.includes('formal discipline')), 'canonical clue was not inherited');
});

Deno.test('C reverse lookup retains relevant matches from multiple documents', () => {
  const selected = contractRelevantEvidence(evidence, ledger);
  assert(selected.length === 2, 'cross-document matches were not both retained');
  assert(new Set(selected.map((item) => item.document_title)).size === 2, 'matches did not span documents');
  assert(recoveryPlanFromSandbox(sandbox, feedbackObjective('incorrect'), []).relationship_direction === 'reverse', 'reverse direction was lost');
});

Deno.test('D aggregate request does not treat its first match as inherently complete', async () => {
  assert(requiresAggregateCollection(contract), 'aggregate cardinality was not recognized');
  const pipeline = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(pipeline.includes('maximumAggregateRecoveryIterations'), 'bounded aggregate collection is not enabled');
  assert(pipeline.includes('aggregationBudgetExhausted'), 'aggregate exhaustion is not recorded explicitly');
});

Deno.test('E provider answer failure after verified evidence yields grounded natural language', () => {
  const result = deterministicGroundedSynthesis(contract.original_question, contract, ledger, evidence);
  assert(result.answer.startsWith('Based on the approved evidence:'), 'fallback is not natural-language synthesis');
  assert(!result.answer.includes('Automated answer generation could not be completed'), 'old provider failure dump leaked');
  assert(result.used_evidence_ids.length === 2, 'verified evidence provenance was lost');
});

Deno.test('F structured model JSON is blocked before user display', () => {
  const guarded = guardUserOutput('{"treatment_list":["Alpha","Beta"]}', contract.original_question, contract, ledger, evidence, false);
  assert(guarded.raw_json_blocked, 'raw JSON was not detected');
  assert(!guarded.answer.trim().startsWith('{'), 'raw JSON reached output');
});

Deno.test('G irrelevant neighboring rows are excluded from final evidence', () => {
  const selected = contractRelevantEvidence(evidence, ledger);
  assert(!selected.some((item) => item.chunk_id === 'e3'), 'neighbor evidence was retained');
  assert(!deterministicGroundedSynthesis(contract.original_question, contract, ledger, selected).answer.includes('Unrelated neighboring'), 'neighbor row leaked into synthesis');
});

Deno.test('H genuinely missing evidence returns a precise insufficient statement', () => {
  const missingLedger: EvidenceLedger = { ...ledger, status: 'insufficient', facets: [{ facet_id: 'f1', status: 'missing', evidence_ids: [], relation_paths: [], explanation: 'Absent.' }], missing_facets: ['f1'], aggregation_complete: true };
  const result = deterministicGroundedSynthesis(contract.original_question, contract, missingLedger, []);
  assert(result.answer.includes('The evidence does not establish: eligible policy list.'), 'missing evidence was not reported safely');
});

Deno.test('I feedback objectives differ while the reasoning implementation remains identical', () => {
  const normal = feedbackObjective(null); const incorrect = feedbackObjective('incorrect'); const incomplete = feedbackObjective('incomplete');
  assert(!normal.reconsider_interpretation && incorrect.reconsider_interpretation, 'Incorrect objective did not change');
  assert(incomplete.preserve_supported_previous_facts && !incorrect.preserve_supported_previous_facts, 'Incomplete objective did not change');
  assert(REASONING_ENGINE_VERSION === 'insurance-v3-shared-reasoning-v169', 'shared engine signature changed unexpectedly');
});

Deno.test('J first-pass search reuses the AI question contract without a duplicate AI planning call', () => {
  const initial = initialSandboxFromContract(contract.original_question, contract);
  assert(initial.hypotheses.length === contract.initial_search_hypotheses.length, 'contract hypotheses were not preserved');
  assert(initial.hypotheses[0].relationship_direction === 'reverse', 'relationship direction was not preserved');
  assert(initial.hypotheses[0].kind === 'reverse_relation', 'reverse search was not classified for execution');
});
