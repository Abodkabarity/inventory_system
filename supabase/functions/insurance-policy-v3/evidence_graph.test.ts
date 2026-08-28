import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { EvidenceLedger, EvidenceRelationPath, QuestionContract } from './ai.ts';
import {
  aggregateSearchState,
  clarificationGate,
  preserveEvidenceLedgerOnProviderFailure,
  validateDocumentRelationshipBindings,
} from './evidence_graph.ts';
import type { SemanticInterpretation, V3Chunk } from './retrieval.ts';

const contract = (overrides: Partial<QuestionContract> = {}): QuestionContract => ({
  original_question: 'Which therapies can Specialist S manage?',
  primary_subject: 'Specialist S', secondary_subjects: [],
  requested_relationships: [{ subject: 'Specialist S', relation: 'eligible for', object: null, direction: 'reverse' }],
  required_answer_facets: [{ id: 'therapy_list', description: 'covered therapies', requested_type: 'treatment', required: true }],
  comparison_axes: [], constraints: [], patient_facts: [], ambiguities: [],
  expected_answer_type: 'treatment list', answer_cardinality: 'aggregate', source_requirement: true,
  initial_search_hypotheses: [{ query: 'Specialist S eligibility', mode: 'all', concepts: [], relationship_direction: 'reverse' }],
  ...overrides,
});

const chunk = (
  id: string, documentId: string, text: string, page: number,
  metadata: Record<string, unknown> = {}, section = `Section ${page}`,
): V3Chunk => ({
  chunk_id: id, document_id: documentId, document_title: `Policy ${documentId}`, file_name: `${documentId}.pdf`,
  page_from: page, page_to: page, sheet_name: null, row_from: null, row_to: null,
  section_title: section, chunk_text: text, metadata, score: 10,
  fts_rank: 0, trigram_score: 0, matched_entity_count: 0, matched_dimensions: [],
});

const path = (
  facetId: string, value: string, directId: string, contextId: string,
  suffix = value.replace(/\W/g, ''), endpointType = 'treatment',
): EvidenceRelationPath => ({
  facet_id: facetId, value, source_node_id: `source-${suffix}`, endpoint_node_id: `endpoint-${suffix}`,
  nodes: [
    { id: `source-${suffix}`, label: 'Specialist S', node_type: 'specialty', evidence_ids: [directId] },
    { id: `document-${suffix}`, label: 'Policy owner', node_type: 'policy', evidence_ids: [directId, contextId] },
    { id: `endpoint-${suffix}`, label: value, node_type: endpointType, evidence_ids: [contextId] },
  ],
  edges: [
    { from_node_id: `source-${suffix}`, relation: 'eligible_under', to_node_id: `document-${suffix}`, evidence_ids: [directId] },
    { from_node_id: `document-${suffix}`, relation: 'governs', to_node_id: `endpoint-${suffix}`, evidence_ids: [contextId] },
  ],
  evidence_ids: [directId, contextId], status: 'supported', rejection_reason: null,
});

const ledger = (paths: EvidenceRelationPath[], evidenceIds = [...new Set(paths.flatMap((item) => item.evidence_ids))]): EvidenceLedger => ({
  status: 'complete',
  facets: [{ facet_id: 'therapy_list', status: 'supported', evidence_ids: evidenceIds, relation_paths: paths, explanation: 'Typed path proposed.' }],
  missing_facets: [], relation_direction_preserved: true, detected_relation_direction: 'reverse',
  cross_document_search: false, aggregation_complete: true, matched_subjects: paths.map((item) => item.value),
  next_searches: [], reason: 'Synthetic verified evidence.',
});

const evidencePair = (documentId = 'D1', treatment = 'Treatment T') => [
  chunk('specialty-row', documentId, 'Eligible Specialty = Specialist S', 2, { policy_scope: 'alpha' }),
  chunk('owner-context', documentId, `This policy covers ${treatment}.`, 1, {
    context_binding: 'same_document_owner_context', policy_scope: 'alpha',
  }),
];

Deno.test('TEST A: cross-page same-document owner context binds specialty to treatment', () => {
  const evidence = evidencePair();
  const result = validateDocumentRelationshipBindings(contract(), evidence, ledger([path('therapy_list', 'Treatment T', 'specialty-row', 'owner-context')]));
  assertEquals(result.ledger.facets[0].status, 'supported');
  assertEquals(result.ledger.facets[0].relation_paths[0].value, 'Treatment T');
  assertEquals(result.diagnostics.document_binding_success, true);
});

Deno.test('TEST B: multiple typed treatment paths in one policy are retained', () => {
  const evidence = evidencePair('D1', 'Treatment T and Treatment U');
  const paths = [
    path('therapy_list', 'Treatment T', 'specialty-row', 'owner-context', 'T'),
    path('therapy_list', 'Treatment U', 'specialty-row', 'owner-context', 'U'),
  ];
  const result = validateDocumentRelationshipBindings(contract(), evidence, ledger(paths));
  assertEquals(result.ledger.facets[0].relation_paths.map((item) => item.value), ['Treatment T', 'Treatment U']);
});

Deno.test('TEST C: aggregate lookup retains separate paths from two documents', () => {
  const evidence = [
    ...evidencePair('D1', 'Treatment T'),
    chunk('specialty-row-2', 'D2', 'Eligible Specialty = Specialist S', 4, { policy_scope: 'beta' }),
    chunk('owner-context-2', 'D2', 'This policy covers Treatment V.', 1, { context_binding: 'same_document_owner_context', policy_scope: 'beta' }),
  ];
  const paths = [
    path('therapy_list', 'Treatment T', 'specialty-row', 'owner-context', 'T'),
    path('therapy_list', 'Treatment V', 'specialty-row-2', 'owner-context-2', 'V'),
  ];
  const result = validateDocumentRelationshipBindings(contract(), evidence, ledger(paths));
  assertEquals(result.ledger.facets[0].relation_paths.length, 2);
  assertEquals(new Set(result.diagnostics.relationship_paths_created.map((item) => item.document_id)).size, 2);
});

Deno.test('TEST D: unrelated same-document policy scopes cannot be joined', () => {
  const evidence = [
    chunk('specialty-row', 'D1', 'Eligible Specialty = Specialist S', 2, { policy_scope: 'alpha' }),
    chunk('unrelated-owner', 'D1', 'A different policy covers Treatment Z.', 9, { context_binding: 'same_document_owner_context', policy_scope: 'beta' }),
  ];
  const result = validateDocumentRelationshipBindings(contract(), evidence, ledger([path('therapy_list', 'Treatment Z', 'specialty-row', 'unrelated-owner')]));
  assertEquals(result.ledger.facets[0].status, 'partial');
  assert(result.diagnostics.relationship_rejection_reason.some((reason) => reason.startsWith('conflicting_document_scope')));
});

Deno.test('TEST E: incomplete aggregate with budget remaining must continue search', () => {
  const state = aggregateSearchState(contract(), { ...ledger([path('therapy_list', 'Treatment T', 'specialty-row', 'owner-context')]), aggregation_complete: false }, 1, 3, true);
  assertEquals(state.state, 'partial_search_remaining');
  assertEquals(state.may_mark_complete, false);
});

Deno.test('TEST F: exhausted aggregate returns partial state without false completeness', () => {
  const state = aggregateSearchState(contract(), { ...ledger([path('therapy_list', 'Treatment T', 'specialty-row', 'owner-context')]), aggregation_complete: false }, 3, 3, true);
  assertEquals(state.state, 'partial_budget_exhausted');
  assertEquals(state.aggregation_budget_exhausted, true);
});

Deno.test('TEST G: known subject relation and facet cannot clarify due to retrieval difficulty', () => {
  const semantic = { route: 'clarification_required' } as SemanticInterpretation;
  const known = contract({ ambiguities: [{ description: 'retrieval uncertainty', interpretations: ['reading one', 'reading two'], materially_distinct: true }] });
  const gate = clarificationGate(known, semantic);
  assertEquals(gate.allow_clarification, false);
  assertEquals(gate.search_incompleteness_detected, true);
});

Deno.test('TEST H: genuinely ambiguous user request passes clarification gate', () => {
  const semantic = { route: 'clarification_required' } as SemanticInterpretation;
  const ambiguous = contract({
    primary_subject: '', requested_relationships: [{ subject: '', relation: 'unknown', object: null, direction: 'unknown' }],
    ambiguities: [{ description: 'two possible subjects', interpretations: ['subject one', 'subject two'], materially_distinct: true }],
  });
  assertEquals(clarificationGate(ambiguous, semantic).allow_clarification, true);
});

Deno.test('TEST I: validated relation path carries both direct and owner evidence', () => {
  const evidence = evidencePair();
  const result = validateDocumentRelationshipBindings(contract(), evidence, ledger([path('therapy_list', 'Treatment T', 'specialty-row', 'owner-context')]));
  assertEquals(result.diagnostics.binding_source_evidence_ids, ['specialty-row']);
  assertEquals(result.diagnostics.binding_context_evidence_ids, ['owner-context']);
  assertEquals(result.diagnostics.verifier_relation_path_result, 'passed');
});

Deno.test('TEST J: specialty endpoint cannot satisfy a treatment facet', () => {
  const evidence = evidencePair();
  const wrong = path('therapy_list', 'Specialist S', 'specialty-row', 'owner-context', 'wrong', 'specialty');
  const result = validateDocumentRelationshipBindings(contract(), evidence, ledger([wrong]));
  assertEquals(result.ledger.facets[0].status, 'partial');
  assertEquals(result.diagnostics.facet_type_validation[0].valid, false);
  assertEquals(result.diagnostics.verifier_relation_path_result, 'failed');
});

Deno.test('TEST K: provider failure preserves the prior evidence ledger', () => {
  const previous = ledger([path('therapy_list', 'Treatment T', 'specialty-row', 'owner-context')]);
  const fallback: EvidenceLedger = {
    ...previous, status: 'insufficient',
    facets: previous.facets.map((facet) => ({ ...facet, status: 'missing', evidence_ids: [], relation_paths: [] })),
    missing_facets: ['therapy_list'],
  };
  assertEquals(preserveEvidenceLedgerOnProviderFailure(previous, fallback), previous);
});
