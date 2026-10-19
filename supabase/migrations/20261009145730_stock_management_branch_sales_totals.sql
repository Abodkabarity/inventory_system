-- Product details load sales for one item at a time. These expression indexes
-- keep the branch-level totals fast even when imported codes contain spaces.
create index if not exists sales_history_2025_item_branch_month_idx
  on public.sales_history_2025 (btrim(item_code), btrim(branch_name), month);
create index if not exists sales_history_item_branch_month_idx
  on public.sales_history (btrim(item_code), btrim(branch_name), month);

create or replace function public.get_stock_management_item(p_item_code text)
returns jsonb language sql stable security invoker set search_path = ''
as $$
  with sales_2025 as (
    select public._norm_text(h.branch_name) as branch_key,
      sum(coalesce(h.cash, 0) + coalesce(h.insurance, 0) + coalesce(h.online, 0))
        as total_sales
    from public.sales_history_2025 h
    where btrim(h.item_code) = p_item_code
      and h.month ~ '^(0[1-9]|1[0-2])/2025$'
    group by public._norm_text(h.branch_name)
  ),
  sales_2026 as (
    select public._norm_text(h.branch_name) as branch_key,
      sum(coalesce(h.cash, 0) + coalesce(h.insurance, 0) + coalesce(h.online, 0))
        as total_sales
    from public.sales_history h
    where btrim(h.item_code) = p_item_code
      and h.month ~ '^(0[1-9]|1[0-2])/2026$'
    group by public._norm_text(h.branch_name)
  ),
  branch_details as (
    select coalesce(
      jsonb_agg(
        b.branch || jsonb_build_object(
          'sales_2025', coalesce(y25.total_sales, 0),
          'sales_2026', coalesce(y26.total_sales, 0)
        )
        order by coalesce((b.branch->>'stock')::numeric, 0) desc,
          b.branch->>'branch'
      ),
      '[]'::jsonb
    ) as branches
    from public.stock_management_snapshot snapshot
    cross join lateral jsonb_array_elements(snapshot.payload->'branches') b(branch)
    left join sales_2025 y25
      on y25.branch_key = public._norm_text(b.branch->>'branch')
    left join sales_2026 y26
      on y26.branch_key = public._norm_text(b.branch->>'branch')
    where snapshot.item_code = p_item_code
  )
  select snapshot.payload || jsonb_build_object(
    'reference', coalesce((
      select nullif(btrim(m.reference), '')
      from public.mrn_apg_2026 m
      where m.item_code = snapshot.item_code
        and m.mrn_date = snapshot.last_mrn_date
        and coalesce(m.mrn_no, '') = coalesce(snapshot.payload->>'last_mrn_no', '')
        and nullif(btrim(m.reference), '') is not null
      order by m.reference
      limit 1
    ), ''),
    'branches', branch_details.branches
  )
  from public.stock_management_snapshot snapshot
  cross join branch_details
  where snapshot.item_code = p_item_code;
$$;
