create table if not exists public.branch_submission_misses (
  id uuid primary key default gen_random_uuid(),
  run_date date not null,
  branch_name text not null,
  zone text,
  zone_manager text,
  zone_manager_email text,
  area text,
  branch_type text,
  expected_submit_by timestamptz not null,
  submitted_at timestamptz,
  status text not null default 'not_submitted',
  minutes_late integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branch_submission_misses_status_check
    check (status in ('not_submitted', 'late_submitted')),
  constraint branch_submission_misses_unique unique (run_date, branch_name)
);

create index if not exists branch_submission_misses_run_date_idx
  on public.branch_submission_misses (run_date desc);

create index if not exists branch_submission_misses_branch_idx
  on public.branch_submission_misses (branch_name);

create index if not exists branch_submission_misses_status_idx
  on public.branch_submission_misses (status);

create index if not exists branch_submission_misses_zone_idx
  on public.branch_submission_misses (zone);
