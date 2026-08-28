import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2.57.4';
import { generateAnswer, repairAnswer, safeGroundedAnswer } from './answer.ts';
import { evaluateExplicitNumericCriteria } from './criteria.ts';
import { compactCandidates, persistAudit } from './diagnostics.ts';
import { buildEvidencePacket, citationsFor } from './evidence.ts';
import { buildFactManifest } from './fact_binding.ts';
import { expandVerifiedMedicationRelations, retrieveEvidenceCandidates, resolveEntities } from './retrieval.ts';
import { applyPolicyEntityRouteGuard, applyVerifiedEntityAmbiguityGuard, interpretQuestion } from './semantic.ts';
import type { Citation, EvidenceBlock, JsonMap, ProviderUsage, SemanticRequest } from './types.ts';
import { validateAnswer } from './validation.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const respond = (body: JsonMap, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, 'Content-Type': 'application/json' },
});

function languageMessage(language: SemanticRequest['language'], kind: 'insufficient' | 'temporary' | 'conversation') {
  const arabic = language === 'ar' || language === 'mixed';
  if (kind === 'temporary') return arabic
    ? 'الخدمة الذكية غير متاحة مؤقتًا، لذلك لم أعتبر تعطل المزود دليلًا على غياب المعلومة. يرجى إعادة المحاولة.'
    : 'The reasoning service is temporarily unavailable, so provider failure was not treated as missing policy evidence. Please retry.';
  if (kind === 'conversation') return arabic ? 'مرحبًا، كيف يمكنني مساعدتك في وثائق التأمين المعتمدة؟' : 'Hello. How can I help with the approved insurance documents?';
  return arabic
    ? 'بعد البحث في القنوات المباشرة والنصية والدلالية وسياق الوثائق المعتمدة، لم أجد دليلًا يثبت المعلومة المطلوبة.'
    : 'After direct, lexical, semantic, and document-context retrieval across the approved sources, I did not find evidence establishing the requested information.';
}

function jsonRows(value: unknown): JsonMap[] {
  return Array.isArray(value) ? value.filter((item): item is JsonMap => !!item && typeof item === 'object' && !Array.isArray(item)) : [];
}

async function saveConversation(
  db: SupabaseClient,
  body: JsonMap,
  question: string,
  answer: string,
  citations: Citation[],
  parsedData: JsonMap,
  deepReview: boolean,
) {
  let sessionId = typeof body.session_id === 'string' ? body.session_id : null;
  if (!sessionId) {
    const { data, error } = await db.from('insurance_chat_sessions').insert({
      branch_name: String(body.branch_name ?? ''),
      title: question.slice(0, 80),
    }).select('id').single();
    if (error) throw new Error(`Unable to create conversation: ${error.message}`);
    sessionId = String(data.id);
  }
  if (!deepReview) {
    const { error } = await db.from('insurance_chat_messages').insert({ session_id: sessionId, role: 'user', message: question, parsed_data: parsedData });
    if (error) throw new Error(`Unable to save the user message: ${error.message}`);
  }
  const { data, error } = await db.from('insurance_chat_messages').insert({
    session_id: sessionId,
    role: 'assistant',
    message: answer,
    citations,
    parsed_data: parsedData,
  }).select('id,created_at').single();
  if (error) throw new Error(`Unable to save the assistant message: ${error.message}`);
  await db.from('insurance_chat_sessions').update({ updated_at: new Date().toISOString() }).eq('id', sessionId);
  return { session_id: sessionId, message_id: String(data.id), created_at: String(data.created_at) };
}

async function saveFeedback(db: SupabaseClient, userId: string, messageId: string, rating: 1 | -1, reason?: string) {
  const record: JsonMap = { message_id: messageId, user_id: userId, rating, updated_at: new Date().toISOString() };
  if (reason) record.reason = reason;
  const { error } = await db.from('insurance_feedback').upsert(record, { onConflict: 'message_id,user_id' });
  if (error) throw new Error(`Unable to record feedback: ${error.message}`);
}

function mergeIncompleteEvidence(current: EvidenceBlock[], prior: unknown) {
  const previous = jsonRows(prior) as unknown as EvidenceBlock[];
  const merged = new Map<string, EvidenceBlock>();
  for (const block of [...previous, ...current]) {
    if (!block || typeof block !== 'object' || !block.search_unit_id || !block.text) continue;
    merged.set(block.search_unit_id, block);
  }
  return [...merged.values()].slice(0, 8).map((block, index) => ({ ...block, id: `E${index + 1}` }));
}

async function medicationCatalog(db: SupabaseClient, hasExplicitMedication: boolean) {
  if (!hasExplicitMedication) return [];
  const { data, error } = await db.from('insurance_v3_entities')
    .select('canonical_name')
    .in('entity_type', ['medication_brand', 'medication_generic'])
    .eq('active', true)
    .limit(2000);
  if (error) return [];
  return (Array.isArray(data) ? data : []).map((row: JsonMap) => String(row.canonical_name));
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return respond({ error: 'Method not allowed.' }, 405);

  const started = Date.now();
  const requestId = crypto.randomUUID();
  let db: SupabaseClient | null = null;
  let userId = '';
  let body: JsonMap = {};
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return respond({ error: 'Authentication required.' }, 401);
    db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: auth, error: authError } = await db.auth.getUser(authorization.slice(7));
    if (authError || !auth.user) return respond({ error: 'Authentication required.' }, 401);
    userId = auth.user.id;
    body = await request.json() as JsonMap;

    if (typeof body.positive_feedback_message_id === 'string') {
      await saveFeedback(db, userId, body.positive_feedback_message_id, 1);
      return respond({ recorded: true, insurance_v4: true });
    }

    const feedbackMessageId = typeof body.feedback_message_id === 'string' ? body.feedback_message_id : null;
    const allowedReasons = new Set(['incorrect', 'incomplete', 'misunderstood']);
    const feedbackReason = allowedReasons.has(String(body.feedback_reason)) ? String(body.feedback_reason) : feedbackMessageId ? 'incorrect' : null;
    let deepReview = false;
    let priorAnswer = '';
    let priorEvidence: unknown = [];
    let deepReviewOfMessageId: string | null = null;
    let question = typeof body.message === 'string' ? body.message.trim() : '';

    if (feedbackMessageId) {
      const { data: assistant, error } = await db.from('insurance_chat_messages')
        .select('id,session_id,message,created_at,parsed_data')
        .eq('id', feedbackMessageId).eq('role', 'assistant').single();
      if (error || !assistant) return respond({ error: 'The feedback message was not found.' }, 404);
      await saveFeedback(db, userId, feedbackMessageId, -1, feedbackReason ?? 'incorrect');
      const { data: audit } = await db.from('insurance_v4_answer_audits')
        .select('deep_review,evidence_packet,raw_question')
        .eq('message_id', feedbackMessageId).order('created_at', { ascending: false }).limit(1).maybeSingle();
      const { data: existingReview } = await db.from('insurance_v4_answer_audits')
        .select('id').eq('deep_review_of_message_id', feedbackMessageId).limit(1).maybeSingle();
      if (audit?.deep_review === true || existingReview) return respond({ recovery_exhausted: true, insurance_v4: true });
      const { data: userMessage } = await db.from('insurance_chat_messages')
        .select('message').eq('session_id', assistant.session_id).eq('role', 'user')
        .lte('created_at', assistant.created_at).order('created_at', { ascending: false }).limit(1).maybeSingle();
      question = String(userMessage?.message ?? audit?.raw_question ?? '').trim();
      if (!question) return respond({ error: 'The original question was not found.' }, 409);
      body = { ...body, session_id: assistant.session_id };
      deepReview = true;
      priorAnswer = String(assistant.message ?? '');
      priorEvidence = audit?.evidence_packet ?? [];
      deepReviewOfMessageId = feedbackMessageId;
    }

    if (!question) return respond({ error: 'A non-empty message is required.' }, 400);
    if (question.length > 6000) return respond({ error: 'The message is too long.' }, 400);

    const providerUsage: ProviderUsage[] = [];
    const latency: JsonMap = {};
    const semanticStarted = Date.now();
    const interpretation = await interpretQuestion(question, deepReview ? { reason: feedbackReason!, priorAnswer } : undefined);
    latency.semantic_ms = Date.now() - semanticStarted;
    if (interpretation.provider) providerUsage.push(interpretation.provider);
    let semantic = applyPolicyEntityRouteGuard(interpretation.semantic);

    if (semantic.route === 'conversation') {
      const answer = semantic.direct_response ?? languageMessage(semantic.language, 'conversation');
      const status = 'conversation';
      const saved = await saveConversation(db, body, question, answer, [], { semantic, insurance_v4: true, recovery_depth: deepReview ? 1 : 0 }, deepReview);
      latency.total_ms = Date.now() - started;
      await persistAudit(db, {
        request_id: requestId, user_id: userId, session_id: saved.session_id, message_id: saved.message_id,
        deep_review_of_message_id: deepReviewOfMessageId, raw_question: question, interpretation: semantic as unknown as JsonMap,
        resolved_entities: [], generated_search_queries: semantic.search_queries, retrieval_channels: [], top_candidates: [], evidence_packet: [],
        final_answer: answer, final_citations: [], validation_checks: { valid: true }, provider_usage: providerUsage, latency,
        feedback_reason: feedbackReason, deep_review: deepReview, answer_status: status, candidate_count: 0, evidence_count: 0,
        normal_reasoning_calls: 1,
      });
      return respond({ ...saved, answer, citations: [], answer_status: status, evidence_checked: false, insurance_v4: true,
        debug: body.debug === true ? { request_id: requestId, semantic_interpretation: semantic, ai: providerUsage, processing_ms: latency.total_ms } : undefined });
    }

    const retrievalStarted = Date.now();
    let entities = await resolveEntities(db, semantic, question);
    semantic = applyVerifiedEntityAmbiguityGuard(semantic, entities);
    if (semantic.route === 'ambiguous') {
      const answer = semantic.ambiguity_question ?? (semantic.language === 'ar' ? 'يرجى توضيح المقصود في سؤالك.' : 'Please clarify what you mean in your question.');
      const saved = await saveConversation(db, body, question, answer, [], { semantic, insurance_v4: true, recovery_depth: deepReview ? 1 : 0 }, deepReview);
      latency.retrieval_ms = Date.now() - retrievalStarted;
      latency.total_ms = Date.now() - started;
      await persistAudit(db, {
        request_id: requestId, user_id: userId, session_id: saved.session_id, message_id: saved.message_id,
        deep_review_of_message_id: deepReviewOfMessageId, raw_question: question, interpretation: semantic as unknown as JsonMap,
        resolved_entities: [], generated_search_queries: semantic.search_queries, retrieval_channels: ['verified_entity'], top_candidates: [], evidence_packet: [],
        final_answer: answer, final_citations: [], validation_checks: { valid: true }, provider_usage: providerUsage, latency,
        feedback_reason: feedbackReason, deep_review: deepReview, answer_status: 'clarification_required', candidate_count: 0, evidence_count: 0,
        normal_reasoning_calls: 1,
      });
      return respond({ ...saved, answer, citations: [], answer_status: 'clarification_required', evidence_checked: true, insurance_v4: true,
        debug: body.debug === true ? { request_id: requestId, semantic_interpretation: semantic, verified_entities: [], ai: providerUsage, processing_ms: latency.total_ms } : undefined });
    }
    entities = await expandVerifiedMedicationRelations(db, entities);
    const retrieval = await retrieveEvidenceCandidates(db, question, semantic, entities, deepReview);
    let packet = await buildEvidencePacket(db, retrieval.candidates, semantic, entities);
    if (deepReview && feedbackReason === 'incomplete') packet = mergeIncompleteEvidence(packet, priorEvidence);
    latency.retrieval_ms = Date.now() - retrievalStarted;

    if (!packet.length) {
      const temporary = interpretation.degraded;
      const answer = languageMessage(semantic.language, temporary ? 'temporary' : 'insufficient');
      const status = temporary ? 'temporarily_unavailable' : 'insufficient_evidence';
      const saved = await saveConversation(db, body, question, answer, [], { semantic, verified_entities: entities, insurance_v4: true, recovery_depth: deepReview ? 1 : 0 }, deepReview);
      latency.total_ms = Date.now() - started;
      await persistAudit(db, {
        request_id: requestId, user_id: userId, session_id: saved.session_id, message_id: saved.message_id,
        deep_review_of_message_id: deepReviewOfMessageId, raw_question: question, interpretation: semantic as unknown as JsonMap,
        resolved_entities: entities, generated_search_queries: retrieval.diagnostics.generated_queries,
        retrieval_channels: retrieval.diagnostics.channels, top_candidates: compactCandidates(retrieval.candidates as unknown as JsonMap[]), evidence_packet: [],
        final_answer: answer, final_citations: [], validation_checks: { valid: true }, provider_usage: providerUsage, latency,
        feedback_reason: feedbackReason, deep_review: deepReview, answer_status: status, candidate_count: retrieval.candidates.length,
        evidence_count: 0, normal_reasoning_calls: 1,
      });
      return respond({ ...saved, answer, citations: [], answer_status: status, evidence_checked: true, insurance_v4: true,
        debug: body.debug === true ? { request_id: requestId, semantic_interpretation: semantic, verified_entities: entities, retrieval: retrieval.diagnostics, ai: providerUsage, processing_ms: latency.total_ms } : undefined });
    }

    const hasExplicitMedication = entities.some((entity) => entity.entity_type === 'medication_brand' || entity.entity_type === 'medication_generic');
    const catalog = await medicationCatalog(db, hasExplicitMedication);
    const factManifest = buildFactManifest(packet, entities, catalog, question);
    const criteria = evaluateExplicitNumericCriteria(question, packet);
    const answerStarted = Date.now();
    let draft = await generateAnswer(question, semantic, entities, packet, criteria, factManifest);
    if (draft.provider) providerUsage.push(draft.provider);
    let validation = validateAnswer({
      answer: draft.answer, usedEvidenceIds: draft.used_evidence_ids, question, semantic, entities, packet, medicationCatalog: catalog, criteria, factManifest,
    });
    const validationAttempts = [{ stage: 'draft', ...validation }];
    let repaired = false;
    if (!validation.valid && !draft.extractive_fallback) {
      draft = await repairAnswer(question, semantic, entities, packet, criteria, factManifest, draft.answer, validation.errors);
      repaired = true;
      if (draft.provider) providerUsage.push(draft.provider);
      validation = validateAnswer({
        answer: draft.answer, usedEvidenceIds: draft.used_evidence_ids, question, semantic, entities, packet, medicationCatalog: catalog, criteria, factManifest,
      });
      validationAttempts.push({ stage: 'repair', ...validation });
    }
    if (!validation.valid) {
      const safe = safeGroundedAnswer(question, semantic, entities, packet, factManifest, criteria);
      draft = {
        answer: safe.answer, used_evidence_ids: safe.used_evidence_ids, provider: null, extractive_fallback: true,
      };
      validation = validateAnswer({ answer: draft.answer, usedEvidenceIds: draft.used_evidence_ids, question, semantic, entities, packet, medicationCatalog: [], criteria, factManifest });
      validationAttempts.push({ stage: 'extractive', ...validation });
    }
    latency.answer_ms = Date.now() - answerStarted;
    const citations = citationsFor(packet, validation.used_evidence_ids.length ? validation.used_evidence_ids : draft.used_evidence_ids);
    const status = draft.extractive_fallback ? 'grounded_extractive' : 'grounded';
    const parsedData: JsonMap = {
      semantic, verified_entities: entities, insurance_v4: true, answer_status: status,
      answer_generator: draft.extractive_fallback ? 'deterministic_extractive' : providerUsage.at(-1)?.provider,
      entity_fact_guard: factManifest.target_medications.length > 0,
      recovery_depth: deepReview ? 1 : 0,
    };
    const saved = await saveConversation(db, body, question, draft.answer, citations, parsedData, deepReview);
    latency.total_ms = Date.now() - started;
    await persistAudit(db, {
      request_id: requestId, user_id: userId, session_id: saved.session_id, message_id: saved.message_id,
      deep_review_of_message_id: deepReviewOfMessageId, raw_question: question, interpretation: semantic as unknown as JsonMap,
      resolved_entities: entities, generated_search_queries: retrieval.diagnostics.generated_queries,
      retrieval_channels: retrieval.diagnostics.channels, top_candidates: compactCandidates(retrieval.candidates as unknown as JsonMap[]),
      evidence_packet: packet, final_answer: draft.answer, final_citations: citations,
      validation_checks: { ...validation, repaired, attempts: validationAttempts, entity_fact_binding: factManifest }, provider_usage: providerUsage, latency,
      feedback_reason: feedbackReason, deep_review: deepReview, answer_status: status,
      candidate_count: retrieval.candidates.length, evidence_count: packet.length,
      normal_reasoning_calls: 2 + (repaired ? 1 : 0),
    });
    return respond({ ...saved, answer: draft.answer, citations, confidence: null, answer_status: status,
      answer_generator: parsedData.answer_generator, evidence_checked: true, insurance_v4: true, recovery_used: deepReview,
      debug: body.debug === true ? { request_id: requestId, semantic_interpretation: semantic, verified_entities: entities,
        retrieval: retrieval.diagnostics, selected_evidence: packet, entity_fact_binding: factManifest, deterministic_criteria: criteria, validation,
        validation_attempts: validationAttempts, ai: providerUsage, processing_ms: latency.total_ms } : undefined });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('insurance_policy_v4_failed', { request_id: requestId, name: error instanceof Error ? error.name : 'unknown' });
    const answer = /[\u0600-\u06ff]/.test(String(body.message ?? ''))
      ? 'تعذر إكمال الطلب مؤقتًا بسبب خطأ داخلي. لم يُفسَّر هذا الخطأ على أنه غياب للمعلومة التأمينية.'
      : 'The request could not be completed because of a temporary internal error. This was not interpreted as missing insurance evidence.';
    return respond({ answer, citations: [], answer_status: 'internal_error', insurance_v4: true,
      debug: body.debug === true ? { request_id: requestId, diagnostic_code: error instanceof Error ? error.name : 'unknown', message: message.slice(0, 300), processing_ms: Date.now() - started } : undefined }, 500);
  }
});
