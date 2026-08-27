export const EMBEDDING_MODEL = Deno.env.get('INSURANCE_EMBEDDING_MODEL') ?? 'intfloat/multilingual-e5-large-instruct';
export const EMBEDDING_DIMENSION = 1024;

export type QueryEmbeddingResult = {
  embedding: number[] | null;
  model: string;
  usage: Record<string, unknown> | null;
  latency_ms: number;
  degraded: boolean;
  reason: string | null;
};

export async function embedRetrievalQuery(query: string): Promise<QueryEmbeddingResult> {
  const started = Date.now();
  const apiKey = Deno.env.get('TOGETHER_API_KEY');
  if (!apiKey) return { embedding: null, model: EMBEDDING_MODEL, usage: null, latency_ms: 0, degraded: true, reason: 'not_configured' };
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetch('https://api.together.xyz/v1/embeddings', {
      method: 'POST', signal: controller.signal,
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: EMBEDDING_MODEL,
        input: `Instruct: Retrieve approved insurance-policy evidence that answers the information need.\nQuery: ${query.slice(0, 1800)}`,
      }),
    });
    if (!response.ok) return { embedding: null, model: EMBEDDING_MODEL, usage: null, latency_ms: Date.now() - started, degraded: true, reason: `http_${response.status}` };
    const payload = await response.json() as Record<string, unknown>;
    const data = Array.isArray(payload.data) ? payload.data as Array<Record<string, unknown>> : [];
    const embedding = data[0]?.embedding;
    if (!Array.isArray(embedding) || embedding.length !== EMBEDDING_DIMENSION || embedding.some((value) => typeof value !== 'number')) {
      return { embedding: null, model: EMBEDDING_MODEL, usage: payload.usage as Record<string, unknown> ?? null, latency_ms: Date.now() - started, degraded: true, reason: 'invalid_dimension' };
    }
    return { embedding: embedding as number[], model: EMBEDDING_MODEL, usage: payload.usage as Record<string, unknown> ?? null, latency_ms: Date.now() - started, degraded: false, reason: null };
  } catch (error) {
    const reason = error instanceof DOMException && error.name === 'AbortError' ? 'timeout' : 'network_error';
    return { embedding: null, model: EMBEDDING_MODEL, usage: null, latency_ms: Date.now() - started, degraded: true, reason };
  } finally {
    clearTimeout(timeout);
  }
}
