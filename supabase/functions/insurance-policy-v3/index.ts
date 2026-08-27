import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { AI_MODEL, answerFromEvidence, interpretQuestion, judgeHydratedEvidenceSufficiency, reformulateRetrievalPlan, rerankAndJudgeEvidence } from './ai.ts';
import { AIProviderError, AIProvidersTemporarilyUnavailableError, type AIProviderName } from './ai_provider.ts';
import { alignSemanticMedication, evaluateOrThresholdTimeWindows, renderDeterministicCriterionAnswer } from './criteria.ts';
import { embedRetrievalQuery } from './embedding.ts';
import {
  buildRetrievalPlan, chunkAnswersDimension, enforceRouteSafety, evidenceForAnswer, isolateMedicationCandidates,
  isolateSearchUnitCandidates, requestedDimensions, rerankChunks, resolveVerifiedEntities, selectEvidence,
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
  const { data, error } = await db.rpc('insurance_v3_hybrid_search', { p_query: lexicalQuery, p_query_embedding: embedding.embedding, p_entity_ids: entities.map((e) => e.id), p_limit: 60 });
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
  return { selection, answerEvidence: answerEvidence.length ? answerEvidence : selection.selected.slice(0, 3), selectedUnits, expandIds, expandedUnits };
}
async function legacyEvidence(db: DBClient, query: string, phrases: string[], hints: string[], entities: V3Entity[], knownEntities: V3Entity[], dimensions: string[], question: string, semantic: SemanticInterpretation) {
  const { data, error } = await db.rpc('insurance_v3_search_semantic_v2', { p_query: query, p_search_phrases: phrases, p_entity_ids: entities.map((e) => e.id), p_hints: hints, p_stage: semantic.treatment_stage, p_document_ids: [], p_limit: 50 });
  if (error) throw error;
  const ranked = rerankChunks(isolateMedicationCandidates((data ?? []) as V3Chunk[], entities, knownEntities), entities, dimensions, semantic.treatment_stage, question, semantic);
  return selectEvidence(ranked, dimensions, 10, semantic);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const started = Date.now();
  let debugRequested = false;
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return respond({ error: 'Authentication required.' }, 401);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
    const { data: auth, error: authError } = await db.auth.getUser(authorization.slice(7));
    if (authError || !auth.user) return respond({ error: 'Authentication required.' }, 401);
    const body = await request.json() as Record<string, unknown>;
    debugRequested = body.debug === true;
    const question = String(body.message ?? '').trim();
    if (!question || question.length > 1200) return respond({ error: 'A question of at most 1200 characters is required.' }, 400);

    const [{ data: entities, error: entityError }, { data: aliases, error: aliasError }, { data: relations, error: relationError }] = await Promise.all([
      db.from('insurance_v3_entities').select('id,canonical_name,normalized_name,entity_type').eq('active', true),
      db.from('insurance_v3_aliases').select('entity_id,alias,normalized_alias,verified').eq('verified', true),
      db.from('insurance_v3_entity_relations').select('subject_entity_id,relation_type,object_entity_id,verified').eq('verified', true),
    ]);
    if (entityError || aliasError || relationError) throw entityError ?? aliasError ?? relationError;
    const aliasMap = new Map<string, string[]>();
    for (const alias of aliases as V3Alias[]) aliasMap.set(alias.entity_id, [...(aliasMap.get(alias.entity_id) ?? []), alias.alias].slice(0, 8));
    const verifiedEntityCatalog = (entities as V3Entity[])
      .filter((entity) => entity.entity_type.startsWith('medication_') || entity.entity_type === 'drug_class' || entity.entity_type === 'indication')
      .map((entity) => ({ canonical_name: entity.canonical_name, entity_type: entity.entity_type, aliases: aliasMap.get(entity.id) ?? [] }));
    const semanticResult = await interpretQuestion(question, verifiedEntityCatalog);
    const verifiedEntities = resolveVerifiedEntities(question, semanticResult.semantic, entities as V3Entity[], aliases as V3Alias[], relations as V3Relation[]);
    const aligned = alignSemanticMedication(semanticResult.semantic, verifiedEntities);
    const dimensions = requestedDimensions(question, aligned);
    const semantic = enforceRouteSafety(aligned, verifiedEntities, dimensions);
    if (semantic.route === 'out_of_scope' || semantic.route === 'clarification_required') {
      return respond({ answer: semantic.route === 'out_of_scope' ? 'This question is outside the approved insurance-policy knowledge base.' : 'Please clarify the medication or policy criterion you want to check.', citations: [], answer_status: semantic.route, insurance_v3: true, debug: body.debug === true ? { semantic_interpretation: semantic, ai: aiDiagnostics(semanticResult, [], null) } : undefined });
    }

    let plan = buildRetrievalPlan(question, semantic, verifiedEntities, dimensions);
    let selection: ReturnType<typeof selectEvidence>;
    let answerEvidence: ReturnType<typeof rerankChunks> = [];
    let units: HybridSearchUnit[] = [], selectedUnits: HybridSearchUnit[] = [], expandIds: string[] = [];
    let sufficiency: RerankResult['sufficiency'] | null = null;
    let evidenceJudgments: RerankResult['judgments'] = [];
    let reformulation: Awaited<ReturnType<typeof reformulateRetrievalPlan>> | null = null;
    let sufficiencyConfirmationUsed = false;
    const rerankCalls: AIMetadata[] = [];
    const embeddingRuns: Awaited<ReturnType<typeof embedRetrievalQuery>>[] = [];

    if (retrievalMode === 'lexical') {
      selection = await legacyEvidence(db, plan.query, plan.phrases, plan.hints, verifiedEntities, entities as V3Entity[], dimensions, question, semantic);
      answerEvidence = selection.selected.slice(0, 3);
      if (!selection.sufficient) {
        reformulation = await reformulateRetrievalPlan(question, semantic, [...selection.missingSignals, ...selection.missingDimensions], selection.selected.map((c) => `${c.document_title}: ${c.section_title ?? ''}`));
        plan = buildRetrievalPlan(question, semantic, verifiedEntities, dimensions, reformulation);
        selection = await legacyEvidence(db, plan.query, plan.phrases, plan.hints, verifiedEntities, entities as V3Entity[], dimensions, question, semantic);
        answerEvidence = selection.selected.slice(0, 3);
      }
    } else {
      let retrieved = await retrieveHybrid(db, lexicalInformationQuery(question, semantic, verifiedEntities), vectorInformationQuery(semantic, verifiedEntities, plan.query), verifiedEntities, entities as V3Entity[]);
      let rerank = await rerankAndJudgeEvidence(question, semantic, verifiedEntities, retrieved.units.slice(0, 18));
      embeddingRuns.push(retrieved.embedding); rerankCalls.push(rerank); units = rerankUnits(retrieved.units, rerank.judgments); sufficiency = rerank.sufficiency; evidenceJudgments = rerank.judgments;
      let hydrated = await hydrateEvidence(db, units, evidenceJudgments, verifiedEntities, entities as V3Entity[], dimensions, question, semantic);
      selection = hydrated.selection; selectedUnits = hydrated.selectedUnits; expandIds = hydrated.expandIds;
      units = [...new Map([...hydrated.expandedUnits, ...units].map((unit) => [unit.search_unit_id, unit])).values()];
      answerEvidence = hydrated.answerEvidence;
      let hydratedSufficiency = await judgeHydratedEvidenceSufficiency(question, semantic, verifiedEntities, selection.selected);
      rerankCalls.push(hydratedSufficiency); sufficiency = hydratedSufficiency.sufficiency;
      if (sufficiency.status !== 'complete' || selection.selected.length === 0) {
        reformulation = await reformulateRetrievalPlan(question, semantic, [...sufficiency.missing_information, ...selection.missingSignals, ...selection.missingDimensions], units.slice(0, 12).map((u) => `${u.document_title}: ${u.section_title ?? u.table_title ?? ''}`));
        plan = buildRetrievalPlan(question, semantic, verifiedEntities, dimensions, reformulation);
        retrieved = await retrieveHybrid(db, lexicalInformationQuery(question, semantic, verifiedEntities, [reformulation.search_query, ...reformulation.search_phrases]), vectorInformationQuery(semantic, verifiedEntities, plan.query, [reformulation.search_query, ...reformulation.retrieval_queries]), verifiedEntities, entities as V3Entity[]);
        embeddingRuns.push(retrieved.embedding); units = mergeUnits(units, retrieved.units);
        rerank = await rerankAndJudgeEvidence(question, semantic, verifiedEntities, units.slice(0, 18));
        rerankCalls.push(rerank); units = rerankUnits(units, rerank.judgments); sufficiency = rerank.sufficiency; evidenceJudgments = rerank.judgments;
        hydrated = await hydrateEvidence(db, units, evidenceJudgments, verifiedEntities, entities as V3Entity[], dimensions, question, semantic);
        selection = hydrated.selection; selectedUnits = hydrated.selectedUnits; expandIds = hydrated.expandIds;
        units = [...new Map([...hydrated.expandedUnits, ...units].map((unit) => [unit.search_unit_id, unit])).values()];
        answerEvidence = hydrated.answerEvidence;
        hydratedSufficiency = await judgeHydratedEvidenceSufficiency(question, semantic, verifiedEntities, selection.selected);
        rerankCalls.push(hydratedSufficiency); sufficiency = hydratedSufficiency.sufficiency;
      }
      // A single stochastic false-negative must not suppress evidence that survived
      // hybrid retrieval, isolation, reranking, structural hydration, and one retry.
      // Confirm only negative outcomes; either independent judge may establish
      // completeness, while two negative judgments are required to reject evidence.
      if (selection.selected.length > 0 && sufficiency.status !== 'complete') {
        const confirmation = await judgeHydratedEvidenceSufficiency(question, semantic, verifiedEntities, selection.selected);
        rerankCalls.push(confirmation); sufficiencyConfirmationUsed = true;
        if (confirmation.sufficiency.status === 'complete') sufficiency = confirmation.sufficiency;
      }
    }

    const evidenceInsufficient = retrievalMode === 'hybrid'
      ? selection.selected.length === 0 || sufficiency?.status !== 'complete'
      : selection.selected.length === 0 || !selection.sufficient;
    if (evidenceInsufficient) {
      return respond({ answer: 'The approved documents do not establish the requested information.', citations: [], answer_status: 'insufficient_evidence', insurance_v3: true, debug: body.debug === true ? { semantic_interpretation: semantic, verified_entities: verifiedEntities, retrieval_mode: retrievalMode, retrieval_plan: plan, hybrid_candidates: units, selected_units: selectedUnits, evidence_judgments: evidenceJudgments, expansion_unit_ids: expandIds, evidence_sufficiency: sufficiency, sufficiency_confirmation_used: sufficiencyConfirmationUsed, retrieved_chunks: selection.selected, retrieval_retry: Boolean(reformulation), embedding: embeddingRuns, ai: aiDiagnostics(semanticResult, rerankCalls, null), processing_ms: Date.now() - started } : undefined });
    }

    const deterministicEvaluations = evaluateOrThresholdTimeWindows(semantic, answerEvidence);
    const deterministicAnswer = renderDeterministicCriterionAnswer(question, semantic, deterministicEvaluations);
    const answerResult = deterministicAnswer ? { answer: deterministicAnswer, used_evidence_ids: ['E1'], usage: null, latency_ms: 0, provider: semanticResult.provider, model: semanticResult.model } : await answerFromEvidence(question, semantic, answerEvidence, deterministicEvaluations, sufficiency);
    const used = evidenceForAnswer(answerEvidence, answerResult.used_evidence_ids, dimensions);
    const citations = used.map((c) => ({ document_id: c.document_id, document_title: c.document_title, file_name: c.file_name, page_from: c.page_from, page_to: c.page_to, sheet_name: c.sheet_name, row_from: c.row_from, row_to: c.row_to, chunk_id: typeof c.metadata.source_chunk_id === 'string' ? c.metadata.source_chunk_id : c.chunk_id }));
    const sourceLines = [...new Set(used.map((c) => c.sheet_name ? `Source: ${c.document_title} — Sheet ${c.sheet_name}, rows ${c.row_from ?? '?'}-${c.row_to ?? '?'}` : `Source: ${c.document_title} — Page ${c.page_from}${c.page_to !== c.page_from ? `-${c.page_to}` : ''}`))];
    const answer = `${answerResult.answer.replace(/\n*Source:\s*[\s\S]*$/i, '').trim()}\n\n${sourceLines.join('\n')}`;

    let sessionId = typeof body.session_id === 'string' ? body.session_id : null;
    if (!sessionId) {
      const { data: session, error } = await db.from('insurance_chat_sessions').insert({ branch_name: String(body.branch_name ?? ''), title: question.slice(0, 80) }).select('id').single();
      if (error) throw error; sessionId = session.id;
    }
    const parsed = { insurance_v3: true, semantic, verified_entity_ids: verifiedEntities.map((e) => e.id) };
    const { error: userError } = await db.from('insurance_chat_messages').insert({ session_id: sessionId, role: 'user', message: question, parsed_data: parsed });
    if (userError) throw userError;
    const { data: assistant, error: assistantError } = await db.from('insurance_chat_messages').insert({ session_id: sessionId, role: 'assistant', message: answer, citations, parsed_data: { ...parsed, answer_status: 'grounded' } }).select('id,created_at').single();
    if (assistantError) throw assistantError;
    return respond({ session_id: sessionId, message_id: assistant.id, created_at: assistant.created_at, answer, citations, confidence: null, answer_status: 'grounded', answer_generator: deterministicAnswer ? 'deterministic_criteria' : 'grounded_ai', evidence_checked: true, insurance_v3: true,
      debug: body.debug === true ? { semantic_interpretation: semantic, verified_entities: verifiedEntities, retrieval_mode: retrievalMode, retrieval_plan: plan,
        retrieval_channels: units.slice(0, 24).map((u) => ({ search_unit_id: u.search_unit_id, source_chunk_ids: u.source_chunk_ids, unit_type: u.unit_type, document: u.document_title, page: u.page_from, vector_rank: u.vector_rank, fts_rank: u.fts_rank, trigram_rank: u.trigram_rank, heading_rank: u.heading_rank, entity_rank: u.entity_rank, rrf_score: u.hybrid_rrf_score, text: u.retrieval_text })),
        selected_units: selectedUnits.map((u) => ({ search_unit_id: u.search_unit_id, source_chunk_ids: u.source_chunk_ids, unit_type: u.unit_type, document: u.document_title, page: u.page_from })), evidence_judgments: evidenceJudgments, expansion_unit_ids: expandIds, evidence_sufficiency: sufficiency, sufficiency_confirmation_used: sufficiencyConfirmationUsed, retrieval_retry: Boolean(reformulation), embedding: embeddingRuns,
        deterministic_criteria_evaluations: deterministicEvaluations, final_evidence_ids: answerEvidence.map((c) => c.chunk_id), retrieved_chunks: selection.selected.map((c) => ({ chunk_id: c.chunk_id, document: c.document_title, page_from: c.page_from, page_to: c.page_to, score: c.deterministic_score, dimensions: dimensions.filter((d) => chunkAnswersDimension(c, d)), text: c.chunk_text })),
        ai: aiDiagnostics(semanticResult, rerankCalls, deterministicAnswer ? null : answerResult), model: AI_MODEL, processing_ms: Date.now() - started } : undefined });
  } catch (error) {
    if (error instanceof AIProvidersTemporarilyUnavailableError) return respond({ answer: 'The AI service is temporarily unavailable. Please try again shortly.', citations: [], answer_status: 'temporarily_unavailable', insurance_v3: true }, 503);
    if (error instanceof AIProviderError) {
      console.error('insurance_v3_ai_provider_error', { provider: error.provider, status: error.status, code: error.providerCode });
      return respond({ error: 'Unable to contact the AI service.', insurance_v3: true, debug: debugRequested ? { provider: error.provider, status: error.status, diagnostic_code: error.providerCode } : undefined }, 502);
    }
    console.error('insurance_v3_error', { message: error instanceof Error ? error.message : String(error) });
    return respond({ error: error instanceof Error ? error.message : 'Unable to answer the V3 policy question.', insurance_v3: true }, 400);
  }
});
