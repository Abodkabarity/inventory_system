begin;

create or replace function public.insurance_v3_structured_entity_field_records(
  p_entity_ids uuid[],
  p_field text,
  p_limit integer default 20
)
returns table(
  chunk_id uuid,
  document_id uuid,
  document_title text,
  file_name text,
  page_from integer,
  page_to integer,
  sheet_name text,
  row_from integer,
  row_to integer,
  chunk_index integer,
  section_title text,
  chunk_text text,
  metadata jsonb,
  matched_entity_ids uuid[]
)
language sql stable security invoker set search_path = ''
as $$
  select
    unit.id,
    unit.document_id,
    document.title,
    document.file_name,
    unit.page_from,
    unit.page_to,
    unit.sheet_name,
    unit.row_from,
    unit.row_to,
    unit.sibling_order,
    unit.section_title,
    coalesce(nullif(unit.metadata->>'row_text', ''), unit.retrieval_text),
    unit.metadata,
    array_agg(distinct chunk_entity.entity_id order by chunk_entity.entity_id)
  from public.insurance_v3_search_units unit
  join public.insurance_v3_documents document
    on document.id = unit.document_id
   and document.is_active
   and document.status in ('ingested', 'ready', 'warning')
  cross join lateral unnest(unit.source_chunk_ids) source_chunk(id)
  join public.insurance_v3_chunk_entities chunk_entity
    on chunk_entity.chunk_id = source_chunk.id
   and chunk_entity.entity_id = any(coalesce(p_entity_ids, '{}'::uuid[]))
  where unit.active
    and unit.unit_type = 'table_row'
    and coalesce((unit.metadata->>'semantic_table_record')::boolean, false)
    and unit.metadata->'fields' ? p_field
    and nullif(btrim(unit.metadata->'fields'->>p_field), '') is not null
  group by unit.id, document.id
  order by document.effective_date desc nulls last,
           document.updated_at desc,
           unit.page_from,
           unit.sibling_order
  limit greatest(1, least(coalesce(p_limit, 20), 40));
$$;

revoke all on function public.insurance_v3_structured_entity_field_records(uuid[], text, integer)
  from public, anon;
grant execute on function public.insurance_v3_structured_entity_field_records(uuid[], text, integer)
  to authenticated, service_role;

comment on function public.insurance_v3_structured_entity_field_records(uuid[], text, integer) is
  'Returns entity-linked, zero-cross-row-overlap structured records for deterministic fact binding.';

commit;
