import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const model = new Supabase.ai.Session('gte-small');
const authorizedServiceKeyHash = '3140b2e62d15f8ac2d954f07ebc459afa4cd4580f092a7d297acabb8c844aade';

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supplied = (request.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!supplied || await sha256(supplied) !== authorizedServiceKeyHash) {
    return json({ error: 'Service-role authorization required' }, 403);
  }

  const client = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const body = await request.json().catch(() => ({}));

  if (body.mode === 'search') {
    const query = String(body.query ?? '').trim();
    if (!query) return json({ error: 'query is required' }, 400);
    const embedding = await model.run(query, { mean_pool: true, normalize: true });
    const { data, error } = await client.rpc('search_insurance_knowledge_v5', {
      query_text: query,
      query_embedding: embedding,
      result_limit: Math.min(24, Math.max(1, Number(body.limit ?? 10))),
      active_only: true,
      entity_hint: body.entity_hint ?? null,
      document_hint: body.document_hint ?? null,
      intent_hint: body.intent_hint ?? null,
    });
    if (error) return json({ error: error.message }, 500);
    return json({ results: data ?? [] });
  }

  const limit = Math.min(20, Math.max(1, Number(body.limit ?? 12)));
  let query = client
    .from('insurance_document_chunks')
    .select('id,document_id,content_text,metadata')
    .is('embedding', null)
    .order('document_id')
    .order('chunk_index')
    .limit(limit);
  if (body.document_id) query = query.eq('document_id', String(body.document_id));
  const { data: rows, error: selectError } = await query;
  if (selectError) return json({ error: selectError.message }, 500);

  const documentIds = new Set<string>();
  for (const row of rows ?? []) {
    const embedding = await model.run(row.content_text, {
      mean_pool: true,
      normalize: true,
    });
    const { error } = await client
      .from('insurance_document_chunks')
      .update({
        embedding,
        embedding_model: 'gte-small',
        metadata: { ...(row.metadata ?? {}), embedding_model: 'gte-small' },
      })
      .eq('id', row.id);
    if (error) return json({ error: error.message, chunk_id: row.id }, 500);
    documentIds.add(row.document_id);
  }

  const completed: string[] = [];
  const failedValidation: Array<{ document_id: string; reasons: string[] }> = [];
  for (const documentId of documentIds) {
    const { count, error } = await client
      .from('insurance_document_chunks')
      .select('id', { count: 'exact', head: true })
      .eq('document_id', documentId)
      .is('embedding', null);
    if (error) return json({ error: error.message }, 500);
    if ((count ?? 0) === 0) {
      const { data: indexedRows, error: validationError } = await client
        .from('insurance_document_chunks')
        .select('id,content_hash,topic_normalized,content_text,processing_run_id')
        .eq('document_id', documentId)
        .order('chunk_index');
      if (validationError) return json({ error: validationError.message }, 500);
      const reasons: string[] = [];
      if (!indexedRows?.length) reasons.push('no_chunks');
      if ((indexedRows ?? []).some((row) => !row.topic_normalized)) reasons.push('missing_topic_metadata');
      if ((indexedRows ?? []).some((row) => /\uFFFD/.test(row.content_text ?? ''))) reasons.push('replacement_character_detected');
      const hashes = new Set((indexedRows ?? []).map((row) => row.content_hash));
      if (hashes.size !== (indexedRows ?? []).length) reasons.push('duplicate_content_hash');
      const now = new Date().toISOString();
      const processingRunId = indexedRows?.[0]?.processing_run_id ?? null;
      await client.from('insurance_documents').update({
        processing_status: reasons.length === 0 ? 'ready' : 'failed',
        processing_error: reasons.length === 0 ? null : `Index validation failed: ${reasons.join(', ')}`,
        embedding_model: 'gte-small',
        extraction_completed_at: now,
        search_validation_status: reasons.length === 0 ? 'verified' : 'failed',
        search_validated_at: now,
      }).eq('id', documentId);
      if (processingRunId) {
        await client.from('insurance_processing_runs').update({
          status: reasons.length === 0 ? 'ready' : 'failed',
          validation_status: reasons.length === 0 ? 'verified' : 'failed',
          validation_report: {
            checks: ['non_empty', 'topic_metadata', 'unicode_integrity', 'deduplication', 'embeddings_complete'],
            reasons,
            chunk_count: indexedRows?.length ?? 0,
          },
          embedded_count: indexedRows?.length ?? 0,
          completed_at: now,
          error: reasons.length === 0 ? null : reasons.join(', '),
        }).eq('id', processingRunId);
      }
      await client.from('insurance_ingestion_jobs').update({
        status: reasons.length === 0 ? 'completed' : 'failed',
        last_error: reasons.length === 0 ? null : reasons.join(', '),
        updated_at: now,
      }).eq('document_id', documentId);
      if (reasons.length === 0) completed.push(documentId);
      else failedValidation.push({ document_id: documentId, reasons });
    }
  }

  const { count: remaining } = await client
    .from('insurance_document_chunks')
    .select('id', { count: 'exact', head: true })
    .is('embedding', null);
  return json({ processed: rows?.length ?? 0, completed, failed_validation: failedValidation, remaining: remaining ?? 0 });
});
