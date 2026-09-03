import {
  callAgenticTurn,
  OPENAI_LUNA_MODEL,
  OPENAI_TERRA_MODEL,
} from "./ai.ts";
import { runAgenticLoop } from "./agentic_loop.ts";

function completedResponse(model: string) {
  return new Response(
    JSON.stringify({
      status: "completed",
      model,
      output: [{
        type: "message",
        content: [{
          type: "output_text",
          text: JSON.stringify({
            action: "insufficient_evidence",
            interpretation: {
              language: "en",
              turn_kind: "standalone",
              canonical_entities: ["Test Drug"],
              indication: null,
              requested_relationships: ["coverage"],
              numeric_qualifiers: [],
              formulation: null,
              resolved_question: "Is Test Drug covered?",
              genuinely_ambiguous: false,
              ambiguity_reason: null,
              clarification_question: null,
            },
            answer: null,
            evidence_ids: [],
            evidence_judgements: [],
            unresolved_facets: ["coverage evidence"],
          }),
        }],
      }],
      usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
    }),
    { status: 200 },
  );
}

Deno.test("normal reasoning uses Luna while on-demand deep review uses Terra", async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = Deno.env.get("OPENAI_API_KEY");
  Deno.env.set("OPENAI_API_KEY", "test-openai-key");
  const models: string[] = [];
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? "{}")) as { model: string };
    models.push(body.model);
    return Promise.resolve(completedResponse(body.model));
  }) as typeof fetch;

  try {
    const normal = await callAgenticTurn([], 5_000);
    const review = await callAgenticTurn([], 5_000, "deep_review");
    if (models.join(",") !== `${OPENAI_LUNA_MODEL},${OPENAI_TERRA_MODEL}`) {
      throw new Error(`Unexpected model routing: ${models.join(",")}`);
    }
    if (normal.usage.provider !== "openai_luna") {
      throw new Error("Normal reasoning did not record Luna.");
    }
    if (review.usage.provider !== "openai_terra") {
      throw new Error("Deep review did not record Terra.");
    }
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) Deno.env.delete("OPENAI_API_KEY");
    else Deno.env.set("OPENAI_API_KEY", originalKey);
  }
});

Deno.test("deep review prompt treats prior answer as diagnostics and starts a fresh search", async () => {
  let systemPrompt = "";
  let userPrompt = "";
  const executor = {
    execute: () => Promise.resolve({ evidence: [] }),
  } as never;
  await runAgenticLoop({
    question: "Is Test Drug covered?",
    context: null,
    executor,
    timeoutForTurn: () => 5_000,
    modelRole: "deep_review",
    deepReview: {
      reason: "incomplete",
      priorAnswer: "Prior incomplete answer",
    },
    callTurn: (input) => {
      systemPrompt = String(input[0]?.content ?? "");
      userPrompt = String(input[1]?.content ?? "");
      return Promise.resolve({
        final: {
          action: "insufficient_evidence",
          interpretation: {
            language: "en",
            turn_kind: "standalone",
            canonical_entities: ["Test Drug"],
            indication: null,
            requested_relationships: ["coverage"],
            numeric_qualifiers: [],
            formulation: null,
            resolved_question: "Is Test Drug covered?",
            genuinely_ambiguous: false,
            ambiguity_reason: null,
            clarification_question: null,
          },
          answer: null,
          evidence_ids: [],
          evidence_judgements: [],
          unresolved_facets: ["coverage evidence"],
        },
        function_calls: [],
        output_items: [],
        usage: {
          provider: "openai_terra",
          model: OPENAI_TERRA_MODEL,
          call_type: "agentic_reasoning",
          latency_ms: 1,
          usage: null,
          fallback_used: false,
        },
        provider_errors: [],
      });
    },
  });
  if (
    !systemPrompt.includes("on-demand deep-review") ||
    !systemPrompt.includes("prior answer is diagnostic context, never evidence")
  ) {
    throw new Error("Deep-review safety prompt was not selected.");
  }
  if (
    !userPrompt.includes("incomplete") ||
    !userPrompt.includes("Prior incomplete answer") ||
    !userPrompt.includes("Run a fresh evidence review")
  ) {
    throw new Error("Deep-review context was not supplied correctly.");
  }
});
