begin;

alter table public.insurance_answer_audits
  add column if not exists request_id uuid,
  add column if not exists verified_entities jsonb not null default '[]'::jsonb,
  add column if not exists reranked_evidence jsonb not null default '[]'::jsonb,
  add column if not exists sufficiency_decision jsonb not null default '{}'::jsonb,
  add column if not exists provider_diagnostics jsonb not null default '{}'::jsonb,
  add column if not exists fallback_used text,
  add column if not exists recovery_trace jsonb not null default '{}'::jsonb,
  add column if not exists token_usage jsonb not null default '{}'::jsonb,
  add column if not exists stage_latency jsonb not null default '{}'::jsonb,
  add column if not exists http_status integer not null default 200,
  add column if not exists answer_generator text,
  add column if not exists final_answer text,
  add column if not exists final_citations jsonb not null default '[]'::jsonb,
  add column if not exists recovery_of_audit_id uuid
    references public.insurance_answer_audits(id) on delete set null,
  add column if not exists recovery_attempt smallint not null default 0;

alter table public.insurance_answer_audits
  drop constraint if exists insurance_answer_audits_answer_status_check;

alter table public.insurance_answer_audits
  add constraint insurance_answer_audits_answer_status_check
  check (answer_status in (
    'answered','grounded','grounded_fallback','recovery_grounded',
    'recovery_fallback','partial','incomplete','insufficient_evidence',
    'clarification_required','conflict','temporarily_unavailable','internal_error'
  )),
  add constraint insurance_answer_audits_http_status_check
  check (http_status between 100 and 599),
  add constraint insurance_answer_audits_recovery_attempt_check
  check (recovery_attempt between 0 and 1);

alter table public.insurance_feedback
  add column if not exists reason text,
  add column if not exists second_rating smallint,
  add column if not exists updated_at timestamptz not null default now();

alter table public.insurance_feedback
  add constraint insurance_feedback_reason_check
  check (reason is null or reason in (
    'incorrect','incomplete','misunderstood','wrong_source','other'
  )),
  add constraint insurance_feedback_second_rating_check
  check (second_rating is null or second_rating in (-1, 1));

create unique index if not exists insurance_answer_audits_request_id_idx
  on public.insurance_answer_audits (request_id)
  where request_id is not null;

create index if not exists insurance_answer_audits_recovery_review_idx
  on public.insurance_answer_audits (created_at desc)
  where recovery_attempt = 1 or fallback_used is not null
    or answer_status in ('insufficient_evidence','internal_error','temporarily_unavailable');

create index if not exists insurance_feedback_negative_review_idx
  on public.insurance_feedback (updated_at desc)
  where rating = -1 or second_rating = -1;

comment on column public.insurance_answer_audits.recovery_trace is
  'Bounded, read-only recovery search plans and outcomes. Never an answer-memory store.';
comment on column public.insurance_answer_audits.provider_diagnostics is
  'Sanitized provider/model/call diagnostics. Secrets and authorization headers are forbidden.';

commit;
