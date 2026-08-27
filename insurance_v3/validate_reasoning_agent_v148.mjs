import crypto from 'node:crypto';

const baseUrl = (process.env.SUPABASE_URL ?? '').replace(/\/$/, '');
const anonKey = process.env.SUPABASE_ANON_KEY ?? '';
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
if (!baseUrl || !anonKey || !serviceKey) throw new Error('Production validation credentials are required.');

const cases = [
  {
    id: 'reverse-professional',
    question: 'For preventive migraine biologics, can a brain-surgery specialist prescribe, and which specialty label proves it?',
    required: ['neurosurgery'], expectedDocsAny: ['Adjudication rule (CGRP) inhibitors drugs Summary Updated', 'CGRP Inhibitors for Migraine Summary tables'], facets: 2,
  },
  {
    id: 'directional-comparison',
    question: 'Compare migraine prevention with rescue treatment: which prescriber specialty appears for rescue but not prevention?',
    required: ['family medicine'], expectedDocs: ['CGRP Inhibitors for Migraine Summary tables'], facets: 1,
  },
  {
    id: 'mixed-multipart',
    question: 'Galcanezumab للـ cluster period: شو مقدار البداية والجدول بعدها، ومتى لازم يتوثق benefit للاستمرار؟',
    required: ['300 mg', 'monthly', '3 months'], expectedDocs: ['Galcanezumab use for Cluster Headach Summary'], facets: 3,
  },
  {
    id: 'misspelling-negative-quantity',
    question: 'Zavgepant nasal لو أخذ 10 mg اليوم، هل جرعة ثانية بنفس 24h مسموحة؟',
    required: ['10 mg', '24'], forbidden: ['20 mg is allowed'], expectedDocs: ['Adjudication rule (CGRP) inhibitors drugs Summary Updated'], facets: 2,
  },
  {
    id: 'cross-document-aggregation',
    question: 'Across the active migraine CGRP summaries, which clinician groups are consistently shown for preventive prescribing?',
    required: ['neurology', 'neurosurgery', 'internal medicine'], expectedDocs: ['Adjudication rule (CGRP) inhibitors drugs Summary Updated', 'CGRP Inhibitors for Migraine Summary tables'], facets: 1, minimumCitationDocs: 2,
  },
  {
    id: 'informal-multipart',
    question: 'For the omega-three policy, can a general internal-medicine doctor prescribe it, and what starting grams per day are documented?',
    required: ['internal medicine', '1-2', 'grams'], expectedDocs: ['Adjudication Rule for Omega 3 Therapies updated 20 8 2025 Summary'], facets: 2,
  },
  {
    id: 'true-missing-detail',
    question: 'Does the omega-three policy specify the exact number of fasting hours required before its follow-up lipid panel?',
    requiredAny: ['not establish', 'not specify', 'not stated'], expectedDocs: [], facets: 1, allowNoCitation: true,
  },
  {
    id: 'genuine-ambiguity',
    question: 'Which one of those can approve it?',
    clarification: true, required: [], expectedDocs: [], facets: 1, allowNoCitation: true,
  },
];
const requestedCaseIds = new Set(String(process.env.VALIDATION_CASES ?? '').split(',').map((value) => value.trim()).filter(Boolean));
const validationCases = requestedCaseIds.size > 0 ? cases.filter((testCase) => requestedCaseIds.has(testCase.id)) : cases;

const normalize = (value) => String(value ?? '').normalize('NFKC').toLocaleLowerCase().replace(/[‐‑‒–—−]/g, '-').replace(/\s+/g, ' ');
async function requestJson(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let body = {};
  try { body = JSON.parse(text); } catch { body = { raw: text }; }
  return { response, body };
}

const email = `reasoning-agent-${Date.now()}-${crypto.randomUUID().slice(0, 6)}@example.invalid`;
const password = `${crypto.randomUUID()}!Aa9`;
let userId = null;
let appUserCreated = false;
const rows = [];
try {
  const created = await requestJson(`${baseUrl}/auth/v1/admin/users`, { method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { purpose: 'v148_reasoning_agent_validation' } }) });
  if (!created.response.ok) throw new Error(`temporary user creation failed (${created.response.status})`);
  userId = created.body.id;
  const appUser = await requestJson(`${baseUrl}/rest/v1/app_users?on_conflict=user_id`, { method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ user_id: userId, role: 'inventory', branch_name: null, is_active: true, user_name: 'V148 reasoning validation' }) });
  if (!appUser.response.ok) throw new Error(`temporary reader grant failed (${appUser.response.status})`);
  appUserCreated = true;
  const signedIn = await requestJson(`${baseUrl}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  if (!signedIn.response.ok || !signedIn.body.access_token) throw new Error(`temporary sign-in failed (${signedIn.response.status})`);
  const token = signedIn.body.access_token;
  for (const testCase of validationCases) {
    const started = Date.now();
    const invoked = await requestJson(`${baseUrl}/functions/v1/insurance-policy-v3`, { method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: testCase.question, branch_name: 'Reasoning Agent Validation', debug: true }) });
    const body = invoked.body; const debug = body.debug ?? {}; const answer = normalize(body.answer);
    const contract = debug.question_contract ?? {}; const ledger = debug.evidence_ledger ?? {}; const verifier = debug.answer_verifier ?? {};
    const citations = Array.isArray(body.citations) ? body.citations : [];
    const citationDocs = [...new Set(citations.map((citation) => String(citation.document_title ?? citation.document ?? '')))];
    const requiredPass = (testCase.required ?? []).every((term) => answer.includes(normalize(term)));
    const requiredAnyPass = !testCase.requiredAny || testCase.requiredAny.some((term) => answer.includes(normalize(term)));
    const forbiddenPass = (testCase.forbidden ?? []).every((term) => !answer.includes(normalize(term)));
    const contractPass = contract.original_question === testCase.question && Array.isArray(contract.required_answer_facets) && contract.required_answer_facets.length >= testCase.facets;
    const ledgerPass = testCase.clarification || (Array.isArray(ledger.facets) && ledger.facets.length >= testCase.facets);
    const sourcePass = testCase.allowNoCitation || (citations.length > 0
      && (testCase.expectedDocs ?? []).every((doc) => citationDocs.includes(doc))
      && (!testCase.expectedDocsAny || testCase.expectedDocsAny.some((doc) => citationDocs.includes(doc)))
      && citationDocs.length >= (testCase.minimumCitationDocs ?? 1));
    const clarificationPass = testCase.clarification ? body.answer_status === 'clarification_required' : body.answer_status !== 'clarification_required';
    const verifierPass = testCase.clarification || typeof verifier.answer_rejected_before_display === 'boolean';
    const pass = invoked.response.status === 200 && requiredPass && requiredAnyPass && forbiddenPass && contractPass && ledgerPass && sourcePass && clarificationPass && verifierPass;
    const ai = debug.ai ?? {}; const reasoning = ai.reasoning_agent ?? {};
    rows.push({ id: testCase.id, pass, http: invoked.response.status, status: body.answer_status, answer: body.answer, semantic: debug.semantic_interpretation ?? null, verified_entities: debug.verified_entities ?? [], latency_ms: Date.now() - started, ai_calls: Number(ai.ai_calls ?? 0), tokens: Number(ai.total_tokens ?? 0), recovery: body.recovery_used === true, provider: ai.provider ?? null, contract_facets: contract.required_answer_facets?.length ?? 0, ledger_status: ledger.status ?? null, missing_facets: ledger.missing_facets ?? [], rejected_before_display: verifier.answer_rejected_before_display ?? null, search_round_count: reasoning.search_round_count ?? null, citation_documents: citationDocs, checks: { requiredPass, requiredAnyPass, forbiddenPass, contractPass, ledgerPass, sourcePass, clarificationPass, verifierPass } });
    process.stdout.write(`${testCase.id}: ${pass ? 'PASS' : 'FAIL'} HTTP=${invoked.response.status} status=${body.answer_status} calls=${Number(ai.ai_calls ?? 0)} recovery=${body.recovery_used === true} latency=${Date.now() - started}ms\n`);
    await new Promise((resolve) => setTimeout(resolve, 2500));
  }
} finally {
  if (appUserCreated && userId) await fetch(`${baseUrl}/rest/v1/app_users?user_id=eq.${userId}`, { method: 'DELETE', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
  if (userId) await fetch(`${baseUrl}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
}

const latencies = rows.map((row) => row.latency_ms).sort((a, b) => a - b);
const normal = rows.filter((row) => !row.recovery); const recovery = rows.filter((row) => row.recovery);
const average = (values) => values.length ? Math.round(values.reduce((sum, value) => sum + value, 0) / values.length) : 0;
const summary = {
  version: 149, passed: rows.filter((row) => row.pass).length, total: rows.length,
  average_latency_ms: average(latencies), p95_latency_ms: latencies[Math.max(0, Math.ceil(latencies.length * 0.95) - 1)] ?? 0,
  average_ai_calls_normal: average(normal.map((row) => row.ai_calls)), average_ai_calls_recovery: average(recovery.map((row) => row.ai_calls)),
  provider_failures: rows.filter((row) => row.status === 'temporarily_unavailable').length,
  http_error_rate: Number((100 * rows.filter((row) => row.http >= 400).length / rows.length).toFixed(2)),
};
console.log(JSON.stringify({ summary, rows }, null, 2));
if (summary.passed !== summary.total) process.exitCode = 1;
