begin;

-- Generic, source-derived metadata for every approved document. No medication,
-- diagnosis, or policy name is hardcoded here.
create table if not exists public.insurance_document_profiles (
  document_id uuid primary key references public.insurance_documents(id) on delete cascade,
  profile jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','verified','failed')),
  extraction_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.insurance_document_sections (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.insurance_documents(id) on delete cascade,
  section_path text not null,
  title text not null,
  normalized_title text not null,
  section_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  unique (document_id, section_path)
);

create table if not exists public.insurance_entity_catalog (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.insurance_documents(id) on delete cascade,
  entity_type text not null check (entity_type in (
    'medication','brand','generic','ingredient','therapy_class','diagnosis',
    'lab','procedure','policy_term'
  )),
  canonical_name text not null,
  normalized_entity text not null,
  aliases jsonb not null default '[]'::jsonb,
  source text not null,
  confidence numeric not null default 1 check (confidence >= 0 and confidence <= 1),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (document_id, entity_type, normalized_entity)
);

create table if not exists public.insurance_document_health_checks (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.insurance_documents(id) on delete cascade,
  run_id uuid,
  status text not null check (status in ('verified','failed')),
  report jsonb not null default '{}'::jsonb,
  worker_version text,
  created_at timestamptz not null default now()
);

create index if not exists insurance_document_sections_lookup_idx
  on public.insurance_document_sections (document_id, normalized_title, section_order);
create index if not exists insurance_entity_catalog_lookup_idx
  on public.insurance_entity_catalog (normalized_entity, entity_type, document_id);
create index if not exists insurance_document_health_checks_latest_idx
  on public.insurance_document_health_checks (document_id, created_at desc);

alter table public.insurance_document_profiles enable row level security;
alter table public.insurance_document_sections enable row level security;
alter table public.insurance_entity_catalog enable row level security;
alter table public.insurance_document_health_checks enable row level security;

drop policy if exists insurance_document_profiles_admin_read on public.insurance_document_profiles;
create policy insurance_document_profiles_admin_read on public.insurance_document_profiles
  for select to authenticated using (public.is_insurance_knowledge_admin());
drop policy if exists insurance_document_sections_reader on public.insurance_document_sections;
create policy insurance_document_sections_reader on public.insurance_document_sections
  for select to authenticated using (public.is_insurance_knowledge_reader());
drop policy if exists insurance_entity_catalog_reader on public.insurance_entity_catalog;
create policy insurance_entity_catalog_reader on public.insurance_entity_catalog
  for select to authenticated using (public.is_insurance_knowledge_reader());
drop policy if exists insurance_document_health_checks_admin_read on public.insurance_document_health_checks;
create policy insurance_document_health_checks_admin_read on public.insurance_document_health_checks
  for select to authenticated using (public.is_insurance_knowledge_admin());

revoke all on public.insurance_document_profiles, public.insurance_document_sections,
  public.insurance_entity_catalog, public.insurance_document_health_checks from anon;
grant select on public.insurance_document_sections, public.insurance_entity_catalog to authenticated;
grant all on public.insurance_document_profiles, public.insurance_document_sections,
  public.insurance_entity_catalog, public.insurance_document_health_checks to service_role;

-- Backfill the architecture from the already-approved corpus. This is
-- intentionally source-derived: it neither invents entities nor changes any
-- existing chunk, embedding, or document lifecycle state. The worker adds
-- richer hierarchy and catalog data whenever a document is subsequently
-- ingested or reprocessed.
insert into public.insurance_document_profiles (
  document_id, profile, status, extraction_version
)
select
  d.id,
  jsonb_build_object(
    'title', d.title,
    'chunk_count', coalesce(s.chunk_count, 0),
    'section_titles', coalesce(s.section_titles, '[]'::jsonb),
    'section_count', coalesce(s.section_count, 0),
    'table_row_count', coalesce(s.table_row_count, 0),
    'list_count', coalesce(s.list_count, 0),
    'form_field_names', coalesce(s.form_field_names, '[]'::jsonb),
    'content_types', coalesce(s.content_types, '[]'::jsonb),
    'backfilled', true
  ),
  case
    when d.processing_status = 'ready'
      and d.search_validation_status = 'verified'
      and coalesce(s.chunk_count, 0) > 0 then 'verified'
    else 'pending'
  end,
  '2026.08.17-generic-backfill-v1'
from public.insurance_documents d
left join lateral (
  select
    count(*)::integer as chunk_count,
    jsonb_agg(distinct c.section_title) filter (where c.section_title is not null and btrim(c.section_title) <> '') as section_titles,
    count(distinct c.section_title) filter (where c.section_title is not null and btrim(c.section_title) <> '')::integer as section_count,
    count(*) filter (where c.content_type = 'table_row')::integer as table_row_count,
    count(*) filter (where c.content_type = 'list')::integer as list_count,
    '[]'::jsonb as form_field_names,
    jsonb_agg(distinct c.content_type) as content_types
  from public.insurance_document_chunks c
  where c.document_id = d.id
) s on true
on conflict (document_id) do nothing;

insert into public.insurance_document_sections (
  document_id, section_path, title, normalized_title, section_order, metadata
)
select
  c.document_id,
  coalesce(nullif(c.metadata ->> 'section_path', ''), c.section_title),
  c.section_title,
  public.insurance_search_normalize_v1(c.section_title),
  min(c.chunk_index)::integer,
  jsonb_build_object('source', 'existing_chunk_backfill')
from public.insurance_document_chunks c
where c.section_title is not null and btrim(c.section_title) <> ''
group by c.document_id,
  coalesce(nullif(c.metadata ->> 'section_path', ''), c.section_title),
  c.section_title
on conflict (document_id, section_path) do nothing;

insert into public.insurance_entity_catalog (
  document_id, entity_type, canonical_name, normalized_entity, aliases,
  source, confidence, metadata
)
select
  de.document_id,
  case lower(de.entity_type)
    when 'medication' then 'medication'
    when 'brand' then 'brand'
    when 'generic' then 'generic'
    when 'ingredient' then 'ingredient'
    when 'therapy_class' then 'therapy_class'
    when 'diagnosis' then 'diagnosis'
    when 'lab' then 'lab'
    when 'procedure' then 'procedure'
    else 'policy_term'
  end,
  de.canonical_name,
  de.normalized_entity,
  jsonb_build_array(de.canonical_name),
  'existing_document_entity_backfill',
  de.confidence,
  de.metadata || jsonb_build_object('role', de.role, 'backfilled', true)
from public.insurance_document_entities de
where btrim(de.canonical_name) <> '' and btrim(de.normalized_entity) <> ''
on conflict (document_id, entity_type, normalized_entity)
do update set
  aliases = public.insurance_entity_catalog.aliases || excluded.aliases,
  confidence = greatest(public.insurance_entity_catalog.confidence, excluded.confidence),
  metadata = public.insurance_entity_catalog.metadata || excluded.metadata,
  updated_at = now();

insert into public.insurance_document_health_checks (
  document_id, status, report, worker_version
)
select
  p.document_id,
  case when p.status = 'verified' then 'verified' else 'failed' end,
  jsonb_build_object(
    'status', p.status,
    'checks', jsonb_build_object(
      'has_chunks', coalesce((p.profile ->> 'chunk_count')::integer, 0) > 0,
      'search_validated', p.status = 'verified',
      'backfilled', true
    )
  ),
  '2026.08.17-generic-backfill-v1'
from public.insurance_document_profiles p;

-- V11 keeps V10's hybrid retrieval, then adds a final document lifecycle gate
-- and a section-aware rank boost. The section hint is a generic semantic
-- target produced by NLU, not a list of known policy headings.
create or replace function public.search_insurance_knowledge_v11(
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
  include_neighbors boolean default true,
  section_hint text default null
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
    select * from public.search_insurance_knowledge_v10(
      query_text, query_embedding, result_limit, active_only, insurance_company,
      insurance_plan, entity_hint, document_hint, intent_hint, topic_hint,
      document_family_hint, include_neighbors
    )
  ), current_documents as (
    select d.id
    from public.insurance_documents d
    where d.is_active
      and d.processing_status = 'ready'
      and d.search_validation_status = 'verified'
      and d.lifecycle_status = 'current'
      and (d.effective_from is null or d.effective_from <= current_date)
      and (d.effective_to is null or d.effective_to >= current_date)
      and not exists (
        select 1 from public.insurance_documents newer
        where newer.supersedes_document_id = d.id
          and newer.is_active
          and newer.processing_status = 'ready'
          and newer.search_validation_status = 'verified'
          and newer.lifecycle_status = 'current'
          and (newer.effective_from is null or newer.effective_from <= current_date)
          and (newer.effective_to is null or newer.effective_to >= current_date)
      )
  ), ranked as (
    select b.*,
      case when coalesce(btrim(section_hint), '') = '' then 0.0
      else greatest(
        similarity(public.insurance_search_normalize_v1(coalesce(b.section_title, '')),
                   public.insurance_search_normalize_v1(section_hint)),
        similarity(public.insurance_search_normalize_v1(coalesce(b.topic, '')),
                   public.insurance_search_normalize_v1(section_hint))
      ) end::double precision as section_score,
      exists (select 1 from current_documents c where c.id = b.document_id) as current_document
    from base b
  )
  select r.chunk_id, r.document_id, r.document_title, r.file_name,
    r.storage_bucket, r.storage_path, r.matched_content,
    r.chunk_metadata || jsonb_build_object('validator', 'v11', 'section_hint', section_hint),
    r.section_title, r.page_from, r.page_to, r.sheet_name, r.row_from, r.row_to,
    r.entity_type, r.entity_name, r.entity_name_normalized, r.query_entity,
    r.query_entity_normalized, r.entity_score, r.intent_score, r.context_score,
    (r.accepted and r.current_document) as accepted,
    case when not r.current_document then 'rejected_noncurrent_document_v11'
         else r.acceptance_reason end,
    r.lexical_score, r.semantic_score,
    (r.combined_score + r.section_score * 0.12)::double precision,
    r.chunk_index, r.parent_group, r.topic, r.topic_normalized, r.document_family
  from ranked r
  order by (r.accepted and r.current_document) desc,
           (r.combined_score + r.section_score * 0.12) desc,
           r.lexical_score desc, r.chunk_id;
$$;

revoke all on function public.search_insurance_knowledge_v11(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text,
  text, text, boolean, text
) from public, anon;
grant execute on function public.search_insurance_knowledge_v11(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text,
  text, text, boolean, text
) to authenticated, service_role;

commit;
