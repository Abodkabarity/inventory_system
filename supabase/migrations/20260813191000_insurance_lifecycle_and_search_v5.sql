begin;

create or replace function public.insurance_intent_compatible_v1(p_intent text, p_content text)
returns boolean language sql immutable parallel safe as $$
  select case lower(btrim(coalesce(p_intent,'')))
    when 'age' then lower(p_content) ~ '(years? old|under[ -]?[0-9]+|younger|adult|pediatric|adolescent|age)'
    when 'dose' then lower(p_content) ~ '(dose|dosage|mg|mcg|gram|capsule|tablet|once|twice|every [0-9]+ hours?)'
    when 'initial_dispensing' then lower(p_content) ~ '(initial|one.month|1.month|no refills?|dispens|supply|new prescription)'
    when 'supply_exception' then lower(p_content) ~ '(three.month|3.month|no refills?|exception|maintenance)'
    when 'lab_requirement' then lower(p_content) ~ '(hba1c|a1c|laboratory|lab result|months?)'
    when 'approval' then lower(p_content) ~ '(approval|authorization|authorisation|appeal|eligible|criteria|required)'
    when 'coverage' then lower(p_content) ~ '(covered|coverage|eligible|criteria|diagnosis|icd-[0-9]|icd-10)'
    when 'documentation' then lower(p_content) ~ '(document|documentation|report|record|form|patient|signed|stamped|required)'
    when 'prescriber' then lower(p_content) ~ '(prescriber|clinician|physician|doctor|specialt|oncology|hematology|neurology|dermatology|rheumatology|gastroenterology|immunology)'
    when 'previous_therapy' then lower(p_content) ~ '(previous|prior|failed|failure|contraindicat|first.line|treatment)'
    when 'definition' then lower(p_content) ~ '(type:|mechanism|is an?|class|antibody|agonist|antagonist|inhibitor)'
    when 'indication' then lower(p_content) ~ '(indicat|treatment|approved for|used for|disease)'
    else true
  end;
$$;

-- Explicit relationship for the only confirmed old/current policy pair.  The
-- current document wins entity resolution without deleting historical audit data.
update public.insurance_documents old_doc
set document_family = 'glp-1-receptor-agonists-adjudication',
    lifecycle_status = 'historical',
    document_priority = 0,
    effective_to = date '2025-12-03',
    inactive_reason = 'Superseded by the 2025-12-04 adjudication summary',
    is_active = false
where old_doc.id = '8758a5f9-3c66-47f9-a4bd-0d9045267dfb';

update public.insurance_documents current_doc
set document_family = 'glp-1-receptor-agonists-adjudication',
    lifecycle_status = 'current',
    document_priority = 250,
    effective_from = date '2025-12-04',
    supersedes_document_id = '8758a5f9-3c66-47f9-a4bd-0d9045267dfb',
    is_active = true
where current_doc.id = '690994d4-5365-4472-99c0-d95110c43391';

insert into public.insurance_source_relations (
  source_document_id, target_document_id, relation_type, priority, notes
) values (
  '690994d4-5365-4472-99c0-d95110c43391',
  '8758a5f9-3c66-47f9-a4bd-0d9045267dfb',
  'supersedes', 250, 'Explicit version relationship established during retrieval hardening'
) on conflict (source_document_id, target_document_id, relation_type)
do update set priority = excluded.priority, notes = excluded.notes;

-- V5 preserves hybrid retrieval while applying a separate fail-closed evidence
-- validation layer.  A semantic neighbor is never accepted merely because its
-- vector is close to the question.
create or replace function public.search_insurance_knowledge_v5(
  query_text text,
  query_embedding extensions.vector(384) default null,
  result_limit integer default 12,
  active_only boolean default true,
  insurance_company uuid default null,
  insurance_plan uuid default null,
  entity_hint text default null,
  document_hint uuid default null,
  intent_hint text default null
)
returns table (
  chunk_id uuid,
  document_id uuid,
  document_title text,
  file_name text,
  storage_bucket text,
  storage_path text,
  matched_content text,
  chunk_metadata jsonb,
  section_title text,
  page_from integer,
  page_to integer,
  sheet_name text,
  row_from integer,
  row_to integer,
  entity_type text,
  entity_name text,
  entity_name_normalized text,
  query_entity text,
  query_entity_normalized text,
  entity_score double precision,
  intent_score double precision,
  context_score double precision,
  accepted boolean,
  acceptance_reason text,
  lexical_score double precision,
  semantic_score double precision,
  combined_score double precision
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with base as (
    select *
    from public.search_insurance_knowledge_v4(
      query_text, query_embedding, 30, active_only, insurance_company,
      insurance_plan, entity_hint, document_hint, intent_hint
    )
  ), validated as (
    select
      b.*, d.lifecycle_status, d.document_priority, d.effective_from,
      exists (
        select 1
        from public.insurance_document_entities de
        where de.document_id = b.document_id
          and de.normalized_entity = lower(btrim(coalesce(entity_hint, b.query_entity_normalized, '')))
          and de.role in ('primary','covered','class','ingredient','mentioned')
      ) as document_entity_match,
      public.insurance_intent_compatible_v1(
        intent_hint,
        b.matched_content || E'\n' || coalesce(b.chunk_metadata->'fields','{}'::jsonb)::text
      ) as intent_match
    from base b
    join public.insurance_documents d on d.id = b.document_id
  ), decided as (
    select v.*,
      (
        v.lifecycle_status = 'current'
        and (document_hint is null or v.document_id = document_hint)
        and (
          nullif(lower(btrim(coalesce(entity_hint, ''))), '') is null
          or v.entity_name_normalized = lower(btrim(entity_hint))
          or v.document_entity_match
        )
        and v.intent_match
      ) as validator_accepted,
      case
        when v.lifecycle_status <> 'current' then 'rejected_inactive_or_superseded_document'
        when document_hint is not null and v.document_id <> document_hint then 'rejected_conflicting_document_scope'
        when nullif(lower(btrim(coalesce(entity_hint, ''))), '') is not null
             and coalesce(v.entity_name_normalized, '') <> lower(btrim(entity_hint))
             and not v.document_entity_match then 'rejected_wrong_entity_or_topic'
        when not v.intent_match then 'rejected_wrong_intent'
        when v.entity_name_normalized = lower(btrim(coalesce(entity_hint, '')))
          then 'accepted_exact_entity_and_intent'
        when v.document_entity_match then 'accepted_document_entity_and_intent'
        when document_hint is not null then 'accepted_hard_document_scope_and_intent'
        else 'accepted_hybrid_relevance_and_intent'
      end as validator_reason,
      (
        v.combined_score
        + case when v.lifecycle_status = 'current' then 0.15 else -2.0 end
        + least(v.document_priority, 300)::double precision / 1000.0
        + case when v.document_entity_match then 0.45 else 0 end
        + case when v.intent_match then 0.20 else -0.70 end
      )::double precision as validator_score
    from validated v
  )
  select
    x.chunk_id, x.document_id, x.document_title, x.file_name,
    x.storage_bucket, x.storage_path, x.matched_content,
    x.chunk_metadata || jsonb_build_object(
      'document_priority', x.document_priority,
      'lifecycle_status', x.lifecycle_status,
      'effective_from', x.effective_from,
      'validator', 'v5'
    ),
    x.section_title, x.page_from, x.page_to, x.sheet_name, x.row_from, x.row_to,
    x.entity_type, x.entity_name, x.entity_name_normalized,
    x.query_entity, x.query_entity_normalized, x.entity_score,
    x.intent_score, x.context_score, x.validator_accepted,
    x.validator_reason, x.lexical_score, x.semantic_score, x.validator_score
  from decided x
  order by x.validator_accepted desc, x.validator_score desc,
           x.lexical_score desc, x.chunk_id
  limit greatest(1, least(coalesce(result_limit, 12), 30));
$$;

revoke all on function public.search_insurance_knowledge_v5(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text
) from public, anon;
grant execute on function public.search_insurance_knowledge_v5(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text
) to authenticated, service_role;

commit;
