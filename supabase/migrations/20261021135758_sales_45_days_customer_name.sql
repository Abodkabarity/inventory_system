-- Keep customer identities separate without changing raw branch/item identities.
-- Existing aggregate rows have no recoverable customer name until the next ERP load.
alter table public.sales_last_45_days
    add column customer_name text not null default '';

drop index public.unique_sales;
create unique index unique_sales on public.sales_last_45_days
    (branch_name, item_code, inv_date, sales_type, inv_type, customer_name);

create or replace function public.upsert_sales(p_data jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
    if jsonb_typeof(p_data) is distinct from 'array' then
        raise exception 'Sales payload must be an array';
    end if;
    if jsonb_array_length(p_data) > 5000 then
        raise exception 'Sales batches must contain at most 5000 rows';
    end if;

    insert into public.sales_last_45_days (
        branch_name, item_code, item_name, qty, inv_date,
        sales_type, inv_type, customer_name
    )
    select x.branch_name, x.item_code, x.item_name, x.qty, x.inv_date,
        coalesce(nullif(trim(x.sales_type), ''), 'UNKNOWN'),
        coalesce(nullif(trim(x.inv_type), ''), 'UNKNOWN'),
        coalesce(trim(x.customer_name), '')
    from jsonb_to_recordset(p_data) as x(
        branch_name text, item_code text, item_name text, qty numeric,
        inv_date date, sales_type text, inv_type text, customer_name text
    )
    on conflict (branch_name, item_code, inv_date, sales_type, inv_type, customer_name)
    do update set
        qty = sales_last_45_days.qty + excluded.qty,
        item_name = excluded.item_name;
end;
$function$;

-- This privileged ingestion endpoint is used by the server automation only.
revoke execute on function public.upsert_sales(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_sales(jsonb) to service_role;

notify pgrst, 'reload schema';
