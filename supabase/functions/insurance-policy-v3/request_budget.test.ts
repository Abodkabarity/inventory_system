import { assertEquals } from 'jsr:@std/assert@1';
import { OPTIONAL_REASONING_CUTOFF_MS, requestBudgetState, SAFE_SYNTHESIS_CUTOFF_MS } from './request_budget.ts';

Deno.test('optional multi-pass reasoning stops with room before the platform timeout', () => {
  const started = 1_000;
  assertEquals(requestBudgetState(started, started + OPTIONAL_REASONING_CUTOFF_MS - 1).optional_reasoning_allowed, true);
  assertEquals(requestBudgetState(started, started + OPTIONAL_REASONING_CUTOFF_MS).optional_reasoning_allowed, false);
});

Deno.test('grounded synthesis replaces another AI call at the answer cutoff', () => {
  const started = 2_000;
  assertEquals(requestBudgetState(started, started + SAFE_SYNTHESIS_CUTOFF_MS - 1).ai_answer_allowed, true);
  assertEquals(requestBudgetState(started, started + SAFE_SYNTHESIS_CUTOFF_MS).ai_answer_allowed, false);
});
