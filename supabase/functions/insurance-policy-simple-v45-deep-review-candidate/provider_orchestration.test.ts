import { callAI, OPENAI_LUNA_MODEL, OPENAI_REASONING_EFFORT } from "./ai.ts";

Deno.test("isolated candidate calls Luna through Responses API only", async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = Deno.env.get("OPENAI_API_KEY");
  Deno.env.set("OPENAI_API_KEY", "test-openai-key");
  const requests: Array<{ url: string; body: Record<string, unknown> }> = [];
  globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? "{}")) as Record<
      string,
      unknown
    >;
    requests.push({ url: String(url), body });
    return Promise.resolve(
      new Response(
        JSON.stringify({
          status: "completed",
          model: OPENAI_LUNA_MODEL,
          output: [{
            type: "message",
            content: [{
              type: "output_text",
              text: JSON.stringify({
                search_terms: ["test"],
                exact_literals: [],
                codes: [],
                important_qualifiers: [],
                requested_relationships: ["coverage"],
                ambiguity: "clear",
                missing_slots: [],
                ambiguity_reason: null,
                clarification_question: null,
              }),
            }],
          }],
          usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;

  try {
    const result = await callAI(
      [{ role: "user", content: "Test coverage" }],
      "search_plan",
      5_000,
    );
    if (requests.length !== 1) throw new Error("Expected one OpenAI request.");
    if (requests[0].url !== "https://api.openai.com/v1/responses") {
      throw new Error("Responses API endpoint was not used.");
    }
    if (requests[0].body.model !== OPENAI_LUNA_MODEL) {
      throw new Error("Luna model was not used.");
    }
    const reasoning = requests[0].body.reasoning as Record<string, unknown>;
    if (reasoning.effort !== OPENAI_REASONING_EFFORT) {
      throw new Error("Medium reasoning was not used.");
    }
    if (
      "messages" in requests[0].body || "response_format" in requests[0].body
    ) {
      throw new Error("Chat Completions fields leaked into Responses request.");
    }
    if (result.usage.provider !== "openai_luna" || result.usage.fallback_used) {
      throw new Error("Isolated OpenAI provider usage was not recorded.");
    }
    if (result.provider_errors.length !== 0) {
      throw new Error("Successful call must not contain provider errors.");
    }
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) Deno.env.delete("OPENAI_API_KEY");
    else Deno.env.set("OPENAI_API_KEY", originalKey);
  }
});

Deno.test("isolated candidate records OpenAI failure without fallback", async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = Deno.env.get("OPENAI_API_KEY");
  Deno.env.set("OPENAI_API_KEY", "test-openai-key");
  let calls = 0;
  globalThis.fetch = (() => {
    calls += 1;
    return Promise.resolve(
      new Response(
        JSON.stringify({ error: { message: "rate limited" } }),
        { status: 429 },
      ),
    );
  }) as typeof fetch;

  try {
    let diagnostics: Array<Record<string, unknown>> = [];
    try {
      await callAI(
        [{ role: "user", content: "Test coverage" }],
        "search_plan",
        5_000,
      );
      throw new Error("Expected provider failure.");
    } catch (error) {
      diagnostics = (error as { diagnostics?: Array<Record<string, unknown>> })
        .diagnostics ?? [];
    }
    if (calls !== 1) {
      throw new Error("Provider must not be retried or replaced.");
    }
    if (
      diagnostics[0]?.provider !== "openai_luna" ||
      diagnostics[0]?.status !== 429
    ) {
      throw new Error("OpenAI failure diagnostic was not preserved.");
    }
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) Deno.env.delete("OPENAI_API_KEY");
    else Deno.env.set("OPENAI_API_KEY", originalKey);
  }
});
