create table public.sales_history_2025 (
  branch_name text,
  item_code text,
  item_name text,
  month text,
  cash numeric,
  online numeric,
  insurance numeric,
  created_at timestamptz default now(),
  total_sales numeric generated always as
  (
    coalesce(cash, 0)
    + coalesce(online, 0)
    + coalesce(insurance, 0)
  ) stored,
  retail numeric,
  sales_value numeric generated always as
  (
    (
      coalesce(cash, 0)
      + coalesce(online, 0)
      + coalesce(insurance, 0)
    ) * coalesce(retail, 0)
  ) stored
);

create index sales_history_2025_branch_item_month_idx
  on public.sales_history_2025 (branch_name, item_code, month);

alter table public.sales_history_2025 enable row level security;

grant select on public.sales_history_2025 to authenticated;

create policy "sales_history_2025_read_authorized"
on public.sales_history_2025
for select
to authenticated
using ((select public.item_tracker_my_role()) in ('inventory', 'purchase', 'category'));
