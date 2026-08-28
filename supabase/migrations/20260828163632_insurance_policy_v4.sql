begin;

create table public.insurance_v4_answer_audits (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid references public.insurance_chat_sessions(id) on delete set null,
  message_id uuid references public.insurance_chat_messages(id) on delete set null,
  deep_review_of_message_id uuid references public.insurance_chat_messages(id) on delete set null,
  raw_question text not null,
  interpretation jsonb not null default '{}'::jsonb,
  resolved_entities jsonb not null default '[]'::jsonb,
  generated_search_queries jsonb not null default '[]'::jsonb,
  retrieval_channels jsonb not null default '[]'::jsonb,
  top_candidates jsonb not null default '[]'::jsonb,
  evidence_packet jsonb not null default '[]'::jsonb,
  final_answer text,
  final_citations jsonb not null default '[]'::jsonb,
  validation_checks jsonb not null default '{}'::jsonb,
  provider_usage jsonb not null default '[]'::jsonb,
  latency jsonb not null default '{}'::jsonb,
  feedback_reason text,
  deep_review boolean not null default false,
  answer_status text not null check (answer_status in (
    'grounded', 'grounded_extractive', 'partial', 'clarification_required',
    'conversation', 'insufficient_evidence', 'temporarily_unavailable', 'internal_error'
  )),
  candidate_count integer not null default 0 check (candidate_count >= 0),
  evidence_count integer not null default 0 check (evidence_count >= 0),
  normal_reasoning_calls smallint not null default 0 check (normal_reasoning_calls between 0 and 3),
  created_at timestamptz not null default now()
);

create index insurance_v4_answer_audits_user_created_idx
  on public.insurance_v4_answer_audits (user_id, created_at desc);
create index insurance_v4_answer_audits_message_idx
  on public.insurance_v4_answer_audits (message_id)
  where message_id is not null;
create index insurance_v4_answer_audits_deep_review_idx
  on public.insurance_v4_answer_audits (deep_review_of_message_id, created_at desc)
  where deep_review;

alter table public.insurance_v4_answer_audits enable row level security;

create policy insurance_v4_answer_audits_own_select
  on public.insurance_v4_answer_audits for select to authenticated
  using ((select auth.uid()) = user_id);

create policy insurance_v4_answer_audits_own_insert
  on public.insurance_v4_answer_audits for insert to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on table public.insurance_v4_answer_audits from public, anon;
grant select, insert on table public.insurance_v4_answer_audits to authenticated;
grant all on table public.insurance_v4_answer_audits to service_role;

comment on table public.insurance_v4_answer_audits is
  'V4-only evidence-first request diagnostics. It does not alter or reinterpret V3 audits.';
comment on column public.insurance_v4_answer_audits.evidence_packet is
  'The bounded 3-8 block approved evidence packet actually offered to answer generation.';
comment on column public.insurance_v4_answer_audits.provider_usage is
  'Sanitized Together/Groq call metadata; authorization headers and secrets are forbidden.';

commit;
