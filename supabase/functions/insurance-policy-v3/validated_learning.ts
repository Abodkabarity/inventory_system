import type { QuestionContract, RecoveryRelationshipDirection, RecoverySearchMode } from './ai.ts';
import type { RecoveryHypothesis } from './semantic_recovery_memory.ts';

const records = (value: unknown) => Array.isArray(value)
  ? value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object')
  : [];
const record = (value: unknown) => value && typeof value === 'object' ? value as Record<string, unknown> : {};

export type LearningGateDecision = { eligible: boolean; reasons: string[] };

export function validatedLearningGate(
  audit: Record<string, unknown> | null | undefined,
  citations: Array<Record<string, unknown>>,
  answer: string,
): LearningGateDecision {
  if (!audit) return { eligible: false, reasons: ['missing_audit'] };
  const completeness = record(audit.completeness);
  const ledger = record(completeness.evidence_ledger);
  const verifier = record(completeness.answer_verifier);
  const retrievalPlan = record(audit.retrieval_plan);
  const contract = record(retrievalPlan.question_contract);
  const shared = record(record(audit.provider_diagnostics).shared_reasoning_engine);
  const reasons: string[] = [];
  if (!['grounded', 'recovery_grounded'].includes(String(audit.answer_status))) reasons.push('answer_status_not_verified_grounded');
  if (!answer.trim()) reasons.push('missing_final_answer');
  if (citations.length === 0 || citations.some((citation) => !String(citation.document_id ?? '').trim() || !String(citation.chunk_id ?? '').trim())) reasons.push('missing_valid_citations');
  if (ledger.status !== 'complete') reasons.push('evidence_ledger_not_complete');
  if (contract.answer_cardinality === 'aggregate' && ledger.aggregation_complete !== true) reasons.push('aggregate_collection_not_complete');
  const finalAnswerVerified = verifier.final_answer_verified === true
    || (verifier.answer_usable === true && verifier.answer_rejected_before_display !== true);
  if (!finalAnswerVerified) reasons.push('answer_verifier_not_passed');
  if (String(audit.answer_generator ?? '').includes('fallback') || audit.fallback_used) reasons.push('fallback_answer_not_learnable');
  if (shared.raw_json_blocked === true || shared.raw_evidence_dump_blocked === true) reasons.push('unsafe_output_was_blocked');
  if (shared.provider_failure_stage) reasons.push('provider_failure_during_reasoning');
  const ambiguities = records(contract.ambiguities);
  if (ambiguities.some((ambiguity) => ambiguity.materially_distinct === true)) reasons.push('material_ambiguity_present');
  return { eligible: reasons.length === 0, reasons };
}

const modes = new Set<RecoverySearchMode>(['all', 'semantic', 'tables', 'headings', 'documents', 'entities']);
const directions = new Set<RecoveryRelationshipDirection>(['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown']);

export function extractVerifiedSearchStrategy(providerDiagnostics: unknown) {
  const diagnostics = record(providerDiagnostics);
  const shared = record(diagnostics.shared_reasoning_engine);
  const reasoning = record(diagnostics.reasoning_agent);
  const candidates = [
    ...records(shared.semantic_hypotheses_generated),
    ...records(reasoning.search_hypotheses),
  ];
  const unique = new Map<string, RecoveryHypothesis>();
  for (const candidate of candidates) {
    const query = String(candidate.query ?? '').trim();
    if (!query) continue;
    const key = query.normalize('NFKC').toLocaleLowerCase();
    if (unique.has(key)) continue;
    const mode = modes.has(candidate.mode as RecoverySearchMode) ? candidate.mode as RecoverySearchMode : 'all';
    const relationshipDirection = directions.has(candidate.relationship_direction as RecoveryRelationshipDirection)
      ? candidate.relationship_direction as RecoveryRelationshipDirection
      : directions.has(shared.relation_direction as RecoveryRelationshipDirection)
      ? shared.relation_direction as RecoveryRelationshipDirection
      : 'unknown';
    unique.set(key, {
      label: String(candidate.label ?? candidate.kind ?? `validated-search-${unique.size + 1}`).slice(0, 160),
      query: query.slice(0, 500), mode,
      concepts: Array.isArray(candidate.concepts) ? [...new Set(candidate.concepts.map(String).map((value) => value.trim()).filter(Boolean))].slice(0, 12) : [],
      relationship_direction: relationshipDirection,
    });
  }
  const hypotheses = [...unique.values()].slice(0, 6);
  const expansionConcepts = Array.isArray(shared.canonical_terms_discovered)
    ? [...new Set(shared.canonical_terms_discovered.map(String).map((value) => value.trim()).filter(Boolean))].slice(0, 24)
    : [];
  const direction = directions.has(shared.relation_direction as RecoveryRelationshipDirection)
    ? shared.relation_direction as RecoveryRelationshipDirection
    : hypotheses.find((hypothesis) => hypothesis.relationship_direction !== 'unknown')?.relationship_direction ?? 'unknown';
  const questionContract = (record(record(diagnostics.reasoning_agent).question_contract) as QuestionContract);
  return { hypotheses, expansionConcepts, relationshipDirection: direction, questionContract };
}
