alter table if exists public.daily_order_receiving_status
add column if not exists note text;

create or replace function public.refresh_daily_order_receiving_status(p_run_date date)
returns void
language plpgsql
as $function$
begin
    delete from public.daily_order_receiving_status
    where run_date = p_run_date;

    insert into public.daily_order_receiving_status (
        run_date,
        branch,
        item_code,
        item_name,
        reorder_qty,
        final_reorder_qty_store_stock_gt_0,
        transferred_qty,
        remaining_qty,
        status,
        note
    )
    with transfer_summary as (
        select
            to_warehouse as branch,
            item_code,
            sum(qty) as transferred_qty
        from public.transfer
        where from_warehouse = 'STORE'
          and transfer_type = 'Daily Order'
          and transfer_date::date = p_run_date
        group by
            to_warehouse,
            item_code
    ),
    additional_summary as (
        select
            branch_name as branch,
            item_code,
            max(item_name) as item_name,
            sum(coalesce(fulfilled_qty, request_qty, 0)) as additional_qty
        from public.additional_requests
        where status = 'done'
          and run_date = p_run_date
        group by
            branch_name,
            item_code
    ),
    item_names as (
        select
            item_code,
            max(item_name) as item_name
        from public.item_report
        group by item_code
    ),
    daily_rows as (
        select
            r.run_date,
            r.branch,
            r.item_code,
            r.item_name,
            coalesce(r.reorder_qty, 0) as reorder_qty,
            coalesce(r.final_reorder_qty_store_stock_gt_0, 0) as final_reorder_qty_store_stock_gt_0,
            least(
                coalesce(r.reorder_qty, 0),
                coalesce(r.final_reorder_qty_store_stock_gt_0, 0)
            ) as daily_expected_qty,
            coalesce(t.transferred_qty, 0) as transferred_qty,
            coalesce(a.additional_qty, 0) as additional_qty
        from public.refail_order r
        left join transfer_summary t
            on t.branch = r.branch
           and t.item_code = r.item_code
        left join additional_summary a
            on a.branch = r.branch
           and a.item_code = r.item_code
        where r.run_date = p_run_date
    ),
    unexpected_transfer_rows as (
        select
            p_run_date as run_date,
            t.branch,
            t.item_code,
            coalesce(a.item_name, ir.item_name, '') as item_name,
            0::numeric as reorder_qty,
            0::numeric as final_reorder_qty_store_stock_gt_0,
            0::numeric as daily_expected_qty,
            coalesce(t.transferred_qty, 0) as transferred_qty,
            coalesce(a.additional_qty, 0) as additional_qty
        from transfer_summary t
        left join public.refail_order r
            on r.run_date = p_run_date
           and r.branch = t.branch
           and r.item_code = t.item_code
        left join additional_summary a
            on a.branch = t.branch
           and a.item_code = t.item_code
        left join item_names ir
            on ir.item_code = t.item_code
        where r.item_code is null
    ),
    all_rows as (
        select * from daily_rows
        union all
        select * from unexpected_transfer_rows
    )
    select
        x.run_date,
        x.branch,
        x.item_code,
        x.item_name,
        x.reorder_qty,
        x.final_reorder_qty_store_stock_gt_0,
        x.transferred_qty,
        greatest(
            (x.daily_expected_qty + x.additional_qty) - x.transferred_qty,
            0
        ) as remaining_qty,
        case
            when x.transferred_qty > (x.daily_expected_qty + x.additional_qty)
            then 'EXTRA_TRANSFER'

            when x.reorder_qty = 0
             and x.final_reorder_qty_store_stock_gt_0 = 0
             and x.transferred_qty > 0
             and x.additional_qty > 0
            then 'COMPLETED'

            when x.final_reorder_qty_store_stock_gt_0 = 0
            then 'OUT_OF_STOCK'

            when x.final_reorder_qty_store_stock_gt_0 < x.reorder_qty
             and x.transferred_qty >= x.final_reorder_qty_store_stock_gt_0
            then 'PARTIAL_STOCK'

            when x.final_reorder_qty_store_stock_gt_0 >= x.reorder_qty
             and x.transferred_qty >= x.reorder_qty
            then 'COMPLETED'

            when x.transferred_qty = 0
            then 'NOT_TRANSFERRED'

            when x.transferred_qty < x.final_reorder_qty_store_stock_gt_0
            then 'PARTIAL_TRANSFER'

            else 'UNKNOWN'
        end as status,
        case
            when x.additional_qty > 0
             and x.transferred_qty > x.daily_expected_qty
             and x.transferred_qty <= (x.daily_expected_qty + x.additional_qty)
            then concat(
                'Additional request covered extra transfer. Additional qty: ',
                x.additional_qty,
                ', daily expected qty: ',
                x.daily_expected_qty,
                ', transferred qty: ',
                x.transferred_qty,
                '.'
            )

            when x.transferred_qty > (x.daily_expected_qty + x.additional_qty)
             and x.additional_qty > 0
            then concat(
                'Unexpected extra transfer. Transferred qty exceeds Daily Order + Additional Request. Daily expected qty: ',
                x.daily_expected_qty,
                ', additional qty: ',
                x.additional_qty,
                ', transferred qty: ',
                x.transferred_qty,
                '.'
            )

            when x.transferred_qty > (x.daily_expected_qty + x.additional_qty)
             and x.additional_qty = 0
            then concat(
                'Unexpected extra transfer. No matching done additional request found. Daily expected qty: ',
                x.daily_expected_qty,
                ', transferred qty: ',
                x.transferred_qty,
                '.'
            )

            else null
        end as note
    from all_rows x;
end;
$function$;
