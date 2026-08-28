begin;

create table public.insurance_v4_entity_facts (
  id uuid primary key default gen_random_uuid(),
  fact_fingerprint text not null unique,
  subject_entity_id uuid references public.insurance_v3_entities(id) on delete restrict,
  subject_name text,
  subject_type text,
  predicate text not null,
  value_text text not null,
  numeric_values jsonb not null default '[]'::jsonb,
  binding_method text not null check (binding_method in (
    'direct_structured_row', 'explicit_single_entity_text', 'multi_entity_numeric_context'
  )),
  verification_status text not null check (verification_status in (
    'auto_verified', 'needs_review', 'human_verified', 'rejected'
  )),
  source_document_id uuid not null references public.insurance_v3_documents(id) on delete cascade,
  source_search_unit_id uuid not null references public.insurance_v3_search_units(id) on delete cascade,
  page_from integer,
  page_to integer,
  sheet_name text,
  row_from integer,
  row_to integer,
  source_excerpt text not null,
  extractor_version text not null default 'entity-fact-v1',
  active boolean not null default true,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((verification_status not in ('human_verified', 'rejected')) or reviewed_at is not null),
  check ((verification_status <> 'auto_verified') or subject_entity_id is not null)
);

create index insurance_v4_entity_facts_subject_idx
  on public.insurance_v4_entity_facts (subject_entity_id, verification_status)
  where active;
create index insurance_v4_entity_facts_document_idx
  on public.insurance_v4_entity_facts (source_document_id, verification_status);
create index insurance_v4_entity_facts_review_idx
  on public.insurance_v4_entity_facts (verification_status, created_at)
  where verification_status = 'needs_review';

create table public.insurance_v4_fact_review_queue (
  id uuid primary key default gen_random_uuid(),
  fact_id uuid not null references public.insurance_v4_entity_facts(id) on delete cascade,
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  resolution_note text,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (fact_id, reason),
  check ((status = 'pending' and resolved_at is null) or (status <> 'pending' and resolved_at is not null))
);

create index insurance_v4_fact_review_queue_pending_idx
  on public.insurance_v4_fact_review_queue (created_at)
  where status = 'pending';

alter table public.insurance_v4_entity_facts enable row level security;
alter table public.insurance_v4_fact_review_queue enable row level security;

revoke all on table public.insurance_v4_entity_facts from public, anon, authenticated;
revoke all on table public.insurance_v4_fact_review_queue from public, anon, authenticated;
grant all on table public.insurance_v4_entity_facts to service_role;
grant all on table public.insurance_v4_fact_review_queue to service_role;

comment on table public.insurance_v4_entity_facts is
  'Shadow-only entity-to-fact bindings. Production answers do not read this table until corpus review and regression gates pass.';
comment on column public.insurance_v4_entity_facts.verification_status is
  'Only direct single-entity structured records are auto-verified; multi-entity numeric contexts are quarantined for review.';
comment on table public.insurance_v4_fact_review_queue is
  'Private service-role review queue for ambiguous or cross-entity insurance facts.';

with medication_terms as (
  select e.id as entity_id, e.canonical_name, e.entity_type, e.normalized_name as term
  from public.insurance_v3_entities e
  where e.active and e.entity_type in ('medication_brand', 'medication_generic')
  union
  select e.id, e.canonical_name, e.entity_type, a.normalized_alias
  from public.insurance_v3_entities e
  join public.insurance_v3_aliases a on a.entity_id = e.id and a.verified
  where e.active and e.entity_type in ('medication_brand', 'medication_generic')
), matched as (
  select
    su.id as search_unit_id,
    su.document_id,
    su.unit_type,
    su.page_from,
    su.page_to,
    su.sheet_name,
    su.row_from,
    su.row_to,
    su.retrieval_text,
    mt.entity_id,
    mt.canonical_name,
    mt.entity_type
  from public.insurance_v3_search_units su
  join public.insurance_v3_documents d on d.id = su.document_id and d.is_active
  join medication_terms mt on (
    ' ' || regexp_replace(lower(su.retrieval_text), '[^a-z0-9]+', ' ', 'g') || ' '
  ) like ('% ' || regexp_replace(lower(mt.term), '[^a-z0-9]+', ' ', 'g') || ' %')
  where su.active
    and (su.unit_type = 'table_row' or su.retrieval_text ~ '[0-9]')
), grouped as (
  select
    search_unit_id,
    document_id,
    unit_type,
    page_from,
    page_to,
    sheet_name,
    row_from,
    row_to,
    retrieval_text,
    count(distinct entity_id) as entity_count,
    min(entity_id::text)::uuid as sole_entity_id,
    min(canonical_name) as sole_entity_name,
    min(entity_type) as sole_entity_type
  from matched
  group by search_unit_id, document_id, unit_type, page_from, page_to, sheet_name, row_from, row_to, retrieval_text
)
insert into public.insurance_v4_entity_facts (
  fact_fingerprint,
  subject_entity_id,
  subject_name,
  subject_type,
  predicate,
  value_text,
  numeric_values,
  binding_method,
  verification_status,
  source_document_id,
  source_search_unit_id,
  page_from,
  page_to,
  sheet_name,
  row_from,
  row_to,
  source_excerpt
)
select
  md5(g.search_unit_id::text || ':entity-fact-v1') as fact_fingerprint,
  case when g.entity_count = 1 then g.sole_entity_id end,
  case when g.entity_count = 1 then g.sole_entity_name end,
  case when g.entity_count = 1 then g.sole_entity_type end,
  case when g.unit_type = 'table_row' then 'structured_record' else 'numeric_context' end,
  g.retrieval_text,
  coalesce((
    select jsonb_agg(distinct match[1])
    from regexp_matches(g.retrieval_text, '([0-9]+(?:\.[0-9]+)?)', 'g') as match
  ), '[]'::jsonb),
  case
    when g.unit_type = 'table_row' and g.entity_count = 1 then 'direct_structured_row'
    when g.entity_count = 1 then 'explicit_single_entity_text'
    else 'multi_entity_numeric_context'
  end,
  case when g.unit_type = 'table_row' and g.entity_count = 1 then 'auto_verified' else 'needs_review' end,
  g.document_id,
  g.search_unit_id,
  g.page_from,
  g.page_to,
  g.sheet_name,
  g.row_from,
  g.row_to,
  left(g.retrieval_text, 4000)
from grouped g
on conflict (fact_fingerprint) do nothing;

insert into public.insurance_v4_fact_review_queue (fact_id, reason)
select
  f.id,
  case
    when f.binding_method = 'multi_entity_numeric_context' then 'multiple_medications_share_one_numeric_context'
    when f.binding_method = 'explicit_single_entity_text' then 'unstructured_numeric_fact_requires_scope_review'
    else 'structured_record_requires_entity_disambiguation'
  end
from public.insurance_v4_entity_facts f
where f.verification_status = 'needs_review'
on conflict (fact_id, reason) do nothing;

commit;
