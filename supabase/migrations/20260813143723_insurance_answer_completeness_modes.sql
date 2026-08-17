begin;

alter table public.insurance_answer_audits
  add column if not exists completeness jsonb not null default '{}'::jsonb;

alter table public.insurance_answer_audits
  drop constraint if exists insurance_answer_audits_answer_status_check;

alter table public.insurance_answer_audits
  add constraint insurance_answer_audits_answer_status_check
  check (
    answer_status in (
      'answered',
      'partial',
      'incomplete',
      'insufficient_evidence',
      'clarification_required',
      'conflict'
    )
  );

comment on column public.insurance_answer_audits.completeness is
  'Records expected and retrieved answer cardinality for list and aggregation questions.';

commit;
