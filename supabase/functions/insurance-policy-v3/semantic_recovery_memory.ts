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

const strings = (values: unknown[]) => [...new Set(values.map(normalize).filter(Boolean))].sort();
const intersection = (left: string[], right: string[]) => left.filter((value) => right.includes(value));
const jaccard = (left: string[], right: string[]) => {
  const union = new Set([...left, ...right]);
  return union.size === 0 ? 1 : intersection(left, right).length / union.size;
};
const textSimilarity = (left: unknown, right: unknown) => jaccard(
  normalize(left).split(' ').filter(Boolean), normalize(right).split(' ').filter(Boolean),
);

export function semanticRecoveryPayload(semantic: SemanticInterpretation, entities: V3Entity[]) {
  return {
    route: semantic.route,
    entity_ids: [...new Set(entities.map((entity) => entity.id))].sort(),
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
  };
}

export async function semanticRecoverySignature(semantic: SemanticInterpretation, entities: V3Entity[]) {
  const bytes = new TextEncoder().encode(JSON.stringify(semanticRecoveryPayload(semantic, entities)));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function scoreSemanticMemory(current: ReturnType<typeof semanticRecoveryPayload>, stored: Record<string, unknown>) {
  const currentEntities = current.entity_ids;
  const storedEntities = Array.isArray(stored.entity_ids) ? stored.entity_ids.map(String).sort() : [];
  // A memory hint may never introduce or substitute an identity. An explicit
  // verified entity requires the same verified entity set in memory.
  if (currentEntities.length > 0 && JSON.stringify(currentEntities) !== JSON.stringify(storedEntities)) return 0;
  if (currentEntities.length === 0 && storedEntities.length > 0) return 0;
  const intent = jaccard(current.intent, Array.isArray(stored.intent) ? stored.intent.map(String) : []);
  const dimensions = jaccard(current.requested_dimensions, Array.isArray(stored.requested_dimensions) ? stored.requested_dimensions.map(String) : []);
  const concepts = jaccard(current.source_concepts, Array.isArray(stored.source_concepts) ? stored.source_concepts.map(String) : []);
  const stage = current.treatment_stage === normalize(stored.treatment_stage) ? 1 : 0;
  const indication = current.indication === normalize(stored.indication) ? 1 : 0;
  const semanticIntent = textSimilarity(current.semantic_intent, stored.semantic_intent);
  const informationNeed = textSimilarity(current.information_need, stored.information_need);
  if ((semanticIntent + informationNeed) / 2 < 0.25) return 0;
  return (intent * 0.18) + (dimensions * 0.18) + (concepts * 0.20) + (stage * 0.10)
    + (indication * 0.10) + (semanticIntent * 0.12) + (informationNeed * 0.12);
}

export async function findVerifiedSemanticMemory(
  db: DBClient, semantic: SemanticInterpretation, entities: V3Entity[],
): Promise<{ hint: SemanticMemoryHint | null; invalidated: Array<{ id: string; reason: string }> }> {
  const payload = semanticRecoveryPayload(semantic, entities);
  let query = db.from('insurance_semantic_recovery_memories').select('*')
    .eq('active', true).gte('confidence', 0.82).order('updated_at', { ascending: false }).limit(40);
  if (payload.entity_ids.length > 0) query = query.contains('verified_entity_ids', payload.entity_ids);
  const { data, error } = await query;
  if (error) return { hint: null, invalidated: [] };
  const ranked = (data ?? []).map((row: Record<string, unknown>) => ({ row, score: scoreSemanticMemory(payload, row.semantic_request as Record<string, unknown> ?? {}) }))
    .filter(({ score }: { score: number }) => score >= 0.82)
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
  expansionConcepts: string[]; hypotheses: RecoveryHypothesis[];
  relationshipDirection: RecoveryHypothesis['relationship_direction']; evidenceIds: string[];
  documents: Array<Record<string, unknown>>; auditId: string;
}) {
  if (input.evidenceIds.length === 0 || input.documents.length === 0 || input.hypotheses.length < 3 || input.hypotheses.length > 6) return null;
  if (input.evidenceIds.some((id) => !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(id))) return null;
  if (input.documents.some((document) => document.is_active !== true
    || !String(document.document_hash ?? '').trim()
    || !String(document.storage_bucket ?? '').trim() || !String(document.storage_path ?? '').trim())) return null;
  const signature = await semanticRecoverySignature(input.semantic, input.entities);
  const now = new Date().toISOString();
  const entityIds = input.entities.map((entity) => entity.id);
  const { data: existing } = await db.from('insurance_semantic_recovery_memories')
    .select('id,confidence,successful_uses,invalidation_reason').eq('semantic_signature', signature).maybeSingle();
  if (existing?.invalidation_reason === 'negative_feedback_confidence_floor') return null;
  const confidence = Math.max(0.86, Number(existing?.confidence ?? 0));
  const { data, error } = await db.from('insurance_semantic_recovery_memories').upsert({
    semantic_signature: signature,
    semantic_request: semanticRecoveryPayload(input.semantic, input.entities),
    verified_entity_ids: entityIds,
    source_concepts: semanticRecoveryPayload(input.semantic, input.entities).source_concepts,
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
