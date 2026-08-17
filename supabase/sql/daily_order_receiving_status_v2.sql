-- Daily Order receiving exceptions, version 2.
--
-- The classification identifies the operational cause of each exception:
--   * Non Recived: inventory shortage or an available order not transferred.
--   * Store Supply: unplanned/excess transfers or preparation shortages.
-- Only Additional Requests whose workflow status is `done` are included.

alter table public.daily_order_receiving_status
  add column if not exists additional_qty numeric not null default 0;

alter table public.daily_order_receiving_status
  add column if not exists store_stock numeric;

alter table public.daily_order_receiving_status
  add column if not exists transfer_types text;

alter table public.daily_order_receiving_status
  add column if not exists branch_edited boolean not null default false;

comment on column public.daily_order_receiving_status.additional_qty is
  'Total request_qty from done Additional Requests for the same order date, branch, and item.';

comment on column public.daily_order_receiving_status.store_stock is
  'Store stock preserved in refail_order for the same date, branch, and item.';

comment on column public.daily_order_receiving_status.transfer_types is
  'Comma-separated distinct transfer_type values found for the same date, destination branch, and item.';

comment on column public.daily_order_receiving_status.branch_edited is
  'True when a finalized order_edits row exists for the same date, branch, and item.';

create or replace function public.refresh_daily_order_receiving_status(
  p_run_date date
)
returns void
language plpgsql
as $function$
begin
  if p_run_date is null then
    raise exception 'p_run_date is required';
  end if;

  delete from public.daily_order_receiving_status
  where run_date = p_run_date;

  insert into public.daily_order_receiving_status (
    run_date,
    branch,
    item_code,
    item_name,
    reorder_qty,
    final_reorder_qty_store_stock_gt_0,
    additional_qty,
    store_stock,
    transferred_qty,
    transfer_types,
    branch_edited,
    remaining_qty,
    status,
    note
  )
  with eligible_branches as (
    select distinct btrim(branch_name) as branch
    from public.branches
    where is_active = true
      and to_char(p_run_date, 'FMDay') = any(order_days)
  ),
  transfer_summary as (
    select
      eb.branch,
      btrim(t.item_code) as item_code,
      max(nullif(btrim(t.item_name), '')) as item_name,
      sum(coalesce(t.qty, 0)) as transferred_qty,
      string_agg(
        distinct nullif(btrim(t.transfer_type), ''),
        ', '
        order by nullif(btrim(t.transfer_type), '')
      ) as transfer_types
    from public.transfer t
    join eligible_branches eb
      on upper(eb.branch) = upper(btrim(t.to_warehouse))
    where t.from_warehouse = 'STORE'
      and t.transfer_date::date = p_run_date
    group by eb.branch, btrim(t.item_code)
  ),
  additional_summary as (
    select
      eb.branch,
      btrim(a.item_code) as item_code,
      max(nullif(btrim(a.item_name), '')) as item_name,
      sum(coalesce(a.request_qty, 0)) as additional_qty
    from public.additional_requests a
    join eligible_branches eb
      on upper(eb.branch) = upper(btrim(a.branch_name))
    where a.status = 'done'
      and a.run_date = p_run_date
    group by eb.branch, btrim(a.item_code)
  ),
  edit_summary as (
    select distinct
      eb.branch,
      btrim(e.item_code) as item_code,
      true as branch_edited
    from public.order_edits e
    join eligible_branches eb
      on upper(eb.branch) = upper(btrim(e.branch_name))
    where e.run_date = p_run_date
  ),
  item_names as (
    select
      btrim(item_code) as item_code,
      max(nullif(btrim(item_name), '')) as item_name
    from public.item_report
    where nullif(btrim(item_code), '') is not null
    group by btrim(item_code)
  ),
  daily_rows as (
    select
      r.run_date,
      eb.branch,
      btrim(r.item_code) as item_code,
      coalesce(nullif(btrim(r.item_name), ''), i.item_name, '') as item_name,
      coalesce(r.store_stock, 0) as store_stock,
      coalesce(r.reorder_qty, 0) as reorder_qty,
      coalesce(r.final_reorder_qty_store_stock_gt_0, 0) as daily_order_qty,
      coalesce(a.additional_qty, 0) as additional_qty,
      coalesce(t.transferred_qty, 0) as transferred_qty,
      coalesce(t.transfer_types, '') as transfer_types,
      coalesce(e.branch_edited, false) as branch_edited
    from public.refail_order r
    join eligible_branches eb
      on upper(eb.branch) = upper(btrim(r.branch))
    left join transfer_summary t
      on t.branch = eb.branch
     and t.item_code = btrim(r.item_code)
    left join additional_summary a
      on a.branch = eb.branch
     and a.item_code = btrim(r.item_code)
    left join edit_summary e
      on e.branch = eb.branch
     and e.item_code = btrim(r.item_code)
    left join item_names i
      on i.item_code = btrim(r.item_code)
    where r.run_date = p_run_date
  ),
  transfer_only_rows as (
    select
      p_run_date as run_date,
      t.branch,
      t.item_code,
      coalesce(a.item_name, t.item_name, i.item_name, '') as item_name,
      null::numeric as store_stock,
      0::numeric as reorder_qty,
      0::numeric as daily_order_qty,
      coalesce(a.additional_qty, 0) as additional_qty,
      coalesce(t.transferred_qty, 0) as transferred_qty,
      coalesce(t.transfer_types, '') as transfer_types,
      coalesce(e.branch_edited, false) as branch_edited
    from transfer_summary t
    left join public.refail_order r
      on r.run_date = p_run_date
     and btrim(r.branch) = t.branch
     and btrim(r.item_code) = t.item_code
    left join additional_summary a
      on a.branch = t.branch
     and a.item_code = t.item_code
    left join edit_summary e
      on e.branch = t.branch
     and e.item_code = t.item_code
    left join item_names i
      on i.item_code = t.item_code
    where r.item_code is null
  ),
  additional_only_rows as (
    -- A done Additional Request with no Daily Order and no transfer must not
    -- disappear: it is an unfulfilled Store Supply exception.
    select
      p_run_date as run_date,
      a.branch,
      a.item_code,
      coalesce(a.item_name, i.item_name, '') as item_name,
      null::numeric as store_stock,
      0::numeric as reorder_qty,
      0::numeric as daily_order_qty,
      a.additional_qty,
      0::numeric as transferred_qty,
      ''::text as transfer_types,
      coalesce(e.branch_edited, false) as branch_edited
    from additional_summary a
    left join public.refail_order r
      on r.run_date = p_run_date
     and btrim(r.branch) = a.branch
     and btrim(r.item_code) = a.item_code
    left join transfer_summary t
      on t.branch = a.branch
     and t.item_code = a.item_code
    left join edit_summary e
      on e.branch = a.branch
     and e.item_code = a.item_code
    left join item_names i
      on i.item_code = a.item_code
    where r.item_code is null
      and t.item_code is null
  ),
  all_rows as (
    select * from daily_rows
    union all
    select * from transfer_only_rows
    union all
    select * from additional_only_rows
  ),
  prepared as (
    select
      x.*,
      case
        when x.branch_edited then x.daily_order_qty
        else x.reorder_qty
      end as comparison_qty
    from all_rows x
  ),
  classified as (
    select
      x.*,
      case
        -- This is more specific than EXTRA_MORE_THAN_ORDER and must come first.
        when x.transferred_qty > 0
         and x.comparison_qty = 0
         and x.additional_qty = 0
        then 'EXTRA_NOT_IN_ORDER'

        -- A finalized branch edit makes Daily Order the approved reference.
        -- Without an edit, the original Reorder remains the reference.
        when x.transferred_qty > (x.comparison_qty + x.additional_qty)
        then 'EXTRA_MORE_THAN_ORDER'

        when x.transferred_qty >= (x.comparison_qty + x.additional_qty)
        then 'COMPLETED'

        -- The original reorder was fully supplied, but a done Additional
        -- Request still has an outstanding quantity.
        when x.additional_qty > 0
         and x.transferred_qty >= x.comparison_qty
         and x.transferred_qty < (x.comparison_qty + x.additional_qty)
        then 'LESS_ADDITIONAL_REQUEST'

        -- The Daily Order was reduced below the original reorder because the
        -- Store did not have enough stock. This remains the primary cause even
        -- if the available quantity was transferred.
        when not x.branch_edited
         and x.reorder_qty > x.daily_order_qty
        then 'STORE_OUT_OF_STOCK'

        -- A low Store balance is treated as an inventory shortage even when
        -- the Daily Order retained the requested quantity. The business
        -- threshold is inclusive: Store Stock 10 is still Out Of Stock.
        when x.comparison_qty > 0
         and x.transferred_qty = 0
         and x.store_stock <= 10
        then 'STORE_OUT_OF_STOCK'

        -- Full quantity was available in the Daily Order, Store Stock is
        -- above the shortage threshold, but nothing moved.
        when x.comparison_qty > 0
         and x.transferred_qty = 0
        then 'AVAILABLE_NOT_TRANSFERRED'

        -- Store had the full Daily Order but prepared only part of it.
        when x.comparison_qty > 0
         and x.transferred_qty > 0
         and x.transferred_qty < x.comparison_qty
        then 'LESS_STORE_PREPARATION_ERROR'

        else 'COMPLETED'
      end as calculated_status
    from prepared x
  )
  select
    c.run_date,
    c.branch,
    c.item_code,
    c.item_name,
    c.reorder_qty,
    c.daily_order_qty,
    c.additional_qty,
    c.store_stock,
    c.transferred_qty,
    nullif(c.transfer_types, '') as transfer_types,
    c.branch_edited,
    greatest(
      (c.comparison_qty + c.additional_qty) - c.transferred_qty,
      0
    ) as remaining_qty,
    c.calculated_status,
    case c.calculated_status
      when 'STORE_OUT_OF_STOCK' then concat(
        'Store stock shortage: reorder ', c.reorder_qty,
        ', Daily Order ', c.daily_order_qty,
        ', transferred ', c.transferred_qty, '.'
      )
      when 'AVAILABLE_NOT_TRANSFERRED' then
        'Available at Store, but no quantity was transferred.'
      when 'EXTRA_NOT_IN_ORDER' then
        'Transferred without a Daily Order or done Additional Request.'
      when 'EXTRA_MORE_THAN_ORDER' then concat(
        'Transferred quantity exceeds ',
        case when c.branch_edited then 'branch-edited Daily Order' else 'Reorder' end,
        ' + Additional Request (', c.comparison_qty, ' + ',
        c.additional_qty, ').'
      )
      when 'LESS_STORE_PREPARATION_ERROR' then concat(
        'Store preparation shortage: Daily Order ', c.daily_order_qty,
        ', transferred ', c.transferred_qty, '.'
      )
      when 'LESS_ADDITIONAL_REQUEST' then concat(
        'Done Additional Request was not fully supplied. Additional qty ',
        c.additional_qty, ', transferred total ', c.transferred_qty, '.'
      )
      else null
    end as note
  from classified c;
end;
$function$;

create index if not exists daily_order_receiving_status_run_status_branch_idx
  on public.daily_order_receiving_status (run_date desc, status, branch);
