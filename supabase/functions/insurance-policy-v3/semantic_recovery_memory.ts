import { normalize, type SemanticInterpretation, type V3Entity, type V3Relation } from './retrieval.ts';
import { relationSnapshot, validatePreferredAnswerSources } from './validated_cache.ts';

// deno-lint-ignore no-explicit-any
type DBClient = any;

export type RecoveryHypothesis = {
  label: string;
  query: string;
  mode: 'all' | 'semantic' | 'tables' | 'headings' | 'documents' | 'entities';
  concepts: string[];
  relationship_direction: 'forward' | 'reverse' | 'bidirectional' | 'aggregation' | 'unknown';
};

export type SemanticMemoryHint = {
  id: string;
  confidence: number;
  score: number;
  expansion_concepts: string[];
  hypotheses: RecoveryHypothesis[];
  relationship_direction: RecoveryHypothesis['relationship_direction'];
};
type ContractShape = { requested_relationships?: Array<{ subject?: string; relation?: string; object?: string | null; direction?: string }>; required_answer_facets?: Array<{ description?: string }>; comparison_axes?: string[] };

const strings = (values: unknown[]) => [...new Set(values.map(normalize).filter(Boolean))].sort();
const intersection = (left: string[], right: string[]) => left.filter((value) => right.includes(value));
const jaccard = (left: string[], right: string[]) => {
  const union = new Set([...left, ...right]);
  return union.size === 0 ? 1 : intersection(left, right).length / union.size;
};
const characterNgrams = (value: unknown, size = 3) => {
  const text = normalize(value).replace(/\s+/g, ' ');
  if (text.length < size) return text ? [text] : [];
  return [...new Set(Array.from({ length: text.length - size + 1 }, (_, index) => text.slice(index, index + size)))];
};
const textSimilarity = (left: unknown, right: unknown) => Math.max(
  jaccard(normalize(left).split(' ').filter(Boolean), normalize(right).split(' ').filter(Boolean)),
  jaccard(characterNgrams(left), characterNgrams(right)),
);
const semanticSetSimilarity = (left: string[], right: string[]) => {
  if (left.length === 0 && right.length === 0) return 1;
  if (left.length === 0 || right.length === 0) return 0;
  const directed = (source: string[], target: string[]) => source.reduce((sum, value) =>
    sum + Math.max(...target.map((candidate) => textSimilarity(value, candidate))), 0) / source.length;
  return (directed(left, right) + directed(right, left)) / 2;
};
const relationshipDirections = (shapes: string[]) => strings(shapes.map((shape) => shape.split(' ').at(-1)));

export function semanticRecoveryPayload(semantic: SemanticInterpretation, entities: V3Entity[], contract?: ContractShape | null) {
  return {
    route: semantic.route,
    entity_ids: [...new Set(entities.map((entity) => entity.id))].sort(),
    identity_entity_ids: [...new Set(entities.filter((entity) => entity.entity_type.startsWith('medication_')).map((entity) => entity.id))].sort(),
    contextual_entity_ids: [...new Set(entities.filter((entity) => !entity.entity_type.startsWith('medication_')).map((entity) => entity.id))].sort(),
    intent: strings(semantic.intent),
    requested_dimensions: strings(semantic.requested_dimensions),
    treatment_stage: normalize(semantic.treatment_stage),
    indication: normalize(semantic.indication),
    semantic_intent: normalize(semantic.semantic_intent),
    information_need: normalize(semantic.information_need),
    source_concepts: strings([
      ...(semantic.search_concepts ?? []), ...(semantic.search_phrases ?? []),
      ...semantic.facts.map((fact) => fact.concept), semantic.medication, semantic.generic,
      semantic.drug_class, semantic.indication,
    ]),
    relationship_shapes: strings((contract?.requested_relationships ?? []).map((relationship) => `${relationship.subject ?? ''}|${relationship.relation ?? ''}|${relationship.object ?? ''}|${relationship.direction ?? ''}`)),
    answer_facets: strings((contract?.required_answer_facets ?? []).map((facet) => facet.description)),
    comparison_axes: strings(contract?.comparison_axes ?? []),
  };
}

export async function semanticRecoverySignature(semantic: SemanticInterpretation, entities: V3Entity[], contract?: ContractShape | null) {
  const bytes = new TextEncoder().encode(JSON.stringify(semanticRecoveryPayload(semantic, entities, contract)));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function scoreSemanticMemory(current: ReturnType<typeof semanticRecoveryPayload>, stored: Record<string, unknown>) {
  const storedEntities = Array.isArray(stored.entity_ids) ? stored.entity_ids.map(String).sort() : [];
  const currentIdentityEntities = current.identity_entity_ids;
  const storedIdentityEntities = Array.isArray(stored.identity_entity_ids)
    ? stored.identity_entity_ids.map(String).sort()
    : storedEntities;
  // Medication identity is the hard isolation boundary. Contextual entities
  // such as an indication may be recognized in one paraphrase and omitted in
  // another; they influence semantic scoring but cannot substitute a drug.
  if (currentIdentityEntities.length > 0
    && JSON.stringify(currentIdentityEntities) !== JSON.stringify(storedIdentityEntities)) return 0;
  if (currentIdentityEntities.length === 0 && storedIdentityEntities.length > 0) return 0;
  const storedContextEntities = Array.isArray(stored.contextual_entity_ids) ? stored.contextual_entity_ids.map(String).sort() : [];
  const contextEntities = jaccard(current.contextual_entity_ids, storedContextEntities);
  const storedIntent = Array.isArray(stored.intent) ? stored.intent.map(String) : [];
  const intent = Math.max(jaccard(current.intent, storedIntent), semanticSetSimilarity(current.intent, storedIntent));
  const dimensions = jaccard(current.requested_dimensions, Array.isArray(stored.requested_dimensions) ? stored.requested_dimensions.map(String) : []);
  const concepts = jaccard(current.source_concepts, Array.isArray(stored.source_concepts) ? stored.source_concepts.map(String) : []);
  const stage = current.treatment_stage === normalize(stored.treatment_stage) ? 1 : 0;
  const indication = current.indication === normalize(stored.indication) ? 1 : 0;
  const semanticIntent = textSimilarity(current.semantic_intent, stored.semantic_intent);
  const informationNeed = textSimilarity(current.information_need, stored.information_need);
  const storedRelationships = Array.isArray(stored.relationship_shapes) ? stored.relationship_shapes.map(String) : [];
  const currentDirections = relationshipDirections(current.relationship_shapes);
  const storedDirections = relationshipDirections(storedRelationships);
  // Direction is a hard safety boundary; surface wording within the same
  // direction is compared semantically so paraphrases can reuse a verified
  // retrieval repair without allowing forward/reverse contamination.
  if (currentDirections.length > 0 && storedDirections.length > 0
    && JSON.stringify(currentDirections) !== JSON.stringify(storedDirections)) return 0;
  const relationships = Math.max(jaccard(current.relationship_shapes, storedRelationships), semanticSetSimilarity(current.relationship_shapes, storedRelationships));
  if (current.relationship_shapes.length > 0 && relationships < 0.25) return 0;
  const storedFacets = Array.isArray(stored.answer_facets) ? stored.answer_facets.map(String) : [];
  const facets = semanticSetSimilarity(current.answer_facets, storedFacets);
  if ((semanticIntent + informationNeed) / 2 < 0.25) return 0;
  const rawScore = (intent * 0.13) + (dimensions * 0.07) + (concepts * 0.13) + (stage * 0.06)
    + (indication * 0.08) + (semanticIntent * 0.12) + (informationNeed * 0.13)
    + (relationships * 0.14) + (facets * 0.10) + (contextEntities * 0.04);
  const anchoredRelationshipBonus = currentIdentityEntities.length > 0
    && current.relationship_shapes.length > 0
    && (semanticIntent + informationNeed) / 2 >= 0.45
    && relationships >= 0.25 ? 0.20 : 0;
  return Math.min(1, rawScore + anchoredRelationshipBonus);
}

export async function findVerifiedSemanticMemory(
  db: DBClient, semantic: SemanticInterpretation, entities: V3Entity[], contract?: ContractShape | null,
): Promise<{ hint: SemanticMemoryHint | null; invalidated: Array<{ id: string; reason: string }> }> {
  const payload = semanticRecoveryPayload(semantic, entities, contract);
  let query = db.from('insurance_semantic_recovery_memories').select('*')
    .eq('active', true).gte('confidence', 0.82).order('updated_at', { ascending: false }).limit(40);
  if (payload.entity_ids.length > 0) query = query.contains('verified_entity_ids', payload.entity_ids);
  const { data, error } = await query;
  if (error) return { hint: null, invalidated: [] };
  // The calibrated 0.68 score is only considered after the hard medication
  // identity and relationship-direction gates inside scoreSemanticMemory.
  // Database confidence remains >= 0.82 and source snapshots are revalidated.
  const ranked = (data ?? []).map((row: Record<string, unknown>) => ({ row, score: scoreSemanticMemory(payload, row.semantic_request as Record<string, unknown> ?? {}) }))
    .filter(({ score }: { score: number }) => score >= 0.68)
    .sort((left: { score: number }, right: { score: number }) => right.score - left.score);
  const invalidated: Array<{ id: string; reason: string }> = [];
  for (const candidate of ranked.slice(0, 5)) {
    const validity = await validatePreferredAnswerSources(db, candidate.row);
    if (!validity.valid) {
      const id = String(candidate.row.id);
      invalidated.push({ id, reason: validity.reason ?? 'source_validation_failed' });
      await db.from('insurance_semantic_recovery_memories').update({
        active: false, invalidated_at: new Date().toISOString(), invalidation_reason: validity.reason, updated_at: new Date().toISOString(),
      }).eq('id', id);
      continue;
    }
    const hypotheses = Array.isArray(candidate.row.retrieval_hypotheses)
      ? candidate.row.retrieval_hypotheses as RecoveryHypothesis[] : [];
    return { hint: {
      id: String(candidate.row.id), confidence: Number(candidate.row.confidence), score: candidate.score,
      expansion_concepts: Array.isArray(candidate.row.expansion_concepts) ? candidate.row.expansion_concepts.map(String).slice(0, 18) : [],
      hypotheses: hypotheses.slice(0, 6),
      relationship_direction: String(candidate.row.relationship_direction ?? 'unknown') as SemanticMemoryHint['relationship_direction'],
    }, invalidated };
  }
  return { hint: null, invalidated };
}

export async function storeVerifiedSemanticRecovery(db: DBClient, input: {
  semantic: SemanticInterpretation; entities: V3Entity[]; relations: V3Relation[];
  contract?: ContractShape | null;
  expansionConcepts: string[]; hypotheses: RecoveryHypothesis[];
  relationshipDirection: RecoveryHypothesis['relationship_direction']; evidenceIds: string[];
  documents: Array<Record<string, unknown>>; auditId: string;
}) {
  if (input.evidenceIds.length === 0 || input.documents.length === 0 || input.hypotheses.length < 3 || input.hypotheses.length > 6) return null;
  if (input.evidenceIds.some((id) => !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(id))) return null;
  if (input.documents.some((document) => document.is_active !== true
    || !String(document.document_hash ?? '').trim()
    || !String(document.storage_bucket ?? '').trim() || !String(document.storage_path ?? '').trim())) return null;
  const signature = await semanticRecoverySignature(input.semantic, input.entities, input.contract);
  const now = new Date().toISOString();
  const entityIds = input.entities.map((entity) => entity.id);
  const { data: existing } = await db.from('insurance_semantic_recovery_memories')
    .select('id,confidence,successful_uses,invalidation_reason').eq('semantic_signature', signature).maybeSingle();
  if (existing?.invalidation_reason === 'negative_feedback_confidence_floor') return null;
  const confidence = Math.max(0.86, Number(existing?.confidence ?? 0));
  const { data, error } = await db.from('insurance_semantic_recovery_memories').upsert({
    semantic_signature: signature,
    semantic_request: semanticRecoveryPayload(input.semantic, input.entities, input.contract),
    verified_entity_ids: entityIds,
    source_concepts: semanticRecoveryPayload(input.semantic, input.entities, input.contract).source_concepts,
    expansion_concepts: strings(input.expansionConcepts).slice(0, 24),
    relationship_direction: input.relationshipDirection,
    retrieval_hypotheses: input.hypotheses.slice(0, 6),
    evidence_ids: [...new Set(input.evidenceIds)], document_snapshots: input.documents,
    relation_snapshot: relationSnapshot(input.relations, entityIds), source_audit_id: input.auditId,
    confidence, successful_uses: Number(existing?.successful_uses ?? 0) + 1, active: true,
    last_verified_at: now, invalidated_at: null, invalidation_reason: null, updated_at: now,
  }, { onConflict: 'semantic_signature' }).select('id').single();
  return error ? null : String(data.id);
}

export async function recordSemanticMemoryFeedback(db: DBClient, memoryId: string, positive: boolean) {
  const { data: row } = await db.from('insurance_semantic_recovery_memories').select('id,confidence,positive_feedback_count,negative_feedback_count')
    .eq('id', memoryId).eq('active', true).maybeSingle();
  if (!row) return;
  const confidence = Math.max(0, Math.min(1, Number(row.confidence) + (positive ? 0.05 : -0.18)));
  await db.from('insurance_semantic_recovery_memories').update({
    confidence,
    positive_feedback_count: Number(row.positive_feedback_count) + (positive ? 1 : 0),
    negative_feedback_count: Number(row.negative_feedback_count) + (positive ? 0 : 1),
    active: confidence >= 0.72,
    invalidated_at: confidence >= 0.72 ? null : new Date().toISOString(),
    invalidation_reason: confidence >= 0.72 ? null : 'negative_feedback_confidence_floor',
    updated_at: new Date().toISOString(),
  }).eq('id', row.id);
}
