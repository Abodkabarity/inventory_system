-- Match the Overview client's 5,000-product background batches.
-- Preserve SECURITY INVOKER, existing grants/RLS and the lightweight payload.
create or replace function public.get_stock_catalog_register_batch(
  p_offset integer default 0, p_limit integer default 5000
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'meta' order by item_code)
      from (select item_code,payload from public.stock_catalog_snapshot order by item_code
        limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)) p),'[]'::jsonb),
    'total',(select count(*) from public.stock_catalog_snapshot),
    'snapshot_at',coalesce((select payload->'meta'->>'refreshed_at' from public.stock_catalog_snapshot limit 1),'')
  );
$function$;

notify pgrst, 'reload schema';
