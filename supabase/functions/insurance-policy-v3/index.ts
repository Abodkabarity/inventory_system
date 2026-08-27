import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { AI_MODEL, answerFromEvidence, answerIncompleteRecovery, interpretQuestion, judgeHydratedEvidenceSufficiency, planRecoverySearch, rerankAndJudgeEvidence, type EvidenceJudgment, type EvidenceSufficiency, type RecoveryPlan } from './ai.ts';
import { AIProviderError, AIProvidersTemporarilyUnavailableError, type AIProviderName } from './ai_provider.ts';
import { groundedExtractiveAnswer, hasStrongVerifiedEvidence } from './fallback.ts';
import { newRequestTrace, persistRequestTrace, type RequestTrace } from './diagnostics.ts';
import { alignSemanticMedication, evaluateOrThresholdTimeWindows, renderDeterministicCriterionAnswer } from './criteria.ts';
import { embedRetrievalQuery } from './embedding.ts';
import { incompleteExtractiveFallback } from './incomplete_recovery.ts';
import { preferredAnswerShouldReplace, relationSnapshot, semanticCachePayload, semanticCacheSignature, validatePreferredAnswerSources } from './validated_cache.ts';
import {
  buildRetrievalPlan, chunkAnswersDimension, enforceRouteSafety, evidenceForAnswer, groundEntityOnlySemantic, isolateMedicationCandidates, normalize,
  isolateSearchUnitCandidates, requestedDimensions, rerankChunks, resolveVerifiedEntities, selectEvidence, strictRetrievalEntityIds,
  type HybridSearchUnit, type SemanticInterpretation, type V3Alias, type V3Chunk, type V3Entity, type V3Relation,
} from './retrieval.ts';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const retrievalMode = Deno.env.get('INSURANCE_V3_RETRIEVAL_MODE') === 'lexical' ? 'lexical' : 'hybrid';
const respond = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
function usageTotal(usage: unknown) {
  if (!usage || typeof usage !== 'object') return 0;
  const r = usage as Record<string, unknown>;
  return typeof r.total_tokens === 'number' ? r.total_tokens : Number(r.prompt_tokens ?? r.input_tokens ?? 0) + Number(r.completion_tokens ?? r.output_tokens ?? 0);
}
function usagePart(usage: unknown, primary: string, alternate: string) {
  if (!usage || typeof usage !== 'object') return 0;
  const value = (usage as Record<string, unknown>)[primary] ?? (usage as Record<string, unknown>)[alternate];
  return typeof value === 'number' ? value : 0;
}
type AIMetadata = { usage: unknown; latency_ms: number; provider: AIProviderName; model: string };
function aiDiagnostics(semantic: AIMetadata, reranks: AIMetadata[], answer: AIMetadata | null) {
  const calls = [semantic, ...reranks, ...(answer ? [answer] : [])];
  return {
    provider: calls.some((call) => call.provider === 'groq_fallback') ? 'groq_fallback' : 'together', model: answer?.model ?? reranks.at(-1)?.model ?? semantic.model,
    semantic_provider: semantic.provider, rerank_providers: reranks.map((call) => call.provider), answer_provider: answer?.provider ?? null,
    semantic_input_tokens: usagePart(semantic.usage, 'prompt_tokens', 'input_tokens'), semantic_output_tokens: usagePart(semantic.usage, 'completion_tokens', 'output_tokens'),
    rerank_input_tokens: reranks.reduce((s, x) => s + usagePart(x.usage, 'prompt_tokens', 'input_tokens'), 0), rerank_output_tokens: reranks.reduce((s, x) => s + usagePart(x.usage, 'completion_tokens', 'output_tokens'), 0),
    answer_input_tokens: usagePart(answer?.usage, 'prompt_tokens', 'input_tokens'), answer_output_tokens: usagePart(answer?.usage, 'completion_tokens', 'output_tokens'),
    total_tokens: calls.reduce((s, x) => s + usageTotal(x.usage), 0), semantic_latency_ms: semantic.latency_ms,
    rerank_latency_ms: reranks.reduce((s, x) => s + x.latency_ms, 0), answer_latency_ms: answer?.latency_ms ?? 0,
  };
}
function mergeUnits(left: HybridSearchUnit[], right: HybridSearchUnit[]) {
  return [...new Map([...left, ...right].map((u) => [u.search_unit_id, u])).values()].sort((a, b) => Number(b.hybrid_rrf_score) - Number(a.hybrid_rrf_score));
}
type RerankResult = Awaited<ReturnType<typeof rerankAndJudgeEvidence>>;
function rerankUnits(units: HybridSearchUnit[], judgments: RerankResult['judgments']) {
  const judgmentById = new Map(judgments.map((judgment) => [judgment.candidate_id, judgment]));
  return [...units].sort((left, right) => {
    const leftJudgment = judgmentById.get(left.search_unit_id);
    const rightJudgment = judgmentById.get(right.search_unit_id);
    const tier = (judgment: typeof leftJudgment) => judgment?.answer_bearing
      ? 3
      : judgment && judgment.relevance_score >= 55
      ? 2
      : judgment
      ? 0
      : 1;
    return tier(rightJudgment) - tier(leftJudgment)
      || Number(rightJudgment?.directness_score ?? 0) - Number(leftJudgment?.directness_score ?? 0)
      || Number(rightJudgment?.relevance_score ?? 0) - Number(leftJudgment?.relevance_score ?? 0)
      || Number(right.hybrid_rrf_score) - Number(left.hybrid_rrf_score);
  });
}
function judgedUnits(units: HybridSearchUnit[], judgments: RerankResult['judgments']) {
  const reranked = rerankUnits(units, judgments);
  const positiveIds = new Set(judgments.filter((x) => x.answer_bearing || x.relevance_score >= 55).map((x) => x.candidate_id));
  const aiSelected = reranked.filter((unit) => positiveIds.has(unit.search_unit_id));
  // The semantic reranker remains mandatory, but it is not allowed to destroy
  // high-confidence, entity-isolated retrieval evidence before structural
  // hydration. A small RRF seed set protects recall; downstream chunk ranking
  // and the hydrated AI sufficiency judge still control usable evidence.
  const recallSeeds = units.slice(0, 10);
  const selected = [...new Map([...aiSelected, ...recallSeeds].map((unit) => [unit.search_unit_id, unit])).values()].slice(0, 14);
  return selected.length ? selected : units.slice(0, 6);
}
// The Edge Function intentionally uses runtime-discovered RPCs introduced by
// the accompanying migration, so there is no generated Database type here.
// deno-lint-ignore no-explicit-any
type DBClient = any;
async function retrieveHybrid(db: DBClient, lexicalQuery: string, vectorQuery: string, entities: V3Entity[], knownEntities: V3Entity[]) {
  const embedding = await embedRetrievalQuery(vectorQuery);
  // The SQL entity filter is a strict identity boundary, not a general topic
  // filter. Only explicit verified medication identity may narrow the corpus at
  // this stage. Indication, class, specialty, documentation, and other open
  // dimensions remain retrieval/reranking signals so reverse and cross-policy
  // questions cannot be reduced to an empty result by incomplete entity links.
  const medicationEntityIds = strictRetrievalEntityIds(entities);
  const { data, error } = await db.rpc('insurance_v3_hybrid_search', { p_query: lexicalQuery, p_query_embedding: embedding.embedding, p_entity_ids: medicationEntityIds, p_limit: 60 });
  if (error) throw error;
  const units = isolateSearchUnitCandidates((data ?? []) as HybridSearchUnit[], entities, knownEntities);
  return { embedding, units };
}
function vectorInformationQuery(semantic: SemanticInterpretation, entities: V3Entity[], fallback: string, alternatives: string[] = []) {
  return [...new Set([
    semantic.information_need, semantic.requested_information, semantic.semantic_intent,
    ...alternatives, ...(semantic.retrieval_queries ?? []).slice(0, 3),
    ...entities.map((entity) => entity.canonical_name), semantic.indication, semantic.treatment_stage,
  ].map((value) => String(value ?? '').trim()).filter(Boolean))].join('\n') || fallback;
}
function lexicalInformationQuery(question: string, semantic: SemanticInterpretation, entities: V3Entity[], alternatives: string[] = []) {
  return [...new Set([
    question, semantic.information_need, semantic.requested_information, semantic.search_query,
    ...alternatives, ...(semantic.search_phrases ?? []).slice(0, 4), ...(semantic.search_concepts ?? []).slice(0, 8),
    ...entities.map((entity) => entity.canonical_name), semantic.indication, semantic.treatment_stage,
  ].map((value) => String(value ?? '').trim()).filter(Boolean))].join(' ');
}
async function hydrateEvidence(db: DBClient, units: HybridSearchUnit[], judgments: RerankResult['judgments'], entities: V3Entity[], knownEntities: V3Entity[], dimensions: string[], question: string, semantic: SemanticInterpretation) {
  const selectedUnits = judgedUnits(units, judgments);
  const judgmentById = new Map(judgments.map((x) => [x.candidate_id, x]));
  const expandIds = selectedUnits.filter((u) => judgmentById.get(u.search_unit_id)?.expansion_needed || ['table_row', 'table', 'section', 'page'].includes(u.unit_type)).map((u) => u.search_unit_id);
  const parentIds = [...new Set(selectedUnits.filter((u) => u.unit_type === 'table_row' && u.parent_unit_id).map((u) => u.parent_unit_id as string))];
  const [hydratedResult, siblingResult] = await Promise.all([
    db.rpc('insurance_v3_hydrate_search_units', { p_unit_ids: selectedUnits.map((u) => u.search_unit_id), p_expand_unit_ids: expandIds, p_limit: 60 }),
    parentIds.length
      ? db.from('insurance_v3_search_units').select('id,document_id,unit_type,page_from,page_to,sheet_name,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata').eq('active', true).in('parent_unit_id', parentIds).order('sibling_order').limit(80)
      : Promise.resolve({ data: [], error: null }),
  ]);
  const { data, error } = hydratedResult;
  if (error) throw error;
  if (siblingResult.error) throw siblingResult.error;
  const unitById = new Map(selectedUnits.map((unit) => [unit.search_unit_id, unit]));
  const sourceJudgmentBoost = new Map<string, number>();
  const answerBearingSourceIds = new Set<string>();
  for (const unit of selectedUnits) {
    const judgment = judgmentById.get(unit.search_unit_id);
    if (!judgment) continue;
    const boost = (judgment.answer_bearing ? 24 : 0) + judgment.directness_score * 0.12 + judgment.relevance_score * 0.05;
    for (const sourceId of unit.source_chunk_ids) {
      sourceJudgmentBoost.set(sourceId, Math.max(sourceJudgmentBoost.get(sourceId) ?? 0, boost));
      if (judgment.answer_bearing) answerBearingSourceIds.add(sourceId);
    }
  }
  const documentById = new Map(selectedUnits.map((unit) => [unit.document_id, { title: unit.document_title, file: unit.file_name }]));
  const projectedRows = [...new Map([
    ...selectedUnits.filter((unit) => unit.unit_type === 'table_row'),
    ...((siblingResult.data ?? []) as Array<Record<string, unknown>>).map((row) => {
      const document = documentById.get(String(row.document_id));
      return {
        ...row, search_unit_id: String(row.id), document_title: document?.title ?? '', file_name: document?.file ?? '',
        vector_rank: null, fts_rank: null, trigram_rank: null, heading_rank: null, entity_rank: null,
        vector_similarity: null, fts_score: null, trigram_score: null, entity_match_count: 0, hybrid_rrf_score: 0,
      } as HybridSearchUnit;
    }),
  ].map((unit) => [unit.search_unit_id, unit])).values()].map((unit): V3Chunk => ({
    chunk_id: unit.search_unit_id, document_id: unit.document_id, document_title: unit.document_title,
    file_name: unit.file_name, page_from: unit.page_from, page_to: unit.page_to, sheet_name: unit.sheet_name,
    row_from: unit.row_from, row_to: unit.row_to, chunk_index: unit.sibling_order, section_title: unit.section_title,
    chunk_text: typeof unit.metadata.row_text === 'string' ? unit.metadata.row_text : unit.retrieval_text,
    metadata: { ...unit.metadata, source_chunk_ids: unit.source_chunk_ids },
    score: (unitById.has(unit.search_unit_id) ? 12 : 7) + (judgmentById.get(unit.search_unit_id)?.answer_bearing ? 24 : 0),
    fts_rank: 0, trigram_score: 0, matched_entity_count: unit.entity_match_count ?? 0, matched_dimensions: [],
  }));
  const projectedSourceIds = new Set(projectedRows.flatMap((chunk) => Array.isArray(chunk.metadata.source_chunk_ids) ? chunk.metadata.source_chunk_ids.map(String) : []));
  const originalChunks = ((data ?? []) as V3Chunk[]).filter((chunk) => !projectedSourceIds.has(chunk.chunk_id))
    .map((chunk) => ({ ...chunk, score: Number(chunk.score || 0) + (sourceJudgmentBoost.get(chunk.chunk_id) ?? 0) }));
  const scoped = isolateMedicationCandidates([...projectedRows, ...originalChunks], entities, knownEntities);
  const ranked = rerankChunks(scoped, entities, dimensions, semantic.treatment_stage, question, semantic);
  const projectedUnitById = new Map(projectedRows.map((chunk) => {
    const unit = [...selectedUnits, ...((siblingResult.data ?? []) as Array<Record<string, unknown>>).map((row) => {
      const document = documentById.get(String(row.document_id));
      return { ...row, search_unit_id: String(row.id), document_title: document?.title ?? '', file_name: document?.file ?? '', vector_rank: null, fts_rank: null, trigram_rank: null, heading_rank: null, entity_rank: null, vector_similarity: null, fts_score: null, trigram_score: null, entity_match_count: 0, hybrid_rrf_score: 0 } as HybridSearchUnit;
    })].find((candidate) => candidate.search_unit_id === chunk.chunk_id);
    return [chunk.chunk_id, unit] as const;
  }));
  // Structural expansion is part of retrieval, not merely answer rendering.
  // Promote the most relevant expanded rows into the final candidate ranking so
  // a large table can surface the matching logical row instead of only the row
  // that happened to discover its parent.
  const expandedUnits = ranked.map((chunk) => projectedUnitById.get(chunk.chunk_id))
    .filter((unit): unit is HybridSearchUnit => Boolean(unit));
  const selection = selectEvidence(ranked, dimensions, 12, semantic);
  const recallSourceIds = new Set(units.slice(0, 10).flatMap((unit) => unit.source_chunk_ids));
  const recallEvidence = ranked.filter((chunk) => recallSourceIds.has(chunk.chunk_id)
    || (Array.isArray(chunk.metadata.source_chunk_ids) && chunk.metadata.source_chunk_ids.some((id) => recallSourceIds.has(String(id)))));
  // Reranking is mandatory and influences priority, but a partial structured
  // response cannot delete entity-isolated TOP10 evidence. Hydrated recall
  // evidence remains visible to the sufficiency and final grounding stages.
  selection.selected = [...new Map([...selection.selected, ...recallEvidence].map((chunk) => [chunk.chunk_id, chunk])).values()].slice(0, 12);
  const judgedAnswerEvidence = ranked.filter((chunk) => answerBearingSourceIds.has(chunk.chunk_id)
    || judgmentById.get(chunk.chunk_id)?.answer_bearing === true
    || (Array.isArray(chunk.metadata.source_chunk_ids) && chunk.metadata.source_chunk_ids.some((id) => answerBearingSourceIds.has(String(id)))));
  const recallTableRows = recallEvidence.filter((chunk) => chunk.row_from !== null || chunk.metadata.semantic_table_record === true);
  const answerEvidenceSeeds = judgedAnswerEvidence.length > 0
    ? [...judgedAnswerEvidence, ...recallTableRows]
    : [selection.selected[0], ...recallTableRows];
  const answerEvidence = [...new Map(answerEvidenceSeeds.filter(Boolean).map((chunk) => [chunk.chunk_id, chunk])).values()].slice(0, 6);
  return { selection, answerEvidence: answerEvidence.length ? answerEvidence : selection.selected.slice(0, 3), selectedUnits, expandIds, expandedUnits, answerBearingSourceIds };
}
async function legacyEvidence(db: DBClient, query: string, phrases: string[], hints: string[], entities: V3Entity[], knownEntities: V3Entity[], dimensions: string[], question: string, semantic: SemanticInterpretation) {
  const { data, error } = await db.rpc('insurance_v3_search_semantic_v2', { p_query: query, p_search_phrases: phrases, p_entity_ids: entities.map((e) => e.id), p_hints: hints, p_stage: semantic.treatment_stage, p_document_ids: [], p_limit: 50 });
  if (error) throw error;
  const ranked = rerankChunks(isolateMedicationCandidates((data ?? []) as V3Chunk[], entities, knownEntities), entities, dimensions, semantic.treatment_stage, question, semantic);
  return selectEvidence(ranked, dimensions, 10, semantic);
}

type PipelineContext = {
  forceRecovery: boolean;
  feedbackReason: string | null;
  originalAuditId: string | null;
  originalAnswer: string | null;
  originalEvidence: unknown;
  originalCitations: unknown;
  originalSemantic: unknown;
};

const citationFor = (
  chunk: V3Chunk,
  storage: { bucket: string; path: string } | undefined,
) => ({
  document_id: chunk.document_id, document_title: chunk.document_title, file_name: chunk.file_name,
  storage_bucket: storage?.bucket ?? null, storage_path: storage?.path ?? null,
  page_from: chunk.page_from, page_to: chunk.page_to, sheet_name: chunk.sheet_name,
  row_from: chunk.row_from, row_to: chunk.row_to,
  chunk_id: typeof chunk.metadata.source_chunk_id === 'string' ? chunk.metadata.source_chunk_id : chunk.chunk_id,
});

function sourceGroundedText(text: string, used: V3Chunk[]) {
  const sourceLines = [...new Set(used.map((chunk) => chunk.sheet_name
    ? `Source: ${chunk.document_title} — Sheet ${chunk.sheet_name}, rows ${chunk.row_from ?? '?'}-${chunk.row_to ?? '?'}`
    : `Source: ${chunk.document_title} — Page ${chunk.page_from}${chunk.page_to !== chunk.page_from ? `-${chunk.page_to}` : ''}`))];
  return `${text.replace(/\n*Source:\s*[\s\S]*$/i, '').trim()}\n\n${sourceLines.join('\n')}`;
}

async function saveConversation(
  db: DBClient, body: Record<string, unknown>, question: string, answer: string,
  citations: Array<Record<string, unknown>>, semantic: SemanticInterpretation,
  verifiedEntities: V3Entity[], status: string, recoveryDepth: number,
) {
  try {
    let sessionId = typeof body.session_id === 'string' ? body.session_id : null;
    if (!sessionId) {
      const { data, error } = await db.from('insurance_chat_sessions').insert({ branch_name: String(body.branch_name ?? ''), title: question.slice(0, 80) }).select('id').single();
      if (error) throw error;
      sessionId = String(data.id);
    }
    const parsed = { insurance_v3: true, semantic, verified_entity_ids: verifiedEntities.map((entity) => entity.id), recovery_depth: recoveryDepth };
    const { error: userError } = await db.from('insurance_chat_messages').insert({ session_id: sessionId, role: 'user', message: question, parsed_data: parsed });
    if (userError) throw userError;
    const { data, error } = await db.from('insurance_chat_messages').insert({ session_id: sessionId, role: 'assistant', message: answer, citations, parsed_data: { ...parsed, answer_status: status } }).select('id,created_at').single();
    if (error) throw error;
    return { session_id: sessionId, message_id: String(data.id), created_at: data.created_at };
  } catch (error) {
    console.error('insurance_v3_conversation_persistence_error', { message: error instanceof Error ? error.message : 'unknown' });
    return { session_id: typeof body.session_id === 'string' ? body.session_id : null, message_id: crypto.randomUUID(), created_at: new Date().toISOString() };
  }
}

function unitModeFilter(units: HybridSearchUnit[], mode: RecoveryPlan['searches'][number]['mode']) {
  if (mode === 'tables') return units.filter((unit) => unit.unit_type === 'table' || unit.unit_type === 'table_row');
  if (mode === 'headings') return units.filter((unit) => unit.unit_type === 'section' || unit.unit_type === 'page' || unit.unit_type === 'table');
  return units;
}

const jsonRows = (value: unknown) => Array.isArray(value)
  ? value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object')
  : [];

async function recordPositiveFeedback(db: DBClient, userId: string, messageId: string) {
  const { data: assistant, error: messageError } = await db.from('insurance_chat_messages')
    .select('id,message,citations,parsed_data').eq('id', messageId).eq('role', 'assistant').single();
  if (messageError || !assistant) return { invalid: true };
  const { error: feedbackError } = await db.from('insurance_feedback').upsert({
    message_id: messageId, user_id: userId, rating: 1, updated_at: new Date().toISOString(),
  }, { onConflict: 'message_id,user_id' });
  if (feedbackError) throw feedbackError;

  const { data: audit } = await db.from('insurance_answer_audits').select(
    'id,raw_question,structured_query,verified_entities,verified_evidence,answer_status,final_answer,final_citations,recovery_attempt,provider_diagnostics,latency_ms',
  ).eq('message_id', messageId).order('created_at', { ascending: false }).limit(1).maybeSingle();
  const cacheableStatuses = new Set(['grounded', 'grounded_fallback', 'recovery_grounded', 'recovery_fallback', 'validated_cache_hit']);
  const citations = jsonRows(audit?.final_citations).length ? jsonRows(audit.final_citations) : jsonRows(assistant.citations);
  const semantic = audit?.structured_query as SemanticInterpretation | undefined;
  const verifiedEntities = jsonRows(audit?.verified_entities) as V3Entity[];
  const answer = String(audit?.final_answer ?? assistant.message ?? '').trim();
  if (!audit || !semantic || !cacheableStatuses.has(String(audit.answer_status)) || !answer || citations.length === 0 || verifiedEntities.length === 0) {
    return { recorded: true, cache_updated: false, reason: 'answer_not_safely_cacheable' };
  }

  const documentIds = [...new Set(citations.map((citation) => String(citation.document_id ?? '')).filter(Boolean))];
  const evidenceIds = [...new Set([
    ...citations.map((citation) => String(citation.chunk_id ?? '')),
    ...jsonRows(audit.verified_evidence).map((evidence) => String(evidence.id ?? evidence.chunk_id ?? '')),
  ].filter((id) => /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(id)))];
  const { data: documents, error: documentError } = await db.from('insurance_v3_documents')
    .select('id,document_hash,version,updated_at,is_active,storage_bucket,storage_path').in('id', documentIds);
  if (documentError || (documents ?? []).length !== documentIds.length || evidenceIds.length === 0
    || (documents ?? []).some((document: Record<string, unknown>) => document.is_active !== true || !String(document.storage_path ?? '').trim())) {
    return { recorded: true, cache_updated: false, reason: 'source_snapshot_unavailable' };
  }
  const { data: relations, error: relationError } = await db.from('insurance_v3_entity_relations')
    .select('subject_entity_id,relation_type,object_entity_id,verified').eq('verified', true);
  if (relationError) return { recorded: true, cache_updated: false, reason: 'relation_snapshot_unavailable' };
  const signature = await semanticCacheSignature(semantic, verifiedEntities);
  const now = new Date().toISOString();
  const entityIds = verifiedEntities.map((entity) => entity.id);
  const preferredSource = Number(audit.recovery_attempt ?? assistant.parsed_data?.recovery_depth ?? 0) > 0 ? 'deep_review' : 'normal';
  const { data: existingPreferred } = await db.from('insurance_validated_answers')
    .select('id,preferred_source').eq('user_id', userId).eq('semantic_signature', signature).maybeSingle();
  if (!preferredAnswerShouldReplace(existingPreferred?.preferred_source, preferredSource)) {
    return { recorded: true, cache_updated: false, reason: 'deep_review_remains_preferred', preferred_source: 'deep_review' };
  }
  if (preferredSource === 'deep_review') {
    await db.from('insurance_validated_answers').update({
      active: false, invalidated_at: now, invalidation_reason: 'replaced_by_accepted_deep_review', updated_at: now,
    }).eq('user_id', userId).eq('normalized_question', normalize(audit.raw_question)).neq('semantic_signature', signature).eq('active', true);
  }
  const { error: cacheError } = await db.from('insurance_validated_answers').upsert({
    user_id: userId, semantic_signature: signature, normalized_question: normalize(audit.raw_question),
    original_question: audit.raw_question, semantic_interpretation: semantic,
    verified_entity_ids: entityIds, intent_signature: semanticCachePayload(semantic, verifiedEntities),
    answer_text: answer, citations, evidence_ids: evidenceIds,
    document_snapshots: documents, relation_snapshot: relationSnapshot(relations as V3Relation[], entityIds),
    preferred_source: preferredSource, source_message_id: messageId, source_audit_id: audit.id,
    provider_metadata: audit.provider_diagnostics ?? {}, source_latency_ms: audit.latency_ms,
    positive_feedback_at: now, active: true, invalidated_at: null, invalidation_reason: null, updated_at: now,
  }, { onConflict: 'user_id,semantic_signature' });
  if (cacheError) throw cacheError;
  return { recorded: true, cache_updated: true, preferred_source: preferredSource };
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const started = Date.now();
  let db: DBClient | null = null;
  let trace: RequestTrace | null = null;
  let debugRequested = false;
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return respond({ error: 'Authentication required.' }, 401);
    db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
    const { data: auth, error: authError } = await db.auth.getUser(authorization.slice(7));
    if (authError || !auth.user) return respond({ error: 'Authentication required.' }, 401);
    let body: Record<string, unknown>;
    try { body = await request.json() as Record<string, unknown>; }
    catch { return respond({ error: 'A valid JSON request body is required.' }, 400); }
    if (body.debug === true) {
      const { data: canDebug, error: debugAuthError } = await db.rpc('is_insurance_knowledge_admin');
      debugRequested = !debugAuthError && canDebug === true;
    }

    if (typeof body.positive_feedback_message_id === 'string') {
      const result = await recordPositiveFeedback(db, auth.user.id, body.positive_feedback_message_id);
      if (result.invalid) return respond({ error: 'The feedback message is invalid.' }, 400);
      return respond({ feedback_recorded: true, validated_cache_updated: result.cache_updated === true, preferred_source: result.preferred_source ?? null, insurance_v3: true });
    }

    let pipelineContext: PipelineContext = { forceRecovery: false, feedbackReason: null, originalAuditId: null, originalAnswer: null, originalEvidence: null, originalCitations: null, originalSemantic: null };
    let question = String(body.message ?? '').trim();
    if (typeof body.feedback_message_id === 'string') {
      const feedbackMessageId = body.feedback_message_id;
      const { data: assistant, error } = await db.from('insurance_chat_messages').select('id,session_id,message,citations,parsed_data,created_at').eq('id', feedbackMessageId).eq('role', 'assistant').single();
      if (error || !assistant) return respond({ error: 'The feedback message is invalid.' }, 400);
      const { data: priorAudit } = await db.from('insurance_answer_audits').select('id,raw_question,structured_query,verified_evidence,final_citations,recovery_attempt').eq('message_id', feedbackMessageId).order('created_at', { ascending: false }).limit(1).maybeSingle();
      if (Number(priorAudit?.recovery_attempt ?? assistant.parsed_data?.recovery_depth ?? 0) >= 1) {
        await db.from('insurance_feedback').upsert({ message_id: feedbackMessageId, user_id: auth.user.id, rating: -1, second_rating: -1, reason: String(body.feedback_reason ?? 'other'), updated_at: new Date().toISOString() }, { onConflict: 'message_id,user_id' });
        return respond({ feedback_recorded: true, recovery_exhausted: true, insurance_v3: true });
      }
      if (priorAudit?.raw_question) question = String(priorAudit.raw_question);
      else {
        const { data: userMessage } = await db.from('insurance_chat_messages').select('message').eq('session_id', assistant.session_id).eq('role', 'user').lte('created_at', assistant.created_at).order('created_at', { ascending: false }).limit(1).maybeSingle();
        question = String(userMessage?.message ?? '').trim();
      }
      if (!question) return respond({ error: 'The original question could not be resolved.' }, 400);
      const feedbackReason = ['incorrect', 'incomplete', 'misunderstood', 'wrong_source', 'other'].includes(String(body.feedback_reason)) ? String(body.feedback_reason) : 'other';
      await db.from('insurance_feedback').upsert({ message_id: feedbackMessageId, user_id: auth.user.id, rating: -1, reason: feedbackReason, updated_at: new Date().toISOString() }, { onConflict: 'message_id,user_id' });
      pipelineContext = {
        forceRecovery: true, feedbackReason, originalAuditId: priorAudit?.id ? String(priorAudit.id) : null,
        originalAnswer: String(assistant.message ?? ''), originalEvidence: priorAudit?.verified_evidence ?? assistant.citations ?? [],
        originalCitations: priorAudit?.final_citations ?? assistant.citations ?? [], originalSemantic: priorAudit?.structured_query ?? assistant.parsed_data?.semantic ?? null,
      };
      body = { ...body, session_id: assistant.session_id };
    }
    if (!question || question.length > 1200) return respond({ error: 'A question of at most 1200 characters is required.' }, 400);
    trace = newRequestTrace(auth.user.id, question);
    trace.recovery_of_audit_id = pipelineContext.originalAuditId;
    trace.recovery_attempt = pipelineContext.forceRecovery ? 1 : 0;
    trace.recovery.feedback_reason = pipelineContext.feedbackReason;

    const entityStarted = Date.now();
    const [{ data: entities, error: entityError }, { data: aliases, error: aliasError }, { data: relations, error: relationError }] = await Promise.all([
      db.from('insurance_v3_entities').select('id,canonical_name,normalized_name,entity_type').eq('active', true),
      db.from('insurance_v3_aliases').select('entity_id,alias,normalized_alias,verified').eq('verified', true),
      db.from('insurance_v3_entity_relations').select('subject_entity_id,relation_type,object_entity_id,verified').eq('verified', true),
    ]);
    if (entityError || aliasError || relationError) throw entityError ?? aliasError ?? relationError;
    trace.latency.entity_resolution_ms = Date.now() - entityStarted;
    const allEntities = entities as V3Entity[];
    const allAliases = aliases as V3Alias[];
    const aliasMap = new Map<string, string[]>();
    for (const alias of allAliases) aliasMap.set(alias.entity_id, [...(aliasMap.get(alias.entity_id) ?? []), alias.alias].slice(0, 8));
    const normalizedQuestion = normalize(question);
    const questionTokens = new Set(normalizedQuestion.split(' ').filter((token) => token.length >= 3));
    const aliasesRelevantToQuestion = (entity: V3Entity) => (aliasMap.get(entity.id) ?? []).filter((alias) => {
      const value = normalize(alias);
      return value.length >= 3 && (` ${normalizedQuestion} `.includes(` ${value} `)
        || value.split(' ').some((token) => token.length >= 3 && questionTokens.has(token)));
    }).slice(0, 8);
    // Every canonical entity remains visible to the mandatory semantic model,
    // while verbose alias lists are attached only when they overlap the user
    // text. This is entity-catalog compression, not intent routing.
    const verifiedEntityCatalog = allEntities.map((entity) => ({ canonical_name: entity.canonical_name, entity_type: entity.entity_type, aliases: aliasesRelevantToQuestion(entity) }));

    const semanticResult = await interpretQuestion(question, verifiedEntityCatalog);
    trace.latency.semantic_ms = semanticResult.latency_ms;
    let verifiedEntities = resolveVerifiedEntities(question, semanticResult.semantic, allEntities, allAliases, relations as V3Relation[]);
    const aligned = alignSemanticMedication(semanticResult.semantic, verifiedEntities);
    const grounded = groundEntityOnlySemantic(question, aligned, verifiedEntities, allAliases);
    const semanticRequestedRecovery = grounded.route === 'clarification_required';
    const dimensions = requestedDimensions(question, grounded);
    const semantic = enforceRouteSafety(grounded, verifiedEntities, dimensions);
    trace.semantic = semantic; trace.verified_entities = verifiedEntities;

    if (!pipelineContext.forceRecovery && semantic.route !== 'out_of_scope' && verifiedEntities.length > 0) {
      const cacheStarted = Date.now();
      const signature = await semanticCacheSignature(semantic, verifiedEntities);
      let { data: cached, error: cacheLookupError } = await db.from('insurance_validated_answers')
        .select('*').eq('user_id', auth.user.id).eq('semantic_signature', signature).eq('active', true).maybeSingle();
      let matchKind = 'semantic_signature';
      if (!cached && !cacheLookupError) {
        const exact = await db.from('insurance_validated_answers').select('*')
          .eq('user_id', auth.user.id).eq('normalized_question', normalize(question)).eq('active', true)
          .order('positive_feedback_at', { ascending: false }).limit(5);
        cacheLookupError = exact.error;
        const currentIds = verifiedEntities.map((entity) => entity.id).sort();
        cached = (exact.data ?? []).find((row: Record<string, unknown>) => {
          const cachedIds = Array.isArray(row.verified_entity_ids) ? row.verified_entity_ids.map(String).sort() : [];
          return JSON.stringify(cachedIds) === JSON.stringify(currentIds);
        }) ?? null;
        matchKind = 'exact_normalized_question';
      }
      const cacheDiagnostics: Record<string, unknown> = {
        validated_cache_lookup: true, cache_hit: false, cache_miss: true,
        invalidation_reason: null, preferred_answer_source: cached?.preferred_source ?? null,
        source_validity_check: cached ? 'pending' : 'not_applicable', semantic_match_confidence: cached ? (matchKind === 'exact_normalized_question' || normalize(question) === cached.normalized_question ? 1 : 0.96) : null,
        match_kind: cached ? matchKind : null,
        latency_saved_ms: 0, ai_calls_avoided: 0,
      };
      if (cacheLookupError) cacheDiagnostics.invalidation_reason = 'cache_lookup_error';
      if (cached) {
        const validity = await validatePreferredAnswerSources(db, cached as Record<string, unknown>);
        cacheDiagnostics.source_validity_check = validity.valid ? 'valid' : 'invalid';
        cacheDiagnostics.invalidation_reason = validity.reason;
        if (!validity.valid) {
          await db.from('insurance_validated_answers').update({ active: false, invalidated_at: new Date().toISOString(), invalidation_reason: validity.reason, updated_at: new Date().toISOString() }).eq('id', cached.id);
        } else {
          const answer = String(cached.answer_text);
          const citations = jsonRows(cached.citations);
          const saved = await saveConversation(db, body, question, answer, citations, semantic, verifiedEntities, 'validated_cache_hit', 0);
          cacheDiagnostics.cache_hit = true; cacheDiagnostics.cache_miss = false;
          cacheDiagnostics.ai_calls_avoided = 2;
          cacheDiagnostics.latency_saved_ms = Math.max(0, Number(cached.source_latency_ms ?? 0) - (Date.now() - started));
          trace.session_id = saved.session_id; trace.message_id = saved.message_id; trace.final_status = 'validated_cache_hit';
          trace.final_answer = answer; trace.citations = citations; trace.final_reason = 'valid_preferred_grounded_answer'; trace.answer_generator = 'validated_cache';
          trace.latency.cache_ms = Date.now() - cacheStarted; trace.latency.total_ms = Date.now() - started;
          trace.providers = { ...aiDiagnostics(semanticResult, [], null), validated_cache: cacheDiagnostics }; trace.token_usage = trace.providers;
          await persistRequestTrace(db, trace);
          return respond({ ...saved, answer, citations, answer_status: 'validated_cache_hit', answer_generator: 'validated_cache', evidence_checked: true, validated_cache: true, insurance_v3: true,
            debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, verified_entities: verifiedEntities, validated_cache: cacheDiagnostics, ai: trace.providers } : undefined });
        }
      }
      trace.providers.validated_cache = cacheDiagnostics;
      trace.latency.cache_ms = Date.now() - cacheStarted;
    }
    if (!pipelineContext.forceRecovery && semantic.route === 'out_of_scope') {
      const answer = 'This question is outside the approved insurance-policy knowledge base.';
      trace.final_status = semantic.route; trace.final_answer = answer; trace.final_reason = 'semantic_route'; trace.latency.total_ms = Date.now() - started;
      trace.providers = aiDiagnostics(semanticResult, [], null); trace.token_usage = trace.providers;
      const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, semantic.route, 0);
      trace.session_id = saved.session_id; trace.message_id = saved.message_id;
      await persistRequestTrace(db, trace);
      return respond({ ...saved, answer, citations: [], answer_status: semantic.route, insurance_v3: true, debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, verified_entities: verifiedEntities, ai: trace.providers } : undefined });
    }

    let plan = buildRetrievalPlan(question, semantic, verifiedEntities, dimensions);
    trace.retrieval_plan = plan;
    let units: HybridSearchUnit[] = [];
    let selection: ReturnType<typeof selectEvidence> = { selected: [], missingDimensions: dimensions, missingSignals: [], requestedCoverage: 0, sufficient: false };
    let answerEvidence: ReturnType<typeof rerankChunks> = [];
    let evidenceJudgments: EvidenceJudgment[] = [];
    let sufficiency: EvidenceSufficiency | null = null;
    let answerBearingSourceIds = new Set<string>();
    let selectedUnits: HybridSearchUnit[] = [];
    let expandIds: string[] = [];
    let strongEvidence = false;
    const aiCalls: AIMetadata[] = [];
    const embeddingRuns: Awaited<ReturnType<typeof embedRetrievalQuery>>[] = [];
    const retrievalStarted = Date.now();

    if (!pipelineContext.forceRecovery) {
      if (retrievalMode === 'lexical') {
        selection = await legacyEvidence(db, plan.query, plan.phrases, plan.hints, verifiedEntities, allEntities, dimensions, question, semantic);
        answerEvidence = selection.selected.slice(0, 4);
        strongEvidence = selection.selected.length > 0 && selection.sufficient && selection.missingDimensions.length === 0;
      } else {
        const retrieved = await retrieveHybrid(db, lexicalInformationQuery(question, semantic, verifiedEntities), vectorInformationQuery(semantic, verifiedEntities, plan.query), verifiedEntities, allEntities);
        embeddingRuns.push(retrieved.embedding); units = retrieved.units;
        try {
          const rerank = await rerankAndJudgeEvidence(question, semantic, verifiedEntities, units.slice(0, 18));
          aiCalls.push(rerank); evidenceJudgments = rerank.judgments; sufficiency = rerank.sufficiency; units = rerankUnits(units, evidenceJudgments);
        } catch (error) {
          trace.fallback_used = 'deterministic_rerank';
          trace.providers.reranker_error = error instanceof Error ? error.name : 'unknown';
        }
        const hydrated = await hydrateEvidence(db, units, evidenceJudgments, verifiedEntities, allEntities, dimensions, question, semantic);
        selection = hydrated.selection; answerEvidence = hydrated.answerEvidence; selectedUnits = hydrated.selectedUnits; expandIds = hydrated.expandIds; answerBearingSourceIds = hydrated.answerBearingSourceIds;
        units = mergeUnits(hydrated.expandedUnits, units);
        strongEvidence = hasStrongVerifiedEvidence(selection, answerEvidence, answerBearingSourceIds);
        if (!strongEvidence && selection.selected.length > 0) {
          try {
            const judged = await judgeHydratedEvidenceSufficiency(question, semantic, verifiedEntities, selection.selected);
            aiCalls.push(judged); sufficiency = judged.sufficiency;
            strongEvidence = sufficiency.status === 'complete';
          } catch (error) {
            trace.fallback_used = trace.fallback_used ?? 'deterministic_sufficiency';
            trace.providers.sufficiency_error = error instanceof Error ? error.name : 'unknown';
          }
        }
      }
    }
    trace.latency.retrieval_ms = Date.now() - retrievalStarted;

    if (pipelineContext.forceRecovery || semanticRequestedRecovery || !strongEvidence) {
      trace.recovery.activated = true;
      trace.recovery.reason = pipelineContext.forceRecovery ? 'negative_feedback' : semanticRequestedRecovery ? 'semantic_ambiguity_or_unexpected_structure' : selection.selected.length ? 'normal_partial_or_rejected' : 'normal_no_evidence';
      const recoveryStarted = Date.now();
      const normalStrongEvidence = strongEvidence;
      if (semanticRequestedRecovery) strongEvidence = false;
      for (let iteration = 1; iteration <= 2 && !strongEvidence; iteration++) {
        let recoveryPlan: Awaited<ReturnType<typeof planRecoverySearch>>;
        try {
          recoveryPlan = await planRecoverySearch(question, semantic, verifiedEntities, {
            normal_failure_reason: trace.recovery.reason,
            first_retrieval_queries: plan,
            retrieved_candidates: units.slice(0, 18).map((unit) => ({ id: unit.search_unit_id, document: unit.document_title, type: unit.unit_type, heading: unit.section_title ?? unit.table_title, page: unit.page_from, text: unit.retrieval_text.slice(0, 500) })),
            selected_evidence: selection.selected.slice(0, 10).map((chunk) => ({ document: chunk.document_title, page: chunk.page_from, text: chunk.chunk_text.slice(0, 700) })),
            prior_recovery_iterations: trace.recovery.iterations,
            feedback_reason: pipelineContext.feedbackReason,
            original_answer: pipelineContext.originalAnswer,
            original_evidence: pipelineContext.originalEvidence,
          });
          aiCalls.push(recoveryPlan);
        } catch (error) {
          trace.providers.recovery_planner_error = error instanceof Error ? error.name : 'unknown';
          break;
        }
        if (pipelineContext.forceRecovery && (
          recoveryPlan.decision === 'use_existing'
          || (recoveryPlan.decision === 'clarification' && !(semanticRequestedRecovery && verifiedEntities.length === 0))
        )) {
          const independentQueries = [...new Set([
            ...(semantic.retrieval_queries ?? []), semantic.search_query,
            semantic.information_need, semantic.requested_information,
          ].map((value) => String(value ?? '').trim()).filter(Boolean))].slice(0, 3);
          recoveryPlan.decision = 'search';
          recoveryPlan.searches = independentQueries.map((query, index) => ({
            query, mode: index === 1 ? 'tables' : index === 2 ? 'headings' : 'all',
          }));
          recoveryPlan.diagnosis = `${recoveryPlan.diagnosis} Independent verification required after negative feedback.`.trim();
        }
        const iterationTrace: Record<string, unknown> = { iteration, decision: recoveryPlan.decision, diagnosis: recoveryPlan.diagnosis, information_need: recoveryPlan.information_need, searches: recoveryPlan.searches, candidate_count_before: units.length };
        const unresolvedSemanticAmbiguity = semanticRequestedRecovery
          && verifiedEntities.length === 0
          && !(recoveryPlan.decision === 'use_existing' && normalStrongEvidence && answerEvidence.length > 0);
        if (unresolvedSemanticAmbiguity) {
          const answer = recoveryPlan.clarification_question ?? 'Please clarify the medicine, policy, or relationship you want to check.';
          trace.recovery.iterations.push({ ...iterationTrace, outcome: 'clarification', safety_rule: 'ai_semantic_ambiguity_without_verified_identity_or_direct_evidence' });
          trace.final_status = 'clarification_required'; trace.final_answer = answer; trace.final_reason = 'recovery_ambiguity'; trace.latency.recovery_ms = Date.now() - recoveryStarted; trace.latency.total_ms = Date.now() - started;
          trace.candidates = units; trace.evidence = selection.selected; trace.sufficiency = sufficiency as unknown as Record<string, unknown> | null; trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, null) }; trace.token_usage = trace.providers;
          const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, 'clarification_required', pipelineContext.forceRecovery ? 1 : 0);
          trace.session_id = saved.session_id; trace.message_id = saved.message_id;
          await persistRequestTrace(db, trace);
          return respond({ ...saved, answer, citations: [], answer_status: 'clarification_required', insurance_v3: true, recovery_used: true, debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, verified_entities: verifiedEntities, retrieval_plan: plan, candidates: units.slice(0, 24), selected_evidence: selection.selected, recovery: trace.recovery, ai: trace.providers } : undefined });
        }
        if (recoveryPlan.decision === 'use_existing' && normalStrongEvidence && answerEvidence.length > 0) {
          strongEvidence = true;
          trace.recovery.iterations.push({ ...iterationTrace, outcome: 'verified_existing_evidence' });
          break;
        }
        if (recoveryPlan.decision === 'clarification') {
          trace.recovery.iterations.push({ ...iterationTrace, outcome: 'clarification' });
          const answer = recoveryPlan.clarification_question ?? 'Please clarify the entity or relationship you want to check.';
          trace.final_status = 'clarification_required'; trace.final_answer = answer; trace.final_reason = 'recovery_ambiguity'; trace.latency.recovery_ms = Date.now() - recoveryStarted; trace.latency.total_ms = Date.now() - started;
          trace.candidates = units; trace.evidence = selection.selected; trace.sufficiency = sufficiency as unknown as Record<string, unknown> | null; trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, null) }; trace.token_usage = trace.providers;
          const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, 'clarification_required', pipelineContext.forceRecovery ? 1 : 0);
          trace.session_id = saved.session_id; trace.message_id = saved.message_id;
          await persistRequestTrace(db, trace);
          return respond({ ...saved, answer, citations: [], answer_status: 'clarification_required', insurance_v3: true, recovery_used: true, debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, recovery: trace.recovery, ai: trace.providers } : undefined });
        }
        if (recoveryPlan.decision === 'not_found' || recoveryPlan.searches.length === 0) {
          trace.recovery.iterations.push({ ...iterationTrace, outcome: 'no_search' });
          break;
        }
        let newUnits: HybridSearchUnit[] = [];
        for (const search of recoveryPlan.searches.slice(0, 3)) {
          try {
            const anchoredEntities = verifiedEntities.some((entity) => entity.entity_type.startsWith('medication_')) ? verifiedEntities : [];
            const retrieved = await retrieveHybrid(db, search.query, search.query, anchoredEntities, allEntities);
            embeddingRuns.push(retrieved.embedding);
            newUnits = mergeUnits(newUnits, unitModeFilter(retrieved.units, search.mode));
          } catch (error) {
            const searchErrors = Array.isArray(iterationTrace.search_errors) ? iterationTrace.search_errors as unknown[] : [];
            searchErrors.push(error instanceof Error ? error.name : 'unknown');
            iterationTrace.search_errors = searchErrors;
          }
        }
        units = mergeUnits(units, newUnits);
        let recoveryJudgments: EvidenceJudgment[] = [];
        try {
          const rerank = await rerankAndJudgeEvidence(question, semantic, verifiedEntities, units.slice(0, 18));
          aiCalls.push(rerank); recoveryJudgments = rerank.judgments; sufficiency = rerank.sufficiency; units = rerankUnits(units, recoveryJudgments);
        } catch (error) {
          trace.fallback_used = trace.fallback_used ?? 'deterministic_recovery_rerank';
          trace.providers.recovery_reranker_error = error instanceof Error ? error.name : 'unknown';
        }
        evidenceJudgments = recoveryJudgments.length ? recoveryJudgments : evidenceJudgments;
        if (units.length > 0) {
          const hydrated = await hydrateEvidence(db, units, evidenceJudgments, verifiedEntities, allEntities, dimensions, question, semantic);
          selection = hydrated.selection; answerEvidence = hydrated.answerEvidence; selectedUnits = hydrated.selectedUnits; expandIds = hydrated.expandIds; answerBearingSourceIds = hydrated.answerBearingSourceIds;
          units = mergeUnits(hydrated.expandedUnits, units);
          strongEvidence = hasStrongVerifiedEvidence(selection, answerEvidence, answerBearingSourceIds) || sufficiency?.status === 'complete';
          if (!strongEvidence && selection.selected.length > 0) {
            try {
              const judged = await judgeHydratedEvidenceSufficiency(question, semantic, verifiedEntities, selection.selected);
              aiCalls.push(judged); sufficiency = judged.sufficiency; strongEvidence = sufficiency.status === 'complete';
            } catch (error) { trace.providers.recovery_sufficiency_error = error instanceof Error ? error.name : 'unknown'; }
          }
        }
        trace.recovery.iterations.push({ ...iterationTrace, new_candidate_count: newUnits.length, selected_evidence_count: selection.selected.length, outcome: strongEvidence ? 'answer_bearing_evidence' : 'insufficient' });
      }
      trace.latency.recovery_ms = Date.now() - recoveryStarted;
    }

    trace.candidates = units; trace.reranked = evidenceJudgments; trace.evidence = selection.selected; trace.sufficiency = sufficiency as unknown as Record<string, unknown> | null;
    trace.rejected = units.filter((unit) => !selectedUnits.some((selected) => selected.search_unit_id === unit.search_unit_id)).slice(0, 20);
    if (!strongEvidence || answerEvidence.length === 0) {
      const answer = 'The approved documents do not establish the requested information.';
      trace.final_status = 'insufficient_evidence'; trace.final_answer = answer; trace.final_reason = 'normal_and_bounded_recovery_exhausted'; trace.latency.total_ms = Date.now() - started;
      trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, null) }; trace.token_usage = trace.providers;
      const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, 'insufficient_evidence', pipelineContext.forceRecovery ? 1 : 0);
      trace.session_id = saved.session_id; trace.message_id = saved.message_id;
      const auditId = await persistRequestTrace(db, trace);
      if (pipelineContext.forceRecovery && auditId) await db.from('insurance_learning_queue').insert({ audit_id: auditId, reason: 'negative_feedback', priority: 3, proposed_change: { request_id: trace.request_id, feedback_reason: pipelineContext.feedbackReason, recovery_exhausted: true } });
      return respond({ ...saved, answer, citations: [], answer_status: 'insufficient_evidence', insurance_v3: true, recovery_used: trace.recovery.activated, debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, verified_entities: verifiedEntities, retrieval_plan: plan, candidates: units.slice(0, 24), selected_evidence: selection.selected, sufficiency, recovery: trace.recovery, ai: trace.providers, processing_ms: Date.now() - started } : undefined });
    }

    const deterministicEvaluations = evaluateOrThresholdTimeWindows(semantic, answerEvidence);
    const deterministicAnswer = renderDeterministicCriterionAnswer(question, semantic, deterministicEvaluations);
    let answerResult: { answer: string; used_evidence_ids: string[] } & AIMetadata;
    let answerGenerator = deterministicAnswer ? 'deterministic_criteria' : 'grounded_ai';
    if (pipelineContext.feedbackReason === 'incomplete') {
      answerGenerator = 'incomplete_grounded_ai';
      try {
        answerResult = await answerIncompleteRecovery(
          question, semantic, answerEvidence,
          {
            original_question: question, original_semantic: pipelineContext.originalSemantic,
            original_answer: pipelineContext.originalAnswer ?? '', original_citations: pipelineContext.originalCitations,
            original_evidence: pipelineContext.originalEvidence,
          },
          deterministicEvaluations,
          sufficiency ?? { status: 'complete', answered_information: [], missing_information: [], reason: 'verified answer-bearing evidence' },
        );
      } catch (error) {
        answerResult = {
          answer: incompleteExtractiveFallback(pipelineContext.originalAnswer ?? '', pipelineContext.originalEvidence, answerEvidence),
          used_evidence_ids: answerEvidence.slice(0, 3).map((_, index) => `E${index + 1}`),
          usage: null, latency_ms: 0, provider: semanticResult.provider, model: semanticResult.model,
        };
        answerGenerator = 'incomplete_extractive_guard_fallback'; trace.fallback_used = 'incomplete_grounded_extractive_answer';
        trace.providers.incomplete_answer_error = error instanceof Error ? error.name : 'unknown';
      }
    } else if (deterministicAnswer) answerResult = { answer: deterministicAnswer, used_evidence_ids: ['E1'], usage: null, latency_ms: 0, provider: semanticResult.provider, model: semanticResult.model };
    else {
      try { answerResult = await answerFromEvidence(question, semantic, answerEvidence, deterministicEvaluations, sufficiency ?? { status: 'complete', answered_information: [], missing_information: [], reason: 'verified answer-bearing evidence' }); }
      catch (error) {
        const fallback = groundedExtractiveAnswer(question, semantic, answerEvidence);
        answerResult = { ...fallback, usage: null, latency_ms: 0, provider: semanticResult.provider, model: semanticResult.model };
        answerGenerator = 'grounded_extractive_fallback'; trace.fallback_used = 'grounded_extractive_answer'; trace.providers.answer_error = error instanceof Error ? error.name : 'unknown';
      }
    }
    const used = evidenceForAnswer(answerEvidence, answerResult.used_evidence_ids, dimensions);
    const safeUsed = used.length ? used : answerEvidence.slice(0, 2);
    const sourceDocumentIds = [...new Set(safeUsed.map((chunk) => chunk.document_id))];
    const { data: sourceDocuments, error: sourceDocumentsError } = await db
      .from('insurance_v3_documents')
      .select('id,storage_bucket,storage_path')
      .in('id', sourceDocumentIds);
    if (sourceDocumentsError) {
      console.error('insurance_v3_citation_storage_lookup_error', {
        message: sourceDocumentsError.message,
      });
    }
    const storageByDocumentId = new Map<string, { bucket: string; path: string }>(
      ((sourceDocuments ?? []) as Array<Record<string, unknown>>).map((document) => [
        String(document.id),
        {
          bucket: String(document.storage_bucket ?? 'insurance-documents'),
          path: String(document.storage_path ?? ''),
        },
      ]),
    );
    const citations = safeUsed.map((chunk) =>
      citationFor(chunk, storageByDocumentId.get(chunk.document_id)),
    );
    const answer = sourceGroundedText(answerResult.answer, safeUsed);
    const status = trace.recovery.activated ? (answerGenerator.includes('fallback') ? 'recovery_fallback' : 'recovery_grounded') : (answerGenerator === 'grounded_extractive_fallback' ? 'grounded_fallback' : 'grounded');
    const saved = await saveConversation(db, body, question, answer, citations, semantic, verifiedEntities, status, pipelineContext.forceRecovery ? 1 : 0);
    trace.session_id = saved.session_id; trace.message_id = saved.message_id; trace.final_status = status; trace.final_answer = answer; trace.citations = citations; trace.final_reason = 'verified_answer_bearing_evidence'; trace.answer_generator = answerGenerator; trace.latency.answer_ms = answerResult.latency_ms; trace.latency.total_ms = Date.now() - started;
    trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, (deterministicAnswer && pipelineContext.feedbackReason !== 'incomplete') || answerGenerator.includes('fallback') ? null : answerResult) }; trace.token_usage = trace.providers;
    const auditId = await persistRequestTrace(db, trace);
    if (pipelineContext.forceRecovery && auditId) await db.from('insurance_learning_queue').insert({ audit_id: auditId, reason: 'negative_feedback', priority: 3, proposed_change: { request_id: trace.request_id, feedback_reason: pipelineContext.feedbackReason, recovery_answer_status: status, recovery_searches: trace.recovery.iterations } });
    return respond({ ...saved, answer, citations, confidence: null, answer_status: status, answer_generator: answerGenerator, evidence_checked: true, insurance_v3: true, recovery_used: trace.recovery.activated,
      debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, verified_entities: verifiedEntities, retrieval_mode: retrievalMode, retrieval_plan: plan, retrieval_channels: units.slice(0, 24), selected_units: selectedUnits, evidence_judgments: evidenceJudgments, expansion_unit_ids: expandIds, evidence_sufficiency: sufficiency, recovery: trace.recovery, deterministic_criteria_evaluations: deterministicEvaluations, final_evidence_ids: answerEvidence.map((chunk) => chunk.chunk_id), retrieved_chunks: selection.selected, embedding: embeddingRuns, fallback_used: trace.fallback_used, ai: trace.providers, model: AI_MODEL, processing_ms: Date.now() - started } : undefined });
  } catch (error) {
    const temporary = error instanceof AIProvidersTemporarilyUnavailableError || error instanceof AIProviderError;
    const answer = temporary ? 'The insurance AI service is temporarily unavailable. Please try again shortly.' : 'The insurance service could not safely complete this request right now. Please try again.';
    console.error('insurance_v3_controlled_failure', { request_id: trace?.request_id, type: error instanceof Error ? error.name : 'unknown', temporary });
    if (trace && db) {
      trace.final_status = temporary ? 'temporarily_unavailable' : 'internal_error'; trace.final_answer = answer; trace.final_reason = error instanceof Error ? error.name : 'unknown'; trace.http_status = 200; trace.latency.total_ms = Date.now() - started;
      await persistRequestTrace(db, trace);
    }
    return respond({ answer, citations: [], answer_status: temporary ? 'temporarily_unavailable' : 'internal_error', insurance_v3: true, debug: debugRequested ? { request_id: trace?.request_id, diagnostic_code: error instanceof Error ? error.name : 'unknown' } : undefined });
  }
});
