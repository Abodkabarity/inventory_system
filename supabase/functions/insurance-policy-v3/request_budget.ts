export const OPTIONAL_REASONING_CUTOFF_MS = 65_000;
export const SAFE_SYNTHESIS_CUTOFF_MS = 92_000;

export function requestBudgetState(startedAt: number, now = Date.now()) {
  const elapsed_ms = Math.max(0, now - startedAt);
  return {
    elapsed_ms,
    optional_reasoning_allowed: elapsed_ms < OPTIONAL_REASONING_CUTOFF_MS,
    ai_answer_allowed: elapsed_ms < SAFE_SYNTHESIS_CUTOFF_MS,
  };
}
