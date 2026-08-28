import type { JsonMap, ProviderUsage } from './types.ts';

export const AI_MODEL = Deno.env.get('INSURANCE_REASONING_MODEL') ?? 'openai/gpt-oss-120b';

type CallType = ProviderUsage['call_type'];
type Message = { role: 'system' | 'user' | 'assistant'; content: string };
type AIResult = { json: JsonMap; usage: ProviderUsage };

const providers = [
  {
    name: 'together' as const,
    endpoint: 'https://api.together.xyz/v1/chat/completions',
    secret: 'TOGETHER_API_KEY',
  },
  {
    name: 'groq_fallback' as const,
    endpoint: 'https://api.groq.com/openai/v1/chat/completions',
    secret: 'GROQ_API_KEY',
  },
];

export class ProvidersUnavailableError extends Error {
  constructor(readonly diagnostics: JsonMap[]) {
    super('Both configured reasoning providers are unavailable.');
    this.name = 'ProvidersUnavailableError';
  }
}

function parseJsonObject(value: unknown): JsonMap {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value as JsonMap;
  if (typeof value !== 'string') throw new Error('The model did not return JSON text.');
  const trimmed = value.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const parsed = JSON.parse(trimmed) as unknown;
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('The model response is not a JSON object.');
  }
  return parsed as JsonMap;
}

function isTransient(status: number) {
  return status === 408 || status === 409 || status === 425 || status === 429 || status >= 500;
}

async function callProvider(
  provider: (typeof providers)[number],
  messages: Message[],
  callType: CallType,
  maxOutputTokens: number,
  timeoutMs: number,
): Promise<AIResult> {
  const apiKey = Deno.env.get(provider.secret);
  if (!apiKey) throw Object.assign(new Error(`${provider.name} is not configured.`), { transient: true });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const started = Date.now();
  try {
    const tokenField = provider.name === 'together'
      ? { max_tokens: maxOutputTokens + 1200 }
      : { max_completion_tokens: maxOutputTokens };
    const response = await fetch(provider.endpoint, {
      method: 'POST',
      signal: controller.signal,
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: AI_MODEL,
        messages,
        temperature: 0,
        reasoning_effort: 'low',
        response_format: { type: 'json_object' },
        ...tokenField,
      }),
    });
    const payload = await response.json().catch(() => ({})) as JsonMap;
    if (!response.ok) {
      const error = Object.assign(new Error(`${provider.name} returned HTTP ${response.status}.`), {
        transient: isTransient(response.status),
        status: response.status,
      });
      throw error;
    }
    const choices = Array.isArray(payload.choices) ? payload.choices as JsonMap[] : [];
    const message = choices[0]?.message as JsonMap | undefined;
    const content = message?.content || message?.reasoning_content;
    return {
      json: parseJsonObject(content),
      usage: {
        provider: provider.name,
        model: AI_MODEL,
        call_type: callType,
        latency_ms: Date.now() - started,
        usage: payload.usage && typeof payload.usage === 'object' ? payload.usage as JsonMap : null,
        fallback_used: provider.name === 'groq_fallback',
      },
    };
  } finally {
    clearTimeout(timeout);
  }
}

export async function callReasoningJson(
  messages: Message[],
  callType: CallType,
  maxOutputTokens: number,
  timeoutMs: number,
): Promise<AIResult> {
  const diagnostics: JsonMap[] = [];
  for (const provider of providers) {
    try {
      return await callProvider(provider, messages, callType, maxOutputTokens, timeoutMs);
    } catch (error) {
      const row = error as Error & { transient?: boolean; status?: number };
      diagnostics.push({ provider: provider.name, status: row.status ?? null, reason: row.name, message: row.message.slice(0, 300) });
    }
  }
  throw new ProvidersUnavailableError(diagnostics);
}
