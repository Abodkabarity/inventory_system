import crypto from 'node:crypto';

const baseUrl = (process.env.SUPABASE_URL ?? '').replace(/\/$/, '');
const anonKey = process.env.SUPABASE_ANON_KEY ?? '';
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
if (!baseUrl || !anonKey || !serviceKey) throw new Error('Production validation credentials are required.');

async function jsonRequest(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let body;
  try { body = JSON.parse(text); } catch { body = { raw: text }; }
  return { response, body };
}

const firstQuestion = 'For Galcanezumab cluster headache, what is the dose at onset and the monthly dose after it?';
const equivalentQuestion = 'In cluster headache, state Galcanezumab onset dosing and its subsequent monthly dosing.';
const email = `semantic-learning-${Date.now()}-${crypto.randomUUID().slice(0, 6)}@example.invalid`;
const password = `${crypto.randomUUID()}!Aa9`;
let userId;
try {
  const adminHeaders = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' };
  const created = await jsonRequest(`${baseUrl}/auth/v1/admin/users`, { method: 'POST', headers: adminHeaders, body: JSON.stringify({ email, password, email_confirm: true }) });
  if (!created.response.ok) throw new Error(`temporary user creation failed (${created.response.status})`);
  userId = created.body.id;
  const granted = await jsonRequest(`${baseUrl}/rest/v1/app_users?on_conflict=user_id`, { method: 'POST', headers: { ...adminHeaders, Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ user_id: userId, role: 'inventory', is_active: true, user_name: 'Semantic learning validation' }) });
  if (!granted.response.ok) throw new Error(`temporary reader grant failed (${granted.response.status})`);
  const signedIn = await jsonRequest(`${baseUrl}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  if (!signedIn.response.ok) throw new Error(`temporary sign-in failed (${signedIn.response.status})`);
  const functionHeaders = { apikey: anonKey, Authorization: `Bearer ${signedIn.body.access_token}`, 'Content-Type': 'application/json' };
  const ask = (payload) => jsonRequest(`${baseUrl}/functions/v1/insurance-policy-v3`, { method: 'POST', headers: functionHeaders, body: JSON.stringify({ ...payload, branch_name: 'Semantic Learning Validation', debug: true }) });

  if (process.env.VALIDATE_LOOKUP_ONLY === '1') {
    const lookup = await ask({ message: equivalentQuestion });
    console.log(JSON.stringify({
      http: lookup.response.status, status: lookup.body.answer_status,
      semantic: lookup.body.debug?.semantic_interpretation ?? null,
      contract: lookup.body.debug?.question_contract ?? null,
      memory: lookup.body.debug?.ai?.semantic_recovery_memory ?? null,
    }, null, 2));
    process.exitCode = lookup.response.ok ? 0 : 1;
  } else {

  const first = await ask({ message: firstQuestion });
  if (!first.response.ok || !first.body.message_id) throw new Error(`first request failed (${first.response.status})`);
  const review = await ask({ feedback_message_id: first.body.message_id, feedback_reason: 'incorrect' });
  const recoveryDiagnostics = review.body.debug?.ai?.semantic_recovery ?? {};
  const createdMemory = recoveryDiagnostics.recovery_memory_created === true;
  const memoryId = review.body.debug?.ai?.semantic_recovery_memory?.memory_id ?? null;
  const second = await ask({ message: equivalentQuestion });
  const memoryDiagnostics = second.body.debug?.ai?.semantic_recovery_memory ?? {};
  const result = {
    first: { http: first.response.status, status: first.body.answer_status, citations: first.body.citations?.length ?? 0 },
    deep_review: { http: review.response.status, status: review.body.answer_status, recovery_used: review.body.recovery_used === true, citations: review.body.citations?.length ?? 0, memory_created: createdMemory, memory_id: memoryId, learning_eligibility: recoveryDiagnostics.learning_eligibility ?? null, answer_verifier: review.body.debug?.answer_verifier ?? null },
    equivalent_normal: { http: second.response.status, status: second.body.answer_status, recovery_used: second.body.recovery_used === true, citations: second.body.citations?.length ?? 0, memory_hit: memoryDiagnostics.hit === true, match_score: memoryDiagnostics.match_score ?? null },
  };
  result.pass = review.response.status === 200 && review.body.recovery_used === true && createdMemory && Boolean(memoryId)
    && second.response.status === 200 && memoryDiagnostics.hit === true && second.body.recovery_used !== true
    && (second.body.citations?.length ?? 0) > 0;
  console.log(JSON.stringify(result, null, 2));
  if (!result.pass) process.exitCode = 1;
  }
} finally {
  if (userId) {
    const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
    await fetch(`${baseUrl}/rest/v1/app_users?user_id=eq.${userId}`, { method: 'DELETE', headers });
    await fetch(`${baseUrl}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers });
  }
}
