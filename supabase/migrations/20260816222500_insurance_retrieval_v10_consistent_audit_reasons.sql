begin;

-- Keep accepted/rejected state and its diagnostic reason consistent. Older
-- retrieval layers can legitimately repair a rejected candidate later in the
-- pipeline, but previously retained the stale rejection label. V10 preserves
-- that upstream label in metadata while exposing one truthful final reason to
-- the Search Inspector and answer audit.
create or replace function public.search_insurance_knowledge_v10(
  query_text text,
  query_embedding extensions.vector(384) default null,
  result_limit integer default 12,
  active_only boolean default true,
  insurance_company uuid default null,
  insurance_plan uuid default null,
  entity_hint text default null,
  document_hint uuid default null,
  intent_hint text default null,
  topic_hint text default null,
  document_family_hint text default null,
  include_neighbors boolean default true
)
returns table (
  chunk_id uuid, document_id uuid, document_title text, file_name text,
  storage_bucket text, storage_path text, matched_content text, chunk_metadata jsonb,
  section_title text, page_from integer, page_to integer, sheet_name text,
  row_from integer, row_to integer, entity_type text, entity_name text,
  entity_name_normalized text, query_entity text, query_entity_normalized text,
  entity_score double precision, intent_score double precision, context_score double precision,
  accepted boolean, acceptance_reason text, lexical_score double precision,
  semantic_score double precision, combined_score double precision, chunk_index integer,
  parent_group text, topic text, topic_normalized text, document_family text
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select s.chunk_id, s.document_id, s.document_title, s.file_name,
    s.storage_bucket, s.storage_path, s.matched_content,
    case
      when s.accepted and lower(coalesce(s.acceptance_reason, '')) like 'rejected_%'
        then s.chunk_metadata || jsonb_build_object(
          'validator', 'v10',
          'upstream_acceptance_reason', s.acceptance_reason
        )
      else s.chunk_metadata || jsonb_build_object('validator', 'v10')
    end,
    s.section_title, s.page_from, s.page_to, s.sheet_name, s.row_from, s.row_to,
    s.entity_type, s.entity_name, s.entity_name_normalized, s.query_entity,
    s.query_entity_normalized, s.entity_score, s.intent_score, s.context_score,
    s.accepted,
    case
      when s.accepted and lower(coalesce(s.acceptance_reason, '')) like 'rejected_%'
        then 'accepted_verified_scope_repair_v10'
      else s.acceptance_reason
    end,
    s.lexical_score, s.semantic_score, s.combined_score, s.chunk_index,
    s.parent_group, s.topic, s.topic_normalized, s.document_family
  from public.search_insurance_knowledge_v9(
    query_text, query_embedding, result_limit, active_only, insurance_company,
    insurance_plan, entity_hint, document_hint, intent_hint, topic_hint,
    document_family_hint, include_neighbors
  ) s
  order by s.accepted desc, s.combined_score desc, s.lexical_score desc, s.chunk_id;
$$;

revoke all on function public.search_insurance_knowledge_v10(text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text, text, text, boolean) from public, anon;
grant execute on function public.search_insurance_knowledge_v10(text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text, text, text, boolean) to authenticated, service_role;

commit;
