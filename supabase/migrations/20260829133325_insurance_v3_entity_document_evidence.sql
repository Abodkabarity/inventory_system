begin;

create or replace function public.insurance_v3_entity_document_evidence(
  p_entity_ids uuid[],
  p_limit integer default 40
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
  metadata jsonb
)
language sql stable security invoker set search_path = ''
as $$
  with ranked as (
    select
      chunk.id as chunk_id,
      chunk.document_id,
      document.title as document_title,
      document.file_name,
      chunk.page_from,
      chunk.page_to,
      chunk.sheet_name,
      chunk.row_from,
      chunk.row_to,
      chunk.chunk_index,
      chunk.section_title,
      chunk.chunk_text,
      chunk.metadata,
      row_number() over (
        partition by chunk.document_id
        order by
          case when public.insurance_v3_normalize(
            coalesce(chunk.section_title, '') || ' ' || chunk.chunk_text
          ) like '%eligible clinician%' then 0 else 1 end,
          chunk.page_from,
          chunk.chunk_index
      ) as document_rank
    from public.insurance_v3_chunk_entities chunk_entity
    join public.insurance_v3_chunks chunk on chunk.id = chunk_entity.chunk_id
    join public.insurance_v3_documents document
      on document.id = chunk.document_id
     and document.is_active
     and document.status in ('ingested', 'ready', 'warning')
    where chunk_entity.entity_id = any(coalesce(p_entity_ids, '{}'::uuid[]))
  )
  select
    ranked.chunk_id,
    ranked.document_id,
    ranked.document_title,
    ranked.file_name,
    ranked.page_from,
    ranked.page_to,
    ranked.sheet_name,
    ranked.row_from,
    ranked.row_to,
    ranked.chunk_index,
    ranked.section_title,
    ranked.chunk_text,
    ranked.metadata
  from ranked
  where ranked.document_rank = 1
  order by ranked.document_title, ranked.page_from
  limit greatest(1, least(coalesce(p_limit, 40), 80));
$$;

revoke all on function public.insurance_v3_entity_document_evidence(uuid[], integer)
  from public, anon;
grant execute on function public.insurance_v3_entity_document_evidence(uuid[], integer)
  to authenticated, service_role;

comment on function public.insurance_v3_entity_document_evidence(uuid[], integer) is
  'Returns one best source chunk per active document linked to a verified entity, for complete reverse policy lookup.';

commit;
