import crypto from 'node:crypto';

const baseUrl = (process.env.SUPABASE_URL ?? '').replace(/\/$/, '');
const anonKey = process.env.SUPABASE_ANON_KEY ?? '';
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const validationToken = process.env.INSURANCE_VALIDATION_TOKEN ?? '';
const seed = process.env.INSURANCE_VALIDATION_SEED ?? crypto.randomUUID();
const totalCases = Math.max(1, Math.min(Number(process.env.INSURANCE_VALIDATION_COUNT ?? 50), 80));
const startOffset = Math.max(0, Number(process.env.INSURANCE_VALIDATION_START_OFFSET ?? 0));
const explicitOffsets = String(process.env.INSURANCE_VALIDATION_OFFSETS ?? '').split(',')
  .map((value) => Number(value.trim())).filter((value) => Number.isInteger(value) && value >= 0);
const validationOffsets = explicitOffsets.length
  ? [...new Set(explicitOffsets)]
  : Array.from({ length: totalCases }, (_, index) => startOffset + index);
// One source-derived case per generation call prevents a model from silently
// omitting array members and keeps every reference answer individually auditable.
const batchSize = 1;
if (!baseUrl || !anonKey || !serviceKey || !validationToken) throw new Error('Validation environment is incomplete.');

async function requestJson(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let body; try { body = JSON.parse(text); } catch { body = { raw: text }; }
  return { response, body };
}
async function generateValidatedCase(offset) {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const attemptSeed = attempt === 0 ? seed : `${seed}-quality-retry-${attempt}`;
    let generated = await requestJson(`${baseUrl}/functions/v1/insurance-v3-validation-generator`, { method: 'POST', headers: { 'x-validation-token': validationToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ seed: attemptSeed, offset, count: 1 }) });
    if (!generated.response.ok) { await wait(2500); continue; }
    if ((generated.body.cases ?? []).length === 1) return generated;
  }
  throw new Error(`Unable to generate one quality-approved random case at offset ${offset}.`);
}
const intersects = (left = [], right = []) => left.some((value) => right.includes(value));
const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const normalizedTokens = (value) => [...new Set(String(value ?? '').normalize('NFKC').toLocaleLowerCase()
  .replace(/[^\p{L}\p{N}]+/gu, ' ').split(/\s+/).filter((token) => token.length >= 2))];
function containsReferenceEvidence(candidate, reference) {
  const expectedTokens = normalizedTokens(reference);
  if (expectedTokens.length < 3) return false;
  const candidateTokens = new Set(normalizedTokens(candidate));
  const covered = expectedTokens.filter((token) => candidateTokens.has(token)).length;
  return covered / expectedTokens.length >= 0.8;
}
const suffix = crypto.randomUUID();
const email = `insurance-v3-random-${suffix}@example.invalid`;
const password = `${crypto.randomUUID()}!Aa9`;
let userId = null;
const sessionIds = new Set();
const results = [];

try {
  const created = await requestJson(`${baseUrl}/auth/v1/admin/users`, { method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { purpose: 'random_hybrid_validation' } }) });
  if (!created.response.ok) throw new Error(`Temporary user creation failed (${created.response.status}).`);
  userId = created.body.id;
  const access = await requestJson(`${baseUrl}/rest/v1/app_users?on_conflict=user_id`, { method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ user_id: userId, role: 'branch', branch_name: null, is_active: true, user_name: `Random hybrid validation ${suffix}` }) });
  if (!access.response.ok) throw new Error(`Temporary reader grant failed (${access.response.status}).`);
  const signedIn = await requestJson(`${baseUrl}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  if (!signedIn.response.ok) throw new Error(`Temporary sign-in failed (${signedIn.response.status}).`);
  const accessToken = signedIn.body.access_token;

  for (const offset of validationOffsets) {
    const generated = await generateValidatedCase(offset);
    const evaluationItems = [];
    const evaluationResultIndexes = [];
    for (const testCase of generated.body.cases ?? []) {
      const invoked = await requestJson(`${baseUrl}/functions/v1/insurance-policy-v3`, { method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: testCase.question, debug: true }) });
      if (invoked.body.session_id) sessionIds.add(invoked.body.session_id);
      const debug = invoked.body.debug ?? {};
      const channels = debug.retrieval_channels ?? debug.hybrid_candidates ?? [];
      const top10 = channels.slice(0, 10);
      const vector10 = channels.filter((item) => Number(item.vector_rank) > 0 && Number(item.vector_rank) <= 10);
      const selected = debug.selected_units ?? [];
      const selectedIds = new Set(selected.map((item) => item.search_unit_id));
      const selectedJudgments = (debug.evidence_judgments ?? []).filter((item) => selectedIds.has(item.candidate_id));
      const expected = testCase.expected_source_chunk_ids ?? [];
      const citations = invoked.body.citations ?? [];
      const textHit10 = top10.some((item) => containsReferenceEvidence(item.text ?? item.retrieval_text, testCase.reference_evidence));
      results.push({
        language: testCase.language, unit_type: testCase.expected_unit_type, http_status: invoked.response.status,
        vector_hit_10: vector10.some((item) => intersects(item.source_chunk_ids, expected)),
        hybrid_hit_10: top10.some((item) => intersects(item.source_chunk_ids, expected)), deterministic_text_hit_10: textHit10,
        selected_hit: selected.some((item) => intersects(item.source_chunk_ids, expected)),
        relevant_selected_count: selected.filter((item) => intersects(item.source_chunk_ids, expected)).length, selected_count: selected.length,
        ai_answer_bearing_selected: selectedJudgments.filter((item) => item.answer_bearing === true).length,
        ai_judged_selected_count: selectedJudgments.length,
        sufficiency_complete: debug.evidence_sufficiency?.status === 'complete',
        source_page_correct: citations.some((item) => expected.includes(item.chunk_id)
          || (item.document_title === testCase.expected_document_title
            && Number(item.page_from) <= Number(testCase.expected_page_from)
            && Number(item.page_to ?? item.page_from) >= Number(testCase.expected_page_from))),
        answer_status: invoked.body.answer_status ?? null, retrieval_retry: debug.retrieval_retry === true,
        provider: debug.ai?.provider ?? null, total_tokens: Number(debug.ai?.total_tokens ?? 0), error: invoked.response.ok ? null : invoked.body.error ?? invoked.body.answer_status,
        diagnostic_code: debug.diagnostic_code ?? null, diagnostic_provider: debug.provider ?? null,
        reference_valid: true,
        independent_top10_answer_bearing: false, independent_selected_evidence_correct: false, independent_final_answer_correct: false, independent_source_supported: false,
      });
      evaluationResultIndexes.push(results.length - 1);
      evaluationItems.push({ case_index: evaluationItems.length, question: testCase.question, reference_answer: testCase.reference_answer, reference_evidence: testCase.reference_evidence, top10_candidates: top10.map((item) => item.text ?? item.retrieval_text).filter(Boolean), selected_evidence: (debug.retrieved_chunks ?? []).map((item) => item.text ?? item.chunk_text).filter(Boolean).slice(0, 12), final_answer: invoked.body.answer ?? null });
      process.stdout.write(`${results.length}/${validationOffsets.length} offset=${offset} ${testCase.language}/${testCase.expected_unit_type} HTTP ${invoked.response.status} hybrid@10=${results.at(-1).hybrid_hit_10} selected=${results.at(-1).selected_hit}${results.at(-1).diagnostic_code ? ` diagnostic=${results.at(-1).diagnostic_provider}:${results.at(-1).diagnostic_code}` : ''}\n`);
      if (!invoked.response.ok) process.stdout.write(`HTTP_ERROR ${JSON.stringify(invoked.body)}\n`);
      if (!results.at(-1).hybrid_hit_10 && invoked.response.ok) {
        process.stdout.write(`MISS_TRACE ${JSON.stringify({ expected: { document: testCase.expected_document_title, page: testCase.expected_page_from, unit_type: testCase.expected_unit_type }, semantic: { medication: debug.semantic_interpretation?.medication, generic: debug.semantic_interpretation?.generic, indication: debug.semantic_interpretation?.indication, information_need: debug.semantic_interpretation?.information_need }, top10: top10.map((item) => ({ document: item.document ?? item.document_title, page: item.page ?? item.page_from, unit_type: item.unit_type, vector_rank: item.vector_rank, rrf: item.rrf_score ?? item.hybrid_rrf_score })), selected: selected.map((item) => ({ document: item.document, page: item.page, unit_type: item.unit_type })), sufficiency: debug.evidence_sufficiency })}\n`);
      }
      await wait(700);
    }
    let evaluated = await requestJson(`${baseUrl}/functions/v1/insurance-v3-validation-generator`, { method: 'POST', headers: { 'x-validation-token': validationToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ mode: 'evaluate', items: evaluationItems }) });
    if (!evaluated.response.ok) { await wait(3000); evaluated = await requestJson(`${baseUrl}/functions/v1/insurance-v3-validation-generator`, { method: 'POST', headers: { 'x-validation-token': validationToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ mode: 'evaluate', items: evaluationItems }) }); }
    for (const evaluation of evaluated.body.evaluations ?? []) {
      const resultIndex = evaluationResultIndexes[Number(evaluation.case_index)];
      if (resultIndex === undefined) continue;
      results[resultIndex].independent_top10_answer_bearing = evaluation.top10_answer_bearing === true;
      results[resultIndex].reference_valid = evaluation.reference_valid !== false;
      results[resultIndex].independent_selected_evidence_correct = evaluation.selected_evidence_answer_bearing === true;
      results[resultIndex].independent_final_answer_correct = evaluation.final_answer_correct === true;
      results[resultIndex].independent_source_supported = evaluation.source_supported === true;
      results[resultIndex].independent_reason = evaluation.reason ?? null;
      if (evaluation.top10_answer_bearing !== true || evaluation.selected_evidence_answer_bearing !== true || evaluation.final_answer_correct !== true || evaluation.source_supported !== true) {
        process.stdout.write(`EVALUATION_MISS ${JSON.stringify({ result_index: resultIndex + 1, top10_answer_bearing: evaluation.top10_answer_bearing, selected_evidence_answer_bearing: evaluation.selected_evidence_answer_bearing, final_answer_correct: evaluation.final_answer_correct, source_supported: evaluation.source_supported, reason: evaluation.reason, validation_item: evaluationItems[Number(evaluation.case_index)] })}\n`);
      }
    }
  }

  const tested = results.length;
  const providerEligible = results.filter((item) => item.http_status === 200);
  const eligible = providerEligible.filter((item) => item.reference_valid !== false);
  const count = (field, subset = results) => subset.filter((item) => item[field] === true).length;
  const tableRows = eligible.filter((item) => item.unit_type === 'table_row');
    const selectedTotal = eligible.reduce((sum, item) => sum + item.selected_count, 0);
    const aiJudgedSelectedTotal = eligible.reduce((sum, item) => sum + item.ai_judged_selected_count, 0);
  const summary = {
    seed, requested_cases: validationOffsets.length, tested, provider_successes: providerEligible.length,
    invalid_reference_cases: providerEligible.length - eligible.length, eligible_retrieval_cases: eligible.length,
    vector_recall_at_10: eligible.length ? count('vector_hit_10', eligible) / eligible.length : 0,
    hybrid_source_id_recall_at_10: eligible.length ? count('hybrid_hit_10', eligible) / eligible.length : 0,
    answer_bearing_recall_at_10: eligible.length ? eligible.filter((item) => item.hybrid_hit_10 || item.deterministic_text_hit_10 || item.independent_top10_answer_bearing).length / eligible.length : 0,
    independent_answer_bearing_recall_at_10: eligible.length ? count('independent_top10_answer_bearing', eligible) / eligible.length : 0,
    reranker_precision: selectedTotal ? eligible.reduce((sum, item) => sum + item.relevant_selected_count, 0) / selectedTotal : 0,
    reranker_ai_judged_precision: aiJudgedSelectedTotal ? eligible.reduce((sum, item) => sum + item.ai_answer_bearing_selected, 0) / aiJudgedSelectedTotal : 0,
    selected_evidence_case_precision: eligible.length ? count('selected_hit', eligible) / eligible.length : 0,
    independent_selected_evidence_precision: eligible.length ? count('independent_selected_evidence_correct', eligible) / eligible.length : 0,
    independent_final_answer_accuracy: eligible.length ? count('independent_final_answer_correct', eligible) / eligible.length : 0,
    independent_source_support_accuracy: eligible.length ? count('independent_source_supported', eligible) / eligible.length : 0,
    evidence_sufficiency_accuracy: eligible.length ? count('sufficiency_complete', eligible) / eligible.length : 0,
    source_page_accuracy: eligible.length ? count('source_page_correct', eligible) / eligible.length : 0,
    table_row_cases: tableRows.length, table_row_hybrid_recall_at_10: tableRows.length ? count('hybrid_hit_10', tableRows) / tableRows.length : null,
    languages: Object.fromEntries([...new Set(eligible.map((item) => item.language))].map((language) => [language, { cases: eligible.filter((item) => item.language === language).length, answer_bearing_hits: eligible.filter((item) => item.language === language && (item.hybrid_hit_10 || item.deterministic_text_hit_10 || item.independent_top10_answer_bearing)).length }])),
    retries: results.filter((item) => item.retrieval_retry).length, http_failures: results.filter((item) => item.http_status !== 200).length,
    total_ai_tokens: results.reduce((sum, item) => sum + item.total_tokens, 0),
  };
  process.stdout.write(`VALIDATION_SUMMARY ${JSON.stringify(summary)}\n`);
} finally {
  for (const sessionId of sessionIds) await fetch(`${baseUrl}/rest/v1/insurance_chat_sessions?id=eq.${sessionId}`, { method: 'DELETE', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
  if (userId) {
    await fetch(`${baseUrl}/rest/v1/app_users?user_id=eq.${userId}`, { method: 'DELETE', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
    await fetch(`${baseUrl}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
  }
}
