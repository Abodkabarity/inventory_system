begin;

-- Language examples teach the assistant how users ask questions. They never
-- contain policy answers, so adding dialects or abbreviations cannot invent
-- insurance knowledge.
create table public.insurance_language_aliases (
  id uuid primary key default gen_random_uuid(),
  alias_type text not null check (alias_type in (
    'intent_phrase','abbreviation','entity_alias','dialect','typo','concept'
  )),
  phrase text not null check (btrim(phrase) <> ''),
  normalized_concept text not null check (btrim(normalized_concept) <> ''),
  language text not null default 'und' check (language in ('en','ar','mixed','und')),
  weight numeric(4,3) not null default 1 check (weight > 0 and weight <= 1),
  status text not null default 'active' check (status in ('active','disabled','draft')),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint insurance_language_aliases_unique unique (alias_type, language, phrase)
);

create table public.insurance_intent_examples (
  id uuid primary key default gen_random_uuid(),
  intent text not null check (btrim(intent) <> ''),
  language text not null default 'und' check (language in ('en','ar','mixed','und')),
  example_text text not null check (btrim(example_text) <> ''),
  normalized_text text not null check (btrim(normalized_text) <> ''),
  secondary_intents text[] not null default '{}',
  weight numeric(4,3) not null default 1 check (weight > 0 and weight <= 1),
  status text not null default 'active' check (status in ('active','disabled','draft')),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint insurance_intent_examples_unique unique (intent, language, normalized_text)
);

-- One entity may legitimately occur in many documents, plans and versions.
-- This removes the old single-document metadata assumption from retrieval.
create table public.insurance_document_entities (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.insurance_documents(id) on delete cascade,
  entity_type text not null check (btrim(entity_type) <> ''),
  canonical_name text not null check (btrim(canonical_name) <> ''),
  normalized_entity text not null check (btrim(normalized_entity) <> ''),
  role text not null default 'mentioned' check (role in (
    'primary','covered','excluded','mentioned','ingredient','class','plan','company','diagnosis'
  )),
  confidence numeric(4,3) not null default 1 check (confidence >= 0 and confidence <= 1),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint insurance_document_entities_unique
    unique (document_id, entity_type, normalized_entity, role)
);

create table public.insurance_source_relations (
  id uuid primary key default gen_random_uuid(),
  source_document_id uuid not null references public.insurance_documents(id) on delete cascade,
  target_document_id uuid not null references public.insurance_documents(id) on delete cascade,
  relation_type text not null check (relation_type in (
    'supersedes','amends','clarifies','conflicts_with','same_policy_family'
  )),
  priority integer not null default 0,
  notes text,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  constraint insurance_source_relations_not_self check (source_document_id <> target_document_id),
  constraint insurance_source_relations_unique
    unique (source_document_id, target_document_id, relation_type)
);

create table public.insurance_answer_audits (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.insurance_chat_sessions(id) on delete set null,
  message_id uuid references public.insurance_chat_messages(id) on delete set null,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  raw_question text not null,
  structured_query jsonb not null default '{}'::jsonb,
  retrieval_plan jsonb not null default '{}'::jsonb,
  retrieved_candidates jsonb not null default '[]'::jsonb,
  verified_evidence jsonb not null default '[]'::jsonb,
  rejected_candidates jsonb not null default '[]'::jsonb,
  answer_status text not null check (answer_status in (
    'answered','partial','insufficient_evidence','clarification_required','conflict'
  )),
  confidence jsonb not null default '{}'::jsonb,
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  created_at timestamptz not null default now()
);

create table public.insurance_learning_queue (
  id uuid primary key default gen_random_uuid(),
  audit_id uuid references public.insurance_answer_audits(id) on delete set null,
  feedback_id uuid references public.insurance_feedback(id) on delete set null,
  reason text not null check (reason in (
    'negative_feedback','low_confidence','unknown_intent','unresolved_entity',
    'insufficient_evidence','source_conflict','manual_review'
  )),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  priority smallint not null default 2 check (priority between 1 and 4),
  proposed_change jsonb not null default '{}'::jsonb,
  resolution_notes text,
  assigned_to uuid references auth.users(id),
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.insurance_documents
  add column if not exists embedding_model text;
alter table public.insurance_document_chunks
  add column if not exists embedding_model text;

create index insurance_language_aliases_lookup_idx
  on public.insurance_language_aliases (status, language, normalized_concept);
create index insurance_intent_examples_lookup_idx
  on public.insurance_intent_examples (status, language, intent);
create index insurance_document_entities_entity_idx
  on public.insurance_document_entities (entity_type, normalized_entity, document_id);
create index insurance_source_relations_source_idx
  on public.insurance_source_relations (source_document_id, relation_type, priority desc);
create index insurance_answer_audits_user_created_idx
  on public.insurance_answer_audits (user_id, created_at desc);
create index insurance_learning_queue_status_idx
  on public.insurance_learning_queue (status, priority desc, created_at);

alter table public.insurance_language_aliases enable row level security;
alter table public.insurance_intent_examples enable row level security;
alter table public.insurance_document_entities enable row level security;
alter table public.insurance_source_relations enable row level security;
alter table public.insurance_answer_audits enable row level security;
alter table public.insurance_learning_queue enable row level security;

create policy insurance_language_aliases_read
on public.insurance_language_aliases for select to authenticated
using (status = 'active' and public.is_insurance_knowledge_reader()
  or public.is_insurance_knowledge_admin());
create policy insurance_language_aliases_admin_write
on public.insurance_language_aliases for all to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());

create policy insurance_intent_examples_read
on public.insurance_intent_examples for select to authenticated
using (status = 'active' and public.is_insurance_knowledge_reader()
  or public.is_insurance_knowledge_admin());
create policy insurance_intent_examples_admin_write
on public.insurance_intent_examples for all to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());

create policy insurance_document_entities_read
on public.insurance_document_entities for select to authenticated
using (public.is_insurance_knowledge_reader() or public.is_insurance_knowledge_admin());
create policy insurance_document_entities_admin_write
on public.insurance_document_entities for all to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());

create policy insurance_source_relations_read
on public.insurance_source_relations for select to authenticated
using (public.is_insurance_knowledge_reader() or public.is_insurance_knowledge_admin());
create policy insurance_source_relations_admin_write
on public.insurance_source_relations for all to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());

create policy insurance_answer_audits_own_read
on public.insurance_answer_audits for select to authenticated
using ((select auth.uid()) = user_id or public.is_insurance_knowledge_admin());
create policy insurance_answer_audits_own_insert
on public.insurance_answer_audits for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy insurance_learning_queue_admin
on public.insurance_learning_queue for all to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());
create policy insurance_learning_queue_own_audit_insert
on public.insurance_learning_queue for insert to authenticated
with check (exists (
  select 1 from public.insurance_answer_audits a
  where a.id = audit_id and a.user_id = (select auth.uid())
));

grant select, insert, update, delete on
  public.insurance_language_aliases,
  public.insurance_intent_examples,
  public.insurance_document_entities,
  public.insurance_source_relations
to authenticated;
grant select, insert on public.insurance_answer_audits to authenticated;
grant select, insert, update, delete on public.insurance_learning_queue to authenticated;
grant all on
  public.insurance_language_aliases,
  public.insurance_intent_examples,
  public.insurance_document_entities,
  public.insurance_source_relations,
  public.insurance_answer_audits,
  public.insurance_learning_queue
to service_role;

-- Backfill the many-to-many registry without assuming that an alias belongs to
-- only one policy. Structured chunk ownership is the most reliable source.
insert into public.insurance_document_entities (
  document_id, entity_type, canonical_name, normalized_entity, role, confidence, metadata
)
select distinct
  c.document_id,
  coalesce(nullif(c.metadata->>'entity_type', ''), 'medication'),
  c.metadata->>'entity_name',
  lower(btrim(c.metadata->>'entity_name_normalized')),
  'primary',
  1,
  jsonb_build_object('source', 'structured_chunk_backfill')
from public.insurance_document_chunks c
where nullif(c.metadata->>'entity_name', '') is not null
  and nullif(c.metadata->>'entity_name_normalized', '') is not null
on conflict do nothing;

commit;
