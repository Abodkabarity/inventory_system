import type { EvidenceLedger, QuestionContract, RecoveryPlan, SemanticHypothesisSandbox } from './ai.ts';
import type { HybridSearchUnit, SemanticInterpretation, V3Chunk, V3Entity } from './retrieval.ts';

export const REASONING_ENGINE_VERSION = 'insurance-v3-shared-reasoning-v171';

export function semanticQuestionContract(
  question: string,
  semantic: SemanticInterpretation,
  entities: V3Entity[],
): QuestionContract {
  const dimensions = [...new Set((semantic.requested_dimensions ?? []).map((value) => String(value).trim()).filter(Boolean))];
  const fallbackNeed = String(semantic.requested_information ?? semantic.information_need ?? semantic.semantic_intent ?? question).trim();
  const semanticFacets = semantic.semantic_facets ?? [];
  const semanticRelationships = semantic.semantic_relationships ?? [];
  const facets = semanticFacets.length > 0
    ? semanticFacets.map((facet, index) => ({ id: `semantic_facet_${index + 1}`, description: facet.description, requested_type: facet.requested_type, required: true }))
    : semanticRelationships.length > 0
    ? semanticRelationships.map((relationship, index) => ({
      id: `semantic_relation_facet_${index + 1}`,
      description: [relationship.subject, relationship.relation, relationship.object].filter(Boolean).join(' '),
      requested_type: String(relationship.object ?? relationship.relation), required: true,
    }))
    : dimensions.length > 0
    ? dimensions.map((description, index) => ({ id: `semantic_facet_${index + 1}`, description, requested_type: description, required: true }))
    : [{ id: 'semantic_information_need', description: fallbackNeed, requested_type: fallbackNeed, required: true }];
  const primarySubject = entities[0]?.canonical_name
    ?? semantic.medication ?? semantic.generic ?? semantic.drug_class ?? semantic.indication
    ?? semanticRelationships[0]?.subject ?? semantic.search_concepts?.[0] ?? semantic.intent?.[0] ?? fallbackNeed;
  const intents = (semantic.intent ?? []).map((value) => String(value).trim()).filter(Boolean);
  const relationships = (semanticRelationships.length ? semanticRelationships : intents.map((intent, index) => ({
    subject: String(primarySubject).slice(0, 240), relation: intent.slice(0, 240),
    object: dimensions[index] ?? dimensions[0] ?? null, direction: 'unknown' as const,
  }))).slice(0, 8);
  const relationshipHypotheses = relationships.map((relationship) => ({
    query: [relationship.subject, relationship.relation, relationship.object].filter(Boolean).join(' ').slice(0, 500),
    mode: 'all' as const,
    concepts: [relationship.subject, relationship.relation, relationship.object].filter((value): value is string => Boolean(value)).slice(0, 10),
    relationship_direction: relationship.direction === 'comparison' ? 'bidirectional' as const : relationship.direction,
  })).filter((hypothesis) => hypothesis.query.length > 0);
  return {
    original_question: question, primary_subject: String(primarySubject).slice(0, 500),
    secondary_subjects: entities.slice(1, 9).map((entity) => entity.canonical_name),
    requested_relationships: relationships, required_answer_facets: facets.slice(0, 12),
    comparison_axes: [], constraints: [],
    patient_facts: (semantic.facts ?? []).map((fact) => [fact.concept, fact.value, fact.unit, fact.temporal].filter((value) => value != null).join(' ')).slice(0, 12),
    ambiguities: [], expected_answer_type: Math.max(intents.length, relationships.length) > 1 ? 'multi-part grounded response' : 'grounded response',
    answer_cardinality: semantic.answer_cardinality ?? (Math.max(intents.length, relationships.length) > 1 && entities.length === 0 ? 'aggregate' : 'unknown'),
    source_requirement: semantic.source_requested,
    initial_search_hypotheses: [{
      query: question.slice(0, 500), mode: 'all' as const,
      concepts: [...new Set([...(semantic.search_concepts ?? []), ...entities.map((entity) => entity.canonical_name)])].slice(0, 10),
      relationship_direction: 'unknown' as const,
    }, ...relationshipHypotheses].slice(0, 3),
  };
}

export function preserveRetrievalSeeds(
  retrievalOrderedUnits: HybridSearchUnit[], judgmentOrderedUnits: HybridSearchUnit[], aiSelectedUnits: HybridSearchUnit[],
  seedLimit = 10, totalLimit = 14,
) {
  const retrievalSeeds = retrievalOrderedUnits.slice(0, seedLimit);
  return [...new Map([...aiSelectedUnits, ...retrievalSeeds, ...judgmentOrderedUnits]
    .map((unit) => [unit.search_unit_id, unit])).values()].slice(0, totalLimit);
}

export type FeedbackObjectiveName = 'normal' | 'incorrect' | 'incomplete' | 'misunderstood';
export type FeedbackObjective = {
  name: FeedbackObjectiveName;
  reconsider_interpretation: boolean;
  require_alternative_semantic_hypotheses: boolean;
  reconsider_relation_direction: boolean;
  preserve_previous_evidence_as_clues: boolean;
  do_not_preserve_previous_claims: boolean;
  preserve_supported_previous_facts: boolean;
  target_missing_contract_facets: boolean;
  search_for_missing_evidence: boolean;
  rebuild_question_contract: boolean;
  reconsider_primary_subject: boolean;
  reconsider_requested_relationship: boolean;
};

export function feedbackObjective(reason: string | null): FeedbackObjective {
  const name: FeedbackObjectiveName = reason === 'incorrect'
    ? 'incorrect'
    : reason === 'incomplete'
    ? 'incomplete'
    : reason === 'misunderstood'
    ? 'misunderstood'
    : 'normal';
  return {
    name,
    reconsider_interpretation: name === 'incorrect' || name === 'misunderstood',
    require_alternative_semantic_hypotheses: name === 'incorrect',
    reconsider_relation_direction: name === 'incorrect' || name === 'misunderstood',
    preserve_previous_evidence_as_clues: name !== 'normal',
    do_not_preserve_previous_claims: name === 'incorrect' || name === 'misunderstood',
    preserve_supported_previous_facts: name === 'incomplete',
    target_missing_contract_facets: name === 'incomplete',
    search_for_missing_evidence: name === 'incomplete',
    rebuild_question_contract: name === 'misunderstood',
    reconsider_primary_subject: name === 'misunderstood',
    reconsider_requested_relationship: name === 'misunderstood',
  };
}

export function requiresAggregateCollection(contract: QuestionContract) {
  return contract.answer_cardinality === 'aggregate';
}

export function mergeCanonicalTerms(...groups: Array<Array<string | null | undefined>>) {
  return [...new Set(groups.flat().map((value) => String(value ?? '').normalize('NFKC').trim()).filter(Boolean))].slice(0, 40);
}

export function initialSandboxFromContract(question: string, contract: QuestionContract): SemanticHypothesisSandbox {
  const literal = question.normalize('NFKC').trim().toLocaleLowerCase();
  const hypotheses = contract.initial_search_hypotheses.slice(0, 5).map((hypothesis, index) => {
    const query = hypothesis.query.normalize('NFKC').trim();
    const queryIsLiteral = query.toLocaleLowerCase() === literal;
    const reverse = ['reverse', 'bidirectional', 'aggregation'].includes(hypothesis.relationship_direction);
    return {
      kind: queryIsLiteral && index === 0 ? 'literal' as const : reverse ? 'reverse_relation' as const : 'canonical' as const,
      query,
      concepts: hypothesis.concepts,
      mode: hypothesis.mode,
      relationship_direction: hypothesis.relationship_direction,
      basis: queryIsLiteral ? 'user_literal' as const : 'general_knowledge_search_only' as const,
    };
  }).filter((hypothesis) => hypothesis.query.length > 0);
  const relationshipDirection = hypotheses.find((hypothesis) => hypothesis.relationship_direction !== 'unknown')?.relationship_direction ?? 'unknown';
  return {
    terminology_mismatch_plausible: hypotheses.some((hypothesis) => hypothesis.kind !== 'literal'),
    relation_direction_original: relationshipDirection,
    relation_direction_reconsidered: relationshipDirection,
    evidence_discovered_terminology: [],
    hypotheses: hypotheses.length ? hypotheses : [{
      kind: 'literal', query: question.trim(), concepts: [], mode: 'all',
      relationship_direction: 'unknown', basis: 'user_literal',
    }],
  };
}

export function recoveryPlanFromSandbox(
  sandbox: SemanticHypothesisSandbox,
  objective: FeedbackObjective,
  canonicalTerms: string[],
): RecoveryPlan {
  const priority = (kind: SemanticHypothesisSandbox['hypotheses'][number]['kind']) => kind === 'evidence_discovered' ? 4 : kind === 'reverse_relation' ? 3 : kind === 'acronym_or_professional' ? 2 : kind === 'canonical' ? 1 : 0;
  const hypotheses = [...sandbox.hypotheses]
    .filter((hypothesis) => objective.require_alternative_semantic_hypotheses ? hypothesis.kind !== 'literal' : true)
    .sort((left, right) => priority(right.kind) - priority(left.kind))
    .slice(0, 5);
  return {
    decision: hypotheses.length ? 'search' : 'not_found',
    diagnosis: 'Provider-independent bounded recovery using the shared semantic sandbox.',
    information_need: '', independent_interpretation: '',
    concept_expansions: canonicalTerms.map((concept) => ({ concept, category: 'request_scoped_semantic_clue' })),
    relationship_direction: sandbox.relation_direction_reconsidered,
    clarification_question: null,
    searches: hypotheses.map((hypothesis, index) => ({
      label: `shared-sandbox-${index + 1}-${hypothesis.kind}`,
      query: hypothesis.query, mode: hypothesis.mode,
      concepts: mergeCanonicalTerms(hypothesis.concepts, canonicalTerms).slice(0, 12),
      relationship_direction: hypothesis.relationship_direction,
    })),
  };
}

function evidenceIds(entry: EvidenceLedger['facets'][number]) {
  return new Set(entry.evidence_ids.map(String));
}

export function contractRelevantEvidence<T extends V3Chunk>(evidence: T[], ledger: EvidenceLedger | null): T[] {
  if (!ledger) return evidence;
  const supported = new Set(ledger.facets.filter((facet) => facet.status !== 'missing').flatMap((facet) => [...evidenceIds(facet)]));
  if (supported.size === 0) return evidence;
  return evidence.filter((chunk) => supported.has(chunk.chunk_id)
    || (Array.isArray(chunk.metadata.source_chunk_ids) && chunk.metadata.source_chunk_ids.some((id) => supported.has(String(id)))));
}

const sourceSuffix = /\n*Source:\s*[\s\S]*$/i;
const rawJsonFence = /```(?:json)?\s*([\s\S]*?)\s*```/i;

export function looksLikeRawStructuredOutput(value: string) {
  const fenced = value.match(rawJsonFence)?.[1];
  const candidates = [fenced, value.trim()];
  const firstObject = value.indexOf('{'); const lastObject = value.lastIndexOf('}');
  const firstArray = value.indexOf('['); const lastArray = value.lastIndexOf(']');
  if (firstObject >= 0 && lastObject > firstObject) candidates.push(value.slice(firstObject, lastObject + 1));
  if (firstArray >= 0 && lastArray > firstArray) candidates.push(value.slice(firstArray, lastArray + 1));
  for (const candidate of candidates) {
    const trimmed = String(candidate ?? '').trim();
    if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) continue;
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === 'object') return true;
    } catch {
      // Continue checking other bounded candidates.
    }
  }
  return false;
}

function normalizedTokens(value: string) {
  return new Set(value.normalize('NFKC').toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').split(' ').filter((token) => token.length > 2));
}

function claimLines(chunk: V3Chunk, facet: string) {
  const facetTokens = normalizedTokens(facet);
  return chunk.chunk_text.replace(/\r/g, '').split(/\n|[;•]/)
    .map((line) => line.replace(/^\s*(?:[-–—▪]|column\s+\d+\s*:?)\s*/i, '').replace(/\s+/g, ' ').trim())
    .filter((line) => line.length >= 12)
    .map((line) => ({ line, overlap: [...normalizedTokens(line)].filter((token) => facetTokens.has(token)).length }))
    .sort((left, right) => right.overlap - left.overlap || left.line.length - right.line.length)
    .map(({ line }) => line.slice(0, 360));
}

export function deterministicGroundedSynthesis(
  question: string,
  contract: QuestionContract,
  ledger: EvidenceLedger,
  evidence: V3Chunk[],
) {
  const arabic = /[\u0600-\u06ff]/.test(question);
  const byId = new Map(evidence.map((chunk, index) => [chunk.chunk_id, { chunk, index }]));
  const bullets: string[] = [];
  const usedIndexes = new Set<number>();
  for (const facet of contract.required_answer_facets) {
    const entry = ledger.facets.find((item) => item.facet_id === facet.id);
    if (!entry || entry.status === 'missing') continue;
    const rows = entry.evidence_ids.flatMap((id) => byId.has(id) ? [byId.get(id)!] : []);
    const claims = [...new Set(rows.flatMap(({ chunk }) => claimLines(chunk, facet.description)))].slice(0, 2);
    rows.forEach(({ index }) => usedIndexes.add(index));
    if (claims.length) bullets.push(`- ${facet.description}: ${claims.join(' ')}`);
  }
  if (bullets.length === 0 && evidence.length > 0) {
    const facet = contract.required_answer_facets[0]?.description ?? contract.expected_answer_type;
    const claims = claimLines(evidence[0], facet).slice(0, 2);
    if (claims.length) {
      bullets.push(`- ${facet}: ${claims.join(' ')}`);
      usedIndexes.add(0);
    }
  }
  const missing = contract.required_answer_facets.filter((facet) => {
    const entry = ledger.facets.find((item) => item.facet_id === facet.id);
    return !entry || entry.status !== 'supported';
  }).map((facet) => facet.description);
  const heading = arabic ? 'وفقًا للأدلة المعتمدة:' : 'Based on the approved evidence:';
  const missingText = missing.length === 0 ? '' : arabic
    ? `\n\nلم تثبت الأدلة: ${missing.join('؛ ')}.`
    : `\n\nThe evidence does not establish: ${missing.join('; ')}.`;
  const aggregatePartial = contract.answer_cardinality === 'aggregate' && ledger.aggregation_complete !== true;
  const aggregateText = !aggregatePartial ? '' : arabic
    ? '\n\nهذه هي النتائج التي ثبتت بالأدلة المتاحة؛ ولم يثبت اكتمال القائمة.'
    : '\n\nThese are the matches established by the available evidence; completeness of the list was not established.';
  return {
    answer: `${heading}\n${bullets.join('\n')}${missingText}${aggregateText}`.trim(),
    used_evidence_ids: [...usedIndexes].sort((a, b) => a - b).map((index) => `E${index + 1}`),
  };
}

export function guardUserOutput(
  answer: string,
  question: string,
  contract: QuestionContract,
  ledger: EvidenceLedger,
  evidence: V3Chunk[],
  rawEvidenceFallback: boolean,
) {
  const rawJsonBlocked = looksLikeRawStructuredOutput(answer.replace(sourceSuffix, '').trim());
  const rawEvidenceDumpBlocked = rawEvidenceFallback;
  if (!rawJsonBlocked && !rawEvidenceDumpBlocked) {
    return { answer, used_evidence_ids: null as string[] | null, raw_json_blocked: false, raw_evidence_dump_blocked: false };
  }
  const replacement = deterministicGroundedSynthesis(question, contract, ledger, evidence);
  return { ...replacement, raw_json_blocked: rawJsonBlocked, raw_evidence_dump_blocked: rawEvidenceDumpBlocked };
}
