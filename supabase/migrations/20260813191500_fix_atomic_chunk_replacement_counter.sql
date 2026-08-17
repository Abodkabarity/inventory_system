begin;

create or replace function public.replace_insurance_document_chunks_v2(
  p_document_id uuid,
  p_processing_run_id uuid,
  p_rows jsonb,
  p_worker_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_inserted_count integer;
  v_embedded_count integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'p_rows must be a non-empty JSON array';
  end if;

  insert into public.insurance_processing_runs (
    id, document_id, status, worker_version, metadata
  ) values (
    p_processing_run_id, p_document_id, 'chunking', p_worker_version,
    jsonb_build_object('replacement', 'atomic_v2')
  ) on conflict (id) do update
    set status = 'chunking', worker_version = excluded.worker_version, error = null;

  delete from public.insurance_document_chunks where document_id = p_document_id;

  insert into public.insurance_document_chunks (
    document_id, chunk_index, page_from, page_to, sheet_name, row_from, row_to,
    section_title, subsection_title, content_text, raw_content, content_type,
    extraction_method, token_count, content_hash, embedding, embedding_model,
    metadata, processing_run_id, parent_group, topic, topic_normalized,
    structured_fields, numeric_facts
  )
  select
    p_document_id, x.chunk_index, x.page_from, x.page_to, x.sheet_name,
    x.row_from, x.row_to, x.section_title, x.subsection_title, x.content_text,
    x.raw_content, x.content_type, x.extraction_method, x.token_count,
    x.content_hash,
    case when nullif(x.embedding, '') is null then null
         else x.embedding::extensions.vector end,
    x.embedding_model, coalesce(x.metadata, '{}'::jsonb), p_processing_run_id,
    coalesce(x.parent_group, x.metadata->>'parent_group'),
    coalesce(x.topic, x.metadata->>'document_topic'),
    coalesce(x.topic_normalized, x.metadata->>'topic_normalized'),
    coalesce(x.structured_fields, x.metadata->'fields', '{}'::jsonb),
    coalesce(x.numeric_facts, '[]'::jsonb)
  from jsonb_to_recordset(p_rows) as x(
    chunk_index integer, page_from integer, page_to integer, sheet_name text,
    row_from integer, row_to integer, section_title text, subsection_title text,
    content_text text, raw_content text, content_type text,
    extraction_method text, token_count integer, content_hash text,
    embedding text, embedding_model text, metadata jsonb, parent_group text,
    topic text, topic_normalized text, structured_fields jsonb, numeric_facts jsonb
  );

  get diagnostics v_inserted_count = row_count;
  select count(*) into v_embedded_count
  from public.insurance_document_chunks
  where document_id = p_document_id and processing_run_id = p_processing_run_id
    and embedding is not null;

  update public.insurance_processing_runs
  set status = case when v_embedded_count = v_inserted_count then 'validating' else 'embedding' end,
      chunk_count = v_inserted_count,
      embedded_count = v_embedded_count
  where id = p_processing_run_id;

  update public.insurance_documents
  set current_processing_run_id = p_processing_run_id,
      processing_status = 'embedding',
      search_validation_status = 'pending', search_validated_at = null,
      processing_error = null
  where id = p_document_id;

  return jsonb_build_object(
    'processing_run_id', p_processing_run_id,
    'chunk_count', v_inserted_count,
    'embedded_count', v_embedded_count
  );
end;
$$;

revoke all on function public.replace_insurance_document_chunks_v2(uuid, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.replace_insurance_document_chunks_v2(uuid, uuid, jsonb, text)
  to service_role;

commit;
