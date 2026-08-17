-- Fill Rate KPI (read-only reporting functions)
-- Expected quantity = order_edits.new_qty when an edit exists, otherwise
-- refail_order.reorder_qty. Zero/negative expected quantities are excluded.

begin;

create index if not exists refail_order_fill_rate_lookup_idx
  on public.refail_order (run_date, branch, item_code);

create index if not exists refail_order_fill_rate_normalized_idx
  on public.refail_order (run_date, btrim(branch), btrim(item_code));

create index if not exists order_edits_fill_rate_normalized_idx
  on public.order_edits (run_date, btrim(branch_name), btrim(item_code));

create index if not exists transfer_fill_rate_lookup_idx
  on public.transfer (transfer_date, from_warehouse, status, to_warehouse, item_code);

create index if not exists transfer_fill_rate_normalized_idx
  on public.transfer (
    transfer_date,
    upper(btrim(coalesce(from_warehouse, ''))),
    upper(btrim(coalesce(status, ''))),
    btrim(to_warehouse),
    btrim(item_code)
  );

create index if not exists purchase_status_fill_rate_normalized_idx
  on public.purchase_status_items (btrim(item_code));

create or replace function public.fill_rate_base_v1(
  p_date_from date,
  p_date_to date,
  p_branch text default null
)
returns table (
  run_date date,
  branch_name text,
  item_code text,
  item_name text,
  original_qty numeric,
  required_qty numeric,
  was_edited boolean,
  transferred_qty numeric,
  supplied_qty numeric,
  fill_rate numeric,
  fulfillment_status text,
  purchase_status text
)
language sql
stable
security invoker
set search_path = public
as $$
  with expected as (
    select
      r.run_date,
      btrim(r.branch) as branch_name,
      btrim(r.item_code) as item_code,
      r.item_name,
      coalesce(r.reorder_qty, 0)::numeric as original_qty,
      coalesce(e.new_qty::numeric, r.reorder_qty, 0)::numeric as required_qty,
      (e.id is not null) as was_edited
    from public.refail_order r
    left join public.order_edits e
      on e.run_date = r.run_date
     and btrim(e.branch_name) = btrim(r.branch)
     and btrim(e.item_code) = btrim(r.item_code)
    where r.run_date between p_date_from and p_date_to
      and (p_branch is null or btrim(r.branch) = btrim(p_branch))
      and coalesce(e.new_qty::numeric, r.reorder_qty, 0) > 0
  ),
  transferred as (
    select
      t.transfer_date,
      btrim(t.to_warehouse) as branch_name,
      btrim(t.item_code) as item_code,
      sum(greatest(coalesce(t.qty, 0), 0))::numeric as transferred_qty
    from public.transfer t
    where t.transfer_date between p_date_from and p_date_to
      and upper(btrim(coalesce(t.from_warehouse, ''))) = 'STORE'
      and upper(btrim(coalesce(t.status, ''))) = 'APPROVED'
      and (p_branch is null or btrim(t.to_warehouse) = btrim(p_branch))
    group by t.transfer_date, btrim(t.to_warehouse), btrim(t.item_code)
  )
  select
    x.run_date,
    x.branch_name,
    x.item_code,
    x.item_name,
    x.original_qty,
    x.required_qty,
    x.was_edited,
    coalesce(t.transferred_qty, 0)::numeric as transferred_qty,
    least(x.required_qty, coalesce(t.transferred_qty, 0))::numeric as supplied_qty,
    round(least(100::numeric, 100 * coalesce(t.transferred_qty, 0) / x.required_qty), 2) as fill_rate,
    case
      when coalesce(t.transferred_qty, 0) <= 0 then 'Not Supplied'
      when t.transferred_qty < x.required_qty then 'Partially Supplied'
      else 'Fully Supplied'
    end as fulfillment_status,
    coalesce(nullif(btrim(ps.status_name), ''), 'Not Assigned') as purchase_status
  from expected x
  left join transferred t
    on t.transfer_date = x.run_date
   and t.branch_name = x.branch_name
   and t.item_code = x.item_code
  -- This canonical view is the RLS-safe purchase-status source already used
  -- by Availability KPI and exposed to authenticated dashboard users.
  left join public.availability_kpi_purchase_status ps
    on ps.item_code = x.item_code;
$$;

create or replace function public.get_fill_rate_summary_v1(
  p_date_from date,
  p_date_to date,
  p_branch text default null
)
returns table (
  branch_name text,
  total_items bigint,
  supplied_items bigint,
  fully_supplied bigint,
  partially_supplied bigint,
  not_supplied bigint,
  required_qty numeric,
  supplied_qty numeric,
  line_fill_rate numeric,
  unit_fill_rate numeric
)
language sql stable security invoker set search_path = public
as $$
  with base as (select * from public.fill_rate_base_v1(p_date_from, p_date_to, p_branch))
  select
    case when grouping(branch_name) = 1 then 'ALL BRANCHES' else branch_name end,
    count(*)::bigint,
    count(*) filter (where transferred_qty > 0)::bigint,
    count(*) filter (where fulfillment_status = 'Fully Supplied')::bigint,
    count(*) filter (where fulfillment_status = 'Partially Supplied')::bigint,
    count(*) filter (where fulfillment_status = 'Not Supplied')::bigint,
    coalesce(sum(required_qty), 0)::numeric,
    coalesce(sum(supplied_qty), 0)::numeric,
    coalesce(round(avg(fill_rate), 2), 0)::numeric,
    coalesce(round(100 * sum(supplied_qty) / nullif(sum(required_qty), 0), 2), 0)::numeric
  from base
  group by grouping sets ((branch_name), ())
  order by grouping(branch_name) desc, branch_name;
$$;

create or replace function public.get_fill_rate_daily_v1(
  p_date_from date,
  p_date_to date,
  p_branch text default null
)
returns table (
  run_date date,
  total_items bigint,
  supplied_items bigint,
  fully_supplied bigint,
  partially_supplied bigint,
  not_supplied bigint,
  line_fill_rate numeric,
  unit_fill_rate numeric
)
language sql stable security invoker set search_path = public
as $$
  select run_date, count(*)::bigint,
    count(*) filter (where transferred_qty > 0)::bigint,
    count(*) filter (where fulfillment_status = 'Fully Supplied')::bigint,
    count(*) filter (where fulfillment_status = 'Partially Supplied')::bigint,
    count(*) filter (where fulfillment_status = 'Not Supplied')::bigint,
    coalesce(round(avg(fill_rate), 2), 0)::numeric,
    coalesce(round(100 * sum(supplied_qty) / nullif(sum(required_qty), 0), 2), 0)::numeric
  from public.fill_rate_base_v1(p_date_from, p_date_to, p_branch)
  group by run_date order by run_date;
$$;

create or replace function public.get_fill_rate_status_v1(
  p_date_from date,
  p_date_to date,
  p_branch text default null
)
returns table (
  purchase_status text,
  total_items bigint,
  supplied_items bigint,
  status_share numeric,
  line_fill_rate numeric,
  unit_fill_rate numeric
)
language sql stable security invoker set search_path = public
as $$
  with base as (select * from public.fill_rate_base_v1(p_date_from, p_date_to, p_branch))
  select purchase_status, count(*)::bigint,
    count(*) filter (where transferred_qty > 0)::bigint,
    round(100 * count(*) / nullif(sum(count(*)) over (), 0), 2)::numeric,
    round(avg(fill_rate), 2)::numeric,
    coalesce(round(100 * sum(supplied_qty) / nullif(sum(required_qty), 0), 2), 0)::numeric
  from base group by purchase_status order by count(*) desc, purchase_status;
$$;

create or replace function public.get_fill_rate_items_v1(
  p_date_from date,
  p_date_to date,
  p_branch text default null,
  p_offset integer default 0,
  p_limit integer default 1000
)
returns table (
  total_count bigint,
  run_date date,
  branch_name text,
  item_code text,
  item_name text,
  original_qty numeric,
  required_qty numeric,
  was_edited boolean,
  transferred_qty numeric,
  supplied_qty numeric,
  fill_rate numeric,
  fulfillment_status text,
  purchase_status text
)
language sql stable security invoker set search_path = public
as $$
  select count(*) over (), b.*
  from public.fill_rate_base_v1(p_date_from, p_date_to, p_branch) b
  order by b.run_date desc, b.branch_name, b.fulfillment_status desc, b.item_code
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 1000), 1), 5000);
$$;

-- One-call dashboard payload. The materialized base is calculated once and
-- reused by every summary, avoiding four concurrent scans on page load.
create or replace function public.get_fill_rate_report_v1(
  p_date_from date,
  p_date_to date,
  p_branch text default null,
  p_detail_limit integer default 1000
)
returns jsonb
language sql stable security invoker set search_path = public
as $$
  with base as materialized (
    select * from public.fill_rate_base_v1(p_date_from, p_date_to, p_branch)
  ),
  summaries as (
    select
      case when grouping(branch_name) = 1 then 'ALL BRANCHES' else branch_name end as branch_name,
      count(*)::bigint as total_items,
      count(*) filter (where transferred_qty > 0)::bigint as supplied_items,
      count(*) filter (where fulfillment_status = 'Fully Supplied')::bigint as fully_supplied,
      count(*) filter (where fulfillment_status = 'Partially Supplied')::bigint as partially_supplied,
      count(*) filter (where fulfillment_status = 'Not Supplied')::bigint as not_supplied,
      coalesce(sum(required_qty), 0)::numeric as required_qty,
      coalesce(sum(supplied_qty), 0)::numeric as supplied_qty,
      coalesce(round(avg(fill_rate), 2), 0)::numeric as line_fill_rate,
      coalesce(round(100 * sum(supplied_qty) / nullif(sum(required_qty), 0), 2), 0)::numeric as unit_fill_rate,
      grouping(branch_name) as sort_group
    from base group by grouping sets ((branch_name), ())
  ),
  daily as (
    select run_date, count(*)::bigint as total_items,
      count(*) filter (where transferred_qty > 0)::bigint as supplied_items,
      count(*) filter (where fulfillment_status = 'Fully Supplied')::bigint as fully_supplied,
      count(*) filter (where fulfillment_status = 'Partially Supplied')::bigint as partially_supplied,
      count(*) filter (where fulfillment_status = 'Not Supplied')::bigint as not_supplied,
      coalesce(round(avg(fill_rate), 2), 0)::numeric as line_fill_rate,
      coalesce(round(100 * sum(supplied_qty) / nullif(sum(required_qty), 0), 2), 0)::numeric as unit_fill_rate
    from base group by run_date
  ),
  statuses as (
    select purchase_status, count(*)::bigint as total_items,
      count(*) filter (where transferred_qty > 0)::bigint as supplied_items,
      coalesce(sum(required_qty), 0)::numeric as required_qty,
      coalesce(sum(supplied_qty), 0)::numeric as supplied_qty,
      round(100 * count(*) / nullif(sum(count(*)) over (), 0), 2)::numeric as status_share,
      round(avg(fill_rate), 2)::numeric as line_fill_rate,
      coalesce(round(100 * sum(supplied_qty) / nullif(sum(required_qty), 0), 2), 0)::numeric as unit_fill_rate
    from base group by purchase_status
  ),
  details as (
    select (select count(*) from base)::bigint as total_count, b.*
    from base b
    order by b.run_date desc, b.branch_name, b.fulfillment_status desc, b.item_code
    limit least(greatest(coalesce(p_detail_limit, 1000), 1), 5000)
  )
  select jsonb_build_object(
    'summaries', coalesce((select jsonb_agg(to_jsonb(s) - 'sort_group' order by s.sort_group desc, s.branch_name) from summaries s), '[]'::jsonb),
    'daily', coalesce((select jsonb_agg(to_jsonb(d) order by d.run_date) from daily d), '[]'::jsonb),
    'statuses', coalesce((select jsonb_agg(to_jsonb(s) order by s.total_items desc, s.purchase_status) from statuses s), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(to_jsonb(i)) from details i), '[]'::jsonb)
  );
$$;

grant execute on function public.fill_rate_base_v1(date,date,text) to authenticated;
grant execute on function public.get_fill_rate_summary_v1(date,date,text) to authenticated;
grant execute on function public.get_fill_rate_daily_v1(date,date,text) to authenticated;
grant execute on function public.get_fill_rate_status_v1(date,date,text) to authenticated;
grant execute on function public.get_fill_rate_items_v1(date,date,text,integer,integer) to authenticated;
grant execute on function public.get_fill_rate_report_v1(date,date,text,integer) to authenticated;

commit;
