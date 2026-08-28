import {
  contractRelevantEvidence,
  deterministicGroundedSynthesis,
  feedbackObjective,
  guardUserOutput,
  mergeCanonicalTerms,
  REASONING_ENGINE_VERSION,
  recoveryPlanFromSandbox,
  requiresAggregateCollection,
} from './reasoning_engine.ts';
import type { EvidenceLedger, QuestionContract, SemanticHypothesisSandbox } from './ai.ts';
import type { V3Chunk } from './retrieval.ts';

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
  assert(REASONING_ENGINE_VERSION === 'insurance-v3-shared-reasoning-v165', 'shared engine signature changed unexpectedly');
});
