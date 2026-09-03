import { assertEquals } from "jsr:@std/assert@1";
import { runAgenticLoop } from "./agentic_loop.ts";
import type { AgenticProviderTurn } from "./ai.ts";
import type { AgenticToolExecutor } from "./agentic_tools.ts";

const usage = {
  provider: "openai_luna" as const,
  model: "gpt-5.6-luna",
  call_type: "agentic_reasoning" as const,
  latency_ms: 1,
  usage: null,
  fallback_used: false,
};

Deno.test("V44 recovers when the first retrieval is not answer-bearing", async () => {
  let calls = 0;
  const turns: AgenticProviderTurn[] = [
    {
      final: null,
      function_calls: [{
        call_id: "c1",
        name: "search_approved_policy",
        arguments: { query: "wrong broad result" },
        raw: {},
      }],
      output_items: [{
        type: "function_call",
        call_id: "c1",
        name: "search_approved_policy",
        arguments: "{}",
      }],
      usage,
      provider_errors: [],
    },
    {
      final: null,
      function_calls: [{
        call_id: "c2",
        name: "fetch_table_context",
        arguments: { document_id: "d1" },
        raw: {},
      }],
      output_items: [{
        type: "function_call",
        call_id: "c2",
        name: "fetch_table_context",
        arguments: "{}",
      }],
      usage,
      provider_errors: [],
    },
    {
      final: {
        action: "answer",
        interpretation: {
          language: "en",
          turn_kind: "standalone",
          canonical_entities: ["Drug X"],
          indication: null,
          requested_relationships: ["specialty eligibility"],
          numeric_qualifiers: [],
          formulation: null,
          resolved_question: "Who can prescribe Drug X?",
          genuinely_ambiguous: false,
          ambiguity_reason: null,
          clarification_question: null,
        },
        answer: "Family Medicine may prescribe it. [E2]",
        evidence_ids: ["E2"],
        evidence_judgements: [{
          evidence_id: "E1",
          disposition: "rejected",
          reason: "wrong_relationship",
        }, {
          evidence_id: "E2",
          disposition: "accepted",
          reason: "answers_requested_relationship",
        }],
        unresolved_facets: [],
      },
      function_calls: [],
      output_items: [{ type: "message" }],
      usage,
      provider_errors: [],
    },
  ];
  const executed: string[] = [];
  const executor = {
    execute: (name: string) => {
      executed.push(name);
      return Promise.resolve({
        candidates: [],
        evidence: [],
        diagnostics: [],
        queries: [],
        metadata: null,
      });
    },
  } as unknown as AgenticToolExecutor;
  const result = await runAgenticLoop({
    question: "Who can prescribe Drug X?",
    context: null,
    executor,
    timeoutForTurn: () => 10_000,
    callTurn: () => Promise.resolve(turns[calls++]),
  });
  assertEquals(executed, ["search_approved_policy", "fetch_table_context"]);
  assertEquals(result.final.action, "answer");
  assertEquals(result.traces.length, 2);
});
