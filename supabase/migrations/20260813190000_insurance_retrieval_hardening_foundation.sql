begin;

-- Document lifecycle and provenance.  Retrieval must be able to distinguish a
-- current rule from a historical copy even when both contain the same drug.
alter table public.insurance_documents
  add column if not exists document_family text,
  add column if not exists document_priority integer not null default 100,
  add column if not exists lifecycle_status text not null default 'current',
  add column if not exists supersedes_document_id uuid references public.insurance_documents(id),
  add column if not exists current_processing_run_id uuid,
  add column if not exists search_validation_status text not null default 'pending',
  add column if not exists search_validated_at timestamptz,
  add column if not exists inactive_reason text;

alter table public.insurance_documents
  drop constraint if exists insurance_documents_lifecycle_status_check,
  add constraint insurance_documents_lifecycle_status_check
    check (lifecycle_status in ('current','superseded','historical','draft')),
  drop constraint if exists insurance_documents_search_validation_status_check,
  add constraint insurance_documents_search_validation_status_check
    check (search_validation_status in ('pending','verified','failed')),
  drop constraint if exists insurance_documents_priority_check,
  add constraint insurance_documents_priority_check check (document_priority between 0 and 1000);

create table if not exists public.insurance_processing_runs (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.insurance_documents(id) on delete cascade,
  status text not null default 'extracting' check (
    status in ('extracting','chunking','embedding','validating','ready','failed','superseded')
  ),
  worker_version text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  chunk_count integer not null default 0 check (chunk_count >= 0),
  embedded_count integer not null default 0 check (embedded_count >= 0),
  validation_status text not null default 'pending' check (
    validation_status in ('pending','verified','failed')
  ),
  validation_report jsonb not null default '{}'::jsonb,
  error text,
  metadata jsonb not null default '{}'::jsonb
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'insurance_documents_current_processing_run_fk'
  ) then
    alter table public.insurance_documents
      add constraint insurance_documents_current_processing_run_fk
      foreign key (current_processing_run_id)
      references public.insurance_processing_runs(id) on delete set null;
  end if;
end $$;

alter table public.insurance_document_chunks
  add column if not exists processing_run_id uuid references public.insurance_processing_runs(id) on delete cascade,
  add column if not exists parent_group text,
  add column if not exists topic text,
  add column if not exists topic_normalized text,
  add column if not exists structured_fields jsonb not null default '{}'::jsonb,
  add column if not exists numeric_facts jsonb not null default '[]'::jsonb;

create index if not exists insurance_documents_family_priority_idx
  on public.insurance_documents (document_family, lifecycle_status, is_active, document_priority desc);
create index if not exists insurance_processing_runs_document_started_idx
  on public.insurance_processing_runs (document_id, started_at desc);
create index if not exists insurance_chunks_processing_run_idx
  on public.insurance_document_chunks (processing_run_id, chunk_index);
create index if not exists insurance_chunks_topic_idx
  on public.insurance_document_chunks (document_id, topic_normalized);
create index if not exists insurance_chunks_parent_group_idx
  on public.insurance_document_chunks (document_id, parent_group);

alter table public.insurance_processing_runs enable row level security;
drop policy if exists insurance_processing_runs_admin_read on public.insurance_processing_runs;
create policy insurance_processing_runs_admin_read
on public.insurance_processing_runs for select to authenticated
using (public.is_insurance_knowledge_admin());
drop policy if exists insurance_processing_runs_admin_write on public.insurance_processing_runs;
create policy insurance_processing_runs_admin_write
on public.insurance_processing_runs for all to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());
grant select, insert, update, delete on public.insurance_processing_runs to authenticated;
grant all on public.insurance_processing_runs to service_role;

-- Therapy classes and clinical topics are first-class query entities.  They
-- must never be stored as medications merely to satisfy a narrow constraint.
alter table public.insurance_entity_aliases
  drop constraint if exists insurance_entity_aliases_entity_type_check;
alter table public.insurance_entity_aliases
  add constraint insurance_entity_aliases_entity_type_check check (
    entity_type in (
      'medication','ingredient','therapy_class','topic','diagnosis','procedure',
      'insurance_company','insurance_plan','intent'
    )
  );
alter table public.insurance_document_entities
  drop constraint if exists insurance_document_entities_role_check;
alter table public.insurance_document_entities
  add constraint insurance_document_entities_role_check check (
    role in (
      'primary','covered','excluded','mentioned','ingredient','class','topic',
      'plan','company','diagnosis','procedure'
    )
  );

-- Remove aliases produced by the old "word before number" heuristic.  This is
-- intentionally limited to the confirmed non-entity vocabulary.
delete from public.insurance_entity_aliases
where normalized_alias = any (array[
  'age','and','after','before','daily','dose','exceeding','for','initial',
  'initiate','maximum','minimum','monthly','months','need','recommended',
  'reaching','than','the','then','three','two','until','max','warrant'
]);
delete from public.insurance_document_entities
where normalized_entity = any (array[
  'age','and','after','before','daily','dose','exceeding','for','initial',
  'initiate','maximum','minimum','monthly','months','need','recommended',
  'reaching','than','the','then','three','two','until','max','warrant'
]);

update public.insurance_documents
set document_family = coalesce(
      nullif(metadata->>'document_family', ''),
      lower(regexp_replace(title, '\\s+(updated|old|new|version)\\b.*$', '', 'i'))
    ),
    effective_from = coalesce(
      effective_from,
      case when version ~ '^20[0-9]{2}-[01][0-9]-[0-3][0-9]$' then version::date end
    )
where document_family is null or effective_from is null;

-- A complete replacement is one database transaction: readers see either the
-- previous valid generation or the new generation, never an empty/partial set.
create or replace function public.replace_insurance_document_chunks_v2(
  p_document_id uuid,
  p_processing_run_id uuid,
  p_rows jsonb,
  p_worker_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  inserted_count integer;
  embedded_count integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'p_rows must be a non-empty JSON array';
  end if;

  insert into public.insurance_processing_runs (
    id, document_id, status, worker_version, metadata
  ) values (
    p_processing_run_id, p_document_id, 'chunking', p_worker_version,
    jsonb_build_object('replacement', 'atomic_v2')
  ) on conflict (id) do update
    set status = 'chunking', worker_version = excluded.worker_version, error = null;

  delete from public.insurance_document_chunks where document_id = p_document_id;

  insert into public.insurance_document_chunks (
    document_id, chunk_index, page_from, page_to, sheet_name, row_from, row_to,
    section_title, subsection_title, content_text, raw_content, content_type,
    extraction_method, token_count, content_hash, embedding, embedding_model,
    metadata, processing_run_id, parent_group, topic, topic_normalized,
    structured_fields, numeric_facts
  )
  select
    p_document_id, x.chunk_index, x.page_from, x.page_to, x.sheet_name,
    x.row_from, x.row_to, x.section_title, x.subsection_title, x.content_text,
    x.raw_content, x.content_type, x.extraction_method, x.token_count,
    x.content_hash,
    case when nullif(x.embedding, '') is null then null
         else x.embedding::extensions.vector end,
    x.embedding_model, coalesce(x.metadata, '{}'::jsonb), p_processing_run_id,
    coalesce(x.parent_group, x.metadata->>'parent_group'),
    coalesce(x.topic, x.metadata->>'document_topic'),
    coalesce(x.topic_normalized, x.metadata->>'topic_normalized'),
    coalesce(x.structured_fields, x.metadata->'fields', '{}'::jsonb),
    coalesce(x.numeric_facts, '[]'::jsonb)
  from jsonb_to_recordset(p_rows) as x(
    chunk_index integer, page_from integer, page_to integer, sheet_name text,
    row_from integer, row_to integer, section_title text, subsection_title text,
    content_text text, raw_content text, content_type text,
    extraction_method text, token_count integer, content_hash text,
    embedding text, embedding_model text, metadata jsonb, parent_group text,
    topic text, topic_normalized text, structured_fields jsonb, numeric_facts jsonb
  );

  get diagnostics inserted_count = row_count;
  select count(*) into embedded_count
  from public.insurance_document_chunks
  where document_id = p_document_id and processing_run_id = p_processing_run_id
    and embedding is not null;

  update public.insurance_processing_runs
  set status = case when embedded_count = inserted_count then 'validating' else 'embedding' end,
      chunk_count = inserted_count,
      embedded_count = embedded_count
  where id = p_processing_run_id;

  update public.insurance_documents
  set current_processing_run_id = p_processing_run_id,
      processing_status = case when embedded_count = inserted_count then 'embedding' else 'embedding' end,
      search_validation_status = 'pending', search_validated_at = null,
      processing_error = null
  where id = p_document_id;

  return jsonb_build_object(
    'processing_run_id', p_processing_run_id,
    'chunk_count', inserted_count,
    'embedded_count', embedded_count
  );
exception when others then
  update public.insurance_processing_runs
  set status = 'failed', error = left(sqlerrm, 2000), completed_at = now()
  where id = p_processing_run_id;
  raise;
end;
$$;
revoke all on function public.replace_insurance_document_chunks_v2(uuid, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.replace_insurance_document_chunks_v2(uuid, uuid, jsonb, text)
  to service_role;

-- Exact alias resolver with lifecycle-aware deterministic document selection.
-- It never falls back to a stale document_id stored in alias metadata.
create or replace function public.resolve_insurance_query_context_v2(query_text text)
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
    select a.entity_type, a.canonical_name, a.normalized_alias,
           length(a.normalized_alias) as match_length
    from public.insurance_entity_aliases a cross join params p
    where length(a.normalized_alias) >= 3
      and a.normalized_alias <> all (array[
        'age','and','for','the','then','three','two','months','need','max'
      ])
      and position(' ' || a.normalized_alias || ' ' in ' ' || p.q || ' ') > 0
  ), best as (
    select * from matches
    order by match_length desc, canonical_name, entity_type
    limit 1
  ), candidates as (
    select d.id, d.title, d.document_priority, d.effective_from,
           case when de.role = 'primary' then 3 when de.role in ('covered','class') then 2 else 1 end as entity_role_score
    from best b
    join public.insurance_document_entities de
      on de.entity_type = b.entity_type and de.normalized_entity = b.normalized_alias
    join public.insurance_documents d on d.id = de.document_id
    where d.processing_status = 'ready' and d.is_active
      and d.lifecycle_status = 'current'
    union all
    select distinct d.id, d.title, d.document_priority, d.effective_from, 0
    from best b
    join public.insurance_document_chunks c
      on lower(c.content_text) like '%' || b.normalized_alias || '%'
    join public.insurance_documents d on d.id = c.document_id
    where d.processing_status = 'ready' and d.is_active
      and d.lifecycle_status = 'current'
  ), choice as (
    select id, title
    from candidates
    order by entity_role_score desc, document_priority desc,
             effective_from desc nulls last, id
    limit 1
  )
  select b.entity_type, b.canonical_name, b.normalized_alias,
         c.id, c.title, c.title, 'exact_alias_lifecycle_priority'
  from best b left join choice c on true;
$$;
revoke all on function public.resolve_insurance_query_context_v2(text) from public, anon;
grant execute on function public.resolve_insurance_query_context_v2(text)
  to authenticated, service_role;

commit;
