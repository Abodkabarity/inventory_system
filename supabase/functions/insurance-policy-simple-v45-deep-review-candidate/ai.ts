import type {
  AgenticToolName,
  EvidenceAssessment,
  JsonMap,
  MissingSemanticSlot,
  ModelDecision,
  ProviderUsage,
  SearchPlan,
} from "./types.ts";

export const OPENAI_LUNA_MODEL = "gpt-5.6-luna";
export const OPENAI_TERRA_MODEL = "gpt-5.6-terra";
export const OPENAI_REASONING_EFFORT = "medium" as const;
export type OpenAIModelRole = "primary" | "deep_review";

type Message = {
  role: "system" | "developer" | "user" | "assistant";
  content: string;
};

type CallType = ProviderUsage["call_type"];
type AIResult = {
  json: JsonMap;
  usage: ProviderUsage;
  provider_errors: JsonMap[];
};

export type AgenticFunctionCall = {
  call_id: string;
  name: AgenticToolName;
  arguments: JsonMap;
  raw: JsonMap;
};

export type AgenticProviderTurn = {
  final: JsonMap | null;
  function_calls: AgenticFunctionCall[];
  output_items: JsonMap[];
  usage: ProviderUsage;
  provider_errors: JsonMap[];
};

const primaryProvider = {
  name: "openai_luna" as const,
  endpoint: "https://api.openai.com/v1/responses",
  secret: "OPENAI_API_KEY",
  model: OPENAI_LUNA_MODEL,
};

const deepReviewProvider = {
  name: "openai_terra" as const,
  endpoint: "https://api.openai.com/v1/responses",
  secret: "OPENAI_API_KEY",
  model: OPENAI_TERRA_MODEL,
};

function providerFor(role: OpenAIModelRole) {
  return role === "deep_review" ? deepReviewProvider : primaryProvider;
}

const stringArray = { type: "array", items: { type: "string" } } as const;
const missingSlotArray = {
  type: "array",
  items: {
    type: "string",
    enum: [
      "entity",
      "entity_resolution",
      "relationship",
      "indication",
      "formulation",
      "patient_numeric",
      "policy_scope",
    ],
  },
} as const;
const searchPlanSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "search_terms",
    "exact_literals",
    "codes",
    "important_qualifiers",
    "requested_relationships",
    "ambiguity",
    "missing_slots",
    "ambiguity_reason",
    "clarification_question",
  ],
  properties: {
    search_terms: stringArray,
    exact_literals: stringArray,
    codes: stringArray,
    important_qualifiers: stringArray,
    requested_relationships: stringArray,
    ambiguity: { type: "string", enum: ["clear", "clarify"] },
    missing_slots: missingSlotArray,
    ambiguity_reason: { type: ["string", "null"] },
    clarification_question: { type: ["string", "null"] },
  },
} as const;

const evidenceAssessmentSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "action",
    "refined_search",
    "clarification_question",
    "missing_slots",
    "ambiguity_reason",
    "conflict_evidence_ids",
    "reason",
  ],
  properties: {
    action: {
      type: "string",
      enum: ["answer", "search_again", "clarify", "conflict"],
    },
    refined_search: { anyOf: [{ type: "null" }, searchPlanSchema] },
    clarification_question: { type: ["string", "null"] },
    missing_slots: missingSlotArray,
    ambiguity_reason: { type: ["string", "null"] },
    conflict_evidence_ids: stringArray,
    reason: { type: "string" },
  },
} as const;

const decisionSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "action",
    "answer",
    "evidence_ids",
    "continuation_clinical",
    "continuation_documentation",
    "refined_search",
  ],
  properties: {
    action: { type: "string", enum: ["answer", "search_again"] },
    answer: { type: ["string", "null"] },
    evidence_ids: stringArray,
    continuation_clinical: {
      type: "string",
      description:
        "For continuation/refill questions, all clinical response and threshold criteria with evidence citations. Otherwise NOT_APPLICABLE.",
    },
    continuation_documentation: {
      type: "string",
      description:
        "For continuation/refill questions, all report, reassessment, submission, and claim-rejection requirements with evidence citations. Otherwise NOT_APPLICABLE.",
    },
    refined_search: {
      anyOf: [
        { type: "null" },
        searchPlanSchema,
      ],
    },
  },
} as const;

const nullableString = { type: ["string", "null"] } as const;
const agenticFinalSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "action",
    "interpretation",
    "answer",
    "evidence_ids",
    "evidence_judgements",
    "unresolved_facets",
  ],
  properties: {
    action: {
      type: "string",
      enum: ["answer", "clarify", "insufficient_evidence", "conflict"],
    },
    interpretation: {
      type: "object",
      additionalProperties: false,
      required: [
        "language",
        "turn_kind",
        "canonical_entities",
        "indication",
        "requested_relationships",
        "numeric_qualifiers",
        "formulation",
        "resolved_question",
        "genuinely_ambiguous",
        "ambiguity_reason",
        "clarification_question",
      ],
      properties: {
        language: { type: "string", enum: ["ar", "en", "mixed"] },
        turn_kind: { type: "string", enum: ["standalone", "follow_up"] },
        canonical_entities: stringArray,
        indication: nullableString,
        requested_relationships: stringArray,
        numeric_qualifiers: stringArray,
        formulation: nullableString,
        resolved_question: { type: "string" },
        genuinely_ambiguous: { type: "boolean" },
        ambiguity_reason: nullableString,
        clarification_question: nullableString,
      },
    },
    answer: nullableString,
    evidence_ids: stringArray,
    evidence_judgements: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["evidence_id", "disposition", "reason"],
        properties: {
          evidence_id: { type: "string" },
          disposition: { type: "string", enum: ["accepted", "rejected"] },
          reason: {
            type: "string",
            enum: [
              "answers_requested_relationship",
              "wrong_entity",
              "wrong_indication",
              "wrong_relationship",
              "superseded_source",
              "semantic_only",
              "conflicting_source",
              "duplicate",
              "other",
            ],
          },
        },
      },
    },
    unresolved_facets: stringArray,
  },
} as const;

const commonSearchProperties = {
  query: { type: "string" },
  entity: nullableString,
  indication: nullableString,
  relationship: nullableString,
  exact_literals: stringArray,
  codes: stringArray,
  qualifiers: stringArray,
} as const;

export const AGENTIC_TOOL_DEFINITIONS = [
  {
    type: "function",
    name: "search_approved_policy",
    description:
      "Search active approved policy text using a focused semantic and literal query.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: Object.keys(commonSearchProperties),
      properties: commonSearchProperties,
    },
  },
  {
    type: "function",
    name: "search_entity_documents",
    description:
      "Find active approved documents and evidence for one canonical entity and indication.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: Object.keys(commonSearchProperties),
      properties: commonSearchProperties,
    },
  },
  {
    type: "function",
    name: "fetch_policy_section",
    description:
      "Fetch an approved section or neighboring units by document, unit, or page.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["document_id", "search_unit_id", "page"],
      properties: {
        document_id: nullableString,
        search_unit_id: nullableString,
        page: { type: ["number", "null"] },
      },
    },
  },
  {
    type: "function",
    name: "fetch_table_context",
    description:
      "Fetch the complete approved table context around a retrieved table row.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["document_id", "search_unit_id", "parent_unit_id", "page"],
      properties: {
        document_id: nullableString,
        search_unit_id: nullableString,
        parent_unit_id: nullableString,
        page: { type: ["number", "null"] },
      },
    },
  },
  {
    type: "function",
    name: "search_policy_family",
    description:
      "Search active approved sources belonging to a named policy family.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["policy_family"],
      properties: { policy_family: { type: "string" } },
    },
  },
  {
    type: "function",
    name: "follow_approved_reference",
    description:
      "Follow an explicit reference from retrieved evidence to another approved source.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["evidence_ids", ...Object.keys(commonSearchProperties)],
      properties: { evidence_ids: stringArray, ...commonSearchProperties },
    },
  },
  {
    type: "function",
    name: "fetch_source_metadata",
    description:
      "Fetch approval, version, effective-date, expiry, and source-family metadata.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["document_ids"],
      properties: { document_ids: stringArray },
    },
  },
] as const;

function responseFormat(callType: CallType) {
  const schema = callType === "search_plan"
    ? searchPlanSchema
    : callType === "evidence_check"
    ? evidenceAssessmentSchema
    : decisionSchema;
  return {
    type: "json_schema",
    json_schema: {
      name: callType === "search_plan"
        ? "search_plan"
        : callType === "evidence_check"
        ? "evidence_assessment"
        : "policy_answer",
      strict: true,
      schema,
    },
  };
}

function responsesTextFormat(callType: CallType) {
  const format = responseFormat(callType).json_schema;
  return {
    type: "json_schema",
    name: format.name,
    strict: format.strict,
    schema: format.schema,
  };
}

export function parseJsonObject(value: unknown): JsonMap {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as JsonMap;
  }
  if (typeof value !== "string") throw new Error("AI response was not JSON.");
  const text = value.trim().replace(/^```(?:json)?\s*/iu, "").replace(
    /\s*```$/u,
    "",
  );
  let parsed: unknown;
  try {
    parsed = JSON.parse(text) as unknown;
  } catch {
    const start = text.indexOf("{");
    let depth = 0;
    let quoted = false;
    let escaped = false;
    let end = -1;
    for (let index = start; index >= 0 && index < text.length; index += 1) {
      const character = text[index];
      if (quoted) {
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === '"') quoted = false;
        continue;
      }
      if (character === '"') quoted = true;
      else if (character === "{") depth += 1;
      else if (character === "}" && --depth === 0) {
        end = index + 1;
        break;
      }
    }
    if (start < 0 || end < 0) throw new Error("AI response was not JSON.");
    parsed = JSON.parse(text.slice(start, end)) as unknown;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("AI response was not a JSON object.");
  }
  return parsed as JsonMap;
}

function isTransient(status: number) {
  return status === 408 || status === 409 || status === 425 || status === 429 ||
    status >= 500;
}

async function callProvider(
  messages: Message[],
  callType: CallType,
  timeoutMs: number,
): Promise<Omit<AIResult, "provider_errors">> {
  const provider = primaryProvider;
  const key = Deno.env.get(provider.secret);
  if (!key) {
    throw Object.assign(new Error(`${provider.name} is not configured.`), {
      transient: true,
    });
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const started = Date.now();
  try {
    const outputTokens = callType === "search_plan" ||
        callType === "evidence_check"
      ? 900
      : 3_200;
    const response = await fetch(provider.endpoint, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: provider.model,
        input: messages,
        reasoning: { effort: OPENAI_REASONING_EFFORT },
        text: { format: responsesTextFormat(callType) },
        max_output_tokens: outputTokens,
        store: false,
      }),
    });
    const payload = await response.json().catch(() => ({})) as JsonMap;
    if (!response.ok) {
      const detail = payload.error && typeof payload.error === "object"
        ? String((payload.error as JsonMap).message ?? "")
        : "";
      throw Object.assign(
        new Error(
          `${provider.name} returned HTTP ${response.status}${
            detail ? `: ${detail.slice(0, 300)}` : ""
          }`,
        ),
        {
          status: response.status,
          transient: isTransient(response.status),
        },
      );
    }
    if (
      payload.status === "incomplete" ||
      (payload.incomplete_details as JsonMap | undefined)?.reason ===
        "max_output_tokens"
    ) {
      throw Object.assign(
        new Error(`${provider.name} response was truncated.`),
        {
          transient: true,
        },
      );
    }
    const output = Array.isArray(payload.output)
      ? payload.output as JsonMap[]
      : [];
    const message = output.find((item) => item.type === "message");
    const content = Array.isArray(message?.content)
      ? message.content as JsonMap[]
      : [];
    const refusal = content.find((item) => item.type === "refusal");
    if (refusal) {
      throw Object.assign(
        new Error(`${provider.name} refused the structured response.`),
        { transient: false },
      );
    }
    const outputText = content.find((item) => item.type === "output_text")
      ?.text;
    return {
      json: parseJsonObject(outputText),
      usage: {
        provider: provider.name,
        model: typeof payload.model === "string"
          ? payload.model
          : provider.model,
        call_type: callType,
        latency_ms: Date.now() - started,
        usage: payload.usage && typeof payload.usage === "object"
          ? payload.usage as JsonMap
          : null,
        fallback_used: false,
      },
    };
  } finally {
    clearTimeout(timer);
  }
}

export class ProvidersUnavailableError extends Error {
  constructor(readonly diagnostics: JsonMap[]) {
    super("All configured AI providers are unavailable.");
    this.name = "ProvidersUnavailableError";
  }
}

export async function callAI(
  messages: Message[],
  callType: CallType,
  timeoutMs: number,
): Promise<AIResult> {
  const diagnostics: JsonMap[] = [];
  try {
    const result = await callProvider(
      messages,
      callType,
      Math.max(500, timeoutMs),
    );
    return { ...result, provider_errors: diagnostics };
  } catch (error) {
    const row = error as Error & { status?: number; transient?: boolean };
    diagnostics.push({
      provider: primaryProvider.name,
      attempt: 1,
      status: row.status ?? null,
      reason: row.name,
      message: row.message.slice(0, 800),
    });
  }
  throw new ProvidersUnavailableError(diagnostics);
}

export async function callAgenticTurn(
  input: JsonMap[],
  timeoutMs: number,
  modelRole: OpenAIModelRole = "primary",
): Promise<AgenticProviderTurn> {
  const provider = providerFor(modelRole);
  const key = Deno.env.get(provider.secret);
  if (!key) {
    throw new ProvidersUnavailableError([{
      provider: provider.name,
      stage: "agentic_reasoning",
      message: `${provider.name} is not configured.`,
    }]);
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(500, timeoutMs));
  const started = Date.now();
  try {
    const response = await fetch(provider.endpoint, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: provider.model,
        input,
        tools: AGENTIC_TOOL_DEFINITIONS,
        tool_choice: "auto",
        parallel_tool_calls: false,
        reasoning: { effort: OPENAI_REASONING_EFFORT },
        text: {
          format: {
            type: "json_schema",
            name: "agentic_policy_result",
            strict: true,
            schema: agenticFinalSchema,
          },
        },
        max_output_tokens: 4_500,
        include: ["reasoning.encrypted_content"],
        store: false,
      }),
    });
    const payload = await response.json().catch(() => ({})) as JsonMap;
    if (!response.ok) {
      const detail = payload.error && typeof payload.error === "object"
        ? String((payload.error as JsonMap).message ?? "")
        : "";
      throw Object.assign(
        new Error(
          `${provider.name} returned HTTP ${response.status}${
            detail ? `: ${detail.slice(0, 300)}` : ""
          }`,
        ),
        { status: response.status, transient: isTransient(response.status) },
      );
    }
    if (payload.status === "incomplete") {
      throw Object.assign(
        new Error(`${provider.name} response was truncated.`),
        { transient: true },
      );
    }
    const outputItems = Array.isArray(payload.output)
      ? payload.output.filter((item): item is JsonMap =>
        !!item && typeof item === "object" && !Array.isArray(item)
      )
      : [];
    const functionCalls: AgenticFunctionCall[] = outputItems
      .filter((item) => item.type === "function_call")
      .map((item) => ({
        call_id: String(item.call_id ?? item.id ?? ""),
        name: String(item.name ?? "") as AgenticToolName,
        arguments: parseJsonObject(item.arguments ?? "{}"),
        raw: item,
      }))
      .filter((call) =>
        call.call_id &&
        AGENTIC_TOOL_DEFINITIONS.some((tool) => tool.name === call.name)
      );
    const message = outputItems.find((item) => item.type === "message");
    const content = Array.isArray(message?.content)
      ? message.content as JsonMap[]
      : [];
    const outputText = content.find((item) => item.type === "output_text")
      ?.text;
    const final = outputText == null ? null : parseJsonObject(outputText);
    return {
      final,
      function_calls: functionCalls,
      output_items: outputItems,
      usage: {
        provider: provider.name,
        model: typeof payload.model === "string"
          ? payload.model
          : provider.model,
        call_type: "agentic_reasoning",
        latency_ms: Date.now() - started,
        usage: payload.usage && typeof payload.usage === "object"
          ? payload.usage as JsonMap
          : null,
        fallback_used: false,
      },
      provider_errors: [],
    };
  } catch (error) {
    if (error instanceof ProvidersUnavailableError) throw error;
    const row = error as Error & { status?: number };
    throw new ProvidersUnavailableError([{
      provider: provider.name,
      stage: "agentic_reasoning",
      status: row.status ?? null,
      reason: row.name,
      message: row.message.slice(0, 800),
    }]);
  } finally {
    clearTimeout(timer);
  }
}

function strings(value: unknown, limit: number) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item).trim()).filter(Boolean))]
    .slice(0, limit);
}

function normalizedLiteral(value: string) {
  return value.normalize("NFKC").toLocaleLowerCase().replace(
    /[^\p{L}\p{N}.%/+\-]+/gu,
    " ",
  ).replace(/\s+/g, " ").trim();
}

function presentInQuestion(items: string[], question: string) {
  if (!question) return items;
  const source = normalizedLiteral(question);
  return items.filter((item) => source.includes(normalizedLiteral(item)));
}

const nonAnchorTokens = new Set([
  "approved",
  "uses",
  "use",
  "specialties",
  "specialty",
  "continued",
  "continuation",
  "therapy",
  "start",
  "started",
  "starting",
  "initiation",
  "date",
  "same",
  "whole",
  "history",
  "section",
  "treatment",
  "documented",
  "requirement",
  "requirements",
  "diagnosis",
  "evidence",
  "coverage",
  "information",
  "data",
  "request",
  "required",
  "policy",
  "listed",
  "restriction",
  "restrictions",
  "exception",
  "exceptions",
  "renewal",
  "refill",
  "reassessment",
  "monitoring",
  "interval",
  "dose",
  "documentation",
  "qualifier",
  "policy",
  "clinical",
  "medicine",
  "medicines",
  "administered",
  "administration",
  "eligibility",
  "prior",
  "treatment",
  "treatments",
  "initial",
  "period",
  "setting",
  "combination",
  "covered",
  "cover",
  "البيانات",
  "المطلوبة",
  "المستندات",
  "طلب",
  "التغطية",
  "التخصصات",
  "العلاج",
  "الاستمرار",
  "التجديد",
  "الاستثناء",
  "الاستثناءات",
  "القيود",
  "الجرعة",
  "المتابعة",
  "متى",
  "مغطاة",
  "مغطى",
  "مغطية",
]);

function hasEntityAnchor(value: string) {
  return normalizedLiteral(value).split(" ").some((token) =>
    token.length >= 2 && !nonAnchorTokens.has(token)
  );
}

export function hasExplicitRequestedRelationship(question: string) {
  return /\b(?:allow(?:ed|ance)?|pass(?:es|ed)?|too frequent|price|cost|source|document|page|version|current|conflict|prescrib\w*|specialt\w*|dose|timing|escalat\w*|schedule|interval|age|weight|duration|initiat\w*|start(?:ed|ing)?|continu\w*|renew\w*|refill\w*|cover\w*|criteri\w*|threshold|required|requirement\w*|monitor\w*|indication\w*|eligib\w*|formulation|restriction\w*|exception\w*|administ\w*|route|frequency|stop(?:ped|ping)?|discontinu\w*)\b|(?:مسموح|ينفع|يمر|يحقق|السعر|التكلفة|المصدر|الوثيقة|الصفحة|الإصدار|النسخة|تعارض|يصف|يصرف|التخصص|الجرعة|التوقيت|التصعيد|الجدول|المواعيد|الفاصل|العمر|الوزن|المدة|بدء|الاستمرار|التجديد|التغطية|الشروط|المعايير|الحد|المتطلبات|المتابعة|الاستطباب|الأهلية|الشكل الدوائي|القيود|الاستثناءات|طريقة الإعطاء|التكرار|إيقاف)/iu
    .test(question);
}

const missingSemanticSlots = new Set<MissingSemanticSlot>([
  "entity",
  "entity_resolution",
  "relationship",
  "indication",
  "formulation",
  "patient_numeric",
  "policy_scope",
]);

function semanticSlots(value: unknown) {
  return strings(value, 8).filter((slot): slot is MissingSemanticSlot =>
    missingSemanticSlots.has(slot as MissingSemanticSlot)
  );
}

function questionHasNumericQualifier(question: string) {
  return /\b\d+(?:\.\d+)?\s*(?:%|mg|mcg|g|kg|ml|units?|years?|months?|weeks?|days?|hours?|mins?|minutes?)?\b|(?:عمره|وزنه|بنسبة|جرعة)\s*\d/iu
    .test(question);
}

function asksPatientSpecificNumericDecision(question: string) {
  const decision =
    /\b(?:does|would|will|is|are|can)\b.{0,80}\b(?:pass|qualif\w*|eligib\w*|allowed?|appropriate|too frequent|too high|too low)\b|(?:هل|ينفع|يمر|يحقق|مسموح).{0,80}(?:الشرط|المعيار|الحد|العمر|الوزن|الجرعة|التكرار)/iu
      .test(question);
  const numericRelationship =
    /\b(?:age|weight|dose|duration|threshold|frequency|interval|timing|escalat\w*)\b|(?:العمر|الوزن|الجرعة|المدة|الحد|التكرار|الفاصل|التوقيت|التصعيد)/iu
      .test(question);
  return decision && numericRelationship;
}

function questionHasIndicationContext(
  question: string,
  exactLiterals: string[],
  qualifiers: string[],
) {
  if (exactLiterals.length >= 2) return true;
  const presentQualifiers = presentInQuestion(qualifiers, question).filter(
    (qualifier) =>
      !hasExplicitRequestedRelationship(qualifier) &&
      !questionHasNumericQualifier(qualifier),
  );
  return presentQualifiers.length > 0 ||
    /\b(?:for|with|diagnosed with|due to|in patients? with)\b.{1,60}\b[\p{L}]{3,}\b|(?:لعلاج|لمرض|مع تشخيص|بسبب)\s+[\p{L}]/iu
      .test(question);
}

function questionHasFormulation(question: string) {
  return /\b(?:tablet|capsule|injection|injectable|syringe|pen|vial|solution|suspension|inhaler|respule|nebuliz\w*|cream|ointment|patch|oral|iv|intravenous|subcutaneous)\b|(?:قرص|أقراص|كبسولة|حقن|إبرة|قلم|قارورة|محلول|معلق|بخاخ|نيبولايزر|كريم|مرهم|لاصقة|فموي|وريدي|تحت الجلد)/iu
    .test(question);
}

export function resolveClarificationGate(
  input: {
    ambiguity: unknown;
    missing_slots: unknown;
    ambiguity_reason: unknown;
    clarification_question: unknown;
    exact_literals: string[];
    codes: string[];
    important_qualifiers: string[];
    requested_relationships: string[];
  },
  question: string,
) {
  const entityResolved = Boolean(
    input.exact_literals.length || input.codes.length,
  );
  const relationshipResolved = hasExplicitRequestedRelationship(question);
  const requestedMissing = semanticSlots(input.missing_slots);
  if (input.ambiguity === "clarify" && !requestedMissing.length) {
    if (!entityResolved) requestedMissing.push("entity");
    if (!relationshipResolved) requestedMissing.push("relationship");
  }
  const effectiveMissing = [
    ...new Set(requestedMissing.filter((slot) => {
      if (slot === "entity") return !entityResolved;
      // A real spelling collision remains ambiguous. Generic relationship
      // words are removed before this point, and canonical alias resolution
      // later decides whether multiple retained names are one identity.
      if (slot === "entity_resolution") return true;
      if (slot === "relationship") return !relationshipResolved;
      if (slot === "indication") {
        return !questionHasIndicationContext(
          question,
          input.exact_literals,
          input.important_qualifiers,
        );
      }
      if (slot === "formulation") return !questionHasFormulation(question);
      if (slot === "patient_numeric") {
        return asksPatientSpecificNumericDecision(question) &&
          !questionHasNumericQualifier(question);
      }
      return !entityResolved;
    })),
  ];
  const clarify = input.ambiguity === "clarify" && effectiveMissing.length > 0;
  const reason = typeof input.ambiguity_reason === "string" &&
      input.ambiguity_reason.trim()
    ? input.ambiguity_reason.trim()
    : null;
  const clarification = typeof input.clarification_question === "string" &&
      input.clarification_question.trim()
    ? input.clarification_question.trim()
    : null;
  return {
    ambiguity: clarify ? "clarify" as const : "clear" as const,
    missing_slots: clarify ? effectiveMissing : [],
    ambiguity_reason: clarify ? reason : null,
    clarification_question: clarify ? clarification : null,
  };
}

export function normalizeSearchPlan(
  value: JsonMap,
  question = "",
): SearchPlan {
  const requestedRelationships = strings(value.requested_relationships, 8);
  const clarification = typeof value.clarification_question === "string" &&
      value.clarification_question.trim()
    ? value.clarification_question.trim()
    : null;
  const exactLiterals = presentInQuestion(
    strings(value.exact_literals, 8),
    question,
  ).filter(hasEntityAnchor);
  const codes = presentInQuestion(strings(value.codes, 8), question);
  const importantQualifiers = strings(value.important_qualifiers, 8);
  const ambiguity = resolveClarificationGate({
    ambiguity: value.ambiguity,
    missing_slots: value.missing_slots,
    ambiguity_reason: value.ambiguity_reason,
    clarification_question: clarification,
    exact_literals: exactLiterals,
    codes,
    important_qualifiers: importantQualifiers,
    requested_relationships: requestedRelationships,
  }, question);
  return {
    search_terms: strings(value.search_terms, 8),
    exact_literals: exactLiterals,
    codes,
    important_qualifiers: importantQualifiers,
    ...(requestedRelationships.length || "requested_relationships" in value
      ? { requested_relationships: requestedRelationships }
      : {}),
    ...("ambiguity" in value
      ? {
        ambiguity: ambiguity.ambiguity,
      }
      : {}),
    ...("missing_slots" in value
      ? { missing_slots: ambiguity.missing_slots }
      : {}),
    ...("ambiguity_reason" in value
      ? { ambiguity_reason: ambiguity.ambiguity_reason }
      : {}),
    ...(clarification || "clarification_question" in value
      ? { clarification_question: ambiguity.clarification_question }
      : {}),
  };
}

export function normalizeEvidenceAssessment(
  value: JsonMap,
  question = "",
  originalPlan: SearchPlan | null = null,
): EvidenceAssessment {
  let action: EvidenceAssessment["action"] = value.action === "search_again" ||
      value.action === "clarify" || value.action === "conflict"
    ? value.action
    : "answer";
  const refined = value.refined_search &&
      typeof value.refined_search === "object" &&
      !Array.isArray(value.refined_search)
    ? normalizeSearchPlan(value.refined_search as JsonMap, question)
    : null;
  const clarification = typeof value.clarification_question === "string" &&
      value.clarification_question.trim()
    ? value.clarification_question.trim()
    : null;
  const basePlan = originalPlan ?? refined ?? {
    search_terms: [],
    exact_literals: [],
    codes: [],
    important_qualifiers: [],
    requested_relationships: [],
  };
  const ambiguity = resolveClarificationGate({
    ambiguity: action === "clarify" ? "clarify" : "clear",
    missing_slots: value.missing_slots,
    ambiguity_reason: value.ambiguity_reason ?? value.reason,
    clarification_question: clarification,
    exact_literals: basePlan.exact_literals,
    codes: basePlan.codes,
    important_qualifiers: basePlan.important_qualifiers,
    requested_relationships: basePlan.requested_relationships ?? [],
  }, question);
  if (action === "clarify" && ambiguity.ambiguity !== "clarify") {
    action = refined ? "search_again" : "answer";
  }
  return {
    action,
    refined_search: refined,
    clarification_question: action === "clarify"
      ? ambiguity.clarification_question
      : null,
    missing_slots: action === "clarify" ? ambiguity.missing_slots : [],
    ambiguity_reason: action === "clarify"
      ? ambiguity.ambiguity_reason ?? ""
      : "",
    conflict_evidence_ids: strings(value.conflict_evidence_ids, 12),
    reason: typeof value.reason === "string" ? value.reason.trim() : "",
  };
}

export function normalizeDecision(
  value: JsonMap,
  question = "",
): ModelDecision {
  const action = value.action === "search_again" ? "search_again" : "answer";
  const refined = value.refined_search &&
      typeof value.refined_search === "object" &&
      !Array.isArray(value.refined_search)
    ? normalizeSearchPlan(value.refined_search as JsonMap, question)
    : null;
  return {
    action,
    answer: typeof value.answer === "string" && value.answer.trim()
      ? value.answer.trim()
      : null,
    evidence_ids: strings(value.evidence_ids, 12),
    continuation_clinical: typeof value.continuation_clinical === "string"
      ? value.continuation_clinical.trim()
      : "",
    continuation_documentation:
      typeof value.continuation_documentation === "string"
        ? value.continuation_documentation.trim()
        : "",
    refined_search: refined,
  };
}
