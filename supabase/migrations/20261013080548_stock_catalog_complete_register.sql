-- Complete catalog loading for one continuous, virtualized product table.
-- Batches limit network payloads; they are not user-visible pages.
create function public.get_stock_catalog_register_batch(p_offset integer default 0,p_limit integer default 4000)
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload-'branch_stock'-'branch_demand'-'monthly_sales'-'meta' order by item_code)
      from (select item_code,payload from public.stock_catalog_snapshot order by item_code
        limit least(greatest(p_limit,1),4000) offset greatest(p_offset,0)) p),'[]'::jsonb),
    'total',(select count(*) from public.stock_catalog_snapshot),
    'snapshot_at',coalesce((select payload->'meta'->>'refreshed_at' from public.stock_catalog_snapshot limit 1),'')
  );
$$;
revoke all on function public.get_stock_catalog_register_batch(integer,integer) from public,anon;
grant execute on function public.get_stock_catalog_register_batch(integer,integer) to authenticated,service_role;
