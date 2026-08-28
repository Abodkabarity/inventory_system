import type { EvidenceLedger, EvidenceRelationPath, QuestionContract } from './ai.ts';
import type { SemanticInterpretation, V3Chunk } from './retrieval.ts';

const normalized = (value: unknown) => String(value ?? '').normalize('NFKC').toLocaleLowerCase()
  .replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

const structuralScopeKeys = [
  'policy_scope', 'scope_id', 'policy_id', 'policy_subject', 'owner_context_id',
  'owner_id', 'subject_id', 'subject_key', 'section_path', 'parent_unit_id',
] as const;

const contextBinding = (chunk: V3Chunk) => String(chunk.metadata.context_binding ?? '') === 'same_document_owner_context';

function scopeValues(chunk: V3Chunk) {
  return new Map(structuralScopeKeys.flatMap((key) => {
    const value = normalized(chunk.metadata[key]);
    return value ? [[key, value] as const] : [];
  }));
}

function conflictingExplicitScope(chunks: V3Chunk[]) {
  for (const key of structuralScopeKeys) {
    const values = new Set(chunks.map((chunk) => scopeValues(chunk).get(key)).filter(Boolean));
    if (values.size > 1) return key;
  }
  return null;
}

function sharesExplicitScope(chunks: V3Chunk[]) {
  if (chunks.length < 2) return true;
  return structuralScopeKeys.some((key) => {
    const values = chunks.map((chunk) => scopeValues(chunk).get(key)).filter(Boolean);
    return values.length >= 2 && new Set(values).size === 1;
  });
}

function typeCompatible(requestedType: string, endpointType: string) {
  const requested = normalized(requestedType);
  const endpoint = normalized(endpointType);
  if (!requested || !endpoint) return false;
  if (requested === endpoint) return true;
  const requestedTokens = new Set(requested.split(' ').filter(Boolean));
  const endpointTokens = new Set(endpoint.split(' ').filter(Boolean));
  return requestedTokens.size > 0 && endpointTokens.size > 0
    && ([...requestedTokens].every((token) => endpointTokens.has(token))
      || [...endpointTokens].every((token) => requestedTokens.has(token)));
}

const genericContainerTokens = new Set(['list', 'array', 'string', 'strings', 'identifier', 'identifiers', 'value', 'values', 'item', 'items', 'of', 'e', 'g']);

function semanticTypeCompatible(requestedType: string, relationshipEndpoint: string | null, endpointType: string) {
  if (typeCompatible(requestedType, endpointType)) return true;
  const semanticRequested = normalized(requestedType).split(' ').filter((token) => token && !genericContainerTokens.has(token)).join(' ');
  return Boolean(semanticRequested && typeCompatible(semanticRequested, endpointType))
    || Boolean(relationshipEndpoint && typeCompatible(relationshipEndpoint, endpointType));
}

function labelCompatible(expected: string, actual: string) {
  const left = normalized(expected); const right = normalized(actual);
  if (!left || !right) return false;
  return left === right || left.includes(right) || right.includes(left);
}

function mentionedInCluster(cluster: string, term: string) {
  const haystack = normalized(cluster); const needle = normalized(term);
  if (!haystack || !needle) return false;
  if (` ${haystack} `.includes(` ${needle} `)) return true;
  const tokens = needle.split(' ').filter((token) => token.length >= 3);
  return tokens.length > 0 && tokens.some((token) => new Set(haystack.split(' ')).has(token));
}

function requestTerminologyCompatible(expected: string, actual: string, contract: QuestionContract) {
  if (labelCompatible(expected, actual)) return true;
  return contract.initial_search_hypotheses.some((hypothesis) => {
    const cluster = `${hypothesis.query} ${hypothesis.concepts.join(' ')}`;
    return mentionedInCluster(cluster, expected) && mentionedInCluster(cluster, actual);
  });
}

function directedRelationshipEndpoints(relationship: QuestionContract['requested_relationships'][number]) {
  if (relationship.direction === 'reverse') return { source: relationship.object ?? relationship.subject, endpoint: relationship.subject };
  return { source: relationship.subject, endpoint: relationship.object };
}

function labelGroundedInEvidence(label: string, chunks: V3Chunk[]) {
  const value = normalized(label);
  if (!value || chunks.length === 0) return false;
  const corpus = normalized(chunks.map((chunk) => [
    chunk.document_title, chunk.section_title, chunk.chunk_text,
    chunk.metadata.row_text, chunk.metadata.table_title, chunk.metadata.policy_subject,
  ].filter(Boolean).join(' ')).join(' '));
  if (corpus.includes(value)) return true;
  const tokens = value.split(' ').filter(Boolean);
  const corpusTokens = new Set(corpus.split(' ').filter(Boolean));
  return tokens.length > 0 && tokens.every((token) => corpusTokens.has(token));
}

function connected(path: EvidenceRelationPath) {
  const reachable = new Set([path.source_node_id]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const edge of path.edges) {
      if (reachable.has(edge.from_node_id) && !reachable.has(edge.to_node_id)) {
        reachable.add(edge.to_node_id);
        changed = true;
      }
    }
  }
  return reachable.has(path.endpoint_node_id);
}

export type EvidenceGraphDiagnostics = {
  document_binding_attempted: boolean;
  document_binding_success: boolean;
  binding_source_evidence_ids: string[];
  binding_context_evidence_ids: string[];
  relationship_paths_created: Array<{ facet_id: string; value: string; evidence_ids: string[]; document_id: string }>;
  relationship_paths_rejected: Array<{ facet_id: string; value: string; evidence_ids: string[]; reason: string }>;
  relationship_rejection_reason: string[];
  facet_type_validation: Array<{ facet_id: string; requested_type: string; endpoint_type: string; valid: boolean }>;
  verifier_relation_path_result: 'passed' | 'failed' | 'not_required';
};

export function validateDocumentRelationshipBindings(
  contract: QuestionContract,
  evidence: V3Chunk[],
  ledger: EvidenceLedger,
): { ledger: EvidenceLedger; diagnostics: EvidenceGraphDiagnostics } {
  const byId = new Map(evidence.map((chunk) => [chunk.chunk_id, chunk]));
  const diagnostics: EvidenceGraphDiagnostics = {
    document_binding_attempted: false,
    document_binding_success: false,
    binding_source_evidence_ids: [],
    binding_context_evidence_ids: [],
    relationship_paths_created: [],
    relationship_paths_rejected: [],
    relationship_rejection_reason: [],
    facet_type_validation: [],
    verifier_relation_path_result: 'not_required',
  };
  const relationshipProofRequired = contract.requested_relationships.length > 0;
  if (relationshipProofRequired) diagnostics.verifier_relation_path_result = 'passed';

  const facets = ledger.facets.map((entry) => {
    const contractFacet = contract.required_answer_facets.find((facet) => facet.id === entry.facet_id);
    const requestedType = contractFacet?.requested_type ?? '';
    const accepted: EvidenceRelationPath[] = [];
    for (const path of entry.relation_paths ?? []) {
      const ids = [...new Set(path.evidence_ids.map(String))];
      const chunks = ids.flatMap((id) => byId.has(id) ? [byId.get(id)!] : []);
      const nodes = new Map(path.nodes.map((node) => [node.id, node]));
      const endpoint = nodes.get(path.endpoint_node_id);
      const source = nodes.get(path.source_node_id);
      const matchingRelationship = source && endpoint ? contract.requested_relationships.find((relationship) => {
        const directed = directedRelationshipEndpoints(relationship);
        return requestTerminologyCompatible(directed.source, source.label, contract)
          && semanticTypeCompatible(requestedType, directed.endpoint, endpoint.node_type);
      }) : null;
      const endpointTypeValid = Boolean(endpoint && (matchingRelationship
        || (contract.requested_relationships.length === 0 && semanticTypeCompatible(requestedType, null, endpoint.node_type))));
      diagnostics.facet_type_validation.push({
        facet_id: entry.facet_id, requested_type: requestedType,
        endpoint_type: endpoint?.node_type ?? '', valid: endpointTypeValid,
      });
      let rejection: string | null = null;
      if (!source || !endpoint || path.nodes.length < 2 || path.edges.length < 1) rejection = 'invalid_path_shape';
      else if (contract.requested_relationships.length > 0 && !matchingRelationship) rejection = 'requested_relationship_mismatch';
      else if (contract.requested_relationships.length === 0 && !requestTerminologyCompatible(contract.primary_subject, source.label, contract)) rejection = 'source_subject_mismatch';
      else if (!endpointTypeValid) rejection = 'facet_endpoint_type_mismatch';
      else if (chunks.length !== ids.length || ids.length === 0) rejection = 'unknown_evidence_reference';
      else if (new Set(chunks.map((chunk) => chunk.document_id)).size !== 1) rejection = 'relationship_path_crosses_document_boundary';
      else if (path.edges.some((edge) => !nodes.has(edge.from_node_id) || !nodes.has(edge.to_node_id)
        || edge.evidence_ids.length === 0 || edge.evidence_ids.some((id) => !ids.includes(id)))) rejection = 'invalid_edge_evidence';
      else if (path.nodes.some((node) => node.evidence_ids.length === 0 || node.evidence_ids.some((id) => !ids.includes(id)))) rejection = 'invalid_node_evidence';
      else if (!labelGroundedInEvidence(source.label, source.evidence_ids.flatMap((id) => byId.has(id) ? [byId.get(id)!] : []))) rejection = 'source_label_not_grounded_in_cited_evidence';
      else if (!labelGroundedInEvidence(endpoint.label, endpoint.evidence_ids.flatMap((id) => byId.has(id) ? [byId.get(id)!] : []))) rejection = 'endpoint_label_not_grounded_in_cited_evidence';
      else if (!connected(path)) rejection = 'relationship_path_not_connected';
      else {
        const conflict = conflictingExplicitScope(chunks);
        const ownerContext = chunks.filter(contextBinding);
        const direct = chunks.filter((chunk) => !contextBinding(chunk));
        if (conflict) rejection = `conflicting_document_scope:${conflict}`;
        else if (direct.length === 0) rejection = 'owner_context_cannot_stand_alone';
        else if (chunks.length > 1 && ownerContext.length === 0 && !sharesExplicitScope(chunks)) rejection = 'cross_section_scope_unbound';
        else {
          diagnostics.document_binding_attempted ||= chunks.length > 1;
          diagnostics.document_binding_success ||= chunks.length > 1;
          diagnostics.binding_source_evidence_ids.push(...direct.map((chunk) => chunk.chunk_id));
          diagnostics.binding_context_evidence_ids.push(...ownerContext.map((chunk) => chunk.chunk_id));
        }
      }
      if (rejection) {
        diagnostics.relationship_paths_rejected.push({ facet_id: entry.facet_id, value: path.value, evidence_ids: ids, reason: rejection });
        diagnostics.relationship_rejection_reason.push(rejection);
        continue;
      }
      const acceptedPath = { ...path, evidence_ids: ids, status: 'supported' as const, rejection_reason: null };
      accepted.push(acceptedPath);
      diagnostics.relationship_paths_created.push({
        facet_id: entry.facet_id, value: path.value, evidence_ids: ids,
        document_id: chunks[0].document_id,
      });
    }
    if (relationshipProofRequired && entry.status === 'supported' && accepted.length === 0) {
      diagnostics.verifier_relation_path_result = 'failed';
      return {
        ...entry, status: 'partial' as const, relation_paths: [],
        explanation: `${entry.explanation} Relationship proof path was not verified.`.trim(),
      };
    }
    const evidenceIds = accepted.length > 0
      ? [...new Set(accepted.flatMap((path) => path.evidence_ids))]
      : entry.evidence_ids;
    return { ...entry, evidence_ids: evidenceIds, relation_paths: accepted };
  });
  diagnostics.binding_source_evidence_ids = [...new Set(diagnostics.binding_source_evidence_ids)];
  diagnostics.binding_context_evidence_ids = [...new Set(diagnostics.binding_context_evidence_ids)];
  diagnostics.relationship_rejection_reason = [...new Set(diagnostics.relationship_rejection_reason)];
  const missing = facets.filter((facet) => facet.status !== 'supported').map((facet) => facet.facet_id);
  const status = missing.length === 0 && (contract.answer_cardinality !== 'aggregate' || ledger.aggregation_complete === true)
    ? 'complete' as const
    : facets.some((facet) => facet.status !== 'missing') ? 'partial' as const : 'insufficient' as const;
  return { ledger: { ...ledger, facets, missing_facets: missing, status }, diagnostics };
}

export type AggregateSearchState = 'complete' | 'partial_search_remaining' | 'partial_budget_exhausted' | 'insufficient_evidence';

export function aggregateSearchState(
  contract: QuestionContract,
  ledger: EvidenceLedger,
  round: number,
  maximumRounds: number,
  searchableFacetsRemain: boolean,
): { state: AggregateSearchState; aggregation_budget_exhausted: boolean; may_mark_complete: boolean } {
  if (contract.answer_cardinality !== 'aggregate') return { state: ledger.status === 'insufficient' ? 'insufficient_evidence' : 'complete', aggregation_budget_exhausted: false, may_mark_complete: ledger.status === 'complete' };
  if (ledger.aggregation_complete === true && ledger.missing_facets.length === 0) return { state: 'complete', aggregation_budget_exhausted: false, may_mark_complete: true };
  const supported = ledger.facets.some((facet) => facet.status === 'supported' && facet.evidence_ids.length > 0);
  const exhausted = round >= maximumRounds || !searchableFacetsRemain;
  if (supported) return { state: exhausted ? 'partial_budget_exhausted' : 'partial_search_remaining', aggregation_budget_exhausted: exhausted, may_mark_complete: false };
  return { state: 'insufficient_evidence', aggregation_budget_exhausted: exhausted, may_mark_complete: false };
}

export function clarificationGate(contract: QuestionContract, semantic: SemanticInterpretation) {
  const materialInterpretations = [...new Set(contract.ambiguities
    .filter((ambiguity) => ambiguity.materially_distinct)
    .flatMap((ambiguity) => ambiguity.interpretations.map((value) => normalized(value)).filter(Boolean)))];
  const subjectKnown = Boolean(normalized(contract.primary_subject));
  const relationKnown = contract.requested_relationships.length > 0
    && contract.requested_relationships.every((relationship) => normalized(relationship.relation) && relationship.direction !== 'unknown');
  const facetsKnown = contract.required_answer_facets.length > 0
    && contract.required_answer_facets.every((facet) => normalized(facet.description) && normalized(facet.requested_type));
  const materialConflict = materialInterpretations.length >= 2;
  const userAmbiguityDetected = materialConflict && (!subjectKnown || !relationKnown || !facetsKnown);
  return {
    allow_clarification: userAmbiguityDetected,
    user_ambiguity_detected: userAmbiguityDetected,
    search_incompleteness_detected: !userAmbiguityDetected && semantic.route === 'clarification_required',
    subject_known: subjectKnown, relation_known: relationKnown, facets_known: facetsKnown,
    candidate_interpretation_count: materialInterpretations.length,
    material_interpretation_conflict: materialConflict,
    reason: userAmbiguityDetected ? 'material_user_request_ambiguity' : 'known_request_must_search_or_answer_partially',
  };
}

export function preserveEvidenceLedgerOnProviderFailure(previous: EvidenceLedger | null, fallback: EvidenceLedger) {
  return previous?.facets.some((facet) => facet.status !== 'missing' && facet.evidence_ids.length > 0) ? previous : fallback;
}

export function relationPathsVerified(ledger: EvidenceLedger, contract?: QuestionContract | null) {
  return ledger.facets.filter((facet) => facet.status === 'supported').every((facet) => {
    const paths = facet.relation_paths ?? [];
    if (contract?.requested_relationships.length && paths.length === 0) return false;
    return paths.every((path) => path.status === 'supported' && path.evidence_ids.length > 0);
  });
}
