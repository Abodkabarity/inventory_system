-- Use the same canonical version as register batches, including metadata-only updates.
-- Preserve refreshed_at for older clients that still use it as the snapshot version.
CREATE OR REPLACE FUNCTION public.get_stock_management_page(p_search text DEFAULT ''::text, p_status text DEFAULT ''::text, p_category text DEFAULT ''::text, p_supplier text DEFAULT ''::text, p_received_from date DEFAULT NULL::date, p_received_to date DEFAULT NULL::date, p_sort text DEFAULT 'latest_mrn'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with filtered as materialized (
    select * from public.stock_management_snapshot s
    where (coalesce(p_search,'')='' or strpos(lower(s.item_code||' '||s.item_name||' '||s.supplier||' '||s.company),lower(btrim(p_search)))>0)
      and (coalesce(p_status,'')='' or s.stock_status=p_status)
      and (coalesce(p_category,'')='' or s.category=p_category)
      and (coalesce(p_supplier,'')='' or s.supplier=p_supplier)
      and (p_received_from is null or s.last_mrn_date>=p_received_from)
      and (p_received_to is null or s.last_mrn_date<=p_received_to)
  ), paged as (
    select * from filtered order by
      case when p_sort='stock_high' then total_stock end desc nulls last,
      case when p_sort='sales_high' then sales_2026 end desc nulls last,
      case when p_sort='days_low' then days_on_hand end asc nulls last,
      last_mrn_date desc,item_code
    limit least(greatest(p_limit,1),100) offset greatest(p_offset,0)
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload - 'branches' - 'monthly_sales' - 'meta') from paged),'[]'::jsonb),
    'summary',(select jsonb_build_object('items',count(*),
      'no_stock',count(*) filter (where stock_status='no_stock'),
      'low_cover',count(*) filter (where stock_status='low_cover'),
      'no_sales',count(*) filter (where stock_status='no_sales'),
      'total_stock',coalesce(sum(total_stock),0)) from filtered),
    'meta',coalesce((select payload->'meta' from public.stock_management_snapshot limit 1),'{}'::jsonb)
      || (select jsonb_build_object('snapshot_at',max(updated_at),'refreshed_at',max(updated_at))
          from public.stock_management_snapshot),
    'categories',coalesce((select jsonb_agg(category order by category) from
      (select distinct category from public.stock_management_snapshot where category<>'') c),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(supplier order by supplier) from
      (select distinct supplier from public.stock_management_snapshot where supplier<>'') c),'[]'::jsonb)
  );
$function$
;

NOTIFY pgrst, 'reload schema';
