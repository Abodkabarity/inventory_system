-- Published definitions captured before the single-serialization rewrite.
-- Test/rollback reference only; this file is never applied as a migration.
CREATE OR REPLACE FUNCTION public.get_stock_management_register_batch(p_offset integer DEFAULT 0, p_limit integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET enable_nestloop TO 'off'
AS $function$with wrapped(value) as materialized (
 with page as materialized (
    select item_code,last_mrn_date,payload from public.stock_management_snapshot
    order by last_mrn_date desc,item_code
    limit least(greatest(coalesce(p_limit,5000),1),5000) offset greatest(coalesce(p_offset,0),0)
  ), receipts as materialized (
    select p.item_code,min(m.expiry_date) filter(where coalesce(m.total_qty,0)>0) expiry_date,
      sum(coalesce(m.ordered_quantity,0)) ordered_quantity,
      sum(coalesce(m.total_qty,0)) received_quantity,
      min(nullif(btrim(m.vendor),'')) vendor,
      count(distinct coalesce(m.mrn_no,'')) receipt_count,
      count(distinct m.expiry_date) filter(where coalesce(m.total_qty,0)>0) expiry_count
    from page p join public.mrn_apg_2026 m
      on btrim(m.item_code)=p.item_code and m.mrn_date=p.last_mrn_date
    where lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
    group by p.item_code
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(
      (p.payload-'branches'-'monthly_sales'-'meta'-'branch_year_sales'-'receipt_lines') ||
      jsonb_build_object('receipt_scope','latest_mrn_date',
        'receipt_count',r.receipt_count,'expiry_count',r.expiry_count,
        'vendor',left(upper(r.vendor),10),'expiry_date',r.expiry_date,
        'ordered_quantity',r.ordered_quantity,'received_quantity',r.received_quantity,
        'last_mrn_qty',coalesce(r.received_quantity,(p.payload->>'last_mrn_qty')::numeric))
      ||jsonb_build_object('supply_insight',coalesce(i.summary,
        '{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
        ||jsonb_build_object('generated_at',i.updated_at))
      order by p.last_mrn_date desc,p.item_code)
      from page p left join receipts r using(item_code)
      left join public.stock_supply_insights i using(item_code)),'[]'::jsonb),
    'total',(select count(*) from public.stock_management_snapshot),
    'snapshot_at',(select max(updated_at) from public.stock_management_snapshot))), version as materialized
        (select stock_management_private.reference_version() token)
        select wrapped.value||jsonb_build_object('rows',stock_management_private.add_reference_columns(wrapped.value->'rows','mrn'),
        'reference_version',version.token)||case when 'mrn'='catalog' then
        jsonb_build_object('meta',coalesce(wrapped.value->'meta','{}'::jsonb)||jsonb_build_object('reference_version',version.token))
        else '{}'::jsonb end from wrapped cross join version;$function$;

CREATE OR REPLACE FUNCTION public.get_stock_catalog_register_batch(p_offset integer DEFAULT 0, p_limit integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET enable_nestloop TO 'off'
AS $function$with wrapped(value) as materialized (
 with page as materialized (
   select item_code,payload from public.stock_catalog_snapshot order by item_code
   limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)
 ) select jsonb_build_object(
   'rows',coalesce((select jsonb_agg(
     (p.payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'current_month_branch_sales'-'daily_sales_45d'-'daily_sales_45d_available'-'meta')
     ||jsonb_build_object('supply_insight',coalesce(i.summary,
       '{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
       ||jsonb_build_object('generated_at',i.updated_at)) order by p.item_code)
     from page p left join public.stock_supply_insights i using(item_code)),'[]'::jsonb),
   'total',(select count(*) from public.stock_catalog_snapshot),
   'snapshot_at',coalesce((select payload->'meta'->>'refreshed_at' from public.stock_catalog_snapshot limit 1),''))), version as materialized
        (select stock_management_private.reference_version() token)
        select wrapped.value||jsonb_build_object('rows',stock_management_private.add_reference_columns(wrapped.value->'rows','catalog'),
        'reference_version',version.token)||case when 'catalog'='catalog' then
        jsonb_build_object('meta',coalesce(wrapped.value->'meta','{}'::jsonb)||jsonb_build_object('reference_version',version.token))
        else '{}'::jsonb end from wrapped cross join version;$function$;

CREATE OR REPLACE FUNCTION stock_management_private.reference_version()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select previous.value||':purchase:'||stock_management_private.purchase_status_version()
    from (
  select 'stock-ref-v1:'||coalesce((select revision::text
    from public.stock_workspace_cache_revisions where source='mrn_receipts'),'unknown')) previous(value);$function$;

CREATE OR REPLACE FUNCTION stock_management_private.add_reference_columns(p_rows jsonb, p_scope text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select case when coalesce(jsonb_array_length(p_rows),0)=0 then '[]'::jsonb else (
    with page as materialized (
      select ordinal,row->>'item_code' item_code,
        nullif(row->>'last_mrn_date','')::date mrn_date,
        nullif(row->>'last_receipt_date','')::date receipt_date,
        nullif(row->>'expiry_date','')::date expiry_date
      from jsonb_array_elements(p_rows) with ordinality p(row,ordinal)
    ), codes as materialized (select distinct item_code from page),
    purchase as materialized (
      select s.item_code,
        string_agg(distinct nullif(btrim(s.status_name),''),' · '
          order by nullif(btrim(s.status_name),'')) status_name
      from public.availability_kpi_purchase_status s join codes c using(item_code)
      group by s.item_code
    ), latest as materialized (
      select btrim(m.item_code) item_code,max(m.mrn_date) mrn_date
      from public.mrn_apg_2026 m join codes c on c.item_code=btrim(m.item_code)
      where p_scope='catalog' and lower(btrim(m.status))='approved'
      group by btrim(m.item_code)
    ), resolved as materialized (
      select p.ordinal,p.item_code,
        case p_scope when 'catalog' then l.mrn_date when 'expiry' then p.receipt_date else p.mrn_date end mrn_date,
        case when p_scope='expiry' then p.expiry_date end expiry_date
      from page p left join latest l using(item_code)
    ), targets as materialized (select distinct item_code,mrn_date,expiry_date from resolved),
    expiry_lines as materialized (
      select t.item_code,t.mrn_date,t.expiry_date,m.mrn_no,m.warehouse,
        sum(coalesce(m.ordered_quantity,0)) ordered_qty,sum(m.total_qty) total_qty,sum(m.bonus) bonus
      from targets t join stock_management_private.mrn_source_lines m on m.scope='store'
        and m.item_code=t.item_code and m.mrn_date=t.mrn_date and m.expiry_date is not distinct from t.expiry_date
      where p_scope='expiry' group by t.item_code,t.mrn_date,t.expiry_date,m.mrn_no,m.warehouse
    ), expiry_evidence as materialized (
      select item_code,mrn_date,expiry_date,jsonb_agg(jsonb_build_object(
        'mrn_date',mrn_date,'mrn_no',mrn_no,'warehouse',warehouse,'expiry_date',expiry_date,
        'ordered_qty',ordered_qty,'received_qty',total_qty,'total_qty',total_qty,'bonus',bonus)
        order by mrn_no desc,warehouse) receipts
      from expiry_lines group by item_code,mrn_date,expiry_date
    ), refs as materialized (
      select t.item_code,t.mrn_date,t.expiry_date, sum(coalesce(m.total_qty,0)) total_qty, sum(coalesce(m.bonus,0)) bonus,
        string_agg(distinct nullif(btrim(m.reference),''),' · ' order by nullif(btrim(m.reference),'')) reference
      from targets t join public.mrn_apg_2026 m
        on btrim(m.item_code)=t.item_code and m.mrn_date=t.mrn_date
        and (p_scope<>'expiry' or m.expiry_date is not distinct from t.expiry_date)
      where lower(btrim(m.status))='approved'
      group by t.item_code,t.mrn_date,t.expiry_date
    )
    select jsonb_agg(raw.row||jsonb_build_object(
      'total_qty',coalesce(r.total_qty,0),'bonus',coalesce(r.bonus,0),
     'received_quantity',coalesce(r.total_qty,0),'received_qty',coalesce(r.total_qty,0),
     'last_mrn_qty',coalesce(r.total_qty,0),'reference',coalesce(r.reference,''),
      'purchase_status_items',coalesce(ps.status_name,'Not assigned'))||
      case when p_scope='expiry' then jsonb_build_object('receipts',coalesce(ee.receipts,'[]'::jsonb),'product_data',
        coalesce(raw.row->'product_data','{}'::jsonb)||jsonb_build_object(
          'total_qty',coalesce(r.total_qty,0),'bonus',coalesce(r.bonus,0),
     'received_quantity',coalesce(r.total_qty,0),'received_qty',coalesce(r.total_qty,0),
     'last_mrn_qty',coalesce(r.total_qty,0),'reference',coalesce(r.reference,''),
          'purchase_status_items',coalesce(ps.status_name,'Not assigned')))
      else '{}'::jsonb end order by p.ordinal)
    from jsonb_array_elements(p_rows) with ordinality raw(row,ordinal)
    join resolved p using(ordinal)
    left join purchase ps on ps.item_code=p.item_code
    left join expiry_evidence ee on ee.item_code=p.item_code and ee.mrn_date is not distinct from p.mrn_date
      and ee.expiry_date is not distinct from p.expiry_date
     left join refs r on r.item_code=p.item_code
      and r.mrn_date is not distinct from p.mrn_date and r.expiry_date is not distinct from p.expiry_date
  ) end;
$function$;
