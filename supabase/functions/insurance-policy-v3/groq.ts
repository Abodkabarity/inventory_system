import type { SemanticInterpretation, V3Chunk } from './retrieval.ts';

export const GROQ_MODEL = 'openai/gpt-oss-20b';
const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';

type Usage = { prompt_tokens?: number; completion_tokens?: number; total_tokens?: number } | null;

async function callGroq(body: Record<string, unknown>) {
  const apiKey = Deno.env.get('GROQ_API_KEY');
  if (!apiKey) throw new Error('groq_not_configured');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);
  try {
    const response = await fetch(ENDPOINT, {
      method: 'POST', signal: controller.signal,
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: GROQ_MODEL, temperature: 0, reasoning_effort: 'low', include_reasoning: false, ...body }),
    });
    if (!response.ok) {
      if (response.status === 429) {
        const retryAfter = response.headers.get('retry-after') ?? 'unknown';
        let limitType = 'unknown';
        try {
          const failure = await response.json();
          limitType = String(failure?.error?.code ?? failure?.error?.type ?? 'unknown').replace(/[^a-z0-9_.-]/gi, '_').slice(0, 80);
        } catch { /* The status and Retry-After header remain sufficient. */ }
        throw new Error(`groq_rate_limited:${limitType}:retry_after_${retryAfter}`);
      }
      let failureCode = 'unknown';
      try {
        const failure = await response.json();
        failureCode = `${failure?.error?.code ?? failure?.error?.type ?? 'unknown'}:${failure?.error?.message ?? ''}`
          .replace(/[^a-z0-9_.:-]/gi, '_').slice(0, 180);
      } catch { /* Preserve the HTTP status when no JSON body exists. */ }
      throw new Error(`groq_http_${response.status}:${failureCode}`);
    }
    return await response.json();
  } finally { clearTimeout(timeout); }
}

function parseJson(value: unknown) {
  if (typeof value !== 'string') throw new Error('groq_malformed_response');
  const clean = value.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  return JSON.parse(clean) as Record<string, unknown>;
}

export async function interpretQuestion(question: string): Promise<{ semantic: SemanticInterpretation; usage: Usage; latency_ms: number }> {
  const started = Date.now();
  const payload = await callGroq({
    max_completion_tokens: 320,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: `Interpret a short insurance-policy question. Never supply policy facts. Return JSON only with: route (policy_question, catalog_discovery, source_request, clarification_required, out_of_scope), medication, generic, indication, intent[], requested_dimensions[], treatment_stage (initiation, continuation, refill, or null), facts[] (concept,value,unit,polarity,temporal), source_requested. Preserve negation, numbers, units, abbreviations, and shorthand. Keep output compact.` },
      { role: 'user', content: question },
    ],
  });
  const raw = parseJson(payload?.choices?.[0]?.message?.content);
  const routes = new Set(['policy_question', 'catalog_discovery', 'source_request', 'clarification_required', 'out_of_scope']);
  const stringOrNull = (value: unknown) => typeof value === 'string' && value.trim() ? value.trim() : null;
  const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string').slice(0, 12) : [];
  const facts = Array.isArray(raw.facts) ? raw.facts.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const fact = item as Record<string, unknown>;
    if (typeof fact.concept !== 'string') return [];
    return [{ concept: fact.concept, value: ['string', 'number', 'boolean'].includes(typeof fact.value) ? fact.value as string | number | boolean : null, unit: stringOrNull(fact.unit), polarity: typeof fact.polarity === 'string' ? fact.polarity : 'unknown', temporal: stringOrNull(fact.temporal) }];
  }).slice(0, 12) : [];
  return {
    semantic: {
      route: routes.has(String(raw.route)) ? raw.route as SemanticInterpretation['route'] : 'clarification_required',
      medication: stringOrNull(raw.medication), generic: stringOrNull(raw.generic), indication: stringOrNull(raw.indication),
      intent: strings(raw.intent), requested_dimensions: strings(raw.requested_dimensions), treatment_stage: stringOrNull(raw.treatment_stage),
      facts, source_requested: raw.source_requested === true,
    },
    usage: payload?.usage ?? null, latency_ms: Date.now() - started,
  };
}

export async function answerFromEvidence(
  question: string, semantic: SemanticInterpretation, evidence: V3Chunk[],
): Promise<{ answer: string; used_evidence_ids: string[]; usage: Usage; latency_ms: number }> {
  const started = Date.now();
  const supplied = evidence.map((chunk, index) => ({
    id: `E${index + 1}`,
    text: chunk.chunk_text,
    source_id: { document: chunk.document_title, file: chunk.file_name, page_from: chunk.page_from, page_to: chunk.page_to, sheet: chunk.sheet_name, row_from: chunk.row_from, row_to: chunk.row_to },
  }));
  const payload = await callGroq({
    max_completion_tokens: 520,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: `Answer insurance-policy questions using ONLY the supplied approved evidence. Never use external medical knowledge or invent missing facts. Preserve thresholds, units, time windows, negation, AND/OR logic, and initiation versus continuation. Reason over comparisons when the source states a criterion. If evidence conflicts, state the conflict. If insufficient, say the approved documents do not establish it. Be concise and answer in the user's language. Do not write source/page citations; the server adds them. Return JSON only: {"answer":"...","used_evidence_ids":["E1"]}. Use only supplied IDs actually relied on.` },
      { role: 'user', content: JSON.stringify({ question, verified_semantic_interpretation: semantic, approved_evidence: supplied }) },
    ],
  });
  const raw = parseJson(payload?.choices?.[0]?.message?.content);
  const allowed = new Set(supplied.map((item) => item.id));
  const used = Array.isArray(raw.used_evidence_ids) ? [...new Set(raw.used_evidence_ids.filter((item): item is string => typeof item === 'string' && allowed.has(item)))] : [];
  if (typeof raw.answer !== 'string' || !raw.answer.trim() || used.length === 0) throw new Error('groq_malformed_response');
  return { answer: raw.answer.trim(), used_evidence_ids: used, usage: payload?.usage ?? null, latency_ms: Date.now() - started };
}
