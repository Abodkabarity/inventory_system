// A durable worker, invoked by pg_cron/pg_net. No workstation process is used.
// Each invocation uploads at most four 6 MiB TUS chunks and then checkpoints.
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
const base = Deno.env.get('SUPABASE_URL')!;
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const storageBase = base.replace('.supabase.co', '.storage.supabase.co');
const bucket = 'sales-report-exports';
const auth = { apikey: key, Authorization: `Bearer ${key}` };
type Job = {
  id: string; generation: string; status: string; byte_size: number;
  storage_path: string; upload_url: string | null;
};
async function rpc(action: string, args: Record<string, unknown> = {}) {
  const response = await fetch(`${base}/rest/v1/rpc/sales_report_worker`, {
    method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_action: action, p_args: args }),
    signal: AbortSignal.timeout(action === 'prepare' ? 120000 : 30000),
  });
  if (!response.ok) throw new Error(`RPC ${action}: ${response.status} ${(await response.text()).slice(0, 350)}`);
  return response.json();
}
function safeUploadUrl(value: string) {
  const url = new URL(value, storageBase);
  if (![new URL(base).origin, new URL(storageBase).origin].includes(url.origin) ||
    !url.pathname.startsWith('/storage/v1/upload/resumable/')) {
    throw new Error('Invalid resumable upload location');
  }
  return url.href;
}
async function createUpload(job: Job) {
  const metadata = { bucketName: bucket, objectName: job.storage_path, contentType: 'text/csv', cacheControl: '0' };
  const response = await fetch(`${storageBase}/storage/v1/upload/resumable`, {
    method: 'POST', headers: {
      ...auth, 'Tus-Resumable': '1.0.0', 'Upload-Length': String(job.byte_size),
      'Upload-Metadata': Object.entries(metadata).map(([k, v]) => `${k} ${btoa(v)}`).join(','),
    }, signal: AbortSignal.timeout(20000),
  });
  if (!response.ok || !response.headers.get('location')) throw new Error(`Create upload: ${response.status}`);
  return safeUploadUrl(response.headers.get('location')!);
}
async function uploadOffset(url: string) {
  const response = await fetch(safeUploadUrl(url), {
    method: 'HEAD', headers: { ...auth, 'Tus-Resumable': '1.0.0' },
    signal: AbortSignal.timeout(15000),
  });
  if (response.status === 404 || response.status === 410) return null;
  if (!response.ok) throw new Error(`Read upload offset: ${response.status}`);
  const value = response.headers.get('Upload-Offset');
  if (value === null || !/^\d+$/.test(value)) throw new Error('Missing upload offset');
  return Number(value);
}
function decode(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
async function run() {
  const claimed = await rpc('claim');
  if (!claimed) return;
  const lease = claimed.lease;
  let job: Job = claimed.job;
  let args = { lease, id: job.id, generation: job.generation };
  try {
    // Remove obsolete immutable files using the Storage API, never SQL deletes.
    const obsolete: string[] = await rpc('garbage', { lease });
    if (obsolete.length) {
      const removed = await fetch(`${base}/storage/v1/object/${bucket}`, {
        method: 'DELETE', headers: { ...auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefixes: obsolete }), signal: AbortSignal.timeout(15000),
      });
      if (!removed.ok) console.error('Sales Report obsolete-file cleanup:', removed.status);
    }
    if (job.status === 'queued') {
      job = await rpc('prepare', args);
      args = { lease, id: job.id, generation: job.generation };
      // Monthly exports checkpoint one month per invocation. release() wakes
      // the next invocation; uploads begin only after every month is prepared.
      if (job.status === 'queued') return;
    }
    // Recover a completed PATCH even when its progress acknowledgement was lost.
    if (await rpc('complete', args)) return;
    let url = job.upload_url;
    const storedOffset = url ? await uploadOffset(url) : null;
    let offset: number;
    if (storedOffset === null) {
      url = await createUpload(job);
      await rpc('upload_url', { ...args, url });
      offset = 0;
    } else {
      offset = storedOffset;
    }
    const started = Date.now();
    for (let part = 0; part < 4 && offset < job.byte_size && Date.now() - started < 35000; part++) {
      const data = await rpc('bytes', { ...args, offset });
      const bytes = decode(data.base64);
      if (bytes.length !== data.length) throw new Error('CSV chunk length mismatch');
      const response: Response = await fetch(safeUploadUrl(url!), {
        method: 'PATCH', headers: {
          ...auth, 'Tus-Resumable': '1.0.0', 'Upload-Offset': String(offset),
          'Content-Type': 'application/offset+octet-stream',
        }, body: bytes, signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) throw new Error(`Upload CSV chunk: ${response.status}`);
      const next: number = Number(response.headers.get('Upload-Offset'));
      if (next !== offset + bytes.length) throw new Error('Unexpected acknowledged upload offset');
      offset = next;
      await rpc('progress', { ...args, offset });
    }
    if (offset === job.byte_size && !await rpc('complete', args)) throw new Error('Stored file size verification failed');
  } catch (error) {
    // Do not log credentials, request bodies, upload URLs or CSV contents.
    const message = error instanceof Error ? error.message : 'Worker failed';
    console.error('Sales Report:', message);
    try { await rpc('error', { ...args, error: message }); } catch { /* A newer generation may have replaced this lease. */ }
  } finally {
    try { await rpc('release', { lease }); } catch { /* pg_cron recovers an expired lease. */ }
  }
}
Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const length = Number(request.headers.get('content-length') ?? 0);
  if (length > 1024) return new Response('Too large', { status: 413 });
  try {
    const body = await request.json();
    if (typeof body.token !== 'string' || body.token.length > 256 || !await rpc('authorize', { token: body.token })) {
      return new Response('Unauthorized', { status: 401 });
    }
    // Gateway JWT checking is disabled ONLY because the function authenticates
    // with its own random, Vault-held worker token. This is not a public worker.
    EdgeRuntime.waitUntil(run());
    return Response.json({ accepted: true }, { status: 202 });
  } catch {
    return new Response('Invalid request', { status: 400 });
  }
});
