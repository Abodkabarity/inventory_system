import { strict as assert } from 'node:assert';
import test from 'node:test';
import { AI_MODEL, callReasoningJson } from './ai_provider.ts';

test('uses the required 120B model and falls back from Together to Groq', async () => {
  assert.equal(AI_MODEL, 'openai/gpt-oss-120b');
  const originalFetch = globalThis.fetch;
  Deno.env.set('TOGETHER_API_KEY', 'test-together');
  Deno.env.set('GROQ_API_KEY', 'test-groq');
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  globalThis.fetch = async (input, init) => {
    calls.push({ url: String(input), body: JSON.parse(String(init?.body)) });
    if (calls.length === 1) return new Response('{"error":"busy"}', { status: 429 });
    return new Response(JSON.stringify({ choices: [{ message: { content: '{"ok":true}' } }], usage: { total_tokens: 5 } }), { status: 200 });
  };
  try {
    const result = await callReasoningJson([{ role: 'user', content: 'test' }], 'semantic', 100, 1000);
    assert.equal(result.json.ok, true);
    assert.equal(result.usage.provider, 'groq_fallback');
    assert.equal(result.usage.fallback_used, true);
    assert.equal(calls.length, 2);
    assert.equal(calls[0].body.model, 'openai/gpt-oss-120b');
    assert.equal(calls[1].body.model, 'openai/gpt-oss-120b');
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.delete('TOGETHER_API_KEY');
    Deno.env.delete('GROQ_API_KEY');
  }
});
