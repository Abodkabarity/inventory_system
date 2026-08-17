begin;

-- V8 keeps fuzzy matching as an explicit user-confirmed clarification only.
-- The lower floor is used solely to show a suggestion chip; it never routes a
-- query or creates an alias automatically.
create or replace function public.suggest_insurance_entity_aliases_v1(
  query_text text,
  result_limit integer default 3
)
returns table (
  candidate_id uuid,
  entity_type text,
  canonical_name text,
  matched_alias text,
  query_fragment text,
  normalized_alias text,
  similarity_score double precision,
  document_ids uuid[]
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with q as (
    select public.insurance_search_normalize_v1(query_text) normalized_query,
      regexp_split_to_array(public.insurance_search_normalize_v1(query_text), ' ') words
  ), windows as (
    select a.id, a.entity_type, a.canonical_name, a.alias, a.normalized_alias,
      array_to_string(q.words[g.pos:g.pos + cardinality(regexp_split_to_array(public.insurance_search_normalize_v1(a.normalized_alias), ' ')) - 1], ' ') query_fragment
    from public.insurance_entity_aliases a cross join q
    cross join lateral generate_series(
      1,
      greatest(1, cardinality(q.words) - cardinality(regexp_split_to_array(public.insurance_search_normalize_v1(a.normalized_alias), ' ')) + 1)
    ) g(pos)
    where a.status = 'active'
      and a.entity_type in ('medication','ingredient','therapy_class','topic','diagnosis','procedure')
      and length(public.insurance_search_normalize_v1(a.normalized_alias)) >= 4
  ), ranked as (
    select w.*,
      greatest(
        similarity(public.insurance_search_normalize_v1(w.normalized_alias), w.query_fragment),
        word_similarity(public.insurance_search_normalize_v1(w.normalized_alias), w.query_fragment),
        strict_word_similarity(public.insurance_search_normalize_v1(w.normalized_alias), w.query_fragment)
      )::double precision score
    from windows w
  ), best_window as (
    select distinct on (r.id) r.*
    from ranked r
    order by r.id, r.score desc, length(r.query_fragment) desc
  )
  select r.id, r.entity_type, r.canonical_name, r.alias, r.query_fragment, r.normalized_alias, r.score,
    coalesce(array_agg(distinct de.document_id) filter (where de.document_id is not null), '{}'::uuid[])
  from best_window r
  left join public.insurance_document_entities de
    on de.entity_type = r.entity_type
   and public.insurance_search_normalize_v1(de.normalized_entity)
       = public.insurance_search_normalize_v1(r.normalized_alias)
  where r.score >= 0.54
  group by r.id, r.entity_type, r.canonical_name, r.alias, r.query_fragment, r.normalized_alias, r.score
  order by r.score desc, length(r.normalized_alias) desc, r.canonical_name
  limit greatest(1, least(coalesce(result_limit, 3), 5));
$$;

-- A verified document selected by the canonical resolver is an authoritative
-- scope. V8 permits clinically relevant rows from that exact document even
-- when legacy intent labels are stale or overly narrow. A conflicting entity
-- remains a hard rejection and cross-document neighbours are never recovered.
create or replace function public.search_insurance_knowledge_v8(
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
    select * from public.search_insurance_knowledge_v7(
      query_text, query_embedding, result_limit, active_only, insurance_company,
      insurance_plan, entity_hint, document_hint, intent_hint, topic_hint,
      document_family_hint, include_neighbors
    )
  ), checked as (
    select b.*,
      (
        coalesce(public.insurance_search_normalize_v1(entity_hint),'') = ''
        or coalesce(public.insurance_search_normalize_v1(b.entity_name_normalized),'') = ''
        or public.insurance_search_normalize_v1(b.entity_name_normalized)
           = public.insurance_search_normalize_v1(entity_hint)
        or public.insurance_search_normalize_v1(b.matched_content)
           like '%' || public.insurance_search_normalize_v1(entity_hint) || '%'
      ) as safe_entity_match,
      (
        b.intent_score > 0
        or lower(coalesce(intent_hint,'')) in ('definition','overview','brief')
        or (lower(coalesce(intent_hint,'')) in ('coverage','indication','eligibility','approval')
          and lower(b.matched_content) ~ '(not effective|criteria|eligible|indications?|must be documented|days? headache|coverage)')
        or (lower(coalesce(intent_hint,'')) in ('prescriber','prescriber_specialty')
          and lower(b.matched_content) ~ '(hematology|oncology|clinician|prescriber|column[[:space:]]*7)')
        or (lower(coalesce(intent_hint,'')) in ('stop_therapy','response_threshold')
          and lower(b.matched_content) ~ '(stop therapy|lack of efficacy|failure to achieve|reduction|response|threshold|continued therapy)')
      ) as clinical_intent_match
    from base b
  ), repaired as (
    select c.*,
      (
        c.accepted or (
          document_hint is not null
          and c.document_id = document_hint
          and c.safe_entity_match
          and c.clinical_intent_match
          and greatest(c.lexical_score, c.semantic_score) >= 0.22
        )
      ) as final_accepted
    from checked c
  )
  select r.chunk_id, r.document_id, r.document_title, r.file_name,
    r.storage_bucket, r.storage_path, r.matched_content,
    r.chunk_metadata || jsonb_build_object('validator','v8','v7_reason',r.acceptance_reason),
    r.section_title, r.page_from, r.page_to, r.sheet_name, r.row_from, r.row_to,
    r.entity_type, r.entity_name, r.entity_name_normalized, r.query_entity,
    r.query_entity_normalized, r.entity_score,
    case when r.clinical_intent_match then greatest(r.intent_score, 1.0) else r.intent_score end,
    r.context_score, r.final_accepted,
    case
      when r.accepted then r.acceptance_reason
      when r.final_accepted then 'accepted_exact_verified_document_clinical_context_v8'
      else r.acceptance_reason
    end,
    r.lexical_score, r.semantic_score, r.combined_score, r.chunk_index,
    r.parent_group, r.topic, r.topic_normalized, r.document_family
  from repaired r
  order by r.final_accepted desc, r.combined_score desc, r.lexical_score desc, r.chunk_id;
$$;

create or replace function public.confirm_insurance_clarification_v1(
  p_clarification_id uuid,
  p_candidate_id uuid
)
returns table (raw_query text, session_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.insurance_clarification_requests%rowtype;
  candidate jsonb;
  alias_row public.insurance_entity_aliases%rowtype;
  normalized_query text;
  normalized_fragment text;
  candidate_similarity double precision;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into request_row
  from public.insurance_clarification_requests
  where id = p_clarification_id and user_id = auth.uid()
  for update;
  if not found then raise exception 'Clarification not found'; end if;
  if request_row.status <> 'pending' or request_row.expires_at <= now() then
    raise exception 'Clarification is no longer active';
  end if;
  select value into candidate
  from jsonb_array_elements(request_row.candidates)
  where value->>'candidate_id' = p_candidate_id::text
  limit 1;
  if candidate is null then raise exception 'Candidate does not belong to this clarification'; end if;

  select * into alias_row
  from public.insurance_entity_aliases
  where id = p_candidate_id and status = 'active';
  if not found
     or alias_row.entity_type <> candidate->>'entity_type'
     or alias_row.canonical_name <> candidate->>'canonical_name' then
    raise exception 'Candidate is not a valid active entity alias';
  end if;

  normalized_query := public.insurance_search_normalize_v1(request_row.raw_query);
  normalized_fragment := public.insurance_search_normalize_v1(candidate->>'query_fragment');
  if length(normalized_fragment) < 3
     or position(normalized_fragment in normalized_query) = 0 then
    raise exception 'Candidate fragment is not present in the original question';
  end if;

  candidate_similarity := greatest(
    extensions.similarity(normalized_fragment, alias_row.normalized_alias)::double precision,
    extensions.word_similarity(normalized_fragment, alias_row.normalized_alias)::double precision,
    extensions.strict_word_similarity(normalized_fragment, alias_row.normalized_alias)::double precision
  );
  if candidate_similarity < 0.54 then
    raise exception 'Candidate similarity is below the safe learning threshold';
  end if;

  insert into public.insurance_entity_aliases (
    entity_type, canonical_name, alias, normalized_alias, language, metadata,
    created_by, source, status, confirmation_count, confirmed_at, last_used_at
  ) values (
    alias_row.entity_type, alias_row.canonical_name,
    candidate->>'query_fragment', normalized_fragment,
    'und', jsonb_build_object('source','user_confirmed_clarification','clarification_id',request_row.id),
    auth.uid(), 'user_confirmed', 'active', 1, now(), now()
  )
  on conflict (entity_type, normalized_alias) do update
  set confirmation_count = public.insurance_entity_aliases.confirmation_count + 1,
      confirmed_at = now(), last_used_at = now(), status = 'active',
      metadata = public.insurance_entity_aliases.metadata || excluded.metadata;

  update public.insurance_clarification_requests
  set status = 'confirmed', selected_candidate = candidate,
      confirmed_at = now()
  where id = request_row.id;
  return query select request_row.raw_query, request_row.session_id;
end;
$$;

revoke all on function public.suggest_insurance_entity_aliases_v1(text, integer) from public, anon;
grant execute on function public.suggest_insurance_entity_aliases_v1(text, integer) to authenticated, service_role;
revoke all on function public.confirm_insurance_clarification_v1(uuid, uuid) from public, anon;
grant execute on function public.confirm_insurance_clarification_v1(uuid, uuid) to authenticated, service_role;
revoke all on function public.search_insurance_knowledge_v8(text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text, text, text, boolean) from public, anon;
grant execute on function public.search_insurance_knowledge_v8(text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text, text, text, boolean) to authenticated, service_role;

commit;
