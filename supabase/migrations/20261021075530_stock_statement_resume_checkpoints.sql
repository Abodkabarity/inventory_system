-- Durable import cursor, committed in the same transaction as each 5000 rows.
create table public.stk_statement_history_load_progress (
  company text not null,
  from_date date not null,
  to_date date not null,
  source_file_sha256 text not null check (source_file_sha256 ~ '^[0-9a-f]{64}$'),
  expected_rows bigint not null check (expected_rows>=0),
  committed_rows bigint not null default 0,
  committed_quantity_sum numeric not null default 0,
  complete boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key(company,from_date,to_date),
  check (from_date<=to_date),
  check (committed_rows>=0 and committed_rows<=expected_rows),
  check (not complete or committed_rows=expected_rows)
);
comment on table public.stk_statement_history_load_progress is
  'Server-authoritative resume position for full monthly statement files. Update the cursor atomically with inserted rows; never advance it before COMMIT.';
alter table public.stk_statement_history_load_progress enable row level security;
revoke all on public.stk_statement_history_load_progress from public,anon,authenticated;
grant select,insert,update on public.stk_statement_history_load_progress to service_role;
create policy stk_statement_history_load_progress_service_role
  on public.stk_statement_history_load_progress for all to service_role
  using(true) with check(true);
notify pgrst,'reload schema';
