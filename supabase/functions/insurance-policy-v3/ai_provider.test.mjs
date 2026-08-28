import assert from 'node:assert/strict';
import test from 'node:test';
import {
  AI_MODEL,
  AIProviderError,
  AIProvidersTemporarilyUnavailableError,
  callAI,
  providerRequestBody,
  rateLimitDiagnostic,
} from './ai_provider.ts';

const request = {
  maxOutputTokens: 320,
  response_format: { type: 'json_object' },
  together_response_format: { type: 'json_schema', json_schema: { name: 'test', schema: { type: 'object' } } },
  messages: [{ role: 'user', content: 'test' }],
};

test('uses provider-specific token parameters and reserves Together reasoning capacity', () => {
  assert.equal(AI_MODEL, 'openai/gpt-oss-120b');
  const together = providerRequestBody('together', request);
  const groq = providerRequestBody('groq_fallback', request);
  assert.equal(together.max_tokens, 1344);
  assert.equal('max_completion_tokens' in together, false);
  assert.equal(groq.max_completion_tokens, 320);
  assert.equal('max_tokens' in groq, false);
  assert.equal(together.temperature, 0);
  assert.equal(groq.temperature, 0);
  assert.equal(together.reasoning_effort, 'low');
  assert.equal(groq.reasoning_effort, 'low');
  assert.equal(together.response_format.type, 'json_schema');
  assert.equal(groq.response_format.type, 'json_schema');
  assert.equal(groq.response_format.json_schema.strict, true);
});

test('captures the exact Groq diagnostic headers without authorization data', () => {
  const response = new Response('{}', {
    status: 429,
    headers: {
      'retry-after': '42',
      'x-ratelimit-limit-tokens': '8000',
      'x-ratelimit-remaining-tokens': '0',
      'x-ratelimit-reset-tokens': '42s',
      'x-ratelimit-limit-requests': '30',
      'x-ratelimit-remaining-requests': '12',
      'x-ratelimit-reset-requests': '2s',
    },
  });
  const diagnostic = rateLimitDiagnostic('groq_fallback', response, request, 'semantic', { usage: { prompt_tokens: 456 } });
  assert.equal(diagnostic['retry-after'], '42');
  assert.equal(diagnostic['x-ratelimit-limit-tokens'], '8000');
  assert.equal(diagnostic['x-ratelimit-reset-requests'], '2s');
  assert.equal(diagnostic.provider, 'groq_fallback');
  assert.equal(diagnostic.model, AI_MODEL);
  assert.equal(diagnostic.prompt_tokens, 456);
  assert.equal(diagnostic.requested_max_output_tokens, 320);
  assert.equal(diagnostic.call_type, 'semantic');
  assert.equal('authorization' in diagnostic, false);
});

test('calls Together first and falls back once to Groq only after a transient response', async () => {
  const originalDeno = globalThis.Deno;
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const originalWarn = console.warn;
  const calls = [];
  globalThis.Deno = { env: { get: (name) => name === 'TOGETHER_API_KEY' ? 'together-test' : name === 'GROQ_API_KEY' ? 'groq-test' : null } };
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), body: JSON.parse(options.body) });
    if (calls.length === 1) return new Response(JSON.stringify({ error: { type: 'rate_limit' } }), { status: 429 });
    return new Response(JSON.stringify({ choices: [{ message: { content: '{}' } }], usage: { total_tokens: 3 } }), { status: 200 });
  };
  console.error = () => {};
  console.warn = () => {};
  try {
    const result = await callAI(request, 'semantic');
    assert.equal(result.provider, 'groq_fallback');
    assert.equal(calls.length, 2);
    assert.equal(calls[0].url, 'https://api.together.xyz/v1/chat/completions');
    assert.equal(calls[1].url, 'https://api.groq.com/openai/v1/chat/completions');
    assert.equal(calls[0].body.max_tokens, 1344);
    assert.equal(calls[1].body.max_completion_tokens, 320);
  } finally {
    globalThis.Deno = originalDeno;
    globalThis.fetch = originalFetch;
    console.error = originalError;
    console.warn = originalWarn;
  }
});

test('returns Together directly without contacting Groq after a successful response', async () => {
  const originalDeno = globalThis.Deno;
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.Deno = { env: { get: () => 'test-key' } };
  globalThis.fetch = async () => {
    calls += 1;
    return new Response(JSON.stringify({ choices: [{ message: { content: '{}' } }], usage: { total_tokens: 2 } }), { status: 200 });
  };
  try {
    const result = await callAI(request, 'semantic');
    assert.equal(result.provider, 'together');
    assert.equal(calls, 1);
  } finally {
    globalThis.Deno = originalDeno;
    globalThis.fetch = originalFetch;
  }
});

test('returns the friendly-service error type only after both providers fail temporarily', async () => {
  const originalDeno = globalThis.Deno;
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const originalWarn = console.warn;
  let calls = 0;
  globalThis.Deno = { env: { get: () => 'test-key' } };
  globalThis.fetch = async () => {
    calls += 1;
    return new Response(JSON.stringify({ error: { type: 'overloaded' } }), { status: 503 });
  };
  console.error = () => {};
  console.warn = () => {};
  try {
    await assert.rejects(() => callAI(request, 'final-answer'), AIProvidersTemporarilyUnavailableError);
    assert.equal(calls, 2);
  } finally {
    globalThis.Deno = originalDeno;
    globalThis.fetch = originalFetch;
    console.error = originalError;
    console.warn = originalWarn;
  }
});

test('does not fall back when Together rejects a non-temporary request', async () => {
  const originalDeno = globalThis.Deno;
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  let calls = 0;
  globalThis.Deno = { env: { get: () => 'test-key' } };
  globalThis.fetch = async () => {
    calls += 1;
    return new Response(JSON.stringify({ error: { type: 'invalid_request' } }), { status: 400 });
  };
  console.error = () => {};
  try {
    await assert.rejects(() => callAI(request, 'semantic'), (error) => {
      assert.equal(error instanceof AIProviderError, true);
      assert.equal(error.temporary, false);
      return true;
    });
    assert.equal(calls, 1);
  } finally {
    globalThis.Deno = originalDeno;
    globalThis.fetch = originalFetch;
    console.error = originalError;
  }
});
