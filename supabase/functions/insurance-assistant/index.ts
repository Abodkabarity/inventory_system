import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import {
  advanceConversationContext,
  buildTurnContext,
  compactEvidence,
  createSearchPlan,
  debugTrace,
  filterEvidence,
  parseQuery,
  recoverContextFromMessages,
  type ConversationContext,
  type ResolvedQueryEntity,
  type SearchPlan,
  type SearchPlanOverrides,
  type SearchRow,
} from './logic.ts';
import { applyLocalNluInterpretation, interpretWithLocalNlu } from './local_nlu.ts';
import { composeVerifiedGroundedAnswer } from './grounded_answer.ts';
import {
  defaultLanguageConfiguration,
  mergePendingSlotReply,
  missingInformationClarification,
  understandQuery,
  type PendingSlotClarification,
} from './language_understanding.ts';
import { routeConversationalMessage } from './conversational_router.ts';
import type {
  EntityAliasMatch,
  LanguageAlias,
  IntentExample,
  LanguageConfiguration,
  UniversalQuery,
} from './query_model.ts';

// Supabase.ai is available in the hosted Edge Runtime. The local function
// runner may not provide that global, so local Ollama tests fall back to the
// existing exact/FTS/trigram retrieval instead of failing before NLU runs.
const embeddingModel = typeof Supabase !== 'undefined' && Supabase.ai?.Session
  ? new Supabase.ai.Session('gte-small')
  : null;

const defaultCorsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function corsHeadersFor(request: Request) {
  const configuredOrigins = Deno.env.get('INSURANCE_ASSISTANT_ALLOWED_ORIGIN')
    ?.split(',')
    .map((origin) => origin.trim())
    .filter(Boolean) ?? [];
  if (configuredOrigins.length === 0) return defaultCorsHeaders;
  const origin = request.headers.get('Origin') ?? '';
  return {
    'Access-Control-Allow-Origin': configuredOrigins.includes(origin) ? origin : 'null',
    'Access-Control-Allow-Headers': defaultCorsHeaders['Access-Control-Allow-Headers'],
  };
}

function responseJson(
  body: Record<string, unknown>,
  status = 200,
  corsHeaders = defaultCorsHeaders,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const legacyIntent: Record<string, string> = {
  eligibility_check: 'coverage',
  entity_definition: 'definition',
  age_eligibility: 'age',
  pregnancy: 'coverage',
  sex_eligibility: 'coverage',
  maximum_dose: 'dose',
  initial_dose: 'dose',
  maintenance: 'dose',
  dosage: 'dose',
  frequency: 'dose',
  dispensing_duration: 'supply_exception',
  quantity_limit: 'initial_dispensing',
  refill: 'initial_dispensing',
  dispensing_rules: 'initial_dispensing',
  authorization_requirements: 'approval',
  authorization_validity: 'approval',
  prior_authorization: 'approval',
  prescriber_specialty: 'prescriber',
  previous_treatment_duration: 'previous_therapy',
  treatment_failure: 'previous_therapy',
  step_therapy: 'previous_therapy',
  lab_recency: 'lab_recency',
  report_content: 'report_content',
  document_validation: 'document_validation',
  document_summary: 'document_summary',
  diagnostic_criteria: 'diagnostic_criteria',
  diagnosis: 'diagnosis',
  response_threshold: 'response_threshold',
  reassessment: 'reassessment',
  monitoring: 'monitoring',
  switching: 'switching',
  contraindication: 'contraindication',
  warning: 'warning',
  interaction: 'interaction',
  combination_therapy: 'combination_therapy',
  formulation: 'formulation',
  comparison: 'comparison',
  source_request: 'source_request',
};

const intentLabels: Record<string, string> = {
  documentation: 'Required documents',
  report_content: 'What the medical report should include',
  prior_authorization: 'Prior authorization',
  prescriber_specialty: 'Allowed prescriber specialty',
  dispensing_duration: 'Allowed dispensing duration',
  dosage: 'Dose and administration',
  coverage: 'Coverage or eligibility',
  eligibility_check: 'Patient eligibility check',
  switching: 'Switching requirements',
  refill: 'Refill rule',
};

function buildIntentClarificationCandidates(
  query: UniversalQuery,
  configuration: LanguageConfiguration,
) {
  if (query.canonicalPlan.intent !== 'unknown') return [];
  const seen = new Set<string>();
  return query.intentCandidates
    .filter((candidate) => candidate.intent !== 'unknown' && candidate.score >= 0.24)
    .flatMap((candidate) => {
      if (seen.has(candidate.intent)) return [];
      const example = configuration.examples.find((item) => item.id && item.intent === candidate.intent);
      if (!example?.id) return [];
      seen.add(candidate.intent);
      return [{
        candidate_id: example.id,
        intent: candidate.intent,
        entity_type: 'intent',
        canonical_name: intentLabels[candidate.intent]
          ?? candidate.intent.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase()),
        matched_alias: example.example_text,
        query_fragment: query.rawQuestion,
        similarity_score: candidate.score,
        language: query.language,
      }];
    })
    .slice(0, 3);
}

function searchPlanOverrides(query: UniversalQuery): SearchPlanOverrides {
  return {
    canonicalSearchQuery: query.canonicalPlan.canonicalSearchText,
    intent: legacyIntent[query.canonicalPlan.intent] ?? query.canonicalPlan.intent,
    patientAge: query.patient.age,
    strength: query.entities.strength
      ? `${query.entities.strength.value} ${query.entities.strength.unit ?? ''}`.trim()
      : null,
    treatmentMode: query.therapy.treatmentScope,
    conditionScope: /\bepisodic\b/i.test(query.normalizedQuestion) ? 'episodic'
      : /\bchronic\b/i.test(query.normalizedQuestion) ? 'chronic' : null,
    contextualFollowUp: query.isFollowUp,
    answerMode: query.answerMode,
    requestedCount: query.requestedCount,
  };
}

function resolvedMatch(entity: ResolvedQueryEntity | null): EntityAliasMatch[] {
  const canonicalName = typeof entity?.canonical_name === 'string' ? entity.canonical_name : null;
  if (!canonicalName) return [];
  const documentId = typeof entity?.document_id === 'string' ? entity.document_id : null;
  return [{
    entity_type: typeof entity?.entity_type === 'string' ? entity.entity_type : 'medication',
    canonical_name: canonicalName,
    normalized_entity: typeof entity?.normalized_entity === 'string'
      ? entity.normalized_entity : canonicalName.toLowerCase(),
    matched_alias: canonicalName,
    match_kind: 'exact',
    match_score: 1,
    document_ids: documentId ? [documentId] : [],
    metadata: {},
  }];
}

function retrievalEntityHint(plan: SearchPlan, resolvedEntity: ResolvedQueryEntity | null) {
  const entityHint = plan.inheritedEntityNormalized ?? plan.inheritedEntity;
  if (!entityHint) return null;
  const entityType = (resolvedEntity?.entity_type ?? '').toLowerCase();
  if (['topic', 'therapy_class', 'therapeutic_class', 'diagnosis', 'procedure'].includes(entityType)) {
    return null;
  }
  const normalizeScope = (value: string | null) => (value ?? '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '');
  const entityKey = normalizeScope(entityHint);
  const topicKey = normalizeScope(plan.topicHint);
  // A policy/class name is a topic constraint, not a medication constraint.
  // Keeping it as both would reject valid class-level chunks whose entity field
  // contains the document title instead of the short class alias (for example GLP-1).
  if (entityKey && topicKey && (entityKey.includes(topicKey) || topicKey.includes(entityKey))) {
    return null;
  }
  return entityHint;
}

async function loadLanguageConfiguration(
  supabase: ReturnType<typeof createClient>,
): Promise<LanguageConfiguration> {
  const defaults = defaultLanguageConfiguration();
  const [aliasesResult, examplesResult] = await Promise.all([
    supabase.from('insurance_language_aliases')
      .select('phrase,normalized_concept,alias_type,language,weight,metadata')
      .eq('status', 'active'),
    supabase.from('insurance_intent_examples')
      .select('id,intent,secondary_intents,language,example_text,normalized_text,weight,metadata')
      .eq('status', 'active'),
  ]);
  // During a rolling deployment the function may briefly precede the schema.
  // Built-in examples keep it operational; database examples enrich it once
  // the migration is present.
  return {
    aliases: [...defaults.aliases, ...((aliasesResult.data ?? []) as LanguageAlias[])],
    examples: [...defaults.examples, ...((examplesResult.data ?? []) as IntentExample[])],
  };
}

async function recoverConversationContext(
  supabase: ReturnType<typeof createClient>,
  sessionId: string,
  stored: ConversationContext,
) {
  if (stored.last_entity && stored.last_document_id
    && typeof stored.last_scope_provenance === 'string'
    && stored.last_scope_provenance.includes('verified')) return stored;
  // Pre-V6 cached scope has no provenance and may have been derived from a
  // wrong semantic neighbor. Ignore those cached scope keys at runtime while
  // preserving every chat message and all non-scope session data.
  const trustedBase: ConversationContext = {
    ...stored,
    last_entity: null,
    last_entity_normalized: null,
    last_intent: null,
    last_document_id: null,
    last_document_title: null,
    last_document_family: null,
    last_therapy_topic: null,
    last_evidence_ids: null,
  };
  const { data, error } = await supabase
    .from('insurance_chat_messages')
    .select('role,parsed_data,citations')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(12);
  if (error) throw error;
  return recoverContextFromMessages(trustedBase, data ?? []);
}

Deno.serve(async (request) => {
  const corsHeaders = corsHeadersFor(request);
  const respond = (body: Record<string, unknown>, status = 200) => responseJson(body, status, corsHeaders);
  if (request.method === 'OPTIONS') {
    return corsHeaders['Access-Control-Allow-Origin'] === 'null'
      ? new Response('Origin is not allowed.', { status: 403 })
      : new Response('ok', { headers: corsHeaders });
  }
  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) throw new Error('Authentication is required.');

    const body = await request.json();
    let message = String(body.message ?? '').trim();
    const branchName = String(body.branch_name ?? '').trim();
    const debugRequested = body.debug === true;
    let sessionId = body.session_id ? String(body.session_id) : null;
    const clarificationId = body.clarification_id ? String(body.clarification_id) : null;
    const candidateId = body.candidate_id ? String(body.candidate_id) : null;
    if (!message && !(clarificationId && candidateId)) throw new Error('Message is required.');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) throw new Error('Invalid user session.');

    let confirmationReplay = false;
    if (clarificationId && candidateId) {
      const { data: confirmed, error: confirmationError } = await supabase.rpc(
        'confirm_insurance_clarification_v1',
        { p_clarification_id: clarificationId, p_candidate_id: candidateId },
      );
      if (confirmationError) throw confirmationError;
      const confirmation = Array.isArray(confirmed) ? confirmed[0] : null;
      if (!confirmation) throw new Error('Clarification could not be confirmed.');
      message = String(confirmation.raw_query ?? '').trim();
      sessionId = String(confirmation.session_id ?? '').trim();
      confirmationReplay = true;
    }

    let conversationContext: ConversationContext = {};
    if (sessionId) {
      const { data: session, error } = await supabase
        .from('insurance_chat_sessions')
        .select('id, context')
        .eq('id', sessionId)
        .maybeSingle();
      if (error) throw error;
      if (!session) throw new Error('Conversation not found or access denied.');
      conversationContext = await recoverConversationContext(
        supabase,
        sessionId,
        (session.context ?? {}) as ConversationContext,
      );
    } else {
      const { data: session, error } = await supabase
        .from('insurance_chat_sessions')
        .insert({
          user_id: userData.user.id,
          branch_name: branchName || null,
          title: message.length > 64 ? `${message.slice(0, 61)}...` : message,
        })
        .select('id, context')
        .single();
      if (error) throw error;
      sessionId = session.id;
      conversationContext = (session.context ?? {}) as ConversationContext;
    }

    const rawPending = conversationContext.pending_clarification;
    const pendingClarification: PendingSlotClarification | null = rawPending
      && typeof rawPending === 'object'
      && typeof (rawPending as Record<string, unknown>).originalQuestion === 'string'
      && Array.isArray((rawPending as Record<string, unknown>).missingSlots)
      ? {
        originalQuestion: String((rawPending as Record<string, unknown>).originalQuestion),
        missingSlots: ((rawPending as Record<string, unknown>).missingSlots as unknown[]).map(String),
      }
      : null;
    const interpretationMessage = mergePendingSlotReply(message, pendingClarification) ?? message;

    // Application-defined conversation is routed before entity resolution,
    // embeddings, or document retrieval. These turns are stored for chat
    // history but deliberately leave the valid insurance context unchanged.
    const conversationalRoute = routeConversationalMessage(message);
    if (conversationalRoute) {
      const { error: userMessageError } = await supabase.from('insurance_chat_messages').insert({
        session_id: sessionId,
        role: 'user',
        message,
        parsed_data: {
          language: conversationalRoute.language,
          primary_intent: conversationalRoute.intent,
          conversational: true,
          retrieval_bypassed: true,
        },
      });
      if (userMessageError) throw userMessageError;

      const { data: assistantMessage, error: assistantError } = await supabase
        .from('insurance_chat_messages')
        .insert({
          session_id: sessionId,
          role: 'assistant',
          message: conversationalRoute.answer,
          parsed_data: {
            intent: conversationalRoute.intent,
            language: conversationalRoute.language,
            conversational: true,
            retrieval_bypassed: true,
            answer_status: 'answered',
          },
          citations: [],
          confidence: conversationalRoute.confidence,
        })
        .select('id, created_at')
        .single();
      if (assistantError) throw assistantError;

      await supabase.from('insurance_chat_sessions').update({
        updated_at: new Date().toISOString(),
      }).eq('id', sessionId);

      return respond({
        session_id: sessionId,
        message_id: assistantMessage.id,
        created_at: assistantMessage.created_at,
        answer: conversationalRoute.answer,
        confidence: conversationalRoute.confidence,
        intent: conversationalRoute.intent,
        conversational: true,
        retrieval_bypassed: true,
        evidence_checked: false,
        citations: [],
      });
    }

    // Language interpretation precedes entity routing. The adapter receives no
    // policy text and is validated below; its only output is structured meaning.
    const localNlu = await interpretWithLocalNlu(interpretationMessage, {
      entity: conversationContext.last_entity ?? null,
      document_family: conversationContext.last_document_family ?? null,
      topic: conversationContext.last_therapy_topic ?? null,
    });
    // Local test mode must make an unavailable model obvious. Production keeps
    // the conservative deterministic fallback unless this development-only
    // flag is explicitly enabled in the local env file.
    if (Deno.env.get('LOCAL_NLU_REQUIRED') === 'true' && localNlu.provider !== 'ollama') {
      throw new Error(
        `Local LLM is unavailable (${localNlu.failure ?? 'unknown failure'}). Check the local Edge Function terminal and Ollama service.`,
      );
    }
    const semantic = localNlu.interpretation;
    const resolverQuery = semantic?.entity
      ? `${semantic.entity}\n${interpretationMessage}`
      : interpretationMessage;
    let turnContext = buildTurnContext(conversationContext, {
      explicitNewEntity: semantic?.explicit_new_entity === true,
      isFollowUp: semantic?.is_followup === true,
    });
    const [{ data: resolvedEntities, error: resolverError }, languageConfiguration] = await Promise.all([
      supabase.rpc('resolve_insurance_query_context_v3', { query_text: resolverQuery }),
      loadLanguageConfiguration(supabase),
    ]);
    if (resolverError) throw resolverError;
    const resolvedEntity: ResolvedQueryEntity | null = Array.isArray(resolvedEntities)
      ? (resolvedEntities[0] as ResolvedQueryEntity)
      : null;
    // Resolver-confirmed entity names are equally authoritative for context
    // isolation when the optional local model is temporarily unavailable.
    if (typeof resolvedEntity?.canonical_name === 'string'
      && resolvedEntity.canonical_name.trim()
      && semantic?.is_followup !== true) {
      turnContext = buildTurnContext(conversationContext, {
        explicitNewEntity: true,
        isFollowUp: false,
      });
    }
    const hasResolvedDocument = typeof resolvedEntity?.document_id === 'string'
      && resolvedEntity.document_id.trim().length > 0;
    if (!hasResolvedDocument && !confirmationReplay) {
      const { data: fuzzyCandidates, error: suggestionError } = await supabase.rpc(
        'suggest_insurance_entity_aliases_v1',
        { query_text: interpretationMessage, result_limit: 3 },
      );
      if (suggestionError) throw suggestionError;
      const candidates = (Array.isArray(fuzzyCandidates) ? fuzzyCandidates : [])
        // Suggestions are not answers and never change routing by themselves.
        // A user must explicitly select the server-issued candidate before it
        // is learned, so this deliberately matches the guarded SQL floor.
        .filter((candidate) => Number(candidate.similarity_score ?? 0) >= 0.54)
        .map((candidate) => ({
          candidate_id: String(candidate.candidate_id),
          entity_type: String(candidate.entity_type),
          canonical_name: String(candidate.canonical_name),
          matched_alias: String(candidate.matched_alias),
          query_fragment: String(candidate.query_fragment),
          normalized_alias: String(candidate.normalized_alias),
          similarity_score: Number(candidate.similarity_score),
          document_ids: candidate.document_ids ?? [],
        }));
      if (candidates.length > 0) {
        const { data: clarification, error: clarificationError } = await supabase
          .from('insurance_clarification_requests')
          .insert({
            user_id: userData.user.id,
            session_id: sessionId,
            raw_query: message,
            clarification_kind: 'entity',
            candidates,
          })
          .select('id,expires_at')
          .single();
        if (clarificationError) throw clarificationError;
        const { error: userMessageError } = await supabase.from('insurance_chat_messages').insert({
          session_id: sessionId,
          role: 'user',
          message,
          parsed_data: { answer_status: 'clarification_required', unresolved_entity: true },
        });
        if (userMessageError) throw userMessageError;
        const names = candidates.map((candidate) => `**${candidate.canonical_name}**`).join(' or ');
        const clarificationAnswer = `I found a close match. Did you mean ${names}? Select the correct option and I will search the approved documents automatically.`;
        const { data: assistantMessage, error: assistantError } = await supabase
          .from('insurance_chat_messages')
          .insert({
            session_id: sessionId,
            role: 'assistant',
            message: clarificationAnswer,
            parsed_data: {
              answer_status: 'clarification_required',
              clarification_id: clarification.id,
              clarification_candidates: candidates,
            },
            citations: [],
            confidence: null,
          })
          .select('id,created_at')
          .single();
        if (assistantError) throw assistantError;
        return respond({
          session_id: sessionId,
          message_id: assistantMessage.id,
          created_at: assistantMessage.created_at,
          answer: clarificationAnswer,
          confidence: null,
          citations: [],
          answer_status: 'clarification_required',
          clarification: {
            id: clarification.id,
            expires_at: clarification.expires_at,
            candidates,
          },
        });
      }
    }
    const fallbackQuery = understandQuery({
      question: interpretationMessage,
      previousContext: turnContext.context,
      configuration: languageConfiguration,
      entityMatches: resolvedMatch(resolvedEntity),
    });
    const structuredQuery = applyLocalNluInterpretation(
      fallbackQuery,
      semantic,
      resolvedMatch(resolvedEntity),
    );
    const intentClarificationCandidates = confirmationReplay
      ? []
      : buildIntentClarificationCandidates(structuredQuery, languageConfiguration);
    if (intentClarificationCandidates.length > 1) {
      const { data: clarification, error: clarificationError } = await supabase
        .from('insurance_clarification_requests')
        .insert({
          user_id: userData.user.id,
          session_id: sessionId,
          raw_query: message,
          clarification_kind: 'intent',
          candidates: intentClarificationCandidates,
        })
        .select('id,expires_at')
        .single();
      if (clarificationError) throw clarificationError;

      const { error: userMessageError } = await supabase.from('insurance_chat_messages').insert({
        session_id: sessionId,
        role: 'user',
        message,
        parsed_data: {
          structured_query: structuredQuery,
          answer_status: 'clarification_required',
          unresolved_intent: true,
        },
      });
      if (userMessageError) throw userMessageError;

      const choices = intentClarificationCandidates
        .map((candidate) => `**${candidate.canonical_name}**`)
        .join(structuredQuery.language === 'ar' || structuredQuery.language === 'mixed' ? ' أو ' : ' or ');
      const clarificationAnswer = structuredQuery.language === 'ar' || structuredQuery.language === 'mixed'
        ? `فهمت الموضوع، لكن نوع المعلومة المطلوبة غير واضح. هل تقصد ${choices}؟`
        : `I understand the topic, but the requested information is ambiguous. Did you mean ${choices}?`;
      const { data: assistantMessage, error: assistantError } = await supabase
        .from('insurance_chat_messages')
        .insert({
          session_id: sessionId,
          role: 'assistant',
          message: clarificationAnswer,
          parsed_data: {
            answer_status: 'clarification_required',
            clarification_id: clarification.id,
            clarification_kind: 'intent',
            clarification_candidates: intentClarificationCandidates,
          },
          citations: [],
          confidence: null,
        })
        .select('id,created_at')
        .single();
      if (assistantError) throw assistantError;

      return respond({
        session_id: sessionId,
        message_id: assistantMessage.id,
        created_at: assistantMessage.created_at,
        answer: clarificationAnswer,
        confidence: null,
        citations: [],
        answer_status: 'clarification_required',
        clarification: {
          id: clarification.id,
          expires_at: clarification.expires_at,
          kind: 'intent',
          candidates: intentClarificationCandidates,
        },
      });
    }
    const missingInformation = missingInformationClarification(structuredQuery);
    if (missingInformation) {
      const { error: userMessageError } = confirmationReplay ? { error: null } : await supabase.from('insurance_chat_messages').insert({
        session_id: sessionId,
        role: 'user',
        message,
        parsed_data: {
          structured_query: structuredQuery,
          interpreted_question: interpretationMessage,
          answer_status: 'clarification_required',
          missing_slots: structuredQuery.canonicalPlan.missingSlots,
          canonical_plan: structuredQuery.canonicalPlan,
        },
      });
      if (userMessageError) throw userMessageError;

      const { data: assistantMessage, error: assistantError } = await supabase
        .from('insurance_chat_messages')
        .insert({
          session_id: sessionId,
          role: 'assistant',
          message: missingInformation,
          parsed_data: {
            structured_query: structuredQuery,
            answer_status: 'clarification_required',
            clarification_kind: 'missing_patient_information',
            missing_slots: structuredQuery.canonicalPlan.missingSlots,
            canonical_plan: structuredQuery.canonicalPlan,
          },
          citations: [],
          confidence: null,
        })
        .select('id, created_at')
        .single();
      if (assistantError) throw assistantError;

      await supabase.from('insurance_chat_sessions').update({
        updated_at: new Date().toISOString(),
        context: {
          ...turnContext.context,
          pending_clarification: {
            originalQuestion: interpretationMessage,
            missingSlots: structuredQuery.canonicalPlan.missingSlots,
          },
        },
      }).eq('id', sessionId);

      return respond({
        session_id: sessionId,
        message_id: assistantMessage.id,
        created_at: assistantMessage.created_at,
        answer: missingInformation,
        confidence: null,
        citations: [],
        answer_status: 'clarification_required',
        clarification: {
          kind: 'missing_patient_information',
          missing_slots: structuredQuery.canonicalPlan.missingSlots,
        },
      });
    }
    const plan = createSearchPlan(
      interpretationMessage,
      turnContext.context,
      resolvedEntity,
      searchPlanOverrides(structuredQuery),
    );
    const { error: userMessageError } = confirmationReplay ? { error: null } : await supabase.from('insurance_chat_messages').insert({
      session_id: sessionId,
      role: 'user',
      message,
      parsed_data: {
        structured_query: structuredQuery,
        language: structuredQuery.language,
        primary_intent: structuredQuery.primaryIntent,
        answer_mode: structuredQuery.answerMode,
        requested_count: structuredQuery.requestedCount,
        secondary_intents: structuredQuery.secondaryIntents,
        intent: plan.intent,
        patient_age: plan.patientAge,
        strength: plan.strength,
        treatment_mode: plan.treatmentMode,
        condition_scope: plan.conditionScope,
        explicit_medication: plan.explicitEntity ? plan.inheritedEntity : null,
        therapy_topic: plan.therapyTopic,
        resolved_document_id: plan.documentId,
        inherited_medication: plan.inheritedEntity,
        contextual_follow_up: plan.contextualFollowUp,
      },
    });
    if (userMessageError) throw userMessageError;

    // Retrieve before asking for clarification. An apparently context-free
    // question can still name a policy class (for example, "CGRP inhibitors")
    // that is resolved against the returned document titles in parseQuery.
    let queryEmbedding: number[] | null = null;
    if (embeddingModel) {
      try {
        queryEmbedding = await embeddingModel.run(plan.searchQuery, {
          mean_pool: true,
          normalize: true,
        });
      } catch {
        // Keep the local test and a temporary embedding-service outage safely
        // operational through lexical retrieval. Do not log the query text.
        console.warn('insurance_embedding_unavailable_using_lexical_retrieval');
      }
    }
    const { data, error: searchError } = await supabase.rpc('search_insurance_knowledge_v11', {
      query_text: plan.searchQuery,
      query_embedding: queryEmbedding,
      result_limit: 24,
      active_only: true,
      entity_hint: retrievalEntityHint(plan, resolvedEntity),
      document_hint: plan.documentId,
      intent_hint: plan.intent,
      topic_hint: plan.topicHint,
      document_family_hint: plan.documentFamily,
      include_neighbors: plan.answerMode !== 'single_fact'
        || ['report_content', 'documentation', 'lab_requirement'].includes(plan.intent),
      section_hint: structuredQuery.canonicalPlan.requestedFields.join(' ')
        || structuredQuery.canonicalPlan.intent,
    });
    if (searchError) throw searchError;
    const retrievedRows = (data ?? []) as SearchRow[];

    const parsed = parseQuery(interpretationMessage, retrievedRows, plan);
    const evidenceRows = filterEvidence(retrievedRows, parsed);
    const result = await composeVerifiedGroundedAnswer({
      query: interpretationMessage,
      parsed,
      structuredQuery,
      rows: evidenceRows,
      previousTopic: typeof turnContext.context.last_therapy_topic === 'string'
        ? turnContext.context.last_therapy_topic : null,
    });
    const usedEvidenceIds = new Set(result.usedEvidenceIds);
    const citationRows = evidenceRows.filter((row) => usedEvidenceIds.has(row.chunk_id))
      .filter((row, index, all) => {
      const key = [
        row.document_id,
        row.page_from ?? '',
        row.sheet_name ?? '',
        row.row_from ?? '',
        row.section_title ?? '',
      ].join(':');
      return all.findIndex((candidate) => [
        candidate.document_id,
        candidate.page_from ?? '',
        candidate.sheet_name ?? '',
        candidate.row_from ?? '',
        candidate.section_title ?? '',
      ].join(':') === key) === index;
      });
    const citations = citationRows.map((row) => ({
      chunk_id: row.chunk_id,
      document_id: row.document_id,
      document_title: row.document_title,
      file_name: row.file_name,
      storage_bucket: row.storage_bucket,
      storage_path: row.storage_path,
      section_title: row.section_title,
      page_from: row.page_from,
      page_to: row.page_to,
      sheet_name: row.sheet_name,
      row_from: row.row_from,
      row_to: row.row_to,
      entity_type: row.entity_type,
      entity_name: row.entity_name,
      excerpt: row.matched_content.slice(0, 1600),
      concise_excerpt: compactEvidence(row.matched_content, interpretationMessage),
      score: row.combined_score,
    }));

    const { data: assistantMessage, error: assistantError } = await supabase
      .from('insurance_chat_messages')
      .insert({
        session_id: sessionId,
        role: 'assistant',
        message: result.answer,
        parsed_data: {
          structured_query: structuredQuery,
          language: structuredQuery.language,
          primary_intent: structuredQuery.primaryIntent,
          secondary_intents: structuredQuery.secondaryIntents,
          intent: parsed.intent,
          medication: parsed.entity,
          patient_age: parsed.patientAge,
          strength: parsed.strength,
          treatment_mode: parsed.treatmentMode,
          condition_scope: parsed.conditionScope,
          therapy_topic: parsed.therapyTopic,
          time_period_hours: parsed.timePeriodHours,
          inherited_context: parsed.inheritedContext,
          decision_scope: parsed.intent === 'age' ? 'age_criterion_only' : null,
          answer_status: result.answerStatus,
          generation: result.generation,
          verified_claims: result.claims,
          used_evidence_ids: result.usedEvidenceIds,
        },
        citations,
        confidence: result.confidence,
      })
      .select('id, created_at')
      .single();
    if (assistantError) throw assistantError;

    const verifiedIds = new Set(evidenceRows.map((row) => row.chunk_id));
    // `completeness` is mandatory for the audit table. Keep this defensive
    // normalization at the API boundary so an older composer response can
    // never turn a valid, already-saved answer into a 400 error.
    const completeness = result.completeness ?? {
      complete: result.answerStatus === 'answered',
      expected: parsed.requestedCount ?? null,
      found: result.usedEvidenceIds.length,
      required_facets: [],
      covered_facets: [],
      missing_information: [],
    };
    const answerStatus = result.answerStatus;
    const candidateSummary = (row: SearchRow) => ({
      chunk_id: row.chunk_id,
      document_id: row.document_id,
      entity_name: row.entity_name,
      accepted_by_retrieval: row.accepted,
      acceptance_reason: row.acceptance_reason,
      scores: {
        lexical: row.lexical_score,
        semantic: row.semantic_score,
        entity: row.entity_score,
        intent: row.intent_score,
        context: row.context_score,
        combined: row.combined_score,
      },
    });
    const { data: audit, error: auditError } = await supabase.from('insurance_answer_audits').insert({
      session_id: sessionId,
      message_id: assistantMessage.id,
      raw_question: message,
      structured_query: structuredQuery,
      retrieval_plan: plan,
      retrieved_candidates: retrievedRows.map(candidateSummary),
      verified_evidence: evidenceRows.map(candidateSummary),
      rejected_candidates: retrievedRows
        .filter((row) => !verifiedIds.has(row.chunk_id))
        .map(candidateSummary),
      answer_status: answerStatus,
      confidence: {
        ...structuredQuery.confidence,
        answer: result.confidence,
        generation: result.generation,
        used_evidence_ids: result.usedEvidenceIds,
        verified_claims: result.claims,
      },
      completeness,
    }).select('id').maybeSingle();
    if (auditError) {
      console.error('insurance_answer_audit_failed', {
        session_id: sessionId,
        message_id: assistantMessage.id,
        error: auditError.message,
      });
      // The answer and citations are already persisted and verified. An
      // observability failure must be visible in server logs, but must not
      // make the user resend the question or create duplicate chat turns.
    }
    if (audit?.id && ['insufficient_evidence', 'partial'].includes(answerStatus)) {
      const { error: learningError } = await supabase.from('insurance_learning_queue').insert({
        audit_id: audit.id,
        reason: structuredQuery.primaryIntent === 'unknown'
          ? 'unknown_intent'
          : structuredQuery.unresolved.includes('entity')
          ? 'unresolved_entity'
          : 'insufficient_evidence',
        priority: 2,
        proposed_change: {
          language: structuredQuery.language,
          primary_intent: structuredQuery.primaryIntent,
          unresolved: structuredQuery.unresolved,
          generation: result.generation,
          completeness,
        },
      });
      if (learningError) console.error('insurance_learning_queue_failed', learningError.message);
    }

    const usedEvidence = evidenceRows.filter((row) => usedEvidenceIds.has(row.chunk_id));
    const nextContext = advanceConversationContext(turnContext.context, {
      parsed,
      plan,
      answerStatus,
      confidence: result.confidence,
      usedEvidence,
      evidenceIds: result.usedEvidenceIds,
      language: structuredQuery.language,
    });
    await supabase
      .from('insurance_chat_sessions')
      .update({
        updated_at: new Date().toISOString(),
        context: {
          ...nextContext,
          schema_version: 1,
          primary_intent: structuredQuery.primaryIntent,
          secondary_intents: structuredQuery.secondaryIntents,
          patient: structuredQuery.patient,
          therapy: structuredQuery.therapy,
          dispensing: structuredQuery.dispensing,
          provider: structuredQuery.provider,
          modifiers: structuredQuery.modifiers,
          pending_clarification: null,
        },
      })
      .eq('id', sessionId);

    let debug: (ReturnType<typeof debugTrace> & {
      nlu_inspector: {
        raw: string;
        interpreted: string;
        normalized: string;
        entity: string | null;
        intent: string;
        answer_mode: string;
        slots: UniversalQuery['canonicalPlan']['conditions'];
        missing: string[];
        canonical_search: string;
        confidence: UniversalQuery['confidence'];
        provider: string;
        local_nlu_failure?: string;
        context_before: ConversationContext;
        context_cleared: string[];
      };
      final_answer: string;
      final_confidence: number | null;
    }) | undefined;
    if (debugRequested) {
      const { data: isAdmin } = await supabase.rpc('is_insurance_knowledge_admin');
      if (isAdmin === true) {
        debug = {
          ...debugTrace(interpretationMessage, parsed, retrievedRows, plan),
          nlu_inspector: {
            raw: message,
            interpreted: interpretationMessage,
            normalized: structuredQuery.normalizedQuestion,
            entity: structuredQuery.canonicalPlan.primaryEntity,
            intent: structuredQuery.canonicalPlan.intent,
            answer_mode: structuredQuery.canonicalPlan.answerMode,
            slots: structuredQuery.canonicalPlan.conditions,
            missing: structuredQuery.canonicalPlan.missingSlots,
            canonical_search: structuredQuery.canonicalPlan.canonicalSearchText,
            confidence: structuredQuery.confidence,
            provider: localNlu.provider,
            ...(localNlu.failure ? { local_nlu_failure: localNlu.failure } : {}),
            context_before: turnContext.contextBefore,
            context_cleared: turnContext.clearedKeys,
          },
          final_answer: result.answer,
          final_confidence: result.confidence,
        };
      }
    }

    return respond({
      session_id: sessionId,
      message_id: assistantMessage.id,
      created_at: assistantMessage.created_at,
      answer: result.answer,
      confidence: result.confidence,
      intent: result.intent,
      medication: parsed.entity,
      patient_age: parsed.patientAge,
      strength: parsed.strength,
      therapy_topic: parsed.therapyTopic,
      answer_mode: parsed.answerMode,
      requested_count: parsed.requestedCount,
      completeness,
      citations,
      answer_status: answerStatus,
      generation: result.generation,
      ...(debug ? { debug } : {}),
    });
  } catch (error) {
    return respond(
      { error: error instanceof Error ? error.message : String(error) },
      400,
    );
  }
});
