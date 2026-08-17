begin;

create schema if not exists extensions;
create extension if not exists vector with schema extensions;
create extension if not exists pg_trgm with schema extensions;

create or replace function public.is_insurance_knowledge_reader()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_users
    where user_id = auth.uid()
      and is_active is not false
      and lower(btrim(role::text)) in ('branch', 'store', 'inventory')
  );
$$;

create or replace function public.is_insurance_knowledge_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_users
    where user_id = auth.uid()
      and is_active is not false
      and lower(btrim(role::text)) = 'inventory'
  );
$$;

create table public.insurance_documents (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  original_file_name text not null,
  storage_bucket text not null default 'insurance-documents',
  storage_path text not null unique,
  mime_type text not null,
  file_extension text not null check (lower(file_extension) in ('pdf', 'docx', 'xlsx')),
  file_size bigint not null check (file_size > 0),
  insurance_company_id uuid,
  insurance_plan_id uuid,
  document_category text,
  title text not null,
  version text,
  effective_from date,
  effective_to date,
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  uploaded_at timestamptz not null default now(),
  processing_status text not null default 'uploaded'
    check (processing_status in ('uploaded','queued','extracting','chunking','embedding','ready','failed')),
  processing_error text,
  extraction_started_at timestamptz,
  extraction_completed_at timestamptz,
  is_active boolean not null default true,
  checksum text not null,
  metadata jsonb not null default '{}'::jsonb,
  constraint insurance_documents_checksum_unique unique (checksum),
  constraint insurance_documents_effective_dates_valid
    check (effective_to is null or effective_from is null or effective_to >= effective_from)
);

create table public.insurance_document_chunks (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.insurance_documents(id) on delete cascade,
  chunk_index integer not null check (chunk_index >= 0),
  page_from integer,
  page_to integer,
  sheet_name text,
  row_from integer,
  row_to integer,
  section_title text,
  subsection_title text,
  content_text text not null check (btrim(content_text) <> ''),
  raw_content text,
  content_type text not null default 'other'
    check (content_type in ('paragraph','section','table','table_row','list','clinical_rule','medication','dosage','coverage','documentation','warning','other')),
  extraction_method text not null default 'native'
    check (extraction_method in ('native','ocr','docx','xlsx')),
  token_count integer,
  content_hash text not null,
  embedding extensions.vector(384),
  metadata jsonb not null default '{}'::jsonb,
  search_vector tsvector generated always as (
    to_tsvector('simple', coalesce(section_title, '') || ' ' || coalesce(subsection_title, '') || ' ' || content_text)
  ) stored,
  created_at timestamptz not null default now(),
  constraint insurance_document_chunks_location_valid check (
    (page_from is null or page_from > 0)
    and (page_to is null or page_to >= page_from)
    and (row_from is null or row_from > 0)
    and (row_to is null or row_to >= row_from)
  ),
  constraint insurance_document_chunks_index_unique unique (document_id, chunk_index),
  constraint insurance_document_chunks_hash_unique unique (document_id, content_hash)
);

create table public.insurance_entity_aliases (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('medication','ingredient','insurance_company','insurance_plan','intent')),
  canonical_name text not null,
  alias text not null,
  normalized_alias text not null,
  language text not null default 'und',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  constraint insurance_entity_aliases_unique unique (entity_type, normalized_alias)
);

create table public.insurance_chat_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  branch_name text,
  title text not null default 'New conversation',
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.insurance_chat_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.insurance_chat_sessions(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  message text not null check (btrim(message) <> ''),
  parsed_data jsonb not null default '{}'::jsonb,
  citations jsonb not null default '[]'::jsonb,
  confidence numeric(5,4),
  created_at timestamptz not null default now()
);

create table public.insurance_feedback (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.insurance_chat_messages(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  rating smallint not null check (rating in (-1, 1)),
  comment text,
  created_at timestamptz not null default now(),
  constraint insurance_feedback_one_per_user unique (message_id, user_id)
);

create table public.insurance_ingestion_jobs (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.insurance_documents(id) on delete cascade,
  status text not null default 'queued' check (status in ('queued','running','completed','failed')),
  attempt_count integer not null default 0,
  locked_at timestamptz,
  locked_by text,
  last_error text,
  available_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint insurance_ingestion_jobs_active_unique unique (document_id)
);

create index insurance_documents_active_ready_idx
  on public.insurance_documents (is_active, processing_status, uploaded_at desc);
create index insurance_documents_company_plan_idx
  on public.insurance_documents (insurance_company_id, insurance_plan_id)
  where is_active;
create index insurance_document_chunks_document_idx
  on public.insurance_document_chunks (document_id, chunk_index);
create index insurance_document_chunks_search_idx
  on public.insurance_document_chunks using gin (search_vector);
create index insurance_document_chunks_content_trgm_idx
  on public.insurance_document_chunks using gin (lower(content_text) gin_trgm_ops);
create index insurance_document_chunks_embedding_idx
  on public.insurance_document_chunks using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;
create index insurance_chat_sessions_user_updated_idx
  on public.insurance_chat_sessions (user_id, updated_at desc);
create index insurance_chat_messages_session_created_idx
  on public.insurance_chat_messages (session_id, created_at);
create index insurance_ingestion_jobs_queue_idx
  on public.insurance_ingestion_jobs (status, available_at)
  where status in ('queued', 'failed');

create or replace function public.search_insurance_knowledge(
  query_text text,
  query_embedding extensions.vector(384) default null,
  result_limit integer default 8,
  active_only boolean default true,
  insurance_company uuid default null,
  insurance_plan uuid default null
)
returns table (
  chunk_id uuid,
  document_id uuid,
  document_title text,
  file_name text,
  storage_bucket text,
  storage_path text,
  matched_content text,
  section_title text,
  page_from integer,
  page_to integer,
  sheet_name text,
  row_from integer,
  row_to integer,
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
      lower(btrim(coalesce(query_text, ''))) as normalized_query
  ), ranked as (
    select
      c.id as chunk_id,
      d.id as document_id,
      d.title as document_title,
      d.original_file_name as file_name,
      d.storage_bucket,
      d.storage_path,
      c.content_text as matched_content,
      c.section_title,
      c.page_from,
      c.page_to,
      c.sheet_name,
      c.row_from,
      c.row_to,
      greatest(
        ts_rank_cd(c.search_vector, p.tsq, 32),
        similarity(lower(c.content_text), p.normalized_query),
        case when p.normalized_query <> '' and lower(c.content_text) like '%' || p.normalized_query || '%' then 1.0 else 0.0 end
      )::double precision as lexical_score,
      case when query_embedding is null or c.embedding is null then 0.0
           else (1 - (c.embedding <=> query_embedding))::double precision end as semantic_score
    from public.insurance_document_chunks c
    join public.insurance_documents d on d.id = c.document_id
    cross join params p
    where d.processing_status = 'ready'
      and (not active_only or d.is_active)
      and (insurance_company is null or d.insurance_company_id = insurance_company)
      and (insurance_plan is null or d.insurance_plan_id = insurance_plan)
      and (
        c.search_vector @@ p.tsq
        or similarity(lower(c.content_text), p.normalized_query) > 0.08
        or (query_embedding is not null and c.embedding is not null)
      )
  )
  select
    r.chunk_id, r.document_id, r.document_title, r.file_name,
    r.storage_bucket, r.storage_path, r.matched_content, r.section_title,
    r.page_from, r.page_to, r.sheet_name, r.row_from, r.row_to,
    r.lexical_score, r.semantic_score,
    (case
      when query_embedding is null then r.lexical_score
      else (r.lexical_score * 0.62) + (r.semantic_score * 0.38)
    end)::double precision as combined_score
  from ranked r
  order by combined_score desc, lexical_score desc
  limit greatest(1, least(coalesce(result_limit, 8), 20));
$$;

alter table public.insurance_documents enable row level security;
alter table public.insurance_document_chunks enable row level security;
alter table public.insurance_entity_aliases enable row level security;
alter table public.insurance_chat_sessions enable row level security;
alter table public.insurance_chat_messages enable row level security;
alter table public.insurance_feedback enable row level security;
alter table public.insurance_ingestion_jobs enable row level security;

create policy insurance_documents_read on public.insurance_documents for select to authenticated
  using (public.is_insurance_knowledge_reader());
create policy insurance_documents_admin_insert on public.insurance_documents for insert to authenticated
  with check (public.is_insurance_knowledge_admin());
create policy insurance_documents_admin_update on public.insurance_documents for update to authenticated
  using (public.is_insurance_knowledge_admin()) with check (public.is_insurance_knowledge_admin());
create policy insurance_documents_admin_delete on public.insurance_documents for delete to authenticated
  using (public.is_insurance_knowledge_admin());
create policy insurance_chunks_read on public.insurance_document_chunks for select to authenticated
  using (public.is_insurance_knowledge_reader());
create policy insurance_aliases_read on public.insurance_entity_aliases for select to authenticated
  using (public.is_insurance_knowledge_reader());
create policy insurance_aliases_admin on public.insurance_entity_aliases for all to authenticated
  using (public.is_insurance_knowledge_admin()) with check (public.is_insurance_knowledge_admin());
create policy insurance_sessions_own on public.insurance_chat_sessions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy insurance_messages_own_read on public.insurance_chat_messages for select to authenticated
  using (exists (select 1 from public.insurance_chat_sessions s where s.id = session_id and s.user_id = auth.uid()));
create policy insurance_messages_own_insert on public.insurance_chat_messages for insert to authenticated
  with check (exists (select 1 from public.insurance_chat_sessions s where s.id = session_id and s.user_id = auth.uid()));
create policy insurance_feedback_own on public.insurance_feedback for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'insurance-documents', 'insurance-documents', false, 52428800,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy insurance_storage_read on storage.objects for select to authenticated
  using (bucket_id = 'insurance-documents' and public.is_insurance_knowledge_reader());
create policy insurance_storage_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'insurance-documents' and public.is_insurance_knowledge_admin());
create policy insurance_storage_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'insurance-documents' and public.is_insurance_knowledge_admin())
  with check (bucket_id = 'insurance-documents' and public.is_insurance_knowledge_admin());
create policy insurance_storage_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'insurance-documents' and public.is_insurance_knowledge_admin());

revoke all on function public.is_insurance_knowledge_reader() from public, anon;
revoke all on function public.is_insurance_knowledge_admin() from public, anon;
revoke all on function public.search_insurance_knowledge(text, extensions.vector, integer, boolean, uuid, uuid) from public, anon;
grant execute on function public.is_insurance_knowledge_reader() to authenticated, service_role;
grant execute on function public.is_insurance_knowledge_admin() to authenticated, service_role;
grant execute on function public.search_insurance_knowledge(text, extensions.vector, integer, boolean, uuid, uuid) to authenticated, service_role;
grant select on public.insurance_document_chunks, public.insurance_entity_aliases to authenticated;
grant select, insert, update, delete on public.insurance_documents to authenticated;
grant select, insert, update, delete on public.insurance_chat_sessions, public.insurance_chat_messages, public.insurance_feedback to authenticated;
grant all on public.insurance_documents, public.insurance_document_chunks, public.insurance_entity_aliases, public.insurance_ingestion_jobs to service_role;

commit;
