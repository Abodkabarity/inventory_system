-- Full statement imports retain all modes, transaction types and document IDs.
alter table public.stk_statement_history_2026
  add column if not exists trans_type text,
  add column if not exists trans_no text;
create index if not exists stk_statement_history_2026_company_date_idx
  on public.stk_statement_history_2026(company,trans_date);
comment on column public.stk_statement_history_2026.trans_no is
  'ERP Trans No as text, preserving leading zeroes and document identity.';
comment on column public.stk_statement_history_2026.archive_fingerprint is
  'Full backfill: company + requested period + source row ordinal + row values; preserves legitimate repeated lines and supports safe retries of a cached file.';
-- No client access is added. These administrative raw facts use service access.
alter table public.stk_statement_history_2026 enable row level security;
create policy stk_statement_history_service_role
  on public.stk_statement_history_2026 for all to service_role
  using (true) with check (true);
grant select,insert on public.stk_statement_history_2026 to service_role;
notify pgrst,'reload schema';
