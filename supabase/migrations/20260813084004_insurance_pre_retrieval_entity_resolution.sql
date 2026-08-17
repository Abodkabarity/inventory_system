-- Build the entity registry from both structured medication rows and prose
-- mentions such as "MOUNJARO 2.5 MG". The ingestion worker maintains this
-- registry for future documents; these inserts backfill existing documents.
insert into public.insurance_entity_aliases (
  entity_type, canonical_name, alias, normalized_alias, language, metadata
)
select distinct
  'medication',
  c.metadata->>'entity_name',
  c.metadata->>'entity_name',
  lower(btrim(c.metadata->>'entity_name_normalized')),
  'und',
  jsonb_build_object(
    'document_id', d.id,
    'document_title', d.title,
    'discovery', 'structured_chunk'
  )
from public.insurance_document_chunks c
join public.insurance_documents d on d.id = c.document_id
where nullif(c.metadata->>'entity_name_normalized', '') is not null
on conflict (entity_type, normalized_alias) do update
set canonical_name = excluded.canonical_name,
    alias = excluded.alias,
    metadata = excluded.metadata;

with prose_mentions as (
  select distinct
    d.id as document_id,
    d.title as document_title,
    initcap(lower(m.parts[1])) as canonical_name,
    lower(m.parts[1]) as normalized_alias,
    m.parts[2] || ' ' || lower(m.parts[3]) as strength
  from public.insurance_document_chunks c
  join public.insurance_documents d on d.id = c.document_id
  cross join lateral regexp_matches(
    c.content_text,
    '\m([A-Z][A-Z0-9-]{2,})\s+([0-9]+(?:\.[0-9]+)?)\s*(MG|MCG|G|ML)\M',
    'g'
  ) as m(parts)
  where lower(m.parts[1]) not in (
    'age', 'dose', 'initial', 'maximum', 'minimum', 'monthly', 'recommended'
  )
)
insert into public.insurance_entity_aliases (
  entity_type, canonical_name, alias, normalized_alias, language, metadata
)
select
  'medication', canonical_name, canonical_name, normalized_alias, 'und',
  jsonb_build_object(
    'document_id', document_id,
    'document_title', document_title,
    'strength', strength,
    'discovery', 'prose_strength_mention'
  )
from prose_mentions
on conflict (entity_type, normalized_alias) do update
set canonical_name = excluded.canonical_name,
    alias = excluded.alias,
    metadata = excluded.metadata;

create or replace function public.resolve_insurance_query_context(query_text text)
returns table (
  entity_type text,
  canonical_name text,
  normalized_entity text,
  document_id uuid,
  document_title text,
  therapy_topic text,
  resolution_source text
)
language sql
stable
security invoker
set search_path = public
as $$
  with params as (
    select lower(regexp_replace(btrim(coalesce(query_text, '')), '[^[:alnum:].-]+', ' ', 'g')) as q
  ), matches as (
    select
      a.entity_type,
      a.canonical_name,
      a.normalized_alias,
      nullif(a.metadata->>'document_id', '')::uuid as mapped_document_id,
      length(a.normalized_alias) as match_length
    from public.insurance_entity_aliases a
    cross join params p
    where position(' ' || a.normalized_alias || ' ' in ' ' || p.q || ' ') > 0
  ), best as (
    select * from matches order by match_length desc, canonical_name limit 1
  ), candidate_documents as (
    select distinct d.id, d.title
    from best b
    join public.insurance_document_chunks c
      on position(b.normalized_alias in lower(c.content_text)) > 0
    join public.insurance_documents d on d.id = c.document_id
    where d.processing_status = 'ready' and d.is_active
  ), document_choice as (
    select
      case when count(*) = 1 then (array_agg(id))[1] else null end as id,
      case when count(*) = 1 then max(title) else null end as title
    from candidate_documents
  )
  select
    b.entity_type,
    b.canonical_name,
    lower(btrim(b.canonical_name)),
    coalesce(dc.id, b.mapped_document_id),
    coalesce(dc.title, d.title),
    coalesce(dc.title, d.title),
    'entity_registry_exact_alias'
  from best b
  cross join document_choice dc
  left join public.insurance_documents d on d.id = b.mapped_document_id;
$$;

revoke all on function public.resolve_insurance_query_context(text) from public, anon;
grant execute on function public.resolve_insurance_query_context(text) to authenticated, service_role;
