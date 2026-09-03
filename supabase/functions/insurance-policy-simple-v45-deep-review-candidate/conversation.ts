import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import type {
  AgenticInterpretation,
  ConversationState,
  JsonMap,
} from "./types.ts";

function records(value: unknown): JsonMap[] {
  return Array.isArray(value)
    ? value.filter((item): item is JsonMap =>
      !!item && typeof item === "object" && !Array.isArray(item)
    )
    : [];
}

function normalized(value: string) {
  return value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

const RELATION_WORDS = new Set([
  "allowed",
  "approved",
  "coverage",
  "covered",
  "dose",
  "schedule",
  "refill",
  "renewal",
  "continue",
  "continuation",
  "price",
  "age",
  "weight",
  "specialty",
  "evidence",
  "source",
  "page",
  "form",
  "مسموح",
  "مغطى",
  "تغطية",
  "جرعة",
  "جدول",
  "تجديد",
  "استمرار",
  "سعر",
  "عمر",
  "وزن",
  "تخصص",
  "دليل",
  "مصدر",
  "صفحة",
  "نموذج",
]);

export type ContextEnvelope = {
  session_id: string | null;
  kind: "standalone" | "follow_up";
  prior: ConversationState | null;
};

export function classifyTurnText(question: string) {
  const value = question.trim();
  if (
    /^(?:new question|different question|start over|موضوع جديد|سؤال جديد|ابدأ من جديد)\b/iu
      .test(value)
  ) {
    return "standalone" as const;
  }
  const tokens = normalized(value).split(/\s+/u).filter(Boolean);
  const connective =
    /^(?:and|also|then|after that|what about|how about|طيب|وماذا|وشو|وبعدها|ثم)(?=\s|[؟?!.,]|$)/iu
      .test(value);
  const pronoun =
    /\b(?:it|this|that|same|there|them)\b|(?:هو|هي|له|لها|هذا|هذه|نفسه|نفسها|عنه|عنها)/iu
      .test(value);
  const relationshipOnly = tokens.length > 0 && tokens.length <= 7 &&
    tokens.every((token) =>
      RELATION_WORDS.has(token) ||
      /^(?:what|which|who|when|how|is|can|does|the|a|an|for|or|and|only|after|that|هل|ما|ماذا|من|متى|كيف|و|او|أو)$/iu
        .test(token)
    );
  return connective || pronoun || relationshipOnly
    ? "follow_up" as const
    : "standalone" as const;
}

function parseState(value: unknown): ConversationState | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const row = value as JsonMap;
  if (row.version !== "v44") return null;
  return {
    version: "v44",
    canonical_entities: Array.isArray(row.canonical_entities)
      ? row.canonical_entities.map(String).filter(Boolean).slice(0, 4)
      : [],
    indication: typeof row.indication === "string" ? row.indication : null,
    formulation: typeof row.formulation === "string" ? row.formulation : null,
    last_relationships: Array.isArray(row.last_relationships)
      ? row.last_relationships.map(String).filter(Boolean).slice(0, 8)
      : [],
    source_user_message_id: typeof row.source_user_message_id === "string"
      ? row.source_user_message_id
      : null,
  };
}

export async function loadContextEnvelope(
  db: SupabaseClient,
  sessionId: string | null,
  question: string,
): Promise<ContextEnvelope> {
  const kind = classifyTurnText(question);
  if (!sessionId || kind === "standalone") {
    return { session_id: sessionId, kind, prior: null };
  }
  const { data, error } = await db.from("insurance_chat_messages")
    .select("id,role,parsed_data,created_at")
    .eq("session_id", sessionId)
    .eq("role", "assistant")
    .order("created_at", { ascending: false })
    .limit(4);
  if (error) return { session_id: sessionId, kind, prior: null };
  for (const row of records(data)) {
    const parsed = row.parsed_data;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      continue;
    }
    const state = parseState((parsed as JsonMap).conversation_state);
    if (state) return { session_id: sessionId, kind, prior: state };
  }
  return { session_id: sessionId, kind, prior: null };
}

export function contextForModel(envelope: ContextEnvelope) {
  if (envelope.kind !== "follow_up" || !envelope.prior) return null;
  return {
    canonical_entities: envelope.prior.canonical_entities,
    indication: envelope.prior.indication,
    formulation: envelope.prior.formulation,
    last_relationships: envelope.prior.last_relationships,
  };
}

export function nextConversationState(
  interpretation: AgenticInterpretation,
  userMessageId: string | null,
): ConversationState {
  return {
    version: "v44",
    canonical_entities: interpretation.canonical_entities.slice(0, 4),
    indication: interpretation.indication,
    formulation: interpretation.formulation,
    last_relationships: interpretation.requested_relationships.slice(0, 8),
    source_user_message_id: userMessageId,
  };
}

export async function saveConversationTurn(
  db: SupabaseClient,
  body: JsonMap,
  question: string,
  answer: string,
  citations: JsonMap[],
  parsedData: JsonMap,
  options: { deepReviewOfMessageId?: string | null } = {},
) {
  let sessionId = typeof body.session_id === "string" && body.session_id
    ? body.session_id
    : null;
  if (!sessionId) {
    const created = await db.from("insurance_chat_sessions").insert({
      branch_name: String(body.branch_name ?? ""),
      title: question.slice(0, 80),
    }).select("id").single();
    if (created.error) {
      throw new Error(
        `Unable to create conversation: ${created.error.message}`,
      );
    }
    sessionId = String(created.data.id);
  }
  let userMessageId: string | null = null;
  if (!options.deepReviewOfMessageId) {
    const userInsert = await db.from("insurance_chat_messages").insert({
      session_id: sessionId,
      role: "user",
      message: question,
      parsed_data: { architecture: "v45-deep-review" },
    }).select("id").single();
    if (userInsert.error) {
      throw new Error(
        `Unable to save user message: ${userInsert.error.message}`,
      );
    }
    userMessageId = String(userInsert.data.id);
  }
  const state =
    parsedData.interpretation && typeof parsedData.interpretation === "object"
      ? nextConversationState(
        parsedData.interpretation as AgenticInterpretation,
        userMessageId,
      )
      : null;
  const assistantInsert = await db.from("insurance_chat_messages").insert({
    session_id: sessionId,
    role: "assistant",
    message: answer,
    citations,
    parsed_data: {
      ...parsedData,
      conversation_state: state,
      ...(options.deepReviewOfMessageId
        ? {
          recovery_depth: 1,
          recovery_of_message_id: options.deepReviewOfMessageId,
        }
        : {}),
    },
  }).select("id,created_at").single();
  if (assistantInsert.error) {
    throw new Error(
      `Unable to save assistant message: ${assistantInsert.error.message}`,
    );
  }
  await db.from("insurance_chat_sessions").update({
    updated_at: new Date().toISOString(),
  }).eq("id", sessionId);
  return {
    session_id: sessionId,
    message_id: String(assistantInsert.data.id),
    user_message_id: userMessageId,
    created_at: String(assistantInsert.data.created_at),
    recovery_of_message_id: options.deepReviewOfMessageId ?? null,
  };
}
