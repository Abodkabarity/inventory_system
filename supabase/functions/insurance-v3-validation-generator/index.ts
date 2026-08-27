import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const generationFormat = { type: 'json_schema', json_schema: { name: 'random_retrieval_cases', schema: { type: 'object', additionalProperties: false, properties: { cases: { type: 'array', maxItems: 8, items: { type: 'object', additionalProperties: false, properties: { candidate_id: { type: 'string' }, question: { type: 'string' }, language: { type: 'string' }, reference_answer: { type: 'string' }, reference_evidence: { type: 'string' } }, required: ['candidate_id', 'question', 'language', 'reference_answer', 'reference_evidence'] } } }, required: ['cases'] } } };
const evaluationFormat = { type: 'json_schema', json_schema: { name: 'random_retrieval_evaluation', schema: { type: 'object', additionalProperties: false, properties: { evaluations: { type: 'array', maxItems: 8, items: { type: 'object', additionalProperties: false, properties: { case_index: { type: 'integer' }, reference_valid: { type: 'boolean' }, top10_answer_bearing: { type: 'boolean' }, selected_evidence_answer_bearing: { type: 'boolean' }, final_answer_correct: { type: 'boolean' }, source_supported: { type: 'boolean' }, reason: { type: 'string' } }, required: ['case_index', 'reference_valid', 'top10_answer_bearing', 'selected_evidence_answer_bearing', 'final_answer_correct', 'source_supported', 'reason'] } } }, required: ['evaluations'] } } };
const qualityFormat = { type: 'json_schema', json_schema: { name: 'random_case_quality', schema: { type: 'object', additionalProperties: false, properties: { checks: { type: 'array', maxItems: 8, items: { type: 'object', additionalProperties: false, properties: { case_index: { type: 'integer' }, valid: { type: 'boolean' }, reason: { type: 'string' } }, required: ['case_index', 'valid', 'reason'] } } }, required: ['checks'] } } };
function parseContent(payload: Record<string, unknown>) {
  const choices = Array.isArray(payload.choices) ? payload.choices as Array<Record<string, unknown>> : [];
  const message = choices[0]?.message as Record<string, unknown> | undefined;
  const text = typeof message?.content === 'string' ? message.content.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '') : '';
  return JSON.parse(text) as Record<string, unknown>;
}

Deno.serve(async (request) => {
  const token = Deno.env.get('INSURANCE_VALIDATION_TOKEN');
  if (!token || request.headers.get('x-validation-token') !== token) return json({ error: 'unauthorized' }, 401);
  const body = await request.json().catch(() => ({})) as Record<string, unknown>;
  const seed = String(body.seed ?? crypto.randomUUID()).replace(/[^a-zA-Z0-9-]/g, '').slice(0, 80);
  const count = Math.max(1, Math.min(Number(body.count ?? 5), 8));
  const offset = Math.max(0, Number(body.offset ?? 0));
  if (body.mode === 'evaluate') {
    const items = Array.isArray(body.items) ? body.items.slice(0, 8) : [];
    const response = await fetch('https://api.together.xyz/v1/chat/completions', {
      method: 'POST', headers: { Authorization: `Bearer ${Deno.env.get('TOGETHER_API_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'openai/gpt-oss-20b', temperature: 0, max_tokens: 2400, reasoning_effort: 'low', response_format: evaluationFormat, messages: [
        { role: 'system', content: `Independently evaluate retrieval results against the supplied source-derived reference. Return JSON only. reference_valid is false when the question is broader, narrower, ambiguous, or differently scoped than the reference answer/evidence, including a broad class question paired with one condition-specific example. top10_answer_bearing is true when any TOP10 candidate contains the same answer as the reference, even in an equivalent approved chunk or page; inspect every candidate and do not return false when the reference wording or its complete meaning is visibly present. selected_evidence_answer_bearing applies the same rule to selected evidence. The final answer is correct only when it preserves the reference meaning without contradiction. Source-supported means the final answer follows from selected evidence. Never use external facts.` },
        { role: 'user', content: JSON.stringify({ items }) },
      ] }),
    });
    if (!response.ok) return json({ error: 'evaluation_failed', status: response.status }, 503);
    const payload = await response.json() as Record<string, unknown>;
    try { return json(parseContent(payload)); } catch { return json({ error: 'evaluation_parse_failed', finish_reason: (payload.choices as Array<Record<string, unknown>> | undefined)?.[0]?.finish_reason ?? null }, 502); }
  }
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const { data, error } = await db.rpc('insurance_v3_random_validation_units', { p_seed: seed, p_offset: offset * 4, p_limit: Math.min(count * 4, 8) });
  if (error) return json({ error: 'sample_failed', detail: error.code }, 500);
  const samples = (data ?? []) as Array<Record<string, unknown>>;
  const documentIds = [...new Set(samples.map((sample) => String(sample.document_id)).filter(Boolean))];
  const { data: contextData, error: contextError } = documentIds.length
    ? await db.from('insurance_v3_chunks').select('document_id,page_from,page_to,chunk_index,section_title,chunk_text').in('document_id', documentIds).order('chunk_index')
    : { data: [], error: null };
  if (contextError) return json({ error: 'context_failed', detail: contextError.code }, 500);
  const contextChunks = (contextData ?? []) as Array<Record<string, unknown>>;
  const structuralContext = (sample: Record<string, unknown>) => {
    const page = Number(sample.page_from);
    const section = String(sample.section_title ?? '').trim();
    const related = contextChunks.filter((chunk) => String(chunk.document_id) === String(sample.document_id)
      && ((page >= Number(chunk.page_from) && page <= Number(chunk.page_to)) || (section && String(chunk.section_title ?? '').trim() === section)));
    return related.map((chunk) => String(chunk.chunk_text ?? '')).filter(Boolean).join('\n').slice(0, 5000)
      || String(sample.retrieval_text).slice(0, 5000);
  };
  const response = await fetch('https://api.together.xyz/v1/chat/completions', {
    method: 'POST', headers: { Authorization: `Bearer ${Deno.env.get('TOGETHER_API_KEY')}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'openai/gpt-oss-20b', temperature: 0, max_tokens: 2400, reasoning_effort: 'low', response_format: generationFormat, messages: [
      { role: 'system', content: `Create exactly requested_count unseen insurance-policy retrieval cases from the supplied candidate excerpts, skipping candidates that contain only layout, demographics, identity, or no substantive policy rule. Return JSON only: {"cases":[{"candidate_id":"...","question":"...","language":"english|arabic|mixed","reference_answer":"...","reference_evidence":"..."}]}. Ask only about a substantive coverage rule, clinical requirement, documentation requirement, administrative approval requirement, exception, dosing rule, or continuation/initiation criterion. Never ask about a person's name, gender, signature line, address, phone, checkbox label, page title, table title, document identity, medicine identity, brand identity, or another form-layout field. The question must have a uniquely identifiable answer: preserve enough non-answer context such as the applicable medicine, diagnosis, indication, stage, or requirement type. Reject vague wording like "the item mentioned in the table". The source must explicitly contain the value of the exact attribute requested by the question. A statement that an item, document, evidence, assessment, or approval is required does not reveal its type, format, contents, method, or implementation details; never generate a question asking for such unspecified details. Substantially paraphrase the question; do not put the answer in it. reference_answer must be a meaningful concise answer and reference_evidence a short exact supporting clause. Use the requested style. Never use remembered or historical questions.` },
      { role: 'user', content: JSON.stringify({ requested_count: count, samples: samples.map((sample, index) => ({ candidate_id: sample.search_unit_id, requested_style: ['english', 'arabic', 'mixed', 'short_fragment', 'colloquial', 'abbreviation'][(offset + index) % 6], unit_type: sample.unit_type, document_context: sample.document_title, section_context: sample.section_title, table_context: sample.table_title, source_excerpt: structuralContext(sample) })) }) },
    ] }),
  });
  if (!response.ok) return json({ error: 'generation_failed', status: response.status }, 503);
  const generationPayload = await response.json() as Record<string, unknown>;
  let generated: Record<string, unknown>;
  try { generated = parseContent(generationPayload); } catch { return json({ error: 'generation_parse_failed', finish_reason: (generationPayload.choices as Array<Record<string, unknown>> | undefined)?.[0]?.finish_reason ?? null }, 502); }
  const byId = new Map(samples.map((sample) => [String(sample.search_unit_id), sample]));
  const generatedCases = Array.isArray(generated.cases) ? generated.cases as Array<Record<string, unknown>> : [];
  const cases = generatedCases.flatMap((item) => {
    const candidateId = typeof item.candidate_id === 'string' ? item.candidate_id : '';
    const sample = candidateId ? byId.get(candidateId) : null;
    const question = typeof item.question === 'string' ? item.question.trim() : '';
    if (!sample || !question || typeof item.reference_answer !== 'string' || typeof item.reference_evidence !== 'string' || item.reference_answer.trim().length < 3) return [];
    return [{ question, language: item.language ?? null, reference_answer: item.reference_answer, reference_evidence: item.reference_evidence, candidate_excerpt: String(sample.retrieval_text).slice(0, 2200), source_excerpt: structuralContext(sample), expected_search_unit_id: sample.search_unit_id, expected_source_chunk_ids: sample.source_chunk_ids, expected_document_id: sample.document_id, expected_document_title: sample.document_title, expected_page_from: sample.page_from, expected_unit_type: sample.unit_type }];
  });
  const qualityResponse = await fetch('https://api.together.xyz/v1/chat/completions', {
    method: 'POST', headers: { Authorization: `Bearer ${Deno.env.get('TOGETHER_API_KEY')}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'openai/gpt-oss-20b', temperature: 0, max_tokens: 1400, reasoning_effort: 'low', response_format: qualityFormat, messages: [
      { role: 'system', content: `Audit each generated validation case against its candidate excerpt and full structural context. valid=true only when: every distinct condition, exception, threshold, negation, alternative, and conjunction stated in reference_answer is explicitly and unambiguously supported by reference_evidence; reference_evidence directly and uniquely answers the question; the answer preserves every applicable option shown for the requested attribute; and question, answer, and evidence concern exactly the same row subject, indication, treatment stage, and concept. The evidence must explicitly state the value of the exact attribute requested. A statement that an item, document, evidence, assessment, or approval is required does not answer a question asking for its unstated type, format, contents, method, or implementation detail. Never borrow a criterion from another table row or adjacent indication merely because it appears on the same page. Do not infer a condition such as "goal not met" from a different statement such as "reduce a level." A disease frequency is not a medicine frequency and a diagnostic value is not a dose. The question must contain enough non-answer context and ask a substantive policy rule, not layout, identity, brand-name, document-title, or demographics. If context contains multiple conditions or options, reject a broad question asking for the only condition, criteria, requirements, situations, recommended dose, or a list unless it explicitly narrows the attribute and the reference exhaustively includes every applicable answer. When the question names a specific age group, indication, stage, route, formulation, or other subgroup, reject the case if the structural context contains a more specific rule for that subgroup which the reference answer omits, even when a broader general rule is also present. Reject any ambiguity, contradiction, cross-row borrowing, invented narrowing, unsupported clause, or incomplete reference. Return JSON only.` },
      { role: 'user', content: JSON.stringify({ cases: cases.map((item, case_index) => ({ case_index, question: item.question, reference_answer: item.reference_answer, reference_evidence: item.reference_evidence, candidate_excerpt: item.candidate_excerpt, source_excerpt: item.source_excerpt })) }) },
    ] }),
  });
  if (!qualityResponse.ok) return json({ error: 'quality_check_failed', status: qualityResponse.status }, 503);
  const qualityPayload = await qualityResponse.json() as Record<string, unknown>;
  let quality: Record<string, unknown>;
  try { quality = parseContent(qualityPayload); } catch { return json({ error: 'quality_parse_failed' }, 502); }
  const validIndexes = new Set((Array.isArray(quality.checks) ? quality.checks as Array<Record<string, unknown>> : []).filter((item) => item.valid === true).map((item) => Number(item.case_index)));
  const structurallyCompleteReference = (item: Record<string, unknown>) => {
    const questionText = String(item.question ?? '').toLocaleLowerCase();
    const context = String(item.source_excerpt ?? '').toLocaleLowerCase();
    const evidence = String(item.reference_evidence ?? '');
    const broadRequest = /(criteria|conditions?|requirements?|eligib|coverage|approval|شرط|شروط|متطلبات|أهلي|اهلي|موافقة)/iu.test(questionText);
    const explicitAttribute = /(age|dose|dosage|weight|lab|eos|hba1c|ige|threshold|time|duration|month|day|documentation|report|specialt|refill|continuation|عمر|جرعة|وزن|تحليل|مختبر|مدة|شهر|تقرير|توثيق|تخصص|استمرار|إعادة صرف)/iu.test(questionText);
    const bulletCount = (context.match(/[•♦]/g) ?? []).length;
    const multiRuleContext = /all conditions|كل الشروط|جميع الشروط/iu.test(context) || bulletCount >= 4;
    const evidenceIsNarrow = evidence.length < Math.max(180, context.length * 0.18);
    return !(broadRequest && !explicitAttribute && multiRuleContext && evidenceIsNarrow);
  };
  const approved = cases.filter((item, index) => validIndexes.has(index) && structurallyCompleteReference(item)).slice(0, count).map(({ source_excerpt: _sourceExcerpt, candidate_excerpt: _candidateExcerpt, ...item }) => item);
  return json({ seed, offset, cases: approved, candidates_checked: samples.length });
});
