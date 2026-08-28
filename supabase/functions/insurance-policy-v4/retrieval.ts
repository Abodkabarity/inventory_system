import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.57.4';
import type { JsonMap, ResolvedEntity, SearchUnit, SemanticRequest } from './types.ts';

const EMBEDDING_MODEL = Deno.env.get('INSURANCE_EMBEDDING_MODEL') ?? 'intfloat/multilingual-e5-large-instruct';

type RetrievalDiagnostics = {
  channels: string[];
  generated_queries: string[];
  embedding_degraded: boolean;
  candidate_count: number;
};

function rows(value: unknown): JsonMap[] {
  return Array.isArray(value) ? value.filter((item): item is JsonMap => !!item && typeof item === 'object' && !Array.isArray(item)) : [];
}

function uniqueQueries(original: string, semantic: SemanticRequest, deepReview: boolean) {
  const base = [original, ...semantic.search_queries, ...semantic.entities, semantic.concepts.join(' ')];
  const queries = [...new Set(base.map((value) => value.trim()).filter(Boolean))];
  return queries.slice(0, deepReview ? 6 : 4);
}

function entityResolutionTerms(semantic: SemanticRequest, question: string) {
  const phrases = [...semantic.entities, ...semantic.search_queries, question];
  const tokens = phrases.flatMap((phrase) => phrase.match(/[\p{L}\p{N}]+(?:-[\p{L}\p{N}]+)*/gu) ?? [])
    .filter((token) => token.length >= 3)
    .flatMap((token) => /s$/i.test(token) && token.length <= 8 ? [token, token.slice(0, -1)] : [token]);
  return [...new Set([...phrases, ...tokens].map((value) => value.trim()).filter(Boolean))].slice(0, 30);
}

export async function resolveEntities(db: SupabaseClient, semantic: SemanticRequest, question: string) {
  const terms = entityResolutionTerms(semantic, question);
  const { data, error } = await db.rpc('insurance_v3_resolve_entities', { p_terms: terms });
  if (error) throw new Error(`Verified entity resolution failed: ${error.message}`);
  return rows(data).map((row): ResolvedEntity => ({
    entity_id: String(row.entity_id),
    canonical_name: String(row.canonical_name),
    entity_type: String(row.entity_type),
    matched_term: String(row.matched_term),
    match_kind: String(row.match_kind),
  }));
}

export async function expandVerifiedMedicationRelations(db: SupabaseClient, entities: ResolvedEntity[]) {
  const medicationIds = [...new Set(entities
    .filter((entity) => entity.entity_type === 'medication_brand' || entity.entity_type === 'medication_generic')
    .map((entity) => entity.entity_id))];
  if (!medicationIds.length) return entities;
  const [subjects, objects] = await Promise.all([
    db.from('insurance_v3_entity_relations').select('subject_entity_id,object_entity_id')
      .eq('verified', true).in('subject_entity_id', medicationIds),
    db.from('insurance_v3_entity_relations').select('subject_entity_id,object_entity_id')
      .eq('verified', true).in('object_entity_id', medicationIds),
  ]);
  if (subjects.error || objects.error) return entities;
  const relations = [...rows(subjects.data), ...rows(objects.data)];
  const relatedIds = [...new Set(relations.flatMap((row) => [String(row.subject_entity_id), String(row.object_entity_id)]))]
    .filter((id) => !medicationIds.includes(id));
  if (!relatedIds.length) return entities;
  const { data, error } = await db.from('insurance_v3_entities').select('id,canonical_name,entity_type')
    .in('id', relatedIds).in('entity_type', ['medication_brand', 'medication_generic']).eq('active', true);
  if (error) return entities;
  const originalById = new Map(entities.map((entity) => [entity.entity_id, entity]));
  const additions = rows(data).flatMap((row): ResolvedEntity[] => {
    const id = String(row.id);
    const relation = relations.find((item) => String(item.subject_entity_id) === id || String(item.object_entity_id) === id);
    const anchorId = String(relation?.subject_entity_id) === id ? String(relation?.object_entity_id) : String(relation?.subject_entity_id);
    const anchor = originalById.get(anchorId);
    if (!anchor) return [];
    return [{
      entity_id: id,
      canonical_name: String(row.canonical_name),
      entity_type: String(row.entity_type),
      matched_term: anchor.matched_term,
      match_kind: 'verified_relation',
    }];
  });
  return [...new Map([...entities, ...additions].map((entity) => [entity.entity_id, entity])).values()];
}


function entityIdsForQuery(query: string, entities: ResolvedEntity[]) {
  const normalizedQuery = query.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const directlyNamed = entities.filter((entity) => [entity.canonical_name, entity.matched_term].some((name) => {
    const normalized = name.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
    return normalized.length >= 3 && (` ${normalizedQuery} `).includes(` ${normalized} `);
  }));
  if (!directlyNamed.length) return [...new Set(entities.map((entity) => entity.entity_id))];
  const matchedTerms = new Set(directlyNamed.map((entity) => entity.matched_term.toLowerCase()));
  return [...new Set(entities.filter((entity) => matchedTerms.has(entity.matched_term.toLowerCase())).map((entity) => entity.entity_id))];
}

async function embedQuery(query: string): Promise<number[] | null> {
  const key = Deno.env.get('TOGETHER_API_KEY');
  if (!key) return null;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch('https://api.together.xyz/v1/embeddings', {
      method: 'POST',
      signal: controller.signal,
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: EMBEDDING_MODEL,
        input: `Instruct: Retrieve approved insurance-policy evidence that answers this request.\nQuery: ${query.slice(0, 1600)}`,
      }),
    });
    if (!response.ok) return null;
    const payload = await response.json() as JsonMap;
    const data = rows(payload.data);
    const embedding = data[0]?.embedding;
    return Array.isArray(embedding) && embedding.length === 1024 && embedding.every((value) => typeof value === 'number')
      ? embedding as number[]
      : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function unitFromRow(row: JsonMap, query: string): SearchUnit {
  const numberOrNull = (value: unknown) => typeof value === 'number' ? value : value == null ? null : Number(value);
  return {
    search_unit_id: String(row.search_unit_id),
    document_id: String(row.document_id),
    document_title: String(row.document_title ?? ''),
    file_name: String(row.file_name ?? ''),
    unit_type: String(row.unit_type ?? 'text_chunk'),
    page_from: numberOrNull(row.page_from),
    page_to: numberOrNull(row.page_to),
    sheet_name: row.sheet_name == null ? null : String(row.sheet_name),
    row_from: numberOrNull(row.row_from),
    row_to: numberOrNull(row.row_to),
    section_title: row.section_title == null ? null : String(row.section_title),
    table_title: row.table_title == null ? null : String(row.table_title),
    parent_unit_id: row.parent_unit_id == null ? null : String(row.parent_unit_id),
    retrieval_text: String(row.retrieval_text ?? ''),
    source_chunk_ids: Array.isArray(row.source_chunk_ids) ? row.source_chunk_ids.map(String) : [],
    metadata: row.metadata && typeof row.metadata === 'object' && !Array.isArray(row.metadata) ? row.metadata as JsonMap : {},
    vector_rank: numberOrNull(row.vector_rank),
    fts_rank: numberOrNull(row.fts_rank),
    trigram_rank: numberOrNull(row.trigram_rank),
    heading_rank: numberOrNull(row.heading_rank),
    entity_rank: numberOrNull(row.entity_rank),
    vector_similarity: numberOrNull(row.vector_similarity),
    fts_score: numberOrNull(row.fts_score),
    trigram_score: numberOrNull(row.trigram_score),
    entity_match_count: Number(row.entity_match_count ?? 0),
    hybrid_rrf_score: Number(row.hybrid_rrf_score ?? 0),
    matched_queries: [query],
  };
}

export async function retrieveEvidenceCandidates(
  db: SupabaseClient,
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  deepReview = false,
): Promise<{ candidates: SearchUnit[]; diagnostics: RetrievalDiagnostics }> {
  const queries = uniqueQueries(question, semantic, deepReview);
  const searches = await Promise.all(queries.map(async (query) => {
    const entityIds = entityIdsForQuery(query, entities);
    const embedding = await embedQuery(query);
    const { data, error } = await db.rpc('insurance_v3_hybrid_search', {
      p_query: query,
      p_query_embedding: embedding,
      p_entity_ids: entityIds,
      p_limit: semantic.answer_cardinality === 'single' ? 36 : 60,
    });
    if (error) throw new Error(`Hybrid retrieval failed: ${error.message}`);
    return { query, embedding: embedding !== null, rows: rows(data) };
  }));

  const merged = new Map<string, SearchUnit>();
  for (const result of searches) {
    for (const row of result.rows) {
      const unit = unitFromRow(row, result.query);
      const existing = merged.get(unit.search_unit_id);
      if (!existing) {
        merged.set(unit.search_unit_id, unit);
      } else {
        existing.matched_queries = [...new Set([...existing.matched_queries, result.query])];
        existing.hybrid_rrf_score = Math.max(existing.hybrid_rrf_score, unit.hybrid_rrf_score);
        existing.entity_match_count = Math.max(existing.entity_match_count, unit.entity_match_count);
        existing.vector_similarity = Math.max(existing.vector_similarity ?? -1, unit.vector_similarity ?? -1);
      }
    }
  }
  const candidates = [...merged.values()];
  return {
    candidates,
    diagnostics: {
      channels: ['verified_entity', 'full_text', 'trigram', 'vector', 'structured_row', 'heading'],
      generated_queries: queries,
      embedding_degraded: searches.some((result) => !result.embedding),
      candidate_count: candidates.length,
    },
  };
}
