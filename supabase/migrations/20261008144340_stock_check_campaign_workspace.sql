-- Additive metadata keeps the branch counting and submission contract intact.
alter table public.stock_check_tasks
  add column if not exists check_kind text not null default 'regular'
    check (check_kind in ('regular', 'kpi')),
  add column if not exists team_name text not null default '',
  add column if not exists owner_name text not null default '',
  add column if not exists kpi_year integer,
  add column if not exists kpi_quarter integer;

alter table public.stock_check_tasks add constraint stock_check_kpi_period_valid
  check ((check_kind = 'regular' and kpi_year is null and kpi_quarter is null)
    or (check_kind = 'kpi' and kpi_year is not null and kpi_year between 2000 and 2200
      and kpi_quarter is not null and kpi_quarter between 1 and 4));

create index if not exists idx_stock_check_tasks_batch_id_id
  on public.stock_check_tasks(batch_id, id);

-- Invoker permissions preserve the existing table access rules.
create or replace view public.stock_check_campaigns
with (security_invoker = true) as
select batch_id, source, min(title) as title,
  min(check_kind) as check_kind, min(team_name) as team_name,
  min(owner_name) as owner_name, min(kpi_year) as kpi_year,
  min(kpi_quarter) as kpi_quarter,
  min(sent_at) as sent_at, min(expires_at) as expires_at,
  count(*) as total,
  count(*) filter (where lower(trim(status)) = 'submitted') as submitted,
  count(distinct branch_name) as branches,
  count(distinct item_code) as products,
  count(*) filter (where lower(trim(status)) = 'submitted' and system_qty is not null and actual_qty is not null) as counted,
  count(*) filter (where lower(trim(status)) = 'submitted' and system_qty is not null and actual_qty is not null
    and abs(actual_qty - system_qty) <= 0.010000001) as correct
from public.stock_check_tasks
group by batch_id, source;

grant select on public.stock_check_campaigns to anon, authenticated;
comment on view public.stock_check_campaigns is
  'Stock Check workspace summaries; details are fetched only for selected campaigns. Legacy campaigns stay regular/unassigned until explicitly classified.';
