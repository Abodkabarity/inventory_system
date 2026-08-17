create or replace function public.search_insurance_knowledge_v3(
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
  ), known_entities as (
    select distinct
      c.metadata->>'entity_type' as entity_type,
      c.metadata->>'entity_name' as entity_name,
      c.metadata->>'entity_name_normalized' as canonical_normalized,
      c.metadata->>'entity_name_normalized' as match_normalized
    from public.insurance_document_chunks c
    where nullif(c.metadata->>'entity_name_normalized', '') is not null
    union
    select distinct
      a.entity_type,
      a.canonical_name,
      lower(btrim(a.canonical_name)),
      lower(btrim(a.normalized_alias))
    from public.insurance_entity_aliases a
  ), matched_entities as (
    select distinct on (e.canonical_normalized)
      e.entity_type, e.entity_name, e.canonical_normalized
    from known_entities e
    cross join params p
    where nullif(e.match_normalized, '') is not null
      and position(e.match_normalized in p.normalized_query) > 0
    order by e.canonical_normalized, length(e.match_normalized) desc
  ), explicit_context as (
    select
      case when count(*) = 1 then max(entity_type) end as entity_type,
      case when count(*) = 1 then max(entity_name) end as entity_name,
      case when count(*) = 1 then max(canonical_normalized) end as entity_normalized,
      count(*) as entity_count
    from matched_entities
  ), hinted_context as (
    select e.entity_type, e.entity_name, e.canonical_normalized as entity_normalized
    from known_entities e
    cross join params p
    where p.normalized_hint <> ''
      and (
        e.canonical_normalized = p.normalized_hint
        or lower(btrim(e.entity_name)) = p.normalized_hint
        or e.match_normalized = p.normalized_hint
      )
    order by
      case when e.canonical_normalized = p.normalized_hint then 0 else 1 end,
      length(e.match_normalized) desc
    limit 1
  ), entity_context as (
    select
      case
        when ec.entity_count = 1 then ec.entity_type
        when ec.entity_count = 0 then hc.entity_type
      end as entity_type,
      case
        when ec.entity_count = 1 then ec.entity_name
        when ec.entity_count = 0 then hc.entity_name
      end as entity_name,
      case
        when ec.entity_count = 1 then ec.entity_normalized
        when ec.entity_count = 0 then hc.entity_normalized
      end as entity_normalized,
      ec.entity_count,
      case when ec.entity_count = 0 and hc.entity_normalized is not null then true else false end as inherited
    from explicit_context ec
    left join hinted_context hc on true
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
      case
        when document_hint is null then 0.0
        when d.id = document_hint then 1.0
        else -0.25
      end::double precision as context_score,
      (
        ec.entity_normalized is null
        or nullif(c.metadata->>'entity_name_normalized', '') is null
        or c.metadata->>'entity_name_normalized' = ec.entity_normalized
      ) as accepted,
      case
        when ec.entity_normalized is null and ec.entity_count > 1 then 'accepted_multi_entity_query'
        when ec.entity_normalized is null then 'accepted_no_exact_entity'
        when c.metadata->>'entity_name_normalized' = ec.entity_normalized
          then case when ec.inherited then 'accepted_inherited_exact_entity' else 'accepted_exact_entity' end
        when nullif(c.metadata->>'entity_name_normalized', '') is null
          then case when ec.inherited then 'accepted_inherited_entity_context' else 'accepted_untagged_context' end
        else 'rejected_conflicting_entity'
      end as acceptance_reason,
      greatest(
        ts_rank_cd(c.search_vector, p.tsq, 32),
        similarity(lower(c.content_text), p.normalized_query),
        case
          when p.normalized_query <> '' and lower(c.content_text) like '%' || p.normalized_query || '%'
          then 1.0 else 0.0
        end,
        case
          when ec.entity_normalized is not null
            and c.metadata->>'entity_name_normalized' = ec.entity_normalized
          then 1.0 else 0.0
        end
      )::double precision as lexical_score,
      case
        when query_embedding is null or c.embedding is null then 0.0
        else (1 - (c.embedding <=> query_embedding))::double precision
      end as semantic_score
    from public.insurance_document_chunks c
    join public.insurance_documents d on d.id = c.document_id
    cross join params p
    cross join entity_context ec
    where d.processing_status = 'ready'
      and (not active_only or d.is_active)
      and (insurance_company is null or d.insurance_company_id = insurance_company)
      and (insurance_plan is null or d.insurance_plan_id = insurance_plan)
      and (
        c.search_vector @@ p.tsq
        or similarity(lower(c.content_text), p.normalized_query) > 0.08
        or (query_embedding is not null and c.embedding is not null)
        or (
          ec.entity_normalized is not null
          and c.metadata->>'entity_name_normalized' = ec.entity_normalized
        )
        or (
          p.normalized_intent = 'age'
          and lower(c.content_text) ~ '(years? old|under[ -]?18|less than *18|younger than *18|< *18|adult|pediatric|adolescent)'
        )
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
    s.intent_score, s.context_score,
    s.accepted, s.acceptance_reason,
    s.lexical_score, s.semantic_score, s.final_score as combined_score
  from scored s
  order by s.accepted desc, s.final_score desc, s.lexical_score desc
  limit greatest(1, least(coalesce(result_limit, 12), 30));
$$;

revoke all on function public.search_insurance_knowledge_v3(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text
) from public, anon;
grant execute on function public.search_insurance_knowledge_v3(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text
) to authenticated, service_role;
