-- Stock Statement 2026 rolling archive.
-- Run this once in Supabase SQL Editor.
-- The source table remains untouched; this copies rows that are older than
-- the most recent 29 calendar days, leaving a one-day safety margin before
-- a rolling 30-day source refresh can remove them.

create table if not exists public.stk_statement_history_2026
  (like public.stk_statement including all);

alter table public.stk_statement_history_2026
  add column if not exists archive_fingerprint text;

create unique index if not exists stk_statement_history_2026_fingerprint_uidx
  on public.stk_statement_history_2026 (archive_fingerprint);

create or replace function public.archive_stk_statement_history_2026_range(
  p_from date,
  p_to date
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_column_list text;
  v_select_list text;
  v_inserted integer := 0;
begin
  if p_from > p_to then
    raise exception 'The start date must be on or before the end date';
  end if;

  select
    string_agg(format('%I', column_name), ', ' order by ordinal_position),
    string_agg(format('s.%I', column_name), ', ' order by ordinal_position)
  into v_column_list, v_select_list
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'stk_statement';

  execute format(
    'insert into public.stk_statement_history_2026 (%s, archive_fingerprint)
     select %s, md5(row_to_json(s)::text)
     from public.stk_statement s
     where s.trans_date::date between $1 and $2
     on conflict (archive_fingerprint) do nothing',
    v_column_list,
    v_select_list
  )
  using p_from, p_to;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create or replace function public.archive_stk_statement_history_2026(
  p_today date default (now() at time zone 'Asia/Dubai')::date
)
returns table (inserted_rows integer, archived_through date)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_column_list text;
  v_select_list text;
  v_cutoff date;
  v_inserted integer := 0;
begin
  if p_today < date '2026-01-01' then
    return query select 0, null::date;
    return;
  end if;

  -- A source that keeps 30 days can be refreshed at any time. Archive the
  -- oldest eligible day one day early, so no date can disappear before copy.
  v_cutoff := least(p_today, date '2026-12-31') - 29;

  if v_cutoff < date '2026-01-01' then
    return query select 0, null::date;
    return;
  end if;

  select
    string_agg(format('%I', column_name), ', ' order by ordinal_position),
    string_agg(format('s.%I', column_name), ', ' order by ordinal_position)
  into v_column_list, v_select_list
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'stk_statement';

  if v_column_list is null then
    raise exception 'public.stk_statement was not found';
  end if;

  execute format(
    'insert into public.stk_statement_history_2026 (%s, archive_fingerprint)
     select %s, md5(row_to_json(s)::text)
     from public.stk_statement s
     where s.trans_date::date between $1 and $2
     on conflict (archive_fingerprint) do nothing',
    v_column_list,
    v_select_list
  )
  using date '2026-01-01', v_cutoff;

  get diagnostics v_inserted = row_count;
  return query select v_inserted, v_cutoff;
end;
$$;

-- Initial backfill for all eligible 2026 records currently in stk_statement.
select * from public.archive_stk_statement_history_2026();

-- Manual one-month archive example:
-- select public.archive_stk_statement_history_2026_range(
--   date '2026-07-01', date '2026-07-31'
-- );

-- Optional daily automation. Run this once after enabling the pg_cron
-- extension in Supabase. 20:10 UTC is 00:10 Asia/Dubai.
-- select cron.schedule(
--   'archive-stk-statement-history-2026',
--   '10 20 * * *',
--   $$select public.archive_stk_statement_history_2026();$$
-- );
