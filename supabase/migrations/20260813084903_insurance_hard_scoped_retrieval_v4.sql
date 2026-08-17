-- Retrieval v4 treats a pre-resolved document as a hard scope. This prevents
-- semantically similar medication rows from another policy from outranking the
-- evidence that belongs to the medication explicitly named by the user.
create or replace function public.search_insurance_knowledge_v4(
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
  with params as (
    select
      plainto_tsquery('simple', coalesce(query_text, '')) as tsq,
      lower(btrim(coalesce(query_text, ''))) as normalized_query,
      lower(btrim(coalesce(entity_hint, ''))) as normalized_hint,
      lower(btrim(coalesce(intent_hint, ''))) as normalized_intent
  ), entity_context as (
    select
      a.entity_type,
      a.canonical_name as entity_name,
      lower(btrim(a.canonical_name)) as entity_normalized
    from public.insurance_entity_aliases a
    cross join params p
    where
      (p.normalized_hint <> '' and (
        lower(btrim(a.canonical_name)) = p.normalized_hint
        or a.normalized_alias = p.normalized_hint
      ))
      or (p.normalized_hint = '' and position(a.normalized_alias in p.normalized_query) > 0)
    order by
      case when p.normalized_hint <> '' and lower(btrim(a.canonical_name)) = p.normalized_hint then 0 else 1 end,
      length(a.normalized_alias) desc
    limit 1
  ), resolved_context as (
    select entity_type, entity_name, entity_normalized from entity_context
    union all
    select null::text, null::text, null::text
    where not exists (select 1 from entity_context)
    limit 1
  ), ranked as (
    select
      c.id as chunk_id,
      d.id as document_id,
      d.title as document_title,
      d.original_file_name as file_name,
      d.storage_bucket,
      d.storage_path,
      c.content_text as matched_content,
      c.metadata as chunk_metadata,
      c.section_title,
      c.page_from,
      c.page_to,
      c.sheet_name,
      c.row_from,
      c.row_to,
      c.metadata->>'entity_type' as entity_type,
      c.metadata->>'entity_name' as entity_name,
      c.metadata->>'entity_name_normalized' as entity_name_normalized,
      ec.entity_name as query_entity,
      ec.entity_normalized as query_entity_normalized,
      case
        when ec.entity_normalized is null then 0.0
        when c.metadata->>'entity_name_normalized' = ec.entity_normalized then 1.0
        when nullif(c.metadata->>'entity_name_normalized', '') is not null then -1.0
        else 0.0
      end::double precision as entity_score,
      case p.normalized_intent
        when 'age' then case when lower(c.content_text) ~
          '(years? old|under[ -]?18|less than *18|younger than *18|< *18|adult|pediatric|adolescent)'
          then 1.0 else 0.0 end
        when 'dose' then case when lower(c.content_text) ~
          '(dose|dosage|mg|mcg|tablet|once daily|every [0-9]+ hours?)'
          then 1.0 else 0.0 end
        when 'initial_dispensing' then case when lower(c.content_text) ~
          '(initial|non-therapeutic|one.month|1.month|no refills?|dispens|supply)'
          then 1.0 else 0.0 end
        when 'supply_exception' then case when lower(c.content_text) ~
          '(three.month|3.month|no refills?|exception|maintenance)'
          then 1.0 else 0.0 end
        when 'lab_requirement' then case when lower(c.content_text) ~
          '(hba1c|a1c|glycated|[0-9]+ months?|laboratory|lab result)'
          then 1.0 else 0.0 end
        when 'approval' then case when lower(c.content_text) ~
          '(approval|authorization|authorisation|appeal|eligible|criteria|required)'
          then 1.0 else 0.0 end
        when 'coverage' then case when lower(c.content_text) ~
          '(covered|coverage|not covered|insurance|eligible|criteria)'
          then 1.0 else 0.0 end
        when 'documentation' then case when lower(c.content_text) ~
          '(document|documentation|report|signed|stamped|prescription|required)'
          then 1.0 else 0.0 end
        when 'prescriber' then case when lower(c.content_text) ~
          '(prescriber|clinician|physician|doctor|specialt)'
          then 1.0 else 0.0 end
        when 'previous_therapy' then case when lower(c.content_text) ~
          '(previous|prior|failed|failure|contraindicat|first-line|first line|treatment)'
          then 1.0 else 0.0 end
        else 0.0
      end::double precision as intent_score,
      case when document_hint is not null and d.id = document_hint then 1.0 else 0.0 end::double precision as context_score,
      (
        ec.entity_normalized is null
        or nullif(c.metadata->>'entity_name_normalized', '') is null
        or c.metadata->>'entity_name_normalized' = ec.entity_normalized
      ) as accepted,
      case
        when ec.entity_normalized is null then 'accepted_no_exact_entity'
        when c.metadata->>'entity_name_normalized' = ec.entity_normalized then 'accepted_exact_entity'
        when nullif(c.metadata->>'entity_name_normalized', '') is null then 'accepted_scoped_document_context'
        else 'rejected_conflicting_entity'
      end as acceptance_reason,
      greatest(
        ts_rank_cd(c.search_vector, p.tsq, 32),
        similarity(lower(c.content_text), p.normalized_query),
        case when p.normalized_query <> '' and lower(c.content_text) like '%' || p.normalized_query || '%' then 1.0 else 0.0 end,
        case when ec.entity_normalized is not null and c.metadata->>'entity_name_normalized' = ec.entity_normalized then 1.0 else 0.0 end
      )::double precision as lexical_score,
      case
        when query_embedding is null or c.embedding is null then 0.0
        else (1 - (c.embedding <=> query_embedding))::double precision
      end as semantic_score
    from public.insurance_document_chunks c
    join public.insurance_documents d on d.id = c.document_id
    cross join params p
    cross join resolved_context ec
    where d.processing_status = 'ready'
      and (not active_only or d.is_active)
      and (insurance_company is null or d.insurance_company_id = insurance_company)
      and (insurance_plan is null or d.insurance_plan_id = insurance_plan)
      and (document_hint is null or d.id = document_hint)
      and (
        c.search_vector @@ p.tsq
        or similarity(lower(c.content_text), p.normalized_query) > 0.08
        or (query_embedding is not null and c.embedding is not null)
        or (ec.entity_normalized is not null and c.metadata->>'entity_name_normalized' = ec.entity_normalized)
        -- Once the entity resolver has selected a document, rank every chunk in
        -- that document. This preserves short policy rows that do not repeat the
        -- medication name and would otherwise fail a lexical-only prefilter.
        or document_hint is not null
      )
  ), scored as (
    select r.*,
      (
        (r.lexical_score * 0.40)
        + (case when query_embedding is null then 0 else r.semantic_score * 0.20 end)
        + (case when r.entity_score = 1 then 0.65 when r.entity_score = -1 then -0.95 else 0 end)
        + (r.intent_score * 0.65)
        + (r.context_score * 0.30)
      )::double precision as final_score
    from ranked r
  )
  select
    s.chunk_id, s.document_id, s.document_title, s.file_name,
    s.storage_bucket, s.storage_path, s.matched_content, s.chunk_metadata,
    s.section_title, s.page_from, s.page_to, s.sheet_name, s.row_from, s.row_to,
    s.entity_type, s.entity_name, s.entity_name_normalized,
    s.query_entity, s.query_entity_normalized, s.entity_score,
    s.intent_score, s.context_score, s.accepted, s.acceptance_reason,
    s.lexical_score, s.semantic_score, s.final_score as combined_score
  from scored s
  order by s.accepted desc, s.final_score desc, s.lexical_score desc
  limit greatest(1, least(coalesce(result_limit, 12), 30));
$$;

revoke all on function public.search_insurance_knowledge_v4(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text
) from public, anon;
grant execute on function public.search_insurance_knowledge_v4(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text
) to authenticated, service_role;
