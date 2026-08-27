import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const MODEL = Deno.env.get('INSURANCE_EMBEDDING_MODEL') ?? 'intfloat/multilingual-e5-large-instruct';
const VERSION = Deno.env.get('INSURANCE_EMBEDDING_VERSION') ?? 'together-e5-v1';
const ENDPOINT = 'https://api.together.xyz/v1/embeddings';
const EXPECTED_DIMENSION = 1024;

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function safeCode(value: unknown) {
  return String(value ?? 'embedding_error').replace(/[^a-zA-Z0-9_.:-]/g, '_').slice(0, 120);
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const expectedToken = Deno.env.get('INSURANCE_EMBEDDING_WORKER_TOKEN');
  if (!expectedToken || request.headers.get('x-worker-token') !== expectedToken) return json({ error: 'unauthorized' }, 401);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
  const body = await request.json().catch(() => ({})) as Record<string, unknown>;
  const batchSize = Math.max(1, Math.min(Number(body.batch_size ?? 32), 64));
  let refresh: unknown = null;
  if (body.refresh_search_units === true) {
    const result = await db.rpc('insurance_v3_refresh_search_units');
    if (result.error) return json({ error: 'refresh_failed', code: safeCode(result.error.code) }, 500);
    refresh = result.data;
  }

  const claim = await db.rpc('insurance_v3_claim_embedding_units', { p_model: MODEL, p_version: VERSION, p_limit: batchSize });
  if (claim.error) return json({ error: 'claim_failed', code: safeCode(claim.error.code) }, 500);
  const units = (claim.data ?? []) as Array<{ id: string; retrieval_text: string; content_hash: string }>;
  if (units.length === 0) return json({ model: MODEL, version: VERSION, claimed: 0, embedded: 0, failed: 0, refresh });

  const apiKey = Deno.env.get('TOGETHER_API_KEY');
  if (!apiKey) return json({ error: 'embedding_provider_not_configured' }, 503);
  let response: Response;
  try {
    response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: MODEL, input: units.map((unit) => `passage: ${unit.retrieval_text.slice(0, 1400)}`) }),
    });
  } catch {
    response = new Response('', { status: 503 });
  }

  if (!response.ok) {
    const code = `provider_http_${response.status}`;
    await Promise.all(units.map((unit) => db.from('insurance_v3_search_units').update({ embedding_status: 'failed', embedding_last_error: code, embedding_updated_at: new Date().toISOString() }).eq('id', unit.id)));
    return json({ error: 'embedding_provider_unavailable', status: response.status, claimed: units.length }, response.status === 429 ? 429 : 503);
  }

  const payload = await response.json() as Record<string, unknown>;
  const data = Array.isArray(payload.data) ? payload.data as Array<Record<string, unknown>> : [];
  let embedded = 0;
  let failed = 0;
  for (let index = 0; index < units.length; index += 1) {
    const vector = data.find((item) => item.index === index)?.embedding;
    if (!Array.isArray(vector) || vector.length !== EXPECTED_DIMENSION || vector.some((value) => typeof value !== 'number')) {
      failed += 1;
      await db.from('insurance_v3_search_units').update({ embedding_status: 'failed', embedding_last_error: 'invalid_embedding_dimension', embedding_updated_at: new Date().toISOString() }).eq('id', units[index].id);
      continue;
    }
    const update = await db.from('insurance_v3_search_units').update({
      embedding: vector, embedding_model: MODEL, embedding_version: VERSION,
      embedding_content_hash: units[index].content_hash, embedding_status: 'ready',
      embedding_last_error: null, embedding_updated_at: new Date().toISOString(),
    }).eq('id', units[index].id);
    if (update.error) {
      failed += 1;
      await db.from('insurance_v3_search_units').update({ embedding_status: 'failed', embedding_last_error: safeCode(update.error.code), embedding_updated_at: new Date().toISOString() }).eq('id', units[index].id);
    } else embedded += 1;
  }
  return json({ model: MODEL, version: VERSION, dimension: EXPECTED_DIMENSION, claimed: units.length, embedded, failed, refresh, usage: payload.usage ?? null });
});
