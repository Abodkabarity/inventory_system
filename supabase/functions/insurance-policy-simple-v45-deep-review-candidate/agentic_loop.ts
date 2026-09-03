import {
  type AgenticProviderTurn,
  callAgenticTurn,
  type OpenAIModelRole,
  ProvidersUnavailableError,
} from "./ai.ts";
import { AgenticToolExecutor, compactToolResult } from "./agentic_tools.ts";
import type {
  AgenticFinal,
  AgenticInterpretation,
  AgenticToolCallTrace,
  JsonMap,
  ProviderUsage,
} from "./types.ts";

const SYSTEM_PROMPT =
  `You are Luna, the primary reasoning agent for an approved insurance-policy knowledge base.

Your job is to understand the user's actual intent, search iteratively with the supplied controlled tools, inspect evidence, reject misleading evidence, and answer professionally from accepted approved evidence only.

Rules:
1. First resolve a structured interpretation: current entity, indication/context, requested relationship, numeric/formulation qualifiers, and whether this is standalone or a true follow-up.
2. A clear standalone question is isolated. Never inherit an old entity, claim, evidence ID, row, or conclusion.
3. A true follow-up may inherit only the entity/indication/formulation supplied in STRUCTURED PRIOR CONTEXT. It may never inherit prior claims, evidence, or conclusions.
4. Use tools to search. Search results are candidates, not mandatory evidence.
5. Inspect each candidate. Reject wrong entity, wrong indication, wrong relationship, semantic-only proximity, superseded source, duplicate, or unresolved conflict.
6. If the first search is poor, refine the search, fetch the surrounding section/table, search the entity's approved documents or policy family, or follow an explicit approved reference.
7. Prefer direct answer-bearing text and complete table context. Use source metadata when versions or authority matter.
8. Do not use general medical knowledge. Do not invent policy facts. Preserve exact drug, dose, number, operator, age, weight, specialty, indication, schedule, modality, exception, and qualifier.
9. Partial evidence proves only the stated part. It never proves full eligibility or approval unless every required facet is established.
10. Ask clarification only when a required semantic slot is genuinely unresolved and would materially change the answer. A short but semantically complete question must be searched and answered.
11. Cite every material claim using accepted evidence IDs such as [E3]. Cite source and page when available.
12. Answer in the user's language. Start with Yes/No when that directly answers the question.
13. Before finalizing, return a judgement for every evidence ID you materially inspected. Only accepted IDs may appear in evidence_ids or the answer.
14. If the user asks how the system should handle a genuinely unresolved conflict between active authoritative sources, use action=conflict; retrieval score is never authority and must not silently select the fact.

Use no more searches than necessary. When evidence is sufficient, stop searching and return the structured final result.`;

const DEEP_REVIEW_SYSTEM_PROMPT =
  `You are Terra, the on-demand deep-review reasoning agent for an approved insurance-policy knowledge base.

You are invoked only because the user marked a prior answer Incorrect or Incomplete. Re-evaluate the ORIGINAL QUESTION independently and produce a replacement answer using only approved evidence found with the supplied controlled tools.

Deep-review rules:
1. The prior answer is diagnostic context, never evidence. Do not defend it, copy its claims, inherit its evidence IDs, or assume its conclusion.
2. The feedback reason indicates what to investigate: Incorrect requires checking entity, relationship, polarity, numbers, qualifiers, and source authority; Incomplete additionally requires checking every directly requested facet and adjacent requirement needed for a complete answer.
3. Search again from the original question. Inspect complete sections/tables and use additional tool rounds when needed.
4. Preserve exact medication, indication, formulation, dose, number, operator, age, weight, specialty, schedule, modality, exception, and qualifier.
5. Partial evidence proves only the stated part and never full eligibility or approval.
6. Cite every material claim with newly accepted evidence IDs from this review.
7. Ask clarification only if the original question is genuinely ambiguous. If evidence remains insufficient or conflicting, say so safely.
8. Answer in the user's language and start with Yes/No when appropriate.
9. Return a judgement for every evidence ID materially inspected. Only accepted IDs may appear in evidence_ids or the answer.

When the evidence is sufficient, return a complete professional replacement answer.`;

function strings(value: unknown, limit: number) {
  return Array.isArray(value)
    ? [...new Set(value.map(String).map((item) => item.trim()).filter(Boolean))]
      .slice(0, limit)
    : [];
}

function nullable(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function normalizeAgenticFinal(value: JsonMap): AgenticFinal {
  const source =
    value.interpretation && typeof value.interpretation === "object" &&
      !Array.isArray(value.interpretation)
      ? value.interpretation as JsonMap
      : {};
  const action =
    ["answer", "clarify", "insufficient_evidence", "conflict"].includes(
        String(value.action),
      )
      ? String(value.action) as AgenticFinal["action"]
      : "insufficient_evidence";
  const language = ["ar", "en", "mixed"].includes(String(source.language))
    ? String(source.language) as AgenticInterpretation["language"]
    : "en";
  const turnKind = source.turn_kind === "follow_up"
    ? "follow_up"
    : "standalone";
  const interpretation: AgenticInterpretation = {
    language,
    turn_kind: turnKind,
    canonical_entities: strings(source.canonical_entities, 4),
    indication: nullable(source.indication),
    requested_relationships: strings(source.requested_relationships, 8),
    numeric_qualifiers: strings(source.numeric_qualifiers, 12),
    formulation: nullable(source.formulation),
    resolved_question: String(source.resolved_question ?? "").trim().slice(
      0,
      4_000,
    ),
    genuinely_ambiguous: source.genuinely_ambiguous === true,
    ambiguity_reason: nullable(source.ambiguity_reason),
    clarification_question: nullable(source.clarification_question),
  };
  const judgements = Array.isArray(value.evidence_judgements)
    ? value.evidence_judgements.flatMap((item) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) return [];
      const row = item as JsonMap;
      const evidenceId = String(row.evidence_id ?? "").trim();
      if (!evidenceId) return [];
      return [{
        evidence_id: evidenceId,
        disposition: row.disposition === "accepted"
          ? "accepted" as const
          : "rejected" as const,
        reason: String(
          row.reason ?? "other",
        ) as AgenticFinal["evidence_judgements"][number]["reason"],
      }];
    })
    : [];
  return {
    action,
    interpretation,
    answer: nullable(value.answer),
    evidence_ids: strings(value.evidence_ids, 24),
    evidence_judgements: judgements,
    unresolved_facets: strings(value.unresolved_facets, 12),
  };
}

function mayUseExceptionalRound(call: { name: string; arguments: JsonMap }) {
  if (
    [
      "fetch_table_context",
      "follow_approved_reference",
      "fetch_source_metadata",
    ].includes(call.name)
  ) return true;
  const values = JSON.stringify(call.arguments);
  return /\b(?:delegat|refer|table|conflict|version|supersed)\b/iu.test(values);
}

export type AgenticLoopResult = {
  final: AgenticFinal;
  traces: AgenticToolCallTrace[];
  usage: ProviderUsage[];
  provider_errors: JsonMap[];
  model_calls: number;
};

export async function runAgenticLoop(input: {
  question: string;
  context: JsonMap | null;
  executor: AgenticToolExecutor;
  timeoutForTurn: () => number;
  callTurn?: (
    input: JsonMap[],
    timeoutMs: number,
  ) => Promise<AgenticProviderTurn>;
  modelRole?: OpenAIModelRole;
  deepReview?:
    | { reason: "incorrect" | "incomplete"; priorAnswer: string }
    | null;
}): Promise<AgenticLoopResult> {
  const modelRole = input.modelRole ?? "primary";
  const callTurn = input.callTurn ??
    ((turnInput, timeoutMs) =>
      callAgenticTurn(turnInput, timeoutMs, modelRole));
  const transcript: JsonMap[] = [
    {
      role: "system",
      content: modelRole === "deep_review"
        ? DEEP_REVIEW_SYSTEM_PROMPT
        : SYSTEM_PROMPT,
    },
    {
      role: "user",
      content: modelRole === "deep_review"
        ? `ORIGINAL USER QUESTION:\n${input.question}\n\nUSER FEEDBACK REASON:\n${
          input.deepReview?.reason ?? "incorrect"
        }\n\nPRIOR ANSWER (DIAGNOSTIC CONTEXT ONLY; NOT EVIDENCE):\n${
          input.deepReview?.priorAnswer ?? ""
        }\n\nRun a fresh evidence review.`
        : `CURRENT USER QUESTION:\n${input.question}\n\nCURRENT TURN CLASSIFICATION AND SAFE PRIOR CONTEXT:\n${
          JSON.stringify(
            input.context ?? { turn_kind: "standalone", prior: null },
          )
        }`,
    },
  ];
  const traces: AgenticToolCallTrace[] = [];
  const usage: ProviderUsage[] = [];
  const providerErrors: JsonMap[] = [];
  let toolRounds = 0;
  let exceptionalRoundAvailable = true;
  for (let modelCalls = 1; modelCalls <= 6; modelCalls += 1) {
    const turn = await callTurn(transcript, input.timeoutForTurn());
    usage.push(turn.usage);
    providerErrors.push(...turn.provider_errors);
    transcript.push(...turn.output_items);
    if (turn.final) {
      return {
        final: normalizeAgenticFinal(turn.final),
        traces,
        usage,
        provider_errors: providerErrors,
        model_calls: modelCalls,
      };
    }
    if (!turn.function_calls.length) {
      throw new ProvidersUnavailableError([{
        provider: modelRole === "deep_review" ? "openai_terra" : "openai_luna",
        stage: "agentic_reasoning",
        message: "Agent returned neither a tool call nor a final result.",
      }]);
    }
    toolRounds += 1;
    const first = turn.function_calls[0];
    const baseAllowed = toolRounds <= 3;
    const exceptionalAllowed = !baseAllowed && exceptionalRoundAvailable &&
      toolRounds === 4 && mayUseExceptionalRound(first);
    if (!baseAllowed && !exceptionalAllowed) {
      transcript.push({
        type: "function_call_output",
        call_id: first.call_id,
        output: JSON.stringify({
          error: "retrieval_round_limit_reached",
          instruction:
            "Return the safest final result from evidence already inspected.",
        }),
      });
      continue;
    }
    if (exceptionalAllowed) exceptionalRoundAvailable = false;
    for (const call of turn.function_calls.slice(0, 1)) {
      const started = Date.now();
      let resultCount = 0;
      let errorMessage: string | null = null;
      let output: JsonMap;
      try {
        const result = await input.executor.execute(call.name, call.arguments);
        resultCount = result.evidence.length;
        output = compactToolResult(result);
      } catch (error) {
        errorMessage = error instanceof Error ? error.message : String(error);
        output = { error: errorMessage };
      }
      traces.push({
        round: toolRounds,
        call_id: call.call_id,
        tool: call.name,
        arguments: call.arguments,
        result_count: resultCount,
        latency_ms: Date.now() - started,
        error: errorMessage,
      });
      transcript.push({
        type: "function_call_output",
        call_id: call.call_id,
        output: JSON.stringify(output),
      });
    }
  }
  throw new ProvidersUnavailableError([{
    provider: modelRole === "deep_review" ? "openai_terra" : "openai_luna",
    stage: "agentic_reasoning",
    message: "Agent did not finalize within the bounded loop.",
  }]);
}
