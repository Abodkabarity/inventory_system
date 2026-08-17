begin;
drop function if exists public.insurance_document_health_v1();
create function public.insurance_document_health_v1()
returns table (
  document_id uuid, title text, original_file_name text, file_size bigint,
  uploaded_at timestamptz, is_active boolean, lifecycle_status text,
  document_priority integer, processing_status text, search_validation_status text,
  chunk_count bigint, embedded_count bigint, entity_count bigint,
  missing_topic_count bigint, replacement_character_count bigint,
  duplicate_hash_count bigint, processing_run_id uuid, run_status text,
  validation_report jsonb, last_error text
)
language plpgsql stable security definer set search_path=public,extensions
as $$
begin
  if not public.is_insurance_knowledge_admin() and auth.role() <> 'service_role' then
    raise exception 'Insurance knowledge administrator access required';
  end if;
  return query
  select d.id,d.title,d.original_file_name,d.file_size,d.uploaded_at,d.is_active,
    d.lifecycle_status,d.document_priority,d.processing_status,d.search_validation_status,
    count(distinct c.id),count(distinct c.id) filter(where c.embedding is not null),
    count(distinct de.id),
    count(distinct c.id) filter(where nullif(btrim(c.topic_normalized),'') is null),
    count(distinct c.id) filter(where c.content_text like '%'||chr(65533)||'%'),
    count(distinct c.id)-count(distinct c.content_hash),d.current_processing_run_id,
    r.status,r.validation_report,coalesce(d.processing_error,r.error)
  from public.insurance_documents d
  left join public.insurance_document_chunks c on c.document_id=d.id
  left join public.insurance_document_entities de on de.document_id=d.id
  left join public.insurance_processing_runs r on r.id=d.current_processing_run_id
  group by d.id,r.id order by d.title;
end;
$$;
revoke all on function public.insurance_document_health_v1() from public,anon;
grant execute on function public.insurance_document_health_v1() to authenticated,service_role;
commit;
