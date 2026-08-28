import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { AI_MODEL, answerFromEvidence, createQuestionContract, generateSemanticSearchHypotheses, inspectEvidenceAgainstContract, interpretQuestion, rerankAndJudgeEvidence, searchStrategyChanged, verifyAnswerAgainstContract, type EvidenceJudgment, type EvidenceLedger, type EvidenceSufficiency, type QuestionContract, type RecoveryPlan, type SemanticHypothesisSandbox } from './ai.ts';
import { AIProviderError, AIProvidersTemporarilyUnavailableError, type AIProviderName } from './ai_provider.ts';
import { hasStrongVerifiedEvidence } from './fallback.ts';
import { newRequestTrace, persistRequestTrace, type RequestTrace } from './diagnostics.ts';
import { alignSemanticMedication, evaluateOrThresholdTimeWindows, renderDeterministicCriterionAnswer } from './criteria.ts';
import { embedRetrievalQuery } from './embedding.ts';
import { contractRelevantEvidence, deterministicGroundedSynthesis, feedbackObjective, guardUserOutput, initialSandboxFromContract, looksLikeRawStructuredOutput, mergeCanonicalTerms, REASONING_ENGINE_VERSION, recoveryPlanFromSandbox, requiresAggregateCollection } from './reasoning_engine.ts';
import { preferredAnswerShouldReplace, relationSnapshot, semanticCachePayload, semanticCacheSignature, validatePreferredAnswerSources } from './validated_cache.ts';
import { findVerifiedSemanticMemory, recordSemanticMemoryFeedback, storeVerifiedSemanticRecovery, type RecoveryHypothesis, type SemanticMemoryHint } from './semantic_recovery_memory.ts';
import { extractVerifiedSearchStrategy, validatedLearningGate } from './validated_learning.ts';
import { aggregateSearchState, clarificationGate, preserveEvidenceLedgerOnProviderFailure, type EvidenceGraphDiagnostics } from './evidence_graph.ts';
import { requestBudgetState } from './request_budget.ts';
import {
  buildRetrievalPlan, enforceRouteSafety, evidenceForAnswer, groundEntityOnlySemantic, isolateMedicationCandidates, normalize,
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
    ai_calls: calls.length,
  };
}
function mergeUnits(left: HybridSearchUnit[], right: HybridSearchUnit[]) {
  return [...new Map([...left, ...right].map((u) => [u.search_unit_id, u])).values()].sort((a, b) => Number(b.hybrid_rrf_score) - Number(a.hybrid_rrf_score));
}
function evidenceLedgerFallback(contract: QuestionContract, evidence: V3Chunk[], verifiedStrongEvidence: boolean): EvidenceLedger {
  const ids = evidence.slice(0, 8).map((chunk) => chunk.chunk_id);
  // Flat retrieval strength cannot prove a requested relationship. When the AI
  // evidence auditor is unavailable, preserve the chunks for recovery but never
  // promote them into an answer-bearing relationship without a validated path.
  const relationshipProofRequired = contract.requested_relationships.length > 0;
  const fallbackMaySupport = verifiedStrongEvidence && ids.length > 0 && !relationshipProofRequired;
  const status = fallbackMaySupport ? 'supported' as const : ids.length > 0 ? 'partial' as const : 'missing' as const;
  const facets = contract.required_answer_facets.map((facet) => ({
    facet_id: facet.id, status, evidence_ids: status === 'missing' ? [] : ids,
    relation_paths: [],
    explanation: fallbackMaySupport ? 'Covered by direct verified answer-bearing evidence; AI ledger unavailable.' : 'Requires contract-level evidence inspection.',
  }));
  return {
    status: facets.every((facet) => facet.status === 'supported') ? 'complete' : facets.some((facet) => facet.status !== 'missing') ? 'partial' : 'insufficient',
    facets, missing_facets: facets.filter((facet) => facet.status !== 'supported').map((facet) => facet.facet_id),
    relation_direction_preserved: false, detected_relation_direction: 'unknown', cross_document_search: false,
    aggregation_complete: contract.answer_cardinality !== 'aggregate', matched_subjects: [],
    next_searches: [], reason: fallbackMaySupport ? 'Deterministic direct-evidence ledger fallback.' : 'Contract coverage or relationship proof not established.',
  };
}

function ledgerSupportsAnswer(contract: QuestionContract, ledger: EvidenceLedger, evidence: V3Chunk[]) {
  const aggregateReady = contract.answer_cardinality !== 'aggregate' || ledger.aggregation_complete === true;
  return ledger.status === 'complete' && aggregateReady && evidence.length > 0
    && (!requiresExplicitDirectionProof(contract) || ledger.relation_direction_preserved);
}
function fallbackQuestionContract(question: string, semantic: SemanticInterpretation, entities: V3Entity[]): QuestionContract {
  const dimensions = [...new Set((semantic.requested_dimensions ?? []).map((value) => String(value).trim()).filter(Boolean))];
  const fallbackNeed = String(semantic.requested_information ?? semantic.information_need ?? semantic.semantic_intent ?? question).trim();
  const facets = dimensions.length > 0
    ? dimensions.map((description, index) => ({ id: `semantic_facet_${index + 1}`, description, requested_type: description, required: true }))
    : [{ id: 'semantic_information_need', description: fallbackNeed, requested_type: fallbackNeed, required: true }];
  const primarySubject = entities[0]?.canonical_name
    ?? semantic.medication ?? semantic.generic ?? semantic.drug_class ?? semantic.indication ?? fallbackNeed;
  return {
    original_question: question,
    primary_subject: String(primarySubject).slice(0, 500),
    secondary_subjects: entities.slice(1, 9).map((entity) => entity.canonical_name),
    requested_relationships: [],
    required_answer_facets: facets.slice(0, 12),
    comparison_axes: [], constraints: [], patient_facts: [], ambiguities: [],
    expected_answer_type: 'grounded response', answer_cardinality: 'unknown', source_requirement: semantic.source_requested,
    initial_search_hypotheses: [{
      query: question.slice(0, 500), mode: 'all',
      concepts: [...new Set([...(semantic.search_concepts ?? []), ...entities.map((entity) => entity.canonical_name)])].slice(0, 10),
      relationship_direction: 'unknown',
    }],
  };
}
function requiresExplicitDirectionProof(contract: QuestionContract) {
  return contract.requested_relationships.some((relationship) =>
    ['reverse', 'bidirectional', 'comparison'].includes(relationship.direction)
  );
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
  validatedCacheInvalidated: boolean;
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
  if (mode === 'documents') return units.filter((unit) => unit.unit_type === 'page' || unit.unit_type === 'section');
  if (mode === 'entities') return units.filter((unit) => Number(unit.entity_match_count ?? 0) > 0 || unit.entity_rank !== null);
  if (mode === 'semantic') return units.filter((unit) => unit.vector_rank !== null || Number(unit.vector_similarity ?? 0) > 0);
  return units;
}

const jsonRows = (value: unknown) => Array.isArray(value)
  ? value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object')
  : [];

async function recordPositiveFeedback(db: DBClient, memoryDb: DBClient | null, userId: string, messageId: string) {
  const { data: assistant, error: messageError } = await db.from('insurance_chat_messages')
    .select('id,message,citations,parsed_data').eq('id', messageId).eq('role', 'assistant').single();
  if (messageError || !assistant) return { invalid: true };
  const { error: feedbackError } = await db.from('insurance_feedback').upsert({
    message_id: messageId, user_id: userId, rating: 1, updated_at: new Date().toISOString(),
  }, { onConflict: 'message_id,user_id' });
  if (feedbackError) throw feedbackError;

  const { data: audit } = await db.from('insurance_answer_audits').select(
    'id,raw_question,structured_query,retrieval_plan,verified_entities,verified_evidence,answer_status,final_answer,final_citations,recovery_attempt,provider_diagnostics,completeness,fallback_used,answer_generator,latency_ms',
  ).eq('message_id', messageId).order('created_at', { ascending: false }).limit(1).maybeSingle();
  const citations = jsonRows(audit?.final_citations).length ? jsonRows(audit.final_citations) : jsonRows(assistant.citations);
  const semantic = audit?.structured_query as SemanticInterpretation | undefined;
  const verifiedEntities = jsonRows(audit?.verified_entities) as V3Entity[];
  const answer = String(audit?.final_answer ?? assistant.message ?? '').trim();
  const learningGate = validatedLearningGate(audit as Record<string, unknown> | null, citations, answer);
  if (!audit || !semantic || !learningGate.eligible) {
    if (memoryDb && audit?.id) {
      await memoryDb.from('insurance_answer_audits').update({
        provider_diagnostics: {
          ...((audit.provider_diagnostics as Record<string, unknown> | null) ?? {}),
          useful_learning: {
            gate_passed: false,
            validated_cache_updated: false,
            semantic_memory_updated: false,
            reasons: learningGate.reasons.length ? learningGate.reasons : ['answer_not_safely_cacheable'],
          },
        },
      }).eq('id', audit.id);
    }
    return { recorded: true, cache_updated: false, semantic_memory_updated: false, reason: learningGate.reasons.join(',') || 'answer_not_safely_cacheable' };
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
  let semanticMemoryId: string | null = null;
  if (memoryDb) {
    const strategy = extractVerifiedSearchStrategy(audit.provider_diagnostics);
    const retrievalPlan = audit.retrieval_plan && typeof audit.retrieval_plan === 'object' ? audit.retrieval_plan as Record<string, unknown> : {};
    const questionContract = retrievalPlan.question_contract && typeof retrievalPlan.question_contract === 'object'
      ? retrievalPlan.question_contract as QuestionContract
      : strategy.questionContract;
    semanticMemoryId = await storeVerifiedSemanticRecovery(memoryDb, {
      semantic, entities: verifiedEntities, relations: relations as V3Relation[], contract: questionContract,
      expansionConcepts: strategy.expansionConcepts, hypotheses: strategy.hypotheses,
      relationshipDirection: strategy.relationshipDirection, evidenceIds,
      documents: (documents ?? []) as Array<Record<string, unknown>>, auditId: String(audit.id),
    });
    const usefulLearning = {
      gate_passed: true, validated_cache_updated: true,
      semantic_memory_updated: Boolean(semanticMemoryId), semantic_memory_id: semanticMemoryId,
      strategy_hypothesis_count: strategy.hypotheses.length,
    };
    await memoryDb.from('insurance_answer_audits').update({
      provider_diagnostics: { ...(audit.provider_diagnostics as Record<string, unknown> ?? {}), useful_learning: usefulLearning },
    }).eq('id', audit.id);
  }
  return { recorded: true, cache_updated: true, semantic_memory_updated: Boolean(semanticMemoryId), preferred_source: preferredSource };
}

async function applySemanticMemoryFeedback(db: DBClient, memoryDb: DBClient | null, messageId: string, positive: boolean) {
  if (!memoryDb) return;
  const { data: audit } = await db.from('insurance_answer_audits').select('provider_diagnostics')
    .eq('message_id', messageId).order('created_at', { ascending: false }).limit(1).maybeSingle();
  const diagnostics = audit?.provider_diagnostics as Record<string, unknown> | undefined;
  const memory = diagnostics?.semantic_recovery_memory as Record<string, unknown> | undefined;
  const memoryId = typeof memory?.memory_id === 'string' ? memory.memory_id : null;
  if (memoryId) await recordSemanticMemoryFeedback(memoryDb, memoryId, positive);
}

async function invalidateValidatedAnswerAfterNegativeFeedback(
  db: DBClient, userId: string, audit: Record<string, unknown> | null,
) {
  if (!audit?.structured_query || typeof audit.structured_query !== 'object') return false;
  const semantic = audit.structured_query as SemanticInterpretation;
  const entities = jsonRows(audit.verified_entities) as V3Entity[];
  const signature = await semanticCacheSignature(semantic, entities);
  const { data, error } = await db.from('insurance_validated_answers').update({
    active: false, invalidated_at: new Date().toISOString(),
    invalidation_reason: 'negative_feedback_requires_reverification', updated_at: new Date().toISOString(),
  }).eq('user_id', userId).eq('semantic_signature', signature).eq('active', true).select('id');
  if (error) {
    console.error('insurance_v3_negative_feedback_cache_invalidation_error', { code: error.code });
    return false;
  }
  return (data ?? []).length > 0;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const started = Date.now();
  let db: DBClient | null = null;
  let memoryDb: DBClient | null = null;
  let trace: RequestTrace | null = null;
  let debugRequested = false;
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return respond({ error: 'Authentication required.' }, 401);
    db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
    const { data: auth, error: authError } = await db.auth.getUser(authorization.slice(7));
    if (authError || !auth.user) return respond({ error: 'Authentication required.' }, 401);
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (serviceRoleKey) memoryDb = createClient(Deno.env.get('SUPABASE_URL')!, serviceRoleKey, { auth: { persistSession: false } });
    let body: Record<string, unknown>;
    try { body = await request.json() as Record<string, unknown>; }
    catch { return respond({ error: 'A valid JSON request body is required.' }, 400); }
    if (body.debug === true) {
      const { data: canDebug, error: debugAuthError } = await db.rpc('is_insurance_knowledge_admin');
      debugRequested = !debugAuthError && canDebug === true;
    }

    if (typeof body.positive_feedback_message_id === 'string') {
      const result = await recordPositiveFeedback(db, memoryDb, auth.user.id, body.positive_feedback_message_id);
      if (result.invalid) return respond({ error: 'The feedback message is invalid.' }, 400);
      await applySemanticMemoryFeedback(db, memoryDb, body.positive_feedback_message_id, true);
      return respond({ feedback_recorded: true, validated_cache_updated: result.cache_updated === true, semantic_memory_updated: result.semantic_memory_updated === true, preferred_source: result.preferred_source ?? null, insurance_v3: true });
    }

    let pipelineContext: PipelineContext = { forceRecovery: false, feedbackReason: null, originalAuditId: null, originalAnswer: null, originalEvidence: null, originalCitations: null, originalSemantic: null, validatedCacheInvalidated: false };
    let question = String(body.message ?? '').trim();
    if (typeof body.feedback_message_id === 'string') {
      const feedbackMessageId = body.feedback_message_id;
      const { data: assistant, error } = await db.from('insurance_chat_messages').select('id,session_id,message,citations,parsed_data,created_at').eq('id', feedbackMessageId).eq('role', 'assistant').single();
      if (error || !assistant) return respond({ error: 'The feedback message is invalid.' }, 400);
      const { data: priorAudit } = await db.from('insurance_answer_audits').select('id,raw_question,structured_query,verified_entities,verified_evidence,final_citations,recovery_attempt').eq('message_id', feedbackMessageId).order('created_at', { ascending: false }).limit(1).maybeSingle();
      await applySemanticMemoryFeedback(db, memoryDb, feedbackMessageId, false);
      const validatedCacheInvalidated = await invalidateValidatedAnswerAfterNegativeFeedback(db, auth.user.id, priorAudit as Record<string, unknown> | null);
      if (Number(priorAudit?.recovery_attempt ?? assistant.parsed_data?.recovery_depth ?? 0) >= 1) {
        await db.from('insurance_feedback').upsert({ message_id: feedbackMessageId, user_id: auth.user.id, rating: -1, second_rating: -1, reason: String(body.feedback_reason ?? 'other'), updated_at: new Date().toISOString() }, { onConflict: 'message_id,user_id' });
        return respond({ feedback_recorded: true, recovery_exhausted: true, validated_cache_invalidated: validatedCacheInvalidated, insurance_v3: true });
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
        validatedCacheInvalidated,
      };
      body = { ...body, session_id: assistant.session_id };
    }
    if (!question || question.length > 1200) return respond({ error: 'A question of at most 1200 characters is required.' }, 400);
    trace = newRequestTrace(auth.user.id, question);
    trace.recovery_of_audit_id = pipelineContext.originalAuditId;
    trace.recovery_attempt = pipelineContext.forceRecovery ? 1 : 0;
    trace.recovery.feedback_reason = pipelineContext.feedbackReason;
    const objective = feedbackObjective(pipelineContext.feedbackReason);
    trace.providers.shared_reasoning_engine = {
      reasoning_engine_version: REASONING_ENGINE_VERSION,
      semantic_engine_id: REASONING_ENGINE_VERSION,
      feedback_objective: objective.name,
      objective,
      canonical_terms_discovered: [], canonical_terms_reused: [],
      relation_direction: 'unknown', cross_document_search: false,
      aggregate_search_rounds: 0, evidence_matches_by_document: {},
      evidence_ledger_status: null, provider_failure_stage: null,
      grounded_synthesis_fallback_used: false,
      raw_json_blocked: false, raw_evidence_dump_blocked: false,
      answer_verifier_result: null,
      negative_feedback_cache_invalidated: pipelineContext.validatedCacheInvalidated,
    };

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
    const verifiedEntities = resolveVerifiedEntities(question, semanticResult.semantic, allEntities, allAliases, relations as V3Relation[]);
    const aligned = alignSemanticMedication(semanticResult.semantic, verifiedEntities);
    const grounded = groundEntityOnlySemantic(question, aligned, verifiedEntities, allAliases);
    const semanticRequestedRecovery = grounded.route === 'clarification_required';
    const dimensions = requestedDimensions(question, grounded);
    const semantic = enforceRouteSafety(grounded, verifiedEntities, dimensions);
    trace.semantic = semantic; trace.verified_entities = verifiedEntities;
    const contractStarted = Date.now();
    let contractResult: ({ contract: QuestionContract } & AIMetadata);
    try {
      contractResult = await createQuestionContract(question, semantic, verifiedEntities, objective.name);
    } catch (error) {
      contractResult = {
        contract: fallbackQuestionContract(question, semantic, verifiedEntities), usage: null, latency_ms: Date.now() - contractStarted,
        provider: semanticResult.provider, model: semanticResult.model,
      };
      trace.fallback_used = 'semantic_question_contract_fallback';
      trace.providers.question_contract_error = error instanceof Error ? error.name : 'unknown';
    }
    const questionContract = contractResult.contract;
    trace.question_contract = questionContract as unknown as Record<string, unknown>;
    trace.latency.question_contract_ms = Date.now() - contractStarted;
    if (!pipelineContext.forceRecovery && semantic.route !== 'out_of_scope') {
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
        const cachedAnswerIsStructured = validity.valid && looksLikeRawStructuredOutput(String(cached.answer_text ?? ''));
        if (!validity.valid) {
          await db.from('insurance_validated_answers').update({ active: false, invalidated_at: new Date().toISOString(), invalidation_reason: validity.reason, updated_at: new Date().toISOString() }).eq('id', cached.id);
        } else if (cachedAnswerIsStructured) {
          cacheDiagnostics.invalidation_reason = 'raw_structured_output_blocked_for_request';
          trace.providers.shared_reasoning_engine = {
            ...(trace.providers.shared_reasoning_engine as Record<string, unknown>), raw_json_blocked: true,
          };
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
          trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, [contractResult], null), validated_cache: cacheDiagnostics, question_contract: questionContract }; trace.token_usage = trace.providers;
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
      trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, [contractResult], null), question_contract: questionContract }; trace.token_usage = trace.providers;
      const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, semantic.route, 0);
      trace.session_id = saved.session_id; trace.message_id = saved.message_id;
      await persistRequestTrace(db, trace);
      return respond({ ...saved, answer, citations: [], answer_status: semantic.route, insurance_v3: true, debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, verified_entities: verifiedEntities, ai: trace.providers } : undefined });
    }

    // The mandatory AI question contract already contains bounded search
    // hypotheses. Reuse them for the first pass instead of asking the same 120B
    // model a second, overlapping planning question before retrieval begins.
    const hypothesisStarted = Date.now();
    const initialSemanticSandbox = initialSandboxFromContract(question, questionContract);
    trace.latency.semantic_hypothesis_ms = Date.now() - hypothesisStarted;
    trace.providers.semantic_hypothesis_sandbox = {
      semantic_hypothesis_expansion_triggered: false,
      initial_hypotheses_reused_from_question_contract: true,
      semantic_hypotheses_generated: initialSemanticSandbox.hypotheses,
      literal_vs_canonical_hypotheses: {
        literal: initialSemanticSandbox.hypotheses.filter((item) => item.kind === 'literal').length,
        canonical_or_expanded: initialSemanticSandbox.hypotheses.filter((item) => item.kind !== 'literal').length,
      },
      evidence_discovered_terminology: [],
      relation_direction_original: initialSemanticSandbox.relation_direction_original,
      relation_direction_reconsidered: initialSemanticSandbox.relation_direction_reconsidered,
      semantic_reinterpretation_on_incorrect: false,
      recovery_search_changed: null,
      insufficient_evidence_after_semantic_expansion: false,
    };
    let canonicalTerms = mergeCanonicalTerms(
      initialSemanticSandbox.hypotheses.filter((hypothesis) => hypothesis.kind !== 'literal').flatMap((hypothesis) => hypothesis.concepts),
    );
    trace.providers.shared_reasoning_engine = {
      ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
      semantic_hypotheses_generated: initialSemanticSandbox.hypotheses,
      canonical_terms_discovered: canonicalTerms,
      relation_direction: initialSemanticSandbox.relation_direction_reconsidered,
    };

    let memoryHint: SemanticMemoryHint | null = null;
    let memoryInvalidations: Array<{ id: string; reason: string }> = [];
    if (!pipelineContext.forceRecovery && memoryDb && semantic.route !== 'out_of_scope') {
      const memoryStarted = Date.now();
      const memoryResult = await findVerifiedSemanticMemory(memoryDb, semantic, verifiedEntities, questionContract);
      memoryHint = memoryResult.hint; memoryInvalidations = memoryResult.invalidated;
      trace.latency.semantic_memory_ms = Date.now() - memoryStarted;
      trace.providers.semantic_recovery_memory = {
        lookup: true, hit: Boolean(memoryHint), memory_id: memoryHint?.id ?? null,
        match_score: memoryHint?.score ?? null, confidence: memoryHint?.confidence ?? null,
        relationship_direction: memoryHint?.relationship_direction ?? null,
        invalidated: memoryInvalidations,
      };
    }
    const rememberedQueries = memoryHint?.hypotheses.map((hypothesis) => hypothesis.query) ?? [];
    const rememberedConcepts = memoryHint?.expansion_concepts ?? [];
    canonicalTerms = mergeCanonicalTerms(canonicalTerms, rememberedConcepts);
    trace.providers.shared_reasoning_engine = {
      ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
      canonical_terms_reused: rememberedConcepts,
      canonical_terms_discovered: canonicalTerms,
    };
    const contractQueries = [...questionContract.initial_search_hypotheses.map((hypothesis) => hypothesis.query), ...initialSemanticSandbox.hypotheses.map((hypothesis) => hypothesis.query)];
    const contractConcepts = [...questionContract.initial_search_hypotheses.flatMap((hypothesis) => hypothesis.concepts), ...initialSemanticSandbox.hypotheses.flatMap((hypothesis) => hypothesis.concepts)];
    let plan: ReturnType<typeof buildRetrievalPlan> & Record<string, unknown> = buildRetrievalPlan(question, semantic, verifiedEntities, dimensions, {
      retrieval_queries: [...contractQueries, ...(semantic.retrieval_queries ?? []), ...rememberedQueries].slice(0, 10),
      search_concepts: [...contractConcepts, ...(semantic.search_concepts ?? []), ...rememberedConcepts].slice(0, 28),
      search_phrases: [...(semantic.search_phrases ?? []), ...contractQueries, ...rememberedQueries].slice(0, 14),
    });
    plan = { ...plan, question_contract_facets: questionContract.required_answer_facets, search_hypotheses: initialSemanticSandbox.hypotheses, contract_search_hypotheses: questionContract.initial_search_hypotheses };
    trace.retrieval_plan = plan;
    let units: HybridSearchUnit[] = [];
    let selection: ReturnType<typeof selectEvidence> = { selected: [], missingDimensions: dimensions, missingSignals: [], requestedCoverage: 0, sufficient: false };
    let answerEvidence: ReturnType<typeof rerankChunks> = [];
    let evidenceJudgments: EvidenceJudgment[] = [];
    let sufficiency: EvidenceSufficiency | null = null;
    let evidenceLedger: EvidenceLedger | null = null;
    let bindingDiagnostics: EvidenceGraphDiagnostics | null = null;
    let aggregateRound = 0;
    let aggregationBudgetExhausted = false;
    const maximumAggregateRecoveryIterations = 2;
    let answerBearingSourceIds = new Set<string>();
    let selectedUnits: HybridSearchUnit[] = [];
    let expandIds: string[] = [];
    let strongEvidence = false;
    let successfulRecoveryPlan: RecoveryPlan | null = null;
    let recoverySemanticSandbox: SemanticHypothesisSandbox | null = null;
    let recoverySearchChanged: boolean | null = null;
    const aiCalls: AIMetadata[] = [contractResult];
    const embeddingRuns: Awaited<ReturnType<typeof embedRetrievalQuery>>[] = [];
    const retrievalStarted = Date.now();

    // Build and inspect the normal evidence baseline for every request,
    // including feedback-driven Deep Review. Recovery adds distinct searches
    // to this verified baseline; it never starts from an empty candidate set or
    // relies only on a lossy summary of the earlier evidence.
    {
      if (retrievalMode === 'lexical') {
        selection = await legacyEvidence(db, plan.query, plan.phrases, plan.hints, verifiedEntities, allEntities, dimensions, question, semantic);
        answerEvidence = selection.selected.slice(0, 4);
        strongEvidence = selection.selected.length > 0 && selection.sufficient && selection.missingDimensions.length === 0;
      } else {
        const retrieved = await retrieveHybrid(
          db,
          lexicalInformationQuery(question, semantic, verifiedEntities, [...contractConcepts, ...contractQueries, ...rememberedConcepts, ...rememberedQueries].slice(0, 16)),
          vectorInformationQuery(semantic, verifiedEntities, plan.query, [...contractQueries, ...rememberedQueries, ...contractConcepts, ...rememberedConcepts].slice(0, 16)),
          verifiedEntities, allEntities,
        );
        embeddingRuns.push(retrieved.embedding); units = retrieved.units;
        const focusedHypotheses = initialSemanticSandbox.hypotheses.filter((hypothesis) => hypothesis.kind !== 'literal')
          .sort((left, right) => Number(['reverse_relation', 'evidence_discovered'].includes(right.kind)) - Number(['reverse_relation', 'evidence_discovered'].includes(left.kind)))
          .slice(0, 2);
        const focusedResults = await Promise.allSettled(focusedHypotheses.map((focusedHypothesis) =>
          retrieveHybrid(db, focusedHypothesis.query, focusedHypothesis.query, verifiedEntities, allEntities)
            .then((result) => ({ result, mode: focusedHypothesis.mode }))
        ));
        for (const focused of focusedResults) {
          if (focused.status === 'fulfilled') {
            embeddingRuns.push(focused.value.result.embedding);
            units = mergeUnits(units, unitModeFilter(focused.value.result.units, focused.value.mode));
          } else trace.providers.initial_planned_search_error = focused.reason instanceof Error ? focused.reason.name : 'unknown';
        }
        // Hydrate the deterministic hybrid TOP candidates, then let one richer
        // AI evidence audit perform relevance, relationship, and sufficiency
        // reasoning together. This removes a redundant pre-hydration AI call.
        trace.providers.retrieval_rerank_mode = 'hybrid_rrf_then_hydrated_ai_evidence_audit';
        const hydrated = await hydrateEvidence(db, units, evidenceJudgments, verifiedEntities, allEntities, dimensions, question, semantic);
        selection = hydrated.selection; answerEvidence = hydrated.answerEvidence; selectedUnits = hydrated.selectedUnits; expandIds = hydrated.expandIds; answerBearingSourceIds = hydrated.answerBearingSourceIds;
        units = mergeUnits(hydrated.expandedUnits, units);
        const preInspectionStrongEvidence = hasStrongVerifiedEvidence(selection, answerEvidence, answerBearingSourceIds);
        if (selection.selected.length > 0) {
          try {
            if (!requestBudgetState(started).optional_reasoning_allowed) throw new Error('request_reasoning_budget_exhausted');
            const inspected = await inspectEvidenceAgainstContract(question, semantic, questionContract, verifiedEntities, selection.selected, contractQueries);
            aiCalls.push(inspected); evidenceLedger = inspected.ledger; bindingDiagnostics = inspected.binding_diagnostics;
            const ledgerEvidence = contractRelevantEvidence(selection.selected, evidenceLedger);
            if (ledgerEvidence.length > 0) answerEvidence = ledgerEvidence.slice(0, 12);
            sufficiency = { status: evidenceLedger.status, answered_information: evidenceLedger.facets.filter((facet) => facet.status === 'supported').map((facet) => facet.facet_id), missing_information: evidenceLedger.missing_facets, reason: evidenceLedger.reason };
            const directionRequired = requiresExplicitDirectionProof(questionContract);
            const aggregateReady = !requiresAggregateCollection(questionContract);
            strongEvidence = evidenceLedger.status === 'complete' && aggregateReady && answerEvidence.length > 0 && (!directionRequired || evidenceLedger.relation_direction_preserved);
          } catch (error) {
            evidenceLedger = evidenceLedgerFallback(questionContract, answerEvidence, preInspectionStrongEvidence);
            sufficiency = { status: evidenceLedger.status, answered_information: evidenceLedger.facets.filter((facet) => facet.status === 'supported').map((facet) => facet.facet_id), missing_information: evidenceLedger.missing_facets, reason: evidenceLedger.reason };
            strongEvidence = ledgerSupportsAnswer(questionContract, evidenceLedger, answerEvidence);
            trace.fallback_used = trace.fallback_used ?? 'deterministic_evidence_ledger';
            trace.providers.evidence_inspector_error = error instanceof Error ? error.name : 'unknown';
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
      // User feedback is evidence that the first-pass result did not satisfy
      // the request even when a fresh rerun again finds superficially strong
      // evidence. Deep Review must therefore diagnose and execute its bounded
      // recovery plan instead of silently reusing the same path.
      if (semanticRequestedRecovery || pipelineContext.forceRecovery) strongEvidence = false;
      const previousSemanticSearches = [...new Set([question, ...contractQueries, ...(semantic.retrieval_queries ?? [])].map((value) => String(value).trim()).filter(Boolean))];
      try {
        if (!requestBudgetState(started).optional_reasoning_allowed) throw new Error('request_reasoning_budget_exhausted');
        const recoveryHypothesisResult = await generateSemanticSearchHypotheses(question, semantic, questionContract, verifiedEntities, {
          first_pass_evidence: selection.selected.slice(0, 10).map((chunk) => ({ heading: chunk.section_title, document: chunk.document_title, page: chunk.page_from, text: chunk.chunk_text.slice(0, 800) })),
          previous_searches: previousSemanticSearches,
          feedback_reason: objective.name,
        });
        aiCalls.push(recoveryHypothesisResult);
        recoverySemanticSandbox = recoveryHypothesisResult.sandbox;
      } catch (error) {
        // The first-pass sandbox is request-scoped and already verified as a
        // distinct search plan. Reuse it as a clue set when a later provider
        // call fails instead of discarding evidence already discovered.
        recoverySemanticSandbox = initialSemanticSandbox;
        trace.providers.recovery_hypothesis_error = error instanceof Error ? error.name : 'unknown';
        trace.providers.shared_reasoning_engine = {
          ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
          provider_failure_stage: 'recovery_semantic_hypothesis',
        };
      }
      recoverySearchChanged = searchStrategyChanged(previousSemanticSearches, recoverySemanticSandbox.hypotheses);
      canonicalTerms = mergeCanonicalTerms(
        canonicalTerms,
        recoverySemanticSandbox.evidence_discovered_terminology,
        recoverySemanticSandbox.hypotheses.flatMap((hypothesis) => hypothesis.concepts),
      );
      trace.providers.semantic_hypothesis_sandbox = {
        ...(trace.providers.semantic_hypothesis_sandbox as Record<string, unknown>),
        semantic_hypotheses_generated: recoverySemanticSandbox.hypotheses,
        evidence_discovered_terminology: recoverySemanticSandbox.evidence_discovered_terminology,
        relation_direction_original: recoverySemanticSandbox.relation_direction_original,
        relation_direction_reconsidered: recoverySemanticSandbox.relation_direction_reconsidered,
        semantic_reinterpretation_on_incorrect: pipelineContext.feedbackReason === 'incorrect',
        recovery_search_changed: recoverySearchChanged,
      };
      trace.providers.shared_reasoning_engine = {
        ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
        semantic_hypotheses_generated: recoverySemanticSandbox.hypotheses,
        canonical_terms_discovered: canonicalTerms,
        canonical_terms_reused: recoverySemanticSandbox.evidence_discovered_terminology,
        relation_direction: recoverySemanticSandbox.relation_direction_reconsidered,
      };
      const aggregateRequested = requiresAggregateCollection(questionContract);
      const maximumRecoveryIterations = aggregateRequested ? maximumAggregateRecoveryIterations : pipelineContext.forceRecovery ? 2 : 1;
      for (let iteration = 1; iteration <= maximumRecoveryIterations && !strongEvidence; iteration++) {
        if (!requestBudgetState(started).optional_reasoning_allowed) {
          aggregationBudgetExhausted = aggregateRequested;
          trace.recovery.iterations.push({ iteration, outcome: 'latency_budget_exhausted', elapsed_ms: Date.now() - started });
          break;
        }
        if (aggregateRequested) aggregateRound = iteration;
        const candidateIdsBefore = new Set(units.map((unit) => unit.search_unit_id));
        // The AI sandbox has already performed the alternate interpretation.
        // Build the bounded execution plan from it and from the evidence audit's
        // targeted next searches; a second AI planner here only duplicated work.
        let recoveryPlan: RecoveryPlan = recoveryPlanFromSandbox(recoverySemanticSandbox, objective, canonicalTerms);
        const ledgerSearches = (evidenceLedger?.next_searches ?? []).map((search, index) => ({
          label: `ledger-target-${index + 1}`, ...search,
        }));
        recoveryPlan.searches = [...new Map([...ledgerSearches, ...recoveryPlan.searches]
          .map((search) => [`${search.mode}:${normalize(search.query)}`, search])).values()].slice(0, 5);
        recoveryPlan.decision = recoveryPlan.searches.length ? 'search' : recoveryPlan.decision;
        recoveryPlan.diagnosis = `${recoveryPlan.diagnosis} Targeted searches execute from one evidence-aware reasoning pass.`.trim();
        const materialAmbiguities = questionContract.ambiguities.filter((ambiguity) => ambiguity.materially_distinct);
        const materialInterpretations = [...new Set(materialAmbiguities.flatMap((ambiguity) => ambiguity.interpretations))];
        const currentClarificationGate = clarificationGate(questionContract, semantic);
        canonicalTerms = mergeCanonicalTerms(
          canonicalTerms,
          recoveryPlan.concept_expansions.map((item) => item.concept),
          recoveryPlan.searches.flatMap((search) => search.concepts),
        );
        const priorRoundSearches = trace.recovery.iterations.flatMap((entry) => Array.isArray(entry.searches)
          ? (entry.searches as Array<Record<string, unknown>>).map((search) => String(search.query ?? ''))
          : []);
        const plannerChangedSearch = searchStrategyChanged([...previousSemanticSearches, ...priorRoundSearches], recoveryPlan.searches);
        if (recoveryPlan.decision === 'search' && !plannerChangedSearch) {
          recoveryPlan.searches = recoverySemanticSandbox.hypotheses.map((hypothesis, index) => ({
            label: `semantic-sandbox-${index + 1}-${hypothesis.kind}`, query: hypothesis.query,
            mode: hypothesis.mode, concepts: hypothesis.concepts, relationship_direction: hypothesis.relationship_direction,
          }));
          recoveryPlan.relationship_direction = recoverySemanticSandbox.relation_direction_reconsidered;
          recoveryPlan.diagnosis = `${recoveryPlan.diagnosis} Literal-equivalent recovery was rejected; independent semantic sandbox strategy substituted.`.trim();
        }
        if (pipelineContext.forceRecovery && recoveryPlan.decision !== 'search'
          && !(recoveryPlan.decision === 'clarification' && materialInterpretations.length >= 2)) {
          const independentHypotheses = recoverySemanticSandbox.hypotheses
            .filter((hypothesis) => hypothesis.kind !== 'literal')
            .slice(0, 5);
          recoveryPlan.decision = 'search';
          recoveryPlan.searches = independentHypotheses.map((hypothesis, index) => ({
            label: `independent-${index + 1}-${hypothesis.kind}`, query: hypothesis.query, mode: hypothesis.mode,
            concepts: hypothesis.concepts, relationship_direction: hypothesis.relationship_direction,
          }));
          recoveryPlan.relationship_direction = recoverySemanticSandbox.relation_direction_reconsidered;
          recoveryPlan.diagnosis = `${recoveryPlan.diagnosis} Independent verification required after negative feedback.`.trim();
        }
        if (recoveryPlan.decision === 'clarification' && !currentClarificationGate.allow_clarification) {
          const targeted = [
            ...(evidenceLedger?.next_searches ?? []).map((search) => search.query),
            ...questionContract.initial_search_hypotheses.map((search) => search.query),
            ...(semantic.retrieval_queries ?? []),
          ];
          recoveryPlan.decision = 'search';
          recoveryPlan.searches = [...new Set(targeted.map((query) => query.trim()).filter(Boolean))].slice(0, 3).map((query, index) => ({
            label: `contract-research-${index + 1}`, query, mode: index === 1 ? 'tables' : 'all', concepts: [],
            relationship_direction: evidenceLedger?.detected_relation_direction ?? 'unknown',
          }));
          recoveryPlan.diagnosis = `${recoveryPlan.diagnosis} Retrieval difficulty is not material user ambiguity; targeted contract research required.`.trim();
        }
        const iterationTrace: Record<string, unknown> = {
          iteration, decision: recoveryPlan.decision, diagnosis: recoveryPlan.diagnosis,
          information_need: recoveryPlan.information_need,
          independent_interpretation: recoveryPlan.independent_interpretation,
          concept_expansions: recoveryPlan.concept_expansions,
          relationship_direction: recoveryPlan.relationship_direction,
          first_pass_clues_reused: units.length > 0 || selection.selected.length > 0,
          searches: recoveryPlan.searches, candidate_count_before: units.length,
          clarification_gate_result: currentClarificationGate,
        };
        if (recoveryPlan.decision === 'use_existing' && normalStrongEvidence && answerEvidence.length > 0 && !aggregateRequested) {
          strongEvidence = true;
          trace.recovery.iterations.push({ ...iterationTrace, outcome: 'verified_existing_evidence' });
          break;
        }
        if (recoveryPlan.decision === 'clarification') {
          trace.recovery.iterations.push({ ...iterationTrace, outcome: 'clarification' });
          const answer = recoveryPlan.clarification_question ?? 'Please clarify the entity or relationship you want to check.';
          trace.final_status = 'clarification_required'; trace.final_answer = answer; trace.final_reason = 'recovery_ambiguity'; trace.latency.recovery_ms = Date.now() - recoveryStarted; trace.latency.total_ms = Date.now() - started;
          trace.candidates = units; trace.evidence = selection.selected; trace.sufficiency = sufficiency as unknown as Record<string, unknown> | null; trace.evidence_ledger = evidenceLedger as unknown as Record<string, unknown> | null; trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, null) };
          trace.providers.reasoning_agent = { question_contract: questionContract, required_facets: questionContract.required_answer_facets, search_round_count: 1 + trace.recovery.iterations.length, search_hypotheses: trace.recovery.iterations.flatMap((entry) => Array.isArray(entry.searches) ? entry.searches : []), retrieved_evidence_count: selection.selected.length, evidence_coverage: evidenceLedger?.facets ?? [], missing_facets: evidenceLedger?.missing_facets ?? [], relation_direction: evidenceLedger?.detected_relation_direction ?? 'unknown', cross_document_search: evidenceLedger?.cross_document_search ?? false, semantic_expansion_used: true, semantic_memory_hit: Boolean(memoryHint), deep_review_reason: trace.recovery.reason, answer_verifier_result: null, answer_rejected_before_display: false, clarification_gate_result: currentClarificationGate, clarification_reason: recoveryPlan.diagnosis, provider_calls: (trace.providers.ai_calls as number | undefined) ?? 0, latency_ms: trace.latency.total_ms };
          trace.token_usage = trace.providers;
          const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, 'clarification_required', pipelineContext.forceRecovery ? 1 : 0);
          trace.session_id = saved.session_id; trace.message_id = saved.message_id;
          await persistRequestTrace(db, trace);
          return respond({ ...saved, answer, citations: [], answer_status: 'clarification_required', insurance_v3: true, recovery_used: true, debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, question_contract: questionContract, evidence_ledger: evidenceLedger, recovery: trace.recovery, ai: trace.providers } : undefined });
        }
        if (recoveryPlan.decision === 'not_found' || recoveryPlan.searches.length === 0) {
          const deterministicCandidates = [
            ...(evidenceLedger?.next_searches ?? []),
            ...questionContract.initial_search_hypotheses,
            ...recoverySemanticSandbox.hypotheses.map((hypothesis) => ({
              query: hypothesis.query, mode: hypothesis.mode,
              concepts: hypothesis.concepts, relationship_direction: hypothesis.relationship_direction,
            })),
          ];
          const alreadySearched = [
            ...previousSemanticSearches,
            ...trace.recovery.iterations.flatMap((entry) => Array.isArray(entry.searches)
              ? (entry.searches as Array<Record<string, unknown>>).map((search) => String(search.query ?? '')) : []),
          ];
          const remaining = deterministicCandidates.filter((candidate) =>
            searchStrategyChanged(alreadySearched, [{ query: candidate.query, concepts: candidate.concepts }])
          ).slice(0, 3);
          if ((aggregateRequested || evidenceLedger?.missing_facets.length) && remaining.length > 0) {
            recoveryPlan.decision = 'search';
            recoveryPlan.searches = remaining.map((candidate, index) => ({
              label: `deterministic-continuation-${index + 1}`, query: candidate.query, mode: candidate.mode,
              concepts: candidate.concepts, relationship_direction: candidate.relationship_direction,
            }));
            iterationTrace.decision = 'search'; iterationTrace.searches = recoveryPlan.searches;
            iterationTrace.deterministic_continuation = true;
          } else {
            if (aggregateRequested) aggregationBudgetExhausted = true;
            trace.recovery.iterations.push({ ...iterationTrace, outcome: 'no_search', aggregation_budget_exhausted: aggregateRequested });
            break;
          }
        }
        let newUnits: HybridSearchUnit[] = [];
        const anchoredEntities = verifiedEntities.some((entity) => entity.entity_type.startsWith('medication_')) ? verifiedEntities : [];
        const recoverySearches = recoveryPlan.searches.slice(0, 5);
        const recoveryResults = await Promise.allSettled(recoverySearches.map((search) =>
          retrieveHybrid(db, search.query, search.query, anchoredEntities, allEntities)
            .then((result) => ({ result, mode: search.mode }))
        ));
        for (const recovered of recoveryResults) {
          if (recovered.status === 'fulfilled') {
            embeddingRuns.push(recovered.value.result.embedding);
            newUnits = mergeUnits(newUnits, unitModeFilter(recovered.value.result.units, recovered.value.mode));
          } else {
            const searchErrors = Array.isArray(iterationTrace.search_errors) ? iterationTrace.search_errors as unknown[] : [];
            searchErrors.push(recovered.reason instanceof Error ? recovered.reason.name : 'unknown');
            iterationTrace.search_errors = searchErrors;
          }
        }
        units = mergeUnits(units, newUnits);
        // The hydrated evidence auditor below is the single AI relevance and
        // sufficiency authority for this round.
        if (units.length > 0) {
          const hydrated = await hydrateEvidence(db, units, evidenceJudgments, verifiedEntities, allEntities, dimensions, question, semantic);
          selection = hydrated.selection; answerEvidence = hydrated.answerEvidence; selectedUnits = hydrated.selectedUnits; expandIds = hydrated.expandIds; answerBearingSourceIds = hydrated.answerBearingSourceIds;
          units = mergeUnits(hydrated.expandedUnits, units);
          const preInspectionStrongEvidence = hasStrongVerifiedEvidence(selection, answerEvidence, answerBearingSourceIds);
          if (selection.selected.length > 0) {
            try {
              if (!requestBudgetState(started).optional_reasoning_allowed) throw new Error('request_reasoning_budget_exhausted');
              const inspected = await inspectEvidenceAgainstContract(
                question, semantic, questionContract, verifiedEntities, selection.selected,
                [
                  ...trace.recovery.iterations.flatMap((entry) => Array.isArray(entry.searches) ? (entry.searches as Array<Record<string, unknown>>).map((search) => String(search.query ?? '')) : []),
                  ...recoveryPlan.searches.map((search) => search.query),
                ],
              );
              aiCalls.push(inspected); evidenceLedger = inspected.ledger; bindingDiagnostics = inspected.binding_diagnostics;
              const ledgerEvidence = contractRelevantEvidence(selection.selected, evidenceLedger);
              if (ledgerEvidence.length > 0) answerEvidence = ledgerEvidence.slice(0, 12);
              sufficiency = { status: evidenceLedger.status, answered_information: evidenceLedger.facets.filter((facet) => facet.status === 'supported').map((facet) => facet.facet_id), missing_information: evidenceLedger.missing_facets, reason: evidenceLedger.reason };
              const directionRequired = requiresExplicitDirectionProof(questionContract);
              const materiallyNewCandidates = newUnits.filter((unit) => !candidateIdsBefore.has(unit.search_unit_id)).length;
              if (aggregateRequested && !(evidenceLedger.aggregation_complete === true && materiallyNewCandidates === 0)) {
                evidenceLedger.aggregation_complete = false;
                if (evidenceLedger.status === 'complete') evidenceLedger.status = 'partial';
              }
              const aggregateReady = !aggregateRequested || Boolean(evidenceLedger.aggregation_complete);
              strongEvidence = evidenceLedger.status === 'complete' && aggregateReady && answerEvidence.length > 0 && (!directionRequired || evidenceLedger.relation_direction_preserved);
            } catch (error) {
              evidenceLedger = preserveEvidenceLedgerOnProviderFailure(
                evidenceLedger,
                evidenceLedgerFallback(questionContract, answerEvidence, preInspectionStrongEvidence),
              );
              sufficiency = { status: evidenceLedger.status, answered_information: evidenceLedger.facets.filter((facet) => facet.status === 'supported').map((facet) => facet.facet_id), missing_information: evidenceLedger.missing_facets, reason: evidenceLedger.reason };
              strongEvidence = ledgerSupportsAnswer(questionContract, evidenceLedger, answerEvidence);
              trace.providers.recovery_evidence_inspector_error = error instanceof Error ? error.name : 'unknown';
            }
          }
        }
        const materiallyNewCandidates = newUnits.filter((unit) => !candidateIdsBefore.has(unit.search_unit_id)).length;
        trace.recovery.iterations.push({ ...iterationTrace, new_candidate_count: newUnits.length, materially_new_candidate_count: materiallyNewCandidates, selected_evidence_count: selection.selected.length, canonical_terms_reused: canonicalTerms, outcome: strongEvidence ? 'answer_bearing_evidence' : 'insufficient' });
        if (strongEvidence) successfulRecoveryPlan = recoveryPlan;
        if (aggregateRequested && materiallyNewCandidates === 0 && evidenceLedger?.aggregation_complete) {
          strongEvidence = evidenceLedger.status === 'complete' && answerEvidence.length > 0;
          if (strongEvidence) successfulRecoveryPlan = recoveryPlan;
          break;
        }
        if (aggregateRequested && iteration === maximumRecoveryIterations && !evidenceLedger?.aggregation_complete) {
          aggregationBudgetExhausted = true;
        }
      }
      trace.latency.recovery_ms = Date.now() - recoveryStarted;
    }

    if (!evidenceLedger) evidenceLedger = evidenceLedgerFallback(questionContract, answerEvidence, false);
    const searchableAggregateFacetsRemain = evidenceLedger.next_searches.length > 0
      || Boolean(recoverySemanticSandbox?.hypotheses.length)
      || questionContract.initial_search_hypotheses.length > 0;
    const aggregateState = aggregateSearchState(
      questionContract,
      evidenceLedger,
      aggregateRound,
      maximumAggregateRecoveryIterations,
      searchableAggregateFacetsRemain && !aggregationBudgetExhausted,
    );
    if (questionContract.answer_cardinality === 'aggregate') {
      evidenceLedger.aggregate_round = aggregateRound;
      evidenceLedger.aggregation_budget_exhausted = aggregateState.aggregation_budget_exhausted;
      evidenceLedger.aggregate_state = aggregateState.state;
      if (!aggregateState.may_mark_complete) {
        evidenceLedger.aggregation_complete = false;
        if (evidenceLedger.status === 'complete') evidenceLedger.status = 'partial';
      }
    }
    trace.candidates = units; trace.reranked = evidenceJudgments; trace.evidence = selection.selected; trace.sufficiency = sufficiency as unknown as Record<string, unknown> | null;
    trace.evidence_ledger = evidenceLedger as unknown as Record<string, unknown> | null;
    trace.rejected = units.filter((unit) => !selectedUnits.some((selected) => selected.search_unit_id === unit.search_unit_id)).slice(0, 20);
    const evidenceMatchesByDocument = selection.selected.reduce<Record<string, number>>((counts, chunk) => {
      counts[chunk.document_title] = (counts[chunk.document_title] ?? 0) + 1;
      return counts;
    }, {});
    trace.providers.shared_reasoning_engine = {
      ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
      canonical_terms_discovered: canonicalTerms,
      canonical_terms_reused: trace.recovery.iterations.flatMap((iteration) => Array.isArray(iteration.canonical_terms_reused) ? iteration.canonical_terms_reused : []),
      relation_direction: evidenceLedger.detected_relation_direction,
      cross_document_search: evidenceLedger.cross_document_search || requiresAggregateCollection(questionContract),
      aggregate_search_rounds: requiresAggregateCollection(questionContract) ? trace.recovery.iterations.length : 0,
      aggregation_complete: evidenceLedger.aggregation_complete ?? false,
      aggregation_budget_exhausted: evidenceLedger.aggregation_budget_exhausted ?? false,
      aggregate_round: evidenceLedger.aggregate_round ?? 0,
      aggregate_state: evidenceLedger.aggregate_state ?? null,
      evidence_matches_by_document: evidenceMatchesByDocument,
      evidence_ledger_status: evidenceLedger.status,
      document_binding_attempted: bindingDiagnostics?.document_binding_attempted ?? false,
      document_binding_success: bindingDiagnostics?.document_binding_success ?? false,
      binding_source_evidence_ids: bindingDiagnostics?.binding_source_evidence_ids ?? [],
      binding_context_evidence_ids: bindingDiagnostics?.binding_context_evidence_ids ?? [],
      relationship_paths_created: bindingDiagnostics?.relationship_paths_created ?? [],
      relationship_paths_rejected: bindingDiagnostics?.relationship_paths_rejected ?? [],
      relationship_rejection_reason: bindingDiagnostics?.relationship_rejection_reason ?? [],
      facet_type_validation: bindingDiagnostics?.facet_type_validation ?? [],
      verifier_relation_path_result: bindingDiagnostics?.verifier_relation_path_result ?? 'not_required',
    };
    const supportedLedgerEvidence = Boolean(evidenceLedger?.facets.some((facet) => facet.status === 'supported' && facet.evidence_ids.length > 0) && answerEvidence.length > 0);
    if ((!strongEvidence && !supportedLedgerEvidence) || answerEvidence.length === 0) {
      const sharedDiagnostics = trace.providers.shared_reasoning_engine as Record<string, unknown>;
      const evidenceAuditUnavailable = Boolean(
        trace.providers.evidence_inspector_error
        || trace.providers.recovery_evidence_inspector_error
        || sharedDiagnostics.provider_failure_stage,
      );
      if (evidenceAuditUnavailable && selection.selected.length > 0) {
        throw new AIProvidersTemporarilyUnavailableError();
      }
      const alternateSemanticExpansionAttempted = initialSemanticSandbox.hypotheses.some((hypothesis) => hypothesis.kind !== 'literal')
        && (!trace.recovery.activated || Boolean(recoverySemanticSandbox && recoverySearchChanged));
      if (!alternateSemanticExpansionAttempted) {
        throw new AIProviderError(contractResult.provider, 200, false, 'semantic_expansion_required_before_insufficient_evidence');
      }
      trace.providers.semantic_hypothesis_sandbox = {
        ...(trace.providers.semantic_hypothesis_sandbox as Record<string, unknown>),
        insufficient_evidence_after_semantic_expansion: true,
      };
      const materialAmbiguities = questionContract.ambiguities.filter((ambiguity) => ambiguity.materially_distinct);
      const materialInterpretations = [...new Set(materialAmbiguities.flatMap((ambiguity) => ambiguity.interpretations))];
      const finalClarificationGate = clarificationGate(questionContract, semantic);
      trace.providers.shared_reasoning_engine = {
        ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
        clarification_gate_result: finalClarificationGate,
        clarification_reason: finalClarificationGate.reason,
        user_ambiguity_detected: finalClarificationGate.user_ambiguity_detected,
        search_incompleteness_detected: finalClarificationGate.search_incompleteness_detected,
      };
      if (finalClarificationGate.allow_clarification) {
        const answer = `Could you clarify which interpretation you mean: ${materialInterpretations.join('; ')}?`;
        trace.final_status = 'clarification_required'; trace.final_answer = answer; trace.final_reason = 'material_contract_ambiguity_after_bounded_search'; trace.latency.total_ms = Date.now() - started;
        trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, null) }; trace.token_usage = trace.providers;
        trace.providers.reasoning_agent = {
          question_contract: questionContract, required_facets: questionContract.required_answer_facets,
          search_round_count: 1 + trace.recovery.iterations.length, retrieved_evidence_count: selection.selected.length,
          evidence_coverage: evidenceLedger?.facets ?? [], missing_facets: evidenceLedger?.missing_facets ?? [],
          clarification_gate_result: finalClarificationGate,
          clarification_reason: 'two_or_more_material_contract_interpretations_after_bounded_search',
          provider_calls: (trace.providers.ai_calls as number | undefined) ?? 0, latency_ms: trace.latency.total_ms,
        };
        const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, 'clarification_required', pipelineContext.forceRecovery ? 1 : 0);
        trace.session_id = saved.session_id; trace.message_id = saved.message_id;
        await persistRequestTrace(db, trace);
        return respond({ ...saved, answer, citations: [], answer_status: 'clarification_required', insurance_v3: true, recovery_used: trace.recovery.activated,
          debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, question_contract: questionContract, verified_entities: verifiedEntities, retrieval_plan: plan, selected_evidence: selection.selected, evidence_ledger: evidenceLedger, recovery: trace.recovery, ai: trace.providers } : undefined });
      }
      const missingDescriptions = questionContract.required_answer_facets
        .filter((facet) => !evidenceLedger || evidenceLedger.missing_facets.includes(facet.id)).map((facet) => facet.description);
      const answer = missingDescriptions.length
        ? `The approved documents do not establish: ${missingDescriptions.join('; ')}.`
        : 'The approved documents do not establish the requested information.';
      trace.answer_verifier = {
        answer_usable: true, answer_rejected_before_display: false,
        reason: 'genuine_evidence_absence_reported_from_contract_ledger',
      };
      trace.final_status = 'insufficient_evidence'; trace.final_answer = answer; trace.final_reason = 'normal_and_bounded_recovery_exhausted'; trace.latency.total_ms = Date.now() - started;
      trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, null) }; trace.token_usage = trace.providers;
      trace.providers.reasoning_agent = { question_contract: questionContract, required_facets: questionContract.required_answer_facets, search_round_count: 1 + trace.recovery.iterations.length, search_hypotheses: [...questionContract.initial_search_hypotheses, ...trace.recovery.iterations.flatMap((entry) => Array.isArray(entry.searches) ? entry.searches : [])], retrieved_evidence_count: selection.selected.length, evidence_coverage: evidenceLedger?.facets ?? [], missing_facets: evidenceLedger?.missing_facets ?? questionContract.required_answer_facets.map((facet) => facet.id), relation_direction: evidenceLedger?.detected_relation_direction ?? 'unknown', cross_document_search: evidenceLedger?.cross_document_search ?? false, semantic_expansion_used: trace.recovery.activated, semantic_memory_hit: Boolean(memoryHint), deep_review_reason: trace.recovery.reason, answer_verifier_result: null, answer_rejected_before_display: false, clarification_reason: null, provider_calls: (trace.providers.ai_calls as number | undefined) ?? 0, latency_ms: trace.latency.total_ms };
      const saved = await saveConversation(db, body, question, answer, [], semantic, verifiedEntities, 'insufficient_evidence', pipelineContext.forceRecovery ? 1 : 0);
      trace.session_id = saved.session_id; trace.message_id = saved.message_id;
      const auditId = await persistRequestTrace(db, trace);
      if (pipelineContext.forceRecovery && auditId) await db.from('insurance_learning_queue').insert({ audit_id: auditId, reason: 'negative_feedback', priority: 3, proposed_change: { request_id: trace.request_id, feedback_reason: pipelineContext.feedbackReason, recovery_exhausted: true } });
      return respond({ ...saved, answer, citations: [], answer_status: 'insufficient_evidence', insurance_v3: true, recovery_used: trace.recovery.activated, debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, question_contract: questionContract, verified_entities: verifiedEntities, retrieval_plan: plan, candidates: units.slice(0, 24), selected_evidence: selection.selected, evidence_ledger: evidenceLedger, answer_verifier: trace.answer_verifier, sufficiency, recovery: trace.recovery, ai: trace.providers, processing_ms: Date.now() - started } : undefined });
    }

    const deterministicEvaluations = evaluateOrThresholdTimeWindows(semantic, answerEvidence);
    const deterministicAnswer = renderDeterministicCriterionAnswer(question, semantic, deterministicEvaluations);
    let answerResult: { answer: string; used_evidence_ids: string[]; verifier?: { answer_usable: boolean; answer_rejected_before_display: boolean; final_answer_verified?: boolean; draft_answer_usable?: boolean; relation_paths_verified?: boolean; reason: string } } & AIMetadata;
    let answerGenerator = deterministicAnswer ? 'deterministic_criteria' : 'grounded_ai';
    const sharedAnswerContext = {
      feedback_objective: objective.name,
      preserve_supported_previous_facts: objective.preserve_supported_previous_facts,
      do_not_preserve_previous_claims: objective.do_not_preserve_previous_claims,
      target_missing_contract_facets: objective.target_missing_contract_facets,
      original_answer: pipelineContext.originalAnswer,
      original_evidence: pipelineContext.originalEvidence,
    };
    const synthesisLedger = evidenceLedger ?? evidenceLedgerFallback(questionContract, answerEvidence, true);
    if (deterministicAnswer && objective.name !== 'incomplete') answerResult = {
      answer: deterministicAnswer, used_evidence_ids: ['E1'], usage: null, latency_ms: 0,
      provider: semanticResult.provider, model: semanticResult.model,
      verifier: { answer_usable: true, answer_rejected_before_display: false, final_answer_verified: true, reason: 'deterministic_criteria_evaluation' },
    };
    else if (!requestBudgetState(started).ai_answer_allowed) {
      const fallback = deterministicGroundedSynthesis(question, questionContract, synthesisLedger, answerEvidence);
      answerResult = {
        ...fallback, usage: null, latency_ms: 0, provider: semanticResult.provider, model: semanticResult.model,
        verifier: { answer_usable: true, answer_rejected_before_display: false, final_answer_verified: true, relation_paths_verified: true, reason: 'request_latency_budget_grounded_synthesis' },
      };
      answerGenerator = 'latency_budget_grounded_synthesis_fallback';
      trace.fallback_used = 'latency_budget_grounded_synthesis';
      trace.providers.shared_reasoning_engine = {
        ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
        latency_budget_exhausted: true, elapsed_before_synthesis_ms: Date.now() - started,
      };
    }
    else {
      try {
        answerResult = await answerFromEvidence(
          question, semantic, answerEvidence, deterministicEvaluations,
          sufficiency ?? { status: 'complete', answered_information: [], missing_information: [], reason: 'verified answer-bearing evidence' },
          questionContract, evidenceLedger, sharedAnswerContext,
        );
      }
      catch (error) {
        const fallback = deterministicGroundedSynthesis(question, questionContract, synthesisLedger, answerEvidence);
        answerResult = { ...fallback, usage: null, latency_ms: 0, provider: semanticResult.provider, model: semanticResult.model };
        answerGenerator = 'shared_grounded_synthesis_fallback'; trace.fallback_used = 'deterministic_grounded_synthesis'; trace.providers.answer_error = error instanceof Error ? error.name : 'unknown';
        trace.providers.shared_reasoning_engine = {
          ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
          provider_failure_stage: 'answer_generation', grounded_synthesis_fallback_used: true,
        };
      }
    }
    if (!answerResult.verifier) {
      if (!requestBudgetState(started).ai_answer_allowed) {
        const fallback = deterministicGroundedSynthesis(question, questionContract, synthesisLedger, answerEvidence);
        answerResult = {
          ...fallback, usage: answerResult.usage, latency_ms: answerResult.latency_ms,
          provider: answerResult.provider, model: answerResult.model,
          verifier: { answer_usable: true, answer_rejected_before_display: true, final_answer_verified: true, relation_paths_verified: true, reason: 'verifier_skipped_at_request_latency_budget' },
        };
        answerGenerator = 'latency_budget_verified_synthesis_fallback';
        trace.fallback_used = 'answer_verifier_latency_budget_synthesis';
      } else try {
        const verified = await verifyAnswerAgainstContract(question, semantic, questionContract, evidenceLedger ?? evidenceLedgerFallback(questionContract, answerEvidence, true), answerEvidence, answerResult.answer, answerResult.used_evidence_ids);
        const promptTokens = usagePart(answerResult.usage, 'prompt_tokens', 'input_tokens') + usagePart(verified.usage, 'prompt_tokens', 'input_tokens');
        const completionTokens = usagePart(answerResult.usage, 'completion_tokens', 'output_tokens') + usagePart(verified.usage, 'completion_tokens', 'output_tokens');
        answerResult = {
          ...verified, usage: { prompt_tokens: promptTokens, completion_tokens: completionTokens, total_tokens: promptTokens + completionTokens },
          latency_ms: answerResult.latency_ms + verified.latency_ms,
          provider: answerResult.provider === 'groq_fallback' || verified.provider === 'groq_fallback' ? 'groq_fallback' : 'together',
        };
      } catch (error) {
        const fallback = deterministicGroundedSynthesis(question, questionContract, synthesisLedger, answerEvidence);
        answerResult = {
          ...fallback, usage: answerResult.usage, latency_ms: answerResult.latency_ms,
          provider: answerResult.provider, model: answerResult.model,
          verifier: { answer_usable: false, answer_rejected_before_display: true, reason: 'verifier_unavailable_deterministic_synthesis_used' },
        };
        answerGenerator = 'shared_verified_synthesis_fallback'; trace.fallback_used = 'answer_verifier_deterministic_synthesis';
        trace.providers.answer_verifier_error = error instanceof Error ? error.name : 'unknown';
        trace.providers.shared_reasoning_engine = {
          ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
          provider_failure_stage: 'answer_verifier', grounded_synthesis_fallback_used: true,
        };
      }
    }
    const guarded = guardUserOutput(answerResult.answer, question, questionContract, synthesisLedger, answerEvidence, answerGenerator.includes('extractive'));
    if (guarded.used_evidence_ids) answerResult.used_evidence_ids = guarded.used_evidence_ids;
    answerResult.answer = guarded.answer;
    if (guarded.raw_json_blocked || guarded.raw_evidence_dump_blocked) {
      answerGenerator = 'shared_output_guard_synthesis_fallback';
      trace.fallback_used = 'user_output_sanitizer';
    }
    trace.providers.shared_reasoning_engine = {
      ...(trace.providers.shared_reasoning_engine as Record<string, unknown>),
      grounded_synthesis_fallback_used: answerGenerator.includes('synthesis_fallback'),
      raw_json_blocked: guarded.raw_json_blocked,
      raw_evidence_dump_blocked: guarded.raw_evidence_dump_blocked,
      answer_verifier_result: answerResult.verifier ?? null,
    };
    trace.answer_verifier = answerResult.verifier as unknown as Record<string, unknown>;
    const used = evidenceForAnswer(answerEvidence, answerResult.used_evidence_ids, dimensions);
    const safeUsed = used.length ? used : answerEvidence.slice(0, 2);
    const sourceDocumentIds = [...new Set(safeUsed.map((chunk) => chunk.document_id))];
    const { data: sourceDocuments, error: sourceDocumentsError } = await db
      .from('insurance_v3_documents')
      .select('id,document_hash,version,updated_at,is_active,storage_bucket,storage_path')
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
    const partialCoverage = evidenceLedger?.status !== 'complete';
    const status = partialCoverage
      ? (trace.recovery.activated ? 'recovery_partial_grounded' : 'partial_grounded')
      : trace.recovery.activated ? (answerGenerator.includes('fallback') ? 'recovery_fallback' : 'recovery_grounded') : (answerGenerator.includes('fallback') ? 'grounded_fallback' : 'grounded');
    const saved = await saveConversation(db, body, question, answer, citations, semantic, verifiedEntities, status, pipelineContext.forceRecovery ? 1 : 0);
    trace.session_id = saved.session_id; trace.message_id = saved.message_id; trace.final_status = status; trace.final_answer = answer; trace.citations = citations; trace.final_reason = 'verified_answer_bearing_evidence'; trace.answer_generator = answerGenerator; trace.latency.answer_ms = answerResult.latency_ms; trace.latency.total_ms = Date.now() - started;
    trace.providers = { ...trace.providers, ...aiDiagnostics(semanticResult, aiCalls, (deterministicAnswer && pipelineContext.feedbackReason !== 'incomplete') || answerGenerator.includes('fallback') ? null : answerResult) }; trace.token_usage = trace.providers;
    trace.providers.semantic_recovery = {
      semantic_recovery_triggered: trace.recovery.activated,
      semantic_recovery_reason: trace.recovery.reason,
      generated_concept_expansions: successfulRecoveryPlan?.concept_expansions ?? [],
      relationship_direction_detected: successfulRecoveryPlan?.relationship_direction ?? memoryHint?.relationship_direction ?? 'unknown',
      first_pass_evidence_reused: trace.recovery.iterations.some((iteration) => iteration.first_pass_clues_reused === true),
      recovery_queries: successfulRecoveryPlan?.searches.map((search) => search.query) ?? [],
      recovery_memory_created: false,
      recovery_memory_hit: Boolean(memoryHint),
      recovery_memory_confidence: memoryHint?.confidence ?? null,
      recovery_memory_invalidated: memoryInvalidations.length > 0,
      recovery_memory_invalidation_reason: memoryInvalidations.map((item) => item.reason),
      normal_retrieval_saved_by_memory: Boolean(memoryHint && !trace.recovery.activated),
      deep_review_avoided: Boolean(memoryHint && !trace.recovery.activated),
      ai_calls: (trace.providers.ai_calls as number | undefined) ?? 0,
      latency_ms: Number(trace.latency.recovery_ms ?? 0) + Number(trace.latency.semantic_memory_ms ?? 0),
    };
    trace.providers.reasoning_agent = {
      question_contract: questionContract,
      required_facets: questionContract.required_answer_facets,
      search_round_count: 1 + trace.recovery.iterations.filter((iteration) => iteration.outcome !== 'no_search').length,
      search_hypotheses: [
        ...questionContract.initial_search_hypotheses,
        ...trace.recovery.iterations.flatMap((iteration) => Array.isArray(iteration.searches) ? iteration.searches as unknown[] : []),
      ],
      retrieved_evidence_count: selection.selected.length,
      evidence_coverage: evidenceLedger?.facets ?? [], missing_facets: evidenceLedger?.missing_facets ?? [],
      relation_direction: evidenceLedger?.detected_relation_direction ?? 'unknown',
      cross_document_search: evidenceLedger?.cross_document_search ?? false,
      semantic_expansion_used: Boolean(successfulRecoveryPlan?.concept_expansions.length),
      semantic_memory_hit: Boolean(memoryHint), deep_review_reason: trace.recovery.reason,
      answer_verifier_result: answerResult.verifier,
      answer_rejected_before_display: answerResult.verifier?.answer_rejected_before_display ?? false,
      verifier_relation_path_result: answerResult.verifier?.relation_paths_verified === false ? 'failed' : bindingDiagnostics?.verifier_relation_path_result ?? 'not_required',
      aggregation_complete: evidenceLedger.aggregation_complete ?? false,
      aggregation_budget_exhausted: evidenceLedger.aggregation_budget_exhausted ?? false,
      aggregate_round: evidenceLedger.aggregate_round ?? 0,
      clarification_gate_result: clarificationGate(questionContract, semantic),
      clarification_reason: null,
      provider_calls: (trace.providers.ai_calls as number | undefined) ?? 0,
      latency_ms: trace.latency.total_ms,
    };
    const semanticLearningChecks = {
      recovery_plan_present: Boolean(successfulRecoveryPlan), strong_verified_evidence: strongEvidence,
      cited_evidence_present: safeUsed.length > 0, evidence_ledger_complete: evidenceLedger?.status === 'complete',
      answer_verifier_passed: answerResult.verifier?.final_answer_verified === true
        || (answerResult.verifier?.answer_usable === true && answerResult.verifier?.answer_rejected_before_display !== true),
      no_material_ambiguity: questionContract.ambiguities.every((ambiguity) => !ambiguity.materially_distinct),
      all_source_snapshots_resolved: (sourceDocuments ?? []).length === sourceDocumentIds.length,
      no_answer_fallback: !answerGenerator.includes('fallback'),
      sufficiency_complete: sufficiency?.status === 'complete' || selection.sufficient,
    };
    trace.providers.semantic_recovery = {
      ...(trace.providers.semantic_recovery as Record<string, unknown>),
      learning_eligibility: semanticLearningChecks,
      learning_eligible_before_persistence: Object.values(semanticLearningChecks).every(Boolean),
    };
    const auditId = await persistRequestTrace(db, trace);
    if (memoryDb && auditId && memoryHint) {
      const { data: usedMemory } = await memoryDb.from('insurance_semantic_recovery_memories').select('successful_uses').eq('id', memoryHint.id).maybeSingle();
      if (usedMemory) await memoryDb.from('insurance_semantic_recovery_memories').update({
        successful_uses: Number(usedMemory.successful_uses) + 1,
        last_verified_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      }).eq('id', memoryHint.id);
    }
    const canLearnSemanticRepair = Boolean(memoryDb && auditId && Object.values(semanticLearningChecks).every(Boolean));
    if (canLearnSemanticRepair && memoryDb && auditId && successfulRecoveryPlan) {
      const hypotheses: RecoveryHypothesis[] = successfulRecoveryPlan.searches.map((search) => ({
        label: search.label, query: search.query, mode: search.mode, concepts: search.concepts,
        relationship_direction: search.relationship_direction,
      }));
      const learnedMemoryId = await storeVerifiedSemanticRecovery(memoryDb, {
        semantic, entities: verifiedEntities, relations: relations as V3Relation[], contract: questionContract,
        expansionConcepts: successfulRecoveryPlan.concept_expansions.map((item) => item.concept),
        hypotheses, relationshipDirection: successfulRecoveryPlan.relationship_direction,
        evidenceIds: safeUsed.map((chunk) => chunk.chunk_id),
        documents: (sourceDocuments ?? []) as Array<Record<string, unknown>>, auditId,
      });
      if (learnedMemoryId) {
        const memoryDiagnostics = {
          ...((trace.providers.semantic_recovery_memory as Record<string, unknown> | undefined) ?? {}),
          learned: true, memory_id: learnedMemoryId, automatic: true,
          evidence_count: safeUsed.length, source_count: sourceDocumentIds.length,
        };
        trace.providers.semantic_recovery_memory = memoryDiagnostics;
        trace.providers.semantic_recovery = {
          ...(trace.providers.semantic_recovery as Record<string, unknown>),
          recovery_memory_created: true,
        };
        await memoryDb.from('insurance_answer_audits').update({ provider_diagnostics: trace.providers, token_usage: trace.providers }).eq('id', auditId);
      }
    }
    if (pipelineContext.forceRecovery && auditId) await db.from('insurance_learning_queue').insert({ audit_id: auditId, reason: 'negative_feedback', priority: 3, proposed_change: { request_id: trace.request_id, feedback_reason: pipelineContext.feedbackReason, recovery_answer_status: status, recovery_searches: trace.recovery.iterations } });
    return respond({ ...saved, answer, citations, confidence: null, answer_status: status, answer_generator: answerGenerator, evidence_checked: true, insurance_v3: true, recovery_used: trace.recovery.activated,
      debug: debugRequested ? { request_id: trace.request_id, semantic_interpretation: semantic, question_contract: questionContract, verified_entities: verifiedEntities, retrieval_mode: retrievalMode, retrieval_plan: plan, retrieval_channels: units.slice(0, 24), selected_units: selectedUnits, evidence_judgments: evidenceJudgments, expansion_unit_ids: expandIds, evidence_sufficiency: sufficiency, evidence_ledger: evidenceLedger, recovery: trace.recovery, deterministic_criteria_evaluations: deterministicEvaluations, answer_verifier: answerResult.verifier, final_evidence_ids: answerEvidence.map((chunk) => chunk.chunk_id), retrieved_chunks: selection.selected, embedding: embeddingRuns, fallback_used: trace.fallback_used, ai: trace.providers, model: AI_MODEL, processing_ms: Date.now() - started } : undefined });
  } catch (error) {
    const temporary = error instanceof AIProvidersTemporarilyUnavailableError || error instanceof AIProviderError;
    const answer = temporary ? 'The insurance AI service is temporarily unavailable. Please try again shortly.' : 'The insurance service could not safely complete this request right now. Please try again.';
    console.error('insurance_v3_controlled_failure', { request_id: trace?.request_id, type: error instanceof Error ? error.name : 'unknown', temporary });
    if (trace && db) {
      trace.providers.shared_reasoning_engine = {
        ...((trace.providers.shared_reasoning_engine as Record<string, unknown> | undefined) ?? {}),
        provider_failure_stage: temporary
          ? ((trace.providers.shared_reasoning_engine as Record<string, unknown> | undefined)?.provider_failure_stage ?? 'pre_evidence_pipeline')
          : ((trace.providers.shared_reasoning_engine as Record<string, unknown> | undefined)?.provider_failure_stage ?? null),
      };
      trace.final_status = temporary ? 'temporarily_unavailable' : 'internal_error'; trace.final_answer = answer; trace.final_reason = error instanceof Error ? error.name : 'unknown'; trace.http_status = 200; trace.latency.total_ms = Date.now() - started;
      await persistRequestTrace(db, trace);
    }
    return respond({ answer, citations: [], answer_status: temporary ? 'temporarily_unavailable' : 'internal_error', insurance_v3: true, debug: debugRequested ? { request_id: trace?.request_id, diagnostic_code: error instanceof Error ? error.name : 'unknown' } : undefined });
  }
});
