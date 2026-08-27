begin;

create table if not exists public.insurance_validated_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  semantic_signature text not null,
  normalized_question text not null,
  original_question text not null,
  semantic_interpretation jsonb not null,
  verified_entity_ids uuid[] not null default '{}'::uuid[],
  intent_signature jsonb not null,
  answer_text text not null,
  citations jsonb not null,
  evidence_ids uuid[] not null default '{}'::uuid[],
  document_snapshots jsonb not null,
  relation_snapshot jsonb not null default '[]'::jsonb,
  preferred_source text not null check (preferred_source in ('normal', 'deep_review')),
  source_message_id uuid references public.insurance_chat_messages(id) on delete set null,
  source_audit_id uuid references public.insurance_answer_audits(id) on delete set null,
  provider_metadata jsonb not null default '{}'::jsonb,
  source_latency_ms integer check (source_latency_ms is null or source_latency_ms >= 0),
  positive_feedback_at timestamptz not null default now(),
  active boolean not null default true,
  invalidated_at timestamptz,
  invalidation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, semantic_signature),
  check (jsonb_typeof(citations) = 'array'),
  check (jsonb_typeof(document_snapshots) = 'array'),
  check (jsonb_typeof(relation_snapshot) = 'array')
);

create index if not exists insurance_validated_answers_active_lookup_idx
  on public.insurance_validated_answers (user_id, semantic_signature)
  where active = true;

alter table public.insurance_validated_answers enable row level security;

create policy insurance_validated_answers_own_read
on public.insurance_validated_answers for select to authenticated
using ((select auth.uid()) = user_id);

create policy insurance_validated_answers_own_insert
on public.insurance_validated_answers for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy insurance_validated_answers_own_update
on public.insurance_validated_answers for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy insurance_validated_answers_admin_all
on public.insurance_validated_answers for all to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());

grant select, insert, update on public.insurance_validated_answers to authenticated;
grant all on public.insurance_validated_answers to service_role;

comment on table public.insurance_validated_answers is
  'Per-user preferred grounded responses. Approved V3 documents remain authoritative; rows are reusable only after runtime source validation.';

alter table public.insurance_answer_audits
  drop constraint if exists insurance_answer_audits_answer_status_check;

alter table public.insurance_answer_audits
  add constraint insurance_answer_audits_answer_status_check
  check (answer_status in (
    'answered','grounded','grounded_fallback','recovery_grounded',
    'recovery_fallback','validated_cache_hit','partial','incomplete',
    'insufficient_evidence','clarification_required','conflict',
    'temporarily_unavailable','internal_error'
  ));

commit;
