begin;

-- V9 is a narrow retrieval hardening layer.  V8 already enforces the most
-- important guardrail: an explicit document/entity scope cannot be crossed.
-- This version allows a clinically-shaped paragraph inside that verified
-- document to reach the deterministic rule evaluator even when an older
-- chunk has no legacy intent label.  It does not relax entity/document scope
-- and never turns an unscoped semantic neighbour into evidence.
create or replace function public.search_insurance_knowledge_v9(
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
  with base as (
    select * from public.search_insurance_knowledge_v8(
      query_text, query_embedding, result_limit, active_only, insurance_company,
      insurance_plan, entity_hint, document_hint, intent_hint, topic_hint,
      document_family_hint, include_neighbors
    )
  ), scored as (
    select b.*,
      (
        select count(*)
        from regexp_split_to_table(public.insurance_search_normalize_v1(query_text), ' ') token
        where length(token) >= 4
          and token not in ('patient','therapy','criteria','coverage','eligible','months','weeks','years','about','using')
          and position(token in public.insurance_search_normalize_v1(b.matched_content)) > 0
      ) as lexical_clinical_overlap,
      (
        public.insurance_search_normalize_v1(b.matched_content) ~ '(>=|<=|[0-9]+[[:space:]]*(months?|weeks?|days?|cells?|percent|%|f[0-4]))'
        or lower(b.matched_content) ~ '(criteria|eligible|excluded|contraindicat|cirrhosis|eosinophil|pregnan|atopic dermatitis|asthma|dehydration|oral intake)'
      ) as is_clinical_rule
    from base b
  ), repaired as (
    select s.*,
      (
        s.accepted
        or (
          document_hint is not null
          and s.document_id = document_hint
          and (
            coalesce(public.insurance_search_normalize_v1(entity_hint),'') = ''
            or coalesce(public.insurance_search_normalize_v1(s.entity_name_normalized),'') = ''
            or public.insurance_search_normalize_v1(s.entity_name_normalized) = public.insurance_search_normalize_v1(entity_hint)
            or public.insurance_search_normalize_v1(s.matched_content) like '%' || public.insurance_search_normalize_v1(entity_hint) || '%'
          )
          and s.is_clinical_rule
          and (s.lexical_clinical_overlap >= 1 or greatest(s.lexical_score, s.semantic_score) >= 0.34)
        )
      ) as final_accepted
    from scored s
  )
  select r.chunk_id, r.document_id, r.document_title, r.file_name,
    r.storage_bucket, r.storage_path, r.matched_content,
    r.chunk_metadata || jsonb_build_object('validator','v9','v8_reason',r.acceptance_reason),
    r.section_title, r.page_from, r.page_to, r.sheet_name, r.row_from, r.row_to,
    r.entity_type, r.entity_name, r.entity_name_normalized, r.query_entity,
    r.query_entity_normalized, r.entity_score,
    case when r.final_accepted then greatest(r.intent_score, 1.0) else r.intent_score end,
    r.context_score, r.final_accepted,
    case
      when r.accepted then r.acceptance_reason
      when r.final_accepted then 'accepted_exact_verified_document_generic_clinical_rule_v9'
      else r.acceptance_reason
    end,
    r.lexical_score, r.semantic_score, r.combined_score, r.chunk_index,
    r.parent_group, r.topic, r.topic_normalized, r.document_family
  from repaired r
  order by r.final_accepted desc, r.combined_score desc, r.lexical_score desc, r.chunk_id;
$$;

revoke all on function public.search_insurance_knowledge_v9(text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text, text, text, boolean) from public, anon;
grant execute on function public.search_insurance_knowledge_v9(text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text, text, text, boolean) to authenticated, service_role;

commit;
