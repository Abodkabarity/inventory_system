begin;

create or replace function public.insurance_document_health_v1()
returns table (
  document_id uuid, title text, original_file_name text, file_size bigint,
  uploaded_at timestamptz, is_active boolean,
  lifecycle_status text, document_priority integer, processing_status text,
  search_validation_status text, chunk_count bigint, embedded_count bigint,
  entity_count bigint, missing_topic_count bigint, replacement_character_count bigint,
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
  select d.id,d.title,d.original_file_name,d.file_size,d.uploaded_at,d.is_active,d.lifecycle_status,
    d.document_priority,d.processing_status,d.search_validation_status,
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
  group by d.id,r.id
  order by d.title;
end;
$$;

create or replace function public.inspect_insurance_search_v1(p_query text)
returns table (
  rank integer, accepted boolean, acceptance_reason text, combined_score double precision,
  document_id uuid, document_title text, chunk_id uuid, section_title text,
  page_from integer, sheet_name text, row_from integer, entity_name text,
  matched_content text, chunk_metadata jsonb
)
language plpgsql stable security definer set search_path=public,extensions
as $$
declare
  v_entity text;
  v_document uuid;
  v_intent text;
begin
  if not public.is_insurance_knowledge_admin() and auth.role() <> 'service_role' then
    raise exception 'Insurance knowledge administrator access required';
  end if;
  select normalized_entity,document_id into v_entity,v_document
  from public.resolve_insurance_query_context_v2(p_query) limit 1;
  v_intent := case
    when lower(p_query) ~ '(dose|dosage|mg|mcg|جرعة)' then 'dose'
    when lower(p_query) ~ '(document|report|source|وثيق|تقرير|مصدر)' then 'documentation'
    when lower(p_query) ~ '(specialt|prescrib|طبيب|تخصص)' then 'prescriber'
    when lower(p_query) ~ '(age|years? old|عمر|سنة)' then 'age'
    when lower(p_query) ~ '(covered|coverage|eligible|تغطي|موافق)' then 'coverage'
    else null end;
  return query
  select row_number() over(order by s.accepted desc,s.combined_score desc)::integer,
    s.accepted,s.acceptance_reason,s.combined_score,s.document_id,s.document_title,
    s.chunk_id,s.section_title,s.page_from,s.sheet_name,s.row_from,s.entity_name,
    s.matched_content,s.chunk_metadata
  from public.search_insurance_knowledge_v5(
    p_query,null,30,true,null,null,v_entity,v_document,v_intent
  ) s;
end;
$$;

create or replace function public.inspect_insurance_source_v1(p_document_id uuid)
returns table (
  chunk_index integer, page_from integer, page_to integer, sheet_name text,
  row_from integer, row_to integer, section_title text, parent_group text,
  topic_normalized text, entity_name text, content_text text, structured_fields jsonb,
  metadata jsonb
)
language plpgsql stable security definer set search_path=public
as $$
begin
  if not public.is_insurance_knowledge_admin() and auth.role() <> 'service_role' then
    raise exception 'Insurance knowledge administrator access required';
  end if;
  return query select c.chunk_index,c.page_from,c.page_to,c.sheet_name,c.row_from,c.row_to,
    c.section_title,c.parent_group,c.topic_normalized,c.metadata->>'entity_name',
    c.content_text,c.structured_fields,c.metadata
  from public.insurance_document_chunks c
  where c.document_id=p_document_id order by c.chunk_index;
end;
$$;

revoke all on function public.insurance_document_health_v1() from public,anon;
revoke all on function public.inspect_insurance_search_v1(text) from public,anon;
revoke all on function public.inspect_insurance_source_v1(uuid) from public,anon;
grant execute on function public.insurance_document_health_v1() to authenticated,service_role;
grant execute on function public.inspect_insurance_search_v1(text) to authenticated,service_role;
grant execute on function public.inspect_insurance_source_v1(uuid) to authenticated,service_role;

commit;
