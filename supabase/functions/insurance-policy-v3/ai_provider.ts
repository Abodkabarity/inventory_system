export const AI_MODEL = 'openai/gpt-oss-20b';

const TOGETHER_ENDPOINT = 'https://api.together.xyz/v1/chat/completions';
const GROQ_ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';
// Together counts hidden GPT-OSS reasoning inside max_tokens. Preserve the
// validated visible-output budget while reserving room for low-effort reasoning.
const TOGETHER_REASONING_TOKEN_RESERVE = 1024;

export type AIProviderName = 'together' | 'groq_fallback';
export type AICallType = 'semantic' | 'rerank' | 'final-answer';
export type AIUsage = {
  prompt_tokens?: number;
  completion_tokens?: number;
  input_tokens?: number;
  output_tokens?: number;
  total_tokens?: number;
} | null;

export type AIRequest = {
  maxOutputTokens: number;
  response_format: Record<string, unknown>;
  together_response_format?: Record<string, unknown>;
  messages: Array<{ role: string; content: string }>;
};

export type AICompletion = {
  payload: Record<string, unknown>;
  provider: AIProviderName;
  model: string;
};

type ProviderConfig = {
  name: AIProviderName;
  endpoint: string;
  secretName: 'TOGETHER_API_KEY' | 'GROQ_API_KEY';
};

const TOGETHER: ProviderConfig = {
  name: 'together', endpoint: TOGETHER_ENDPOINT, secretName: 'TOGETHER_API_KEY',
};
const GROQ_FALLBACK: ProviderConfig = {
  name: 'groq_fallback', endpoint: GROQ_ENDPOINT, secretName: 'GROQ_API_KEY',
};

const GROQ_RATE_LIMIT_HEADERS = [
  'retry-after',
  'x-ratelimit-limit-tokens',
  'x-ratelimit-remaining-tokens',
  'x-ratelimit-reset-tokens',
  'x-ratelimit-limit-requests',
  'x-ratelimit-remaining-requests',
  'x-ratelimit-reset-requests',
] as const;

const TOGETHER_RATE_LIMIT_HEADERS = [
  'retry-after',
  'x-ratelimit-limit',
  'x-ratelimit-remaining',
  'x-ratelimit-reset',
  'x-tokenlimit-limit',
  'x-tokenlimit-remaining',
  'x-ratelimit-limit-dynamic',
  'x-ratelimit-remaining-dynamic',
  'x-tokenlimit-limit-dynamic',
  'x-tokenlimit-remaining-dynamic',
] as const;

export class AIProviderError extends Error {
  readonly provider: AIProviderName;
  readonly status: number | null;
  readonly temporary: boolean;
  readonly providerCode: string;

  constructor(
    provider: AIProviderName,
    status: number | null,
    temporary: boolean,
    providerCode: string,
  ) {
    super(`ai_provider_error:${provider}:${status ?? 'network'}:${providerCode}`);
    this.name = 'AIProviderError';
    this.provider = provider;
    this.status = status;
    this.temporary = temporary;
    this.providerCode = providerCode;
  }
}

export class AIProvidersTemporarilyUnavailableError extends Error {
  constructor() {
    super('ai_providers_temporarily_unavailable');
    this.name = 'AIProvidersTemporarilyUnavailableError';
  }
}

function sanitizedCode(value: unknown) {
  return String(value ?? 'unknown').replace(/[^a-z0-9_.-]/gi, '_').slice(0, 80);
}

function failureRecord(value: unknown) {
  return value && typeof value === 'object' ? value as Record<string, unknown> : null;
}

function failureCode(failure: Record<string, unknown> | null) {
  const error = failureRecord(failure?.error);
  return sanitizedCode(error?.code ?? error?.type ?? failure?.error_type ?? 'unknown');
}

function numericUsageValue(failure: Record<string, unknown> | null, key: 'prompt_tokens' | 'input_tokens') {
  const error = failureRecord(failure?.error);
  const candidates = [failure?.usage, error?.usage, failure, error];
  for (const candidate of candidates) {
    const record = failureRecord(candidate);
    const value = record?.[key];
    if (typeof value === 'number') return value;
  }
  return null;
}

export function providerRequestBody(provider: AIProviderName, request: AIRequest) {
  const common = {
    model: AI_MODEL,
    temperature: 0,
    reasoning_effort: 'low',
  };
  return provider === 'together'
    ? {
      ...common,
      response_format: request.together_response_format ?? request.response_format,
      // Together's GPT-OSS chat template uses the OpenAI developer role for
      // instruction messages. The prompt text itself remains unchanged.
      messages: request.messages.map((message) => message.role === 'system' ? { ...message, role: 'developer' } : message),
      max_tokens: request.maxOutputTokens + TOGETHER_REASONING_TOKEN_RESERVE,
    }
    : {
      ...common,
      response_format: request.response_format,
      messages: request.messages,
      include_reasoning: false,
      max_completion_tokens: request.maxOutputTokens,
    };
}

export function rateLimitDiagnostic(
  provider: AIProviderName,
  response: Response,
  request: AIRequest,
  callType: AICallType,
  failure: Record<string, unknown> | null,
) {
  const names = provider === 'together' ? TOGETHER_RATE_LIMIT_HEADERS : GROQ_RATE_LIMIT_HEADERS;
  const headers = Object.fromEntries(names.map((name) => [name, response.headers.get(name)]));
  return {
    ...headers,
    provider,
    model: AI_MODEL,
    prompt_tokens: numericUsageValue(failure, 'prompt_tokens'),
    input_tokens: numericUsageValue(failure, 'input_tokens'),
    requested_max_output_tokens: request.maxOutputTokens,
    call_type: callType,
  };
}

function isTemporaryStatus(status: number) {
  return status === 408 || status === 429 || status >= 500;
}

async function callProvider(provider: ProviderConfig, request: AIRequest, callType: AICallType): Promise<AICompletion> {
  const apiKey = Deno.env.get(provider.secretName);
  if (!apiKey) throw new AIProviderError(provider.name, null, false, 'not_configured');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);
  let response: Response;
  try {
    response = await fetch(provider.endpoint, {
      method: 'POST', signal: controller.signal,
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(providerRequestBody(provider.name, request)),
    });
  } catch (error) {
    const code = error instanceof DOMException && error.name === 'AbortError' ? 'timeout' : 'network_error';
    console.error('ai_provider_temporary_error', { provider: provider.name, model: AI_MODEL, call_type: callType, status: null, code });
    throw new AIProviderError(provider.name, null, true, code);
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    let failure: Record<string, unknown> | null = null;
    try { failure = failureRecord(await response.json()); } catch { /* Status remains authoritative. */ }
    const code = failureCode(failure);
    if (response.status === 429) {
      console.error('ai_provider_429_diagnostic', rateLimitDiagnostic(provider.name, response, request, callType, failure));
    } else {
      console.error('ai_provider_http_error', { provider: provider.name, model: AI_MODEL, call_type: callType, status: response.status, code });
    }
    throw new AIProviderError(provider.name, response.status, isTemporaryStatus(response.status), code);
  }

  const payload = failureRecord(await response.json());
  if (!payload) throw new AIProviderError(provider.name, response.status, false, 'malformed_response');
  return { payload, provider: provider.name, model: AI_MODEL };
}

export async function callAI(request: AIRequest, callType: AICallType): Promise<AICompletion> {
  try {
    return await callProvider(TOGETHER, request, callType);
  } catch (primaryError) {
    if (!(primaryError instanceof AIProviderError) || !primaryError.temporary) throw primaryError;
    console.warn('ai_provider_fallback', {
      from: 'together', to: 'groq_fallback', model: AI_MODEL, call_type: callType,
      status: primaryError.status, code: primaryError.providerCode,
    });
    try {
      return await callProvider(GROQ_FALLBACK, request, callType);
    } catch (fallbackError) {
      if (fallbackError instanceof AIProviderError && fallbackError.temporary) {
        throw new AIProvidersTemporarilyUnavailableError();
      }
      throw fallbackError;
    }
  }
}

export async function callGroqAfterMalformedTogether(
  request: AIRequest,
  callType: AICallType,
): Promise<AICompletion> {
  console.warn('ai_provider_fallback', {
    from: 'together', to: 'groq_fallback', model: AI_MODEL, call_type: callType,
    status: 200, code: `malformed_structured_output_${callType}`,
  });
  try {
    return await callProvider(GROQ_FALLBACK, request, callType);
  } catch (error) {
    if (error instanceof AIProviderError && error.temporary) {
      throw new AIProvidersTemporarilyUnavailableError();
    }
    throw error;
  }
}
