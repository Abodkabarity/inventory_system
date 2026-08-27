import fs from 'node:fs';
import crypto from 'node:crypto';

const baseUrl = (process.env.SUPABASE_URL ?? '').replace(/\/$/, '');
const anonKey = process.env.SUPABASE_ANON_KEY ?? '';
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
if (!baseUrl || !anonKey || !serviceKey) throw new Error('Validation credentials are required in process environment.');

const cases = [
  ['attack-window', 'In the updated CGRP adjudication-rule summary, what documented attack-duration range applies?', 'Adjudication rule (CGRP) inhibitors drugs Summary Updated', ['4 hours', '72 hours'], [], ['attack', 'duration']],
  ['omega-overview', 'Which two omega-3 therapy groups are named in the coverage subject?', 'Adjudication Rule for Omega 3 Therapies updated 20 8 2025 Summary', ['Omega-3-Acid Ethyl Esters', 'Icosapent Ethyl'], [], ['omega', 'therapy']],
  ['glp-recency', 'In the updated GLP-1 adjudication-guideline summary, is an HbA1c result from ten weeks ago recent enough for initiation?', 'Adjudication Rule GLP 1 R.A. Summary updated 4 12 2025', ['3 months'], [], ['HbA1c', 'initiat']],
  ['botox-urology', 'Can a 17-year-old meet the Botox urinary-incontinence age rule in this policy?', 'Botulinum Toxin ( BOTOX) Summary', ['18'], [], ['Botox', 'urinary']],
  ['legend', 'In the migraine CGRP summary tables, what does the light-green legend mean?', 'CGRP Inhibitors for Migraine Summary tables', ['Positive benchmarks', 'response'], [], ['legend', 'light green']],
  ['filgrastim-clinician', 'For febrile-neutropenia risk during myelosuppressive chemotherapy, which specialties may request filgrastim?', 'Coverage of Filgrastim ZARZIO under Daman', ['Oncology', 'Hematology'], [], ['filgrastim', 'special']],
  ['dupilumab-regimen', 'What loading and follow-up regimen is documented for the 400 mg asthma pathway of Dupixent?', 'Dupilumab Overview', ['400 mg', '200 mg', '2 weeks'], [], ['Dupixent', 'dose']],
  ['biologic-form-fields', 'What patient-detail fields are explicitly requested on the biologic prerequisite form?', 'F 6030 190414 Daman Pre requisite Form for Biologic Therapy V1R1', ['Date of Birth', 'Weight'], [], ['patient', 'details']],
  ['cluster-indication', 'What indication is listed for galcanezumab in the cluster-headache summary?', 'Galcanezumab use for Cluster Headach Summary', ['Cluster Headache'], [], ['galcanezumab', 'indication']],
  ['jaki-firstline-summary', 'According to the JAKi summary, what is the first-line therapy category for autoimmune diseases?', 'JAKi summary Updated 25 06 2026', ['DMARD'], [], ['first-line', 'autoimmune']],
  ['jaki-not-firstline', 'Are Janus kinase inhibitors normally considered first-line treatment?', 'Janus Kinase Inhibitors Adjudication Guideline Updated', ['first-line'], [], ['JAK', 'first-line']],
  ['mepolizumab-specialty', 'Is Paediatric Rheumatology listed as an eligible specialty for mepolizumab?', 'Mepolizumab Overview', ['Paediatric Rheumatology'], [], ['mepolizumab', 'specialty']],
  ['omalizumab-specialty', 'Is Respiratory Medicine an eligible clinical specialty for omalizumab?', 'Omalizumab Overview', ['Respiratory Medicine'], [], ['omalizumab', 'specialty']],
  ['ondansetron-route', 'For postoperative nausea in a two-month-old child, what route does the guideline recommend?', 'Ondansetron Adjudication Guideline Summary', ['IV'], [], ['ondansetron', 'postoperative']],
  ['tralokinumab-reassessment', 'After the initial 16 weeks of tralokinumab, which scores are used to assess continuation?', 'Overview of Tralokinumab Policy', ['IGA', 'EASI'], [], ['tralokinumab', 'continuation']],
  ['pcsk9-generic', 'Which generic is paired with the REPATHA 140 mg pre-filled pen?', 'PCSK9 Inhibitors Updated summary', ['Evolocumab'], [], ['Repatha', 'generic']],
  ['ppi-eoe', 'For eosinophilic esophagitis, what PPI dose range and duration are shown in the diagnosis table?', 'PPI Dx CODES updated 13 01 2026', ['Double Dose', '8-12 weeks'], [], ['eosinophilic esophagitis', 'duration']],
  ['mash-titration', 'How is Wegovy titrated from the initial dose to maintenance in the MASH summary?', 'Summary of GLP 1 R.A. for MASH', ['0.25 mg', '4-week', '2.4 mg'], [], ['Wegovy', 'titration']],
  ['t2dm-titration', 'After the starting Mounjaro dose, when may the next 2.5 mg increase occur?', 'Summary of GLP 1 R.A. for T2DM', ['4 weeks'], [], ['Mounjaro', 'dose']],
  ['ppi-double', 'What is the documented double dose for esomeprazole?', 'What you should know about the PPI coverage', ['40 mg'], [], ['esomeprazole', 'dose']],
  ['arabic-specialty', 'هل طب الجهاز التنفسي موجود ضمن التخصصات المؤهلة لأوماليزوماب؟', 'Omalizumab Overview', ['Respiratory Medicine'], [], ['omalizumab', 'specialty']],
  ['mixed-table', 'EoE مع PPI double dose، كم الـ duration حسب الجدول؟', 'PPI Dx CODES updated 13 01 2026', ['8-12 weeks'], [], ['EoE', 'duration']],
  ['typo-colloquial', 'بعد 16 wk على tralokinumab شنو scores اللي نراجعها للاستمرار؟', 'Overview of Tralokinumab Policy', ['IGA', 'EASI'], [], ['tralokinumab', 'continuation']],
  ['cross-document', 'Which GLP-1 policy summaries state a maximum allowance of one box per month?', null, ['Summary of GLP 1 R.A. for MASH', 'Summary of GLP 1 R.A. for T2DM'], [], ['maximum', 'box']],
  ['ambiguous', 'دواء', null, [], [], [], true],
];
const selectedCases = process.env.VALIDATION_CASE_ID
  ? cases.filter((item) => item[0] === process.env.VALIDATION_CASE_ID)
  : cases;

async function requestJson(url, options) {
  const response = await fetch(url, options);
  let data = {};
  try { data = await response.json(); } catch { /* status is retained */ }
  return { response, data };
}
const email = `insurance-recovery-${Date.now()}-${crypto.randomUUID().slice(0, 6)}@example.test`;
const password = `${crypto.randomUUID()}!Aa9`;
let userId = null;
let appUserCreated = false;
const results = [];
let feedbackValidation = null;
try {
  const created = await requestJson(`${baseUrl}/auth/v1/admin/users`, { method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { purpose: 'insurance_v3_resilient_recovery_validation' } }) });
  if (!created.response.ok) throw new Error(`test user creation failed (${created.response.status})`);
  userId = created.data.id;
  const appUser = await requestJson(`${baseUrl}/rest/v1/app_users?on_conflict=user_id`, { method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ user_id: userId, role: 'inventory', branch_name: null, is_active: true, user_name: `Recovery validation ${Date.now()}` }) });
  if (!appUser.response.ok) throw new Error(`test reader grant failed (${appUser.response.status})`);
  appUserCreated = true;
  const signedIn = await requestJson(`${baseUrl}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  if (!signedIn.response.ok || !signedIn.data.access_token) throw new Error(`test sign-in failed (${signedIn.response.status})`);
  const token = signedIn.data.access_token;
  for (const [id, question, expectedDoc, required, forbidden, semanticTerms, expectsClarification = false] of selectedCases) {
    const started = Date.now();
    const invoked = await requestJson(`${baseUrl}/functions/v1/insurance-policy-v3`, { method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: question, branch_name: 'Recovery Validation', debug: true }) });
    const debug = invoked.data.debug ?? {};
    const answer = String(invoked.data.answer ?? '');
    const semantic = debug.semantic_interpretation ?? {};
    const candidates = debug.retrieval_channels ?? debug.candidates ?? [];
    const selected = debug.selected_units ?? debug.selected_evidence ?? [];
    const citations = invoked.data.citations ?? [];
    const docOf = (row) => String(row.document_title ?? row.document ?? '');
    const normalizeForAssertion = (value) => String(value).normalize('NFKC').toLocaleLowerCase()
      .replace(/[‐‑‒–—−]/g, '-').replace(/[\u00a0\u202f]/g, ' ').replace(/\s+/g, ' ');
    const normalizedAnswer = normalizeForAssertion(answer);
    const requiredPass = required.every((value) => normalizedAnswer.includes(normalizeForAssertion(value)));
    const forbiddenPass = forbidden.every((value) => !normalizedAnswer.includes(normalizeForAssertion(value)));
    const semanticText = JSON.stringify(semantic).toLocaleLowerCase();
    const semanticPass = expectsClarification || semanticTerms.every((value) => semanticText.includes(String(value).toLocaleLowerCase()));
    const recall10 = expectedDoc === null ? true : candidates.slice(0, 10).some((row) => docOf(row) === expectedDoc);
    const selectedPass = expectedDoc === null ? true : selected.some((row) => docOf(row) === expectedDoc) || citations.some((row) => docOf(row) === expectedDoc);
    const citedPass = expectsClarification ? citations.length === 0 : citations.length > 0 && answer.includes('Source:');
    const finalPass = expectsClarification ? invoked.data.answer_status === 'clarification_required' : requiredPass && forbiddenPass && !/do not establish|not established/i.test(answer);
    const ai = debug.ai ?? {};
    results.push({ id, question, http_status: invoked.response.status, answer_status: invoked.data.answer_status, semantic_pass: semanticPass, recall_at_10: recall10, selected_evidence_pass: selectedPass, final_answer_pass: finalPass, source_supported_pass: citedPass, clarification_pass: expectsClarification ? finalPass : null, recovery_used: invoked.data.recovery_used === true, provider: ai.provider ?? null, model: ai.model ?? null, total_tokens: Number(ai.total_tokens ?? 0), latency_ms: Date.now() - started, expected_document: expectedDoc, citation_documents: citations.map(docOf), answer, ...(process.env.VALIDATION_CASE_ID ? { debug } : {}) });
    if (process.env.VALIDATE_FEEDBACK === 'true' && !feedbackValidation && invoked.data.message_id) {
      const recovered = await requestJson(`${baseUrl}/functions/v1/insurance-policy-v3`, { method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ feedback_message_id: invoked.data.message_id, feedback_reason: 'incomplete', branch_name: 'Recovery Validation', debug: true }) });
      const second = recovered.data.message_id ? await requestJson(`${baseUrl}/functions/v1/insurance-policy-v3`, { method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ feedback_message_id: recovered.data.message_id, feedback_reason: 'incorrect', branch_name: 'Recovery Validation', debug: true }) }) : null;
      feedbackValidation = { first_http_status: recovered.response.status, first_answer_status: recovered.data.answer_status, first_recovery_used: recovered.data.recovery_used === true, first_has_citation: Array.isArray(recovered.data.citations) && recovered.data.citations.length > 0, first_message_id: Boolean(recovered.data.message_id), second_http_status: second?.response.status ?? null, second_recovery_exhausted: second?.data.recovery_exhausted === true, second_feedback_recorded: second?.data.feedback_recorded === true };
    }
    process.stdout.write(`${results.length}/${selectedCases.length} ${id}: HTTP ${invoked.response.status} semantic=${semanticPass} R@10=${recall10} selected=${selectedPass} final=${finalPass} source=${citedPass} recovery=${invoked.data.recovery_used === true} tokens=${Number(ai.total_tokens ?? 0)}\n`);
    await new Promise((resolve) => setTimeout(resolve, 2500));
  }
} finally {
  if (appUserCreated && userId) await fetch(`${baseUrl}/rest/v1/app_users?user_id=eq.${userId}`, { method: 'DELETE', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
  if (userId) await fetch(`${baseUrl}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
}
const pct = (key, rows = results) => rows.length ? Number((100 * rows.filter((row) => row[key] === true).length / rows.length).toFixed(2)) : 0;
const normal = results.filter((row) => !row.recovery_used);
const recovery = results.filter((row) => row.recovery_used);
const sortedLatency = results.map((row) => row.latency_ms).sort((a, b) => a - b);
const summary = {
  generated_at: new Date().toISOString(), deployed_version: 139, total: results.length,
  semantic_understanding_accuracy: pct('semantic_pass'), answer_bearing_recall_at_10: pct('recall_at_10'),
  selected_evidence_accuracy: pct('selected_evidence_pass'), final_answer_accuracy: pct('final_answer_pass'),
  source_supported_accuracy: pct('source_supported_pass'), clarification_accuracy: pct('clarification_pass', results.filter((row) => row.clarification_pass !== null)),
  recovery_success_rate: pct('final_answer_pass', recovery), false_not_established_rate: Number((100 * results.filter((row) => /do not establish|not established/i.test(row.answer) && row.final_answer_pass === false).length / results.length).toFixed(2)),
  http_error_rate: Number((100 * results.filter((row) => row.http_status >= 400).length / results.length).toFixed(2)),
  provider_fallback_rate: Number((100 * results.filter((row) => row.provider === 'groq_fallback').length / results.length).toFixed(2)),
  average_latency_ms: Math.round(results.reduce((sum, row) => sum + row.latency_ms, 0) / results.length),
  p95_latency_ms: sortedLatency[Math.ceil(sortedLatency.length * .95) - 1],
  average_tokens: Math.round(results.reduce((sum, row) => sum + row.total_tokens, 0) / results.length),
  normal_path: { count: normal.length, average_tokens: normal.length ? Math.round(normal.reduce((sum, row) => sum + row.total_tokens, 0) / normal.length) : 0 },
  recovery_path: { count: recovery.length, average_tokens: recovery.length ? Math.round(recovery.reduce((sum, row) => sum + row.total_tokens, 0) / recovery.length) : 0 },
};
const outputPath = process.env.VALIDATION_CASE_ID
  ? `insurance_v3/resilient_recovery_v139_${process.env.VALIDATION_CASE_ID}_result.json`
  : 'insurance_v3/resilient_recovery_v139_results.json';
fs.writeFileSync(outputPath, JSON.stringify({ summary: { ...summary, feedback_validation: feedbackValidation }, results }, null, 2));
console.log(JSON.stringify(summary, null, 2));
