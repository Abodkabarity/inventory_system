import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.57.4";
import { AgenticToolExecutor } from "./agentic_tools.ts";
import { runAgenticLoop } from "./agentic_loop.ts";
import { ProvidersUnavailableError } from "./ai.ts";
import {
  contextForModel,
  loadContextEnvelope,
  saveConversationTurn,
} from "./conversation.ts";
import { validateAgenticResult } from "./safety_validators.ts";
import { citationsFor } from "./structural.ts";
import type {
  AgenticFinal,
  AgenticToolCallTrace,
  EvidenceBlock,
  JsonMap,
  ProviderUsage,
  SearchCandidate,
} from "./types.ts";

const ENGINE_VERSION = "simple-v45-agentic-deep-review";
const REQUEST_BUDGET_MS = 138_000;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function respond(body: JsonMap, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function remaining(started: number, reserve = 10_000) {
  return Math.max(
    1_500,
    Math.min(36_000, REQUEST_BUDGET_MS - (Date.now() - started) - reserve),
  );
}

function arabic(question: string) {
  return /\p{Script=Arabic}/u.test(question);
}

function safeMessage(
  question: string,
  kind: "temporary" | "insufficient" | "clarify" | "conflict",
  final?: AgenticFinal | null,
) {
  const ar = arabic(question);
  if (kind === "temporary") {
    return ar
      ? "خدمة التحليل الذكي غير متاحة مؤقتًا. لم أعتبر تعطل المزود دليلًا على غياب المعلومة؛ يرجى إعادة المحاولة."
      : "The reasoning service is temporarily unavailable. Provider failure was not treated as missing policy evidence; please retry.";
  }
  if (kind === "clarify") {
    return final?.interpretation.clarification_question ||
      (ar
        ? "يلزم توضيح الكيان أو الاستطباب الذي تقصده لأن الإجابة تختلف بصورة جوهرية."
        : "Please clarify the intended entity or indication because the policy answer materially differs.");
  }
  if (kind === "conflict") {
    return final?.answer ||
      (ar
        ? "توجد أدلة معتمدة متعارضة ولم تسمح بيانات المصدر بتحديد المرجع الحاكم بأمان."
        : "Approved evidence conflicts, and source metadata does not safely establish which source governs.");
  }
  return final?.answer ||
    (ar
      ? "لم أجد في الأدلة المعتمدة المباشرة ما يكفي لإثبات العلاقة المطلوبة."
      : "The direct approved evidence retrieved was not sufficient to establish the requested relationship.");
}

function compactCandidates(candidates: SearchCandidate[]) {
  return candidates.slice(0, 36).map((candidate) => ({
    search_unit_id: candidate.search_unit_id,
    document_id: candidate.document_id,
    document_title: candidate.document_title,
    page_from: candidate.page_from,
    row_from: candidate.row_from,
    unit_type: candidate.unit_type,
    score: candidate.score,
    matched_queries: candidate.matched_queries,
    retrieval_text: candidate.retrieval_text.slice(0, 2_000),
  }));
}

async function persistAudit(
  db: SupabaseClient,
  input: {
    requestId: string;
    userId: string;
    sessionId: string | null;
    messageId: string | null;
    question: string;
    final: AgenticFinal | null;
    traces: AgenticToolCallTrace[];
    candidates: SearchCandidate[];
    packet: EvidenceBlock[];
    answer: string;
    citations: JsonMap[];
    validation: JsonMap;
    usage: ProviderUsage[];
    providerErrors: JsonMap[];
    latency: JsonMap;
    status: string;
    deepReview: boolean;
    deepReviewOfMessageId: string | null;
    feedbackReason: string | null;
  },
) {
  const persistedStatus = input.status === "conflicting_evidence"
    ? "insufficient_evidence"
    : input.status;
  const payload = {
    request_id: input.requestId,
    user_id: input.userId,
    session_id: input.sessionId,
    message_id: input.messageId,
    deep_review_of_message_id: input.deepReviewOfMessageId,
    raw_question: input.question,
    interpretation: {
      architecture: ENGINE_VERSION,
      semantic: input.final?.interpretation ?? null,
      agentic_trace: input.traces,
    },
    resolved_entities: input.final?.interpretation.canonical_entities ?? [],
    generated_search_queries: input.traces.map((trace) =>
      String(trace.arguments.query ?? trace.tool)
    ),
    retrieval_channels: [...new Set(input.traces.map((trace) => trace.tool))],
    top_candidates: compactCandidates(input.candidates),
    evidence_packet: input.packet,
    final_answer: input.answer,
    final_citations: input.citations,
    validation_checks: {
      ...input.validation,
      reported_answer_status: input.status,
      provider_errors: input.providerErrors,
      validation_scope: "numeric_contradiction_entity_evidence_only",
    },
    provider_usage: input.usage,
    latency: input.latency,
    feedback_reason: input.feedbackReason,
    deep_review: input.deepReview,
    answer_status: persistedStatus,
    candidate_count: input.candidates.length,
    evidence_count: input.packet.length,
    normal_reasoning_calls: Math.min(3, input.usage.length),
  };
  let lastError: JsonMap | null = null;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    const { error } = await db.from("insurance_v4_answer_audits").insert(
      payload,
    );
    if (!error || error.code === "23505") {
      return { recorded: true, attempts: attempt };
    }
    lastError = { code: error.code, message: error.message };
  }
  return { recorded: false, attempts: 2, error: lastError };
}

async function savePositiveFeedback(
  db: SupabaseClient,
  userId: string,
  messageId: string,
) {
  const { error } = await db.from("insurance_feedback").upsert({
    message_id: messageId,
    user_id: userId,
    rating: 1,
    updated_at: new Date().toISOString(),
  }, { onConflict: "message_id,user_id" });
  if (error) throw new Error(`Unable to record feedback: ${error.message}`);
}

async function saveNegativeFeedback(
  db: SupabaseClient,
  userId: string,
  messageId: string,
  reason: "incorrect" | "incomplete",
) {
  const { error } = await db.from("insurance_feedback").upsert({
    message_id: messageId,
    user_id: userId,
    rating: -1,
    reason,
    updated_at: new Date().toISOString(),
  }, { onConflict: "message_id,user_id" });
  if (error) throw new Error(`Unable to record feedback: ${error.message}`);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") {
    return respond({ error: "Method not allowed." }, 405);
  }

  const started = Date.now();
  const requestId = crypto.randomUUID();
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return respond({ error: "Authentication required." }, 401);
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    },
  );
  const { data: auth, error: authError } = await db.auth.getUser(
    authorization.slice(7),
  );
  if (authError || !auth.user) {
    return respond({ error: "Authentication required." }, 401);
  }
  const userId = auth.user.id;
  let body = await request.json().catch(() => ({})) as JsonMap;

  if (typeof body.positive_feedback_message_id === "string") {
    await savePositiveFeedback(db, userId, body.positive_feedback_message_id);
    return respond({ ok: true });
  }

  const feedbackMessageId = typeof body.feedback_message_id === "string" &&
      body.feedback_message_id.trim()
    ? body.feedback_message_id.trim()
    : null;
  const requestedFeedbackReason = String(body.feedback_reason ?? "");
  const feedbackReason = feedbackMessageId &&
      (requestedFeedbackReason === "incorrect" ||
        requestedFeedbackReason === "incomplete")
    ? requestedFeedbackReason as "incorrect" | "incomplete"
    : feedbackMessageId
    ? "incorrect"
    : null;
  let deepReview = false;
  let deepReviewOfMessageId: string | null = null;
  let priorAnswer = "";
  let question = typeof body.message === "string" ? body.message.trim() : "";

  if (feedbackMessageId && feedbackReason) {
    const assistantResult = await db.from("insurance_chat_messages")
      .select("id,session_id,message,created_at")
      .eq("id", feedbackMessageId)
      .eq("role", "assistant")
      .single();
    if (assistantResult.error || !assistantResult.data) {
      return respond({ error: "The feedback message was not found." }, 404);
    }
    await saveNegativeFeedback(db, userId, feedbackMessageId, feedbackReason);
    const auditResult = await db.from("insurance_v4_answer_audits")
      .select("raw_question,deep_review")
      .eq("message_id", feedbackMessageId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    const existingReview = await db.from("insurance_v4_answer_audits")
      .select("id")
      .eq("deep_review_of_message_id", feedbackMessageId)
      .limit(1)
      .maybeSingle();
    if (auditResult.data?.deep_review === true || existingReview.data) {
      return respond({ recovery_exhausted: true });
    }
    const userMessage = await db.from("insurance_chat_messages")
      .select("message")
      .eq("session_id", assistantResult.data.session_id)
      .eq("role", "user")
      .lte("created_at", assistantResult.data.created_at)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    question = String(
      userMessage.data?.message ?? auditResult.data?.raw_question ?? "",
    ).trim();
    if (!question) {
      return respond({ error: "The original question was not found." }, 409);
    }
    body = { ...body, session_id: assistantResult.data.session_id };
    deepReview = true;
    deepReviewOfMessageId = feedbackMessageId;
    priorAnswer = String(assistantResult.data.message ?? "");
  }

  if (!question) return respond({ error: "message is required." }, 400);
  if (question.length > 4_000) {
    return respond({ error: "message is too long." }, 400);
  }

  const envelope = deepReview
    ? {
      session_id: typeof body.session_id === "string" ? body.session_id : null,
      kind: "standalone" as const,
      prior: null,
    }
    : await loadContextEnvelope(
      db,
      typeof body.session_id === "string" ? body.session_id : null,
      question,
    );
  const executor = new AgenticToolExecutor(db, question);
  let final: AgenticFinal | null = null;
  let traces: AgenticToolCallTrace[] = [];
  let usage: ProviderUsage[] = [];
  let providerErrors: JsonMap[] = [];
  let answer = "";
  let answerStatus = "temporarily_unavailable";
  let validation: JsonMap = {};
  let citations: JsonMap[] = [];
  let saved: JsonMap = { session_id: envelope.session_id, message_id: null };
  let httpStatus = 200;

  try {
    const loop = await runAgenticLoop({
      question,
      context: { turn_kind: envelope.kind, prior: contextForModel(envelope) },
      executor,
      timeoutForTurn: () => remaining(started),
      modelRole: deepReview ? "deep_review" : "primary",
      deepReview: deepReview && feedbackReason
        ? { reason: feedbackReason, priorAnswer }
        : null,
    });
    final = loop.final;
    traces = loop.traces;
    usage = loop.usage;
    providerErrors = loop.provider_errors;
    const packet = executor.evidencePacket();
    const safety = validateAgenticResult(question, final, packet);
    validation = {
      valid: safety.valid,
      failures: safety.failures,
      diagnostics: safety.diagnostics,
      evidence_judgements: final.evidence_judgements,
      bounded_retrieval_rounds: Math.max(
        0,
        ...traces.map((trace) => trace.round),
      ),
    };
    if (final.action === "answer" && safety.valid && final.answer) {
      answer = final.answer;
      answerStatus = "grounded";
      citations = citationsFor(packet, final.evidence_ids);
    } else if (final.action === "clarify") {
      answer = safeMessage(question, "clarify", final);
      answerStatus = "clarification_required";
    } else if (final.action === "conflict") {
      answer = safeMessage(question, "conflict", final);
      answerStatus = "conflicting_evidence";
      citations = citationsFor(packet, final.evidence_ids);
    } else {
      answer = safeMessage(question, "insufficient", final);
      answerStatus = "insufficient_evidence";
      if (!safety.valid) validation.blocked_by_safety_validator = true;
    }
  } catch (error) {
    if (error instanceof ProvidersUnavailableError) {
      providerErrors = error.diagnostics;
    } else {
      const row = error as Error;
      providerErrors = [{
        stage: "runtime",
        reason: row.name,
        message: row.message.slice(0, 800),
      }];
    }
    answer = safeMessage(question, "temporary");
    answerStatus = "temporarily_unavailable";
    httpStatus = 503;
  }

  const packet = executor.evidencePacket();
  const candidates = executor.allCandidates();
  const parsedData: JsonMap = {
    architecture: ENGINE_VERSION,
    answer_status: answerStatus,
    answer_generator: deepReview
      ? "openai_terra_deep_review"
      : "openai_luna_agentic",
    evidence_checked: citations.length > 0,
    citations,
    interpretation: final?.interpretation ?? null,
    agentic_trace: traces,
    validation,
    provider_usage: usage,
    provider_errors: providerErrors,
    request_id: requestId,
    recovery_depth: deepReview ? 1 : 0,
    recovery_of_message_id: deepReviewOfMessageId,
    feedback_reason: feedbackReason,
  };
  let conversationPersistence: JsonMap;
  try {
    saved = await saveConversationTurn(
      db,
      body,
      question,
      answer,
      citations,
      parsedData,
      { deepReviewOfMessageId },
    );
    conversationPersistence = { recorded: true };
  } catch (error) {
    conversationPersistence = {
      recorded: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
  const latency = { total_ms: Date.now() - started };
  const audit = await persistAudit(db, {
    requestId,
    userId,
    sessionId: typeof saved.session_id === "string" ? saved.session_id : null,
    messageId: typeof saved.message_id === "string" ? saved.message_id : null,
    question,
    final,
    traces,
    candidates,
    packet,
    answer,
    citations,
    validation,
    usage,
    providerErrors,
    latency,
    status: answerStatus,
    deepReview,
    deepReviewOfMessageId,
    feedbackReason,
  });

  return respond({
    insurance_simple: true,
    engine_version: ENGINE_VERSION,
    request_id: requestId,
    session_id: saved.session_id ?? null,
    message_id: saved.message_id ?? requestId,
    id: saved.message_id ?? requestId,
    role: "assistant",
    message: answer,
    answer,
    answer_status: answerStatus,
    created_at: saved.created_at ?? new Date().toISOString(),
    citations,
    evidence_checked: citations.length > 0,
    recovery_used: deepReview,
    recovery_of_message_id: deepReviewOfMessageId,
    parsed_data: parsedData,
    audit_persistence: audit,
    conversation_persistence: conversationPersistence,
    debug: body.debug === true
      ? {
        interpretation: final?.interpretation ?? null,
        agentic_trace: traces,
        evidence_judgements: final?.evidence_judgements ?? [],
        validation,
        provider_usage: usage,
        provider_errors: providerErrors,
        latency,
      }
      : null,
  }, httpStatus);
});
