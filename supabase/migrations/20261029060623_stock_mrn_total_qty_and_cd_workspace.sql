-- Shared, invoker-only receipt projection. total_qty is authoritative: bonus
-- is explanatory and must never be added to total_qty a second time.
create view stock_management_private.mrn_source_lines with(security_invoker=true) as
select 'store'::text scope,id,btrim(item_code) item_code,btrim(warehouse) warehouse,
  mrn_date,coalesce(mrn_no,'') mrn_no,expiry_date,ordered_quantity,
  coalesce(total_qty,0) total_qty,coalesce(bonus,0) bonus,reference,vendor,
  item_name,category_1,supplier,company
from public.mrn_apg_2026 where lower(btrim(status))='approved'
union all
select 'cd'::text,id,btrim(item_code),btrim(warehouse),mrn_date,coalesce(mrn_no,''),
  expiry_date,ordered_quantity,coalesce(total_qty,0),coalesce(bonus,0),reference,
  vendor,item_name,category_1,supplier,company
from public.mrn_cd_apg_2026 where lower(btrim(status))='approved';
revoke all on stock_management_private.mrn_source_lines from public,anon;
grant select on stock_management_private.mrn_source_lines to authenticated,service_role;

create index if not exists mrn_cd_apg_2026_approved_item_warehouse_idx
  on public.mrn_cd_apg_2026(btrim(item_code),btrim(warehouse),mrn_date desc)
  where lower(btrim(status))='approved';

create table stock_management_private.mrn_cd_revision (
  singleton boolean primary key default true check(singleton),
  revision bigint not null default 1,
  updated_at timestamptz not null default clock_timestamp()
);
insert into stock_management_private.mrn_cd_revision(singleton) values(true);
alter table stock_management_private.mrn_cd_revision enable row level security;
revoke all on stock_management_private.mrn_cd_revision from public,anon,authenticated;
grant select on stock_management_private.mrn_cd_revision to authenticated;
grant all on stock_management_private.mrn_cd_revision to service_role;
create policy mrn_cd_revision_read on stock_management_private.mrn_cd_revision for select to authenticated
  using ((select public.item_tracker_my_role())='inventory' or (select stock_management_private.is_view_user()));
create function stock_management_private.bump_mrn_cd_revision()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update stock_management_private.mrn_cd_revision set revision=revision+1,updated_at=clock_timestamp();
  return null;
end;
$$;
revoke all on function stock_management_private.bump_mrn_cd_revision() from public,anon,authenticated,service_role;
create trigger stock_mrn_cd_revision after insert or update or delete or truncate
  on public.mrn_cd_apg_2026 for each statement execute function stock_management_private.bump_mrn_cd_revision();

create function stock_management_private.mrn_cd_version()
returns text language sql stable security invoker set search_path='' as $$
  select 'mrn-cd-v1:'||revision::text||':'||stock_management_private.catalog_cache_version(true)
  from stock_management_private.mrn_cd_revision where singleton;
$$;
revoke all on function stock_management_private.mrn_cd_version() from public,anon;
grant execute on function stock_management_private.mrn_cd_version() to authenticated,service_role;

create function stock_management_private.receipt_summary(p_code text,p_scope text,p_warehouse text default null)
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('mrn_count',count(distinct (mrn_date,mrn_no)),
    'day_count',count(distinct mrn_date),'total_qty',coalesce(sum(total_qty),0),
    'received_qty',coalesce(sum(total_qty),0),'bonus',coalesce(sum(bonus),0),
    'from',min(mrn_date),'through',max(mrn_date))
  from stock_management_private.mrn_source_lines
  where item_code=btrim(p_code) and scope=p_scope
    and (p_scope<>'cd' or warehouse=btrim(p_warehouse));
$$;

create function stock_management_private.receipt_details(p_code text,p_date date,p_scope text,p_warehouse text default null)
returns jsonb language sql stable security invoker set search_path='' as $$
  with lines as materialized (
    select mrn_date,mrn_no,warehouse,expiry_date,sum(coalesce(ordered_quantity,0)) ordered_qty,
      sum(total_qty) total_qty,sum(bonus) bonus,min(nullif(btrim(vendor),'')) vendor,
      string_agg(distinct nullif(btrim(reference),''),' · ' order by nullif(btrim(reference),'')) reference
    from stock_management_private.mrn_source_lines
    where item_code=btrim(p_code) and scope=p_scope and mrn_date=p_date
      and (p_scope<>'cd' or warehouse=btrim(p_warehouse))
    group by mrn_date,mrn_no,warehouse,expiry_date
  ) select case when count(*)=0 then '{}'::jsonb else jsonb_build_object(
    'receipt_scope','latest_mrn_date','receipt_count',count(distinct mrn_no),'receipt_line_count',count(*),
    'expiry_count',count(distinct expiry_date) filter(where total_qty>0),
    'expiry_date',min(expiry_date) filter(where total_qty>0),
    'ordered_quantity',sum(ordered_qty),'total_qty',sum(total_qty),'bonus',sum(bonus),
    'received_quantity',sum(total_qty),'last_mrn_qty',sum(total_qty),'vendor',left(upper(min(vendor)),10),
    'receipt_lines',jsonb_agg(jsonb_build_object('mrn_date',mrn_date,'mrn_no',mrn_no,'warehouse',warehouse,
      'expiry_date',expiry_date,'ordered_qty',ordered_qty,'total_qty',total_qty,'received_qty',total_qty,
      'bonus',bonus,'vendor',left(upper(vendor),10),'reference',coalesce(reference,''))
      order by mrn_date desc,mrn_no desc,expiry_date nulls last,warehouse)) end from lines;
$$;

create function stock_management_private.receipt_history(p_code text,p_scope text,p_warehouse text,p_offset integer,p_limit integer)
returns jsonb language sql stable security invoker set search_path='' as $$
  with lines as materialized (
    select mrn_date,mrn_no,warehouse,expiry_date,sum(coalesce(ordered_quantity,0)) ordered_qty,
      sum(total_qty) total_qty,sum(bonus) bonus,left(upper(min(nullif(btrim(vendor),''))),10) vendor,
      string_agg(distinct nullif(btrim(reference),''),' · ' order by nullif(btrim(reference),'')) reference
    from stock_management_private.mrn_source_lines
    where item_code=btrim(p_code) and scope=p_scope
      and (p_scope<>'cd' or warehouse=btrim(p_warehouse))
    group by mrn_date,mrn_no,warehouse,expiry_date
  ), page as (
    select jsonb_build_object('line_id',jsonb_build_array(mrn_date,mrn_no,warehouse,expiry_date)::text,
      'mrn_date',mrn_date,'mrn_no',mrn_no,'warehouse',warehouse,'expiry_date',expiry_date,
      'ordered_qty',ordered_qty,'received_qty',total_qty,'total_qty',total_qty,'bonus',bonus,
      'vendor',vendor,'reference',coalesce(reference,'')) row,
      mrn_date,mrn_no,warehouse,expiry_date
    from lines order by mrn_date desc nulls last,mrn_no desc,warehouse,expiry_date nulls last
    limit least(greatest(coalesce(p_limit,5000),1),5000) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object('item_code',btrim(p_code),'warehouse',p_warehouse,
    'rows',coalesce((select jsonb_agg(row order by mrn_date desc nulls last,mrn_no desc,warehouse,expiry_date nulls last) from page),'[]'::jsonb),
    'total',(select count(*) from lines),'mrn_count',(select count(distinct (mrn_date,mrn_no)) from lines),
    'day_count',(select count(distinct mrn_date) from lines),'received_qty',(select coalesce(sum(total_qty),0) from lines),
    'total_qty',(select coalesce(sum(total_qty),0) from lines),'bonus',(select coalesce(sum(bonus),0) from lines),
    'ordered_qty',(select coalesce(sum(ordered_qty),0) from lines),
    'from',(select min(mrn_date) from lines),'through',(select max(mrn_date) from lines),
    'snapshot_version',case p_scope when 'cd' then stock_management_private.mrn_cd_version() else
      (select 'mrn-total-v2:'||revision::text from public.stock_workspace_cache_revisions where source='mrn_receipts') end);
$$;
revoke all on function stock_management_private.receipt_summary(text,text,text),
  stock_management_private.receipt_details(text,date,text,text),
  stock_management_private.receipt_history(text,text,text,integer,integer) from public,anon;
grant execute on function stock_management_private.receipt_summary(text,text,text),
  stock_management_private.receipt_details(text,date,text,text),
  stock_management_private.receipt_history(text,text,text,integer,integer) to authenticated,service_role;

create or replace function stock_management_private.mrn_receipt_details(p_item_code text,p_date date)
returns jsonb language sql stable security invoker set search_path='' as $$
  select stock_management_private.receipt_details(p_item_code,p_date,'store',null);
$$;
create or replace function stock_management_private.mrn_receipt_history_summary(p_item_code text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select stock_management_private.receipt_summary(p_item_code,'store',null);
$$;
create or replace function public.get_stock_management_receipt_history(p_item_code text,p_offset integer default 0,p_limit integer default 5000)
returns jsonb language sql stable security invoker set search_path='' as $$
  select stock_management_private.receipt_history(p_item_code,'store',null,p_offset,p_limit);
$$;

-- Keep current page identities and references. Add authoritative quantities in
-- the existing shared enrichment rather than serializing the register twice.
do $quantity$
declare definition text;
begin
  definition:=pg_get_functiondef('stock_management_private.add_reference_columns(jsonb,text)'::regprocedure);
  if position('''total_qty''' in definition)>0 then raise exception 'Receipt quantity enrichment already installed'; end if;
  definition:=replace(definition,
    'select t.item_code,t.mrn_date,t.expiry_date,',
    'select t.item_code,t.mrn_date,t.expiry_date, sum(coalesce(m.total_qty,0)) total_qty, sum(coalesce(m.bonus,0)) bonus,');
  definition:=replace(definition,'''reference'',coalesce(r.reference,''''),',
    '''total_qty'',coalesce(r.total_qty,0),''bonus'',coalesce(r.bonus,0),
     ''received_quantity'',coalesce(r.total_qty,0),''received_qty'',coalesce(r.total_qty,0),
     ''last_mrn_qty'',coalesce(r.total_qty,0),''reference'',coalesce(r.reference,''''),');
  definition:=replace(definition,'refs as materialized (',
    'expiry_lines as materialized (
      select t.item_code,t.mrn_date,t.expiry_date,m.mrn_no,m.warehouse,
        sum(coalesce(m.ordered_quantity,0)) ordered_qty,sum(m.total_qty) total_qty,sum(m.bonus) bonus
      from targets t join stock_management_private.mrn_source_lines m on m.scope=''store''
        and m.item_code=t.item_code and m.mrn_date=t.mrn_date and m.expiry_date is not distinct from t.expiry_date
      where p_scope=''expiry'' group by t.item_code,t.mrn_date,t.expiry_date,m.mrn_no,m.warehouse
    ), expiry_evidence as materialized (
      select item_code,mrn_date,expiry_date,jsonb_agg(jsonb_build_object(
        ''mrn_date'',mrn_date,''mrn_no'',mrn_no,''warehouse'',warehouse,''expiry_date'',expiry_date,
        ''ordered_qty'',ordered_qty,''received_qty'',total_qty,''total_qty'',total_qty,''bonus'',bonus)
        order by mrn_no desc,warehouse) receipts
      from expiry_lines group by item_code,mrn_date,expiry_date
    ), refs as materialized (');
  definition:=replace(definition,'left join refs r on r.item_code=p.item_code',
    'left join expiry_evidence ee on ee.item_code=p.item_code and ee.mrn_date is not distinct from p.mrn_date
      and ee.expiry_date is not distinct from p.expiry_date
     left join refs r on r.item_code=p.item_code');
  definition:=replace(definition,'then jsonb_build_object(''product_data'',',
    'then jsonb_build_object(''receipts'',coalesce(ee.receipts,''[]''::jsonb),''product_data'',');
  execute definition;
end $quantity$;

-- Existing expiry discovery must retain zero-price/bonus-only receipts too.
do $expiry$
declare definition text; signature text;
begin
  foreach signature in array array[
    'stock_management_private.discover_expiry_receipts()',
    'public.get_stock_management_register_batch(integer,integer)',
    'public.get_stock_management_item(text)',
    'public.get_stock_expiry_page(text,text,text,integer,integer)'
  ] loop
    definition:=pg_get_functiondef(signature::regprocedure);
    execute replace(definition,'m.received_quantity','m.total_qty');
  end loop;
end $expiry$;

-- Each CD register row is one receiving warehouse + product, latest receipt day.
create view stock_management_private.mrn_cd_register with(security_invoker=true) as
with latest as (
  select item_code,warehouse,max(mrn_date) last_mrn_date
  from stock_management_private.mrn_source_lines where scope='cd' and nullif(item_code,'') is not null
    and nullif(warehouse,'') is not null group by item_code,warehouse
), receipts as (
  select l.item_code,l.warehouse,l.last_mrn_date,min(m.item_name) item_name,
    min(m.category_1) category,min(m.supplier) supplier,min(m.company) company,
    sum(coalesce(m.ordered_quantity,0)) ordered_quantity,sum(m.total_qty) total_qty,sum(m.bonus) bonus,
    min(m.expiry_date) filter(where m.total_qty>0) expiry_date,count(distinct m.expiry_date) filter(where m.total_qty>0) expiry_count,
    count(distinct m.mrn_no) receipt_count,max(m.mrn_no) last_mrn_no,
    left(upper(min(nullif(btrim(m.vendor),''))),10) vendor,
    string_agg(distinct nullif(btrim(m.reference),''),' · ' order by nullif(btrim(m.reference),'')) reference
  from latest l join stock_management_private.mrn_source_lines m
    on m.scope='cd' and m.item_code=l.item_code and m.warehouse=l.warehouse and m.mrn_date=l.last_mrn_date
  group by l.item_code,l.warehouse,l.last_mrn_date
) select r.*,s.payload catalog_payload,
  coalesce(s.payload->>'stock_status','unavailable') stock_status,
  coalesce((s.payload->>'total_stock')::numeric,0) total_stock,
  (s.payload->>'days_on_hand')::numeric days_on_hand,
  coalesce(ps.status_name,'Not assigned') purchase_status_items
from receipts r left join public.stock_catalog_snapshot s using(item_code)
left join (select item_code,string_agg(distinct nullif(btrim(status_name),''),' · '
  order by nullif(btrim(status_name),'')) status_name from public.availability_kpi_purchase_status group by item_code) ps using(item_code);
revoke all on stock_management_private.mrn_cd_register from public,anon;
grant select on stock_management_private.mrn_cd_register to authenticated,service_role;

create function stock_management_private.mrn_cd_payload(p stock_management_private.mrn_cd_register)
returns jsonb language sql stable security invoker set search_path='' as $$
select coalesce(p.catalog_payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'current_month_branch_sales'-'daily_sales_45d'-'daily_sales_45d_available'-'branches'-'branch_year_sales'-'meta','{}'::jsonb)
  ||jsonb_build_object('item_code',p.item_code,'item_name',coalesce(p.catalog_payload->>'item_name',p.item_name),
    'category',coalesce(p.catalog_payload->>'category',p.category),
    'supplier',coalesce(p.catalog_payload->>'supplier',p.supplier),'company',coalesce(p.catalog_payload->>'company',p.company),
    'warehouse',p.warehouse,'receipt_source','mrn_cd_apg_2026','register_key',jsonb_build_array(p.warehouse,p.item_code)::text,
    'last_mrn_date',p.last_mrn_date,'last_mrn_no',p.last_mrn_no,'reference',coalesce(p.reference,''),
    'ordered_quantity',p.ordered_quantity,'total_qty',p.total_qty,'received_quantity',p.total_qty,'bonus',p.bonus,
    'last_mrn_qty',p.total_qty,'expiry_date',p.expiry_date,'expiry_count',p.expiry_count,
    'receipt_count',p.receipt_count,'receipt_scope','latest_mrn_date','vendor',p.vendor,
    'stock_status',p.stock_status,'stock_unavailable',p.catalog_payload is null,
    'purchase_status_items',p.purchase_status_items);
$$;
revoke all on function stock_management_private.mrn_cd_payload(stock_management_private.mrn_cd_register) from public,anon;
grant execute on function stock_management_private.mrn_cd_payload(stock_management_private.mrn_cd_register) to authenticated,service_role;

create function public.get_stock_mrn_cd_page(p_search text default '',p_status text default '',p_category text default '',
  p_supplier text default '',p_received_from date default null,p_received_to date default null,
  p_sort text default 'latest_mrn',p_offset integer default 0,p_limit integer default 5000)
returns jsonb language sql stable security invoker set search_path='' set enable_nestloop=off as $$
with data as materialized (
  select r.* from stock_management_private.mrn_cd_register r
  where (coalesce(p_search,'')='' or r.item_code ilike '%'||p_search||'%' or r.item_name ilike '%'||p_search||'%' or r.warehouse ilike '%'||p_search||'%')
    and (coalesce(p_status,'')='' or r.stock_status=p_status)
    and (coalesce(p_category,'')='' or coalesce(r.catalog_payload->>'category',r.category)=p_category)
    and (coalesce(p_supplier,'')='' or coalesce(r.catalog_payload->>'supplier',r.supplier)=p_supplier)
    and (p_received_from is null or r.last_mrn_date>=p_received_from)
    and (p_received_to is null or r.last_mrn_date<=p_received_to)
), page as materialized (
  select * from data order by
    case when p_sort='days_low' then days_on_hand end asc nulls last,
    case when p_sort='stock_high' then total_stock end desc nulls last,
    case when p_sort='sales_high' then (catalog_payload->'years'->'2026'->>'total')::numeric end desc nulls last,
    last_mrn_date desc,item_code,warehouse
  limit least(greatest(coalesce(p_limit,5000),1),5000) offset greatest(coalesce(p_offset,0),0)
), token as materialized (select stock_management_private.mrn_cd_version() version)
select jsonb_build_object('rows',coalesce((select jsonb_agg(stock_management_private.mrn_cd_payload(p::stock_management_private.mrn_cd_register)
  order by case when p_sort='days_low' then p.days_on_hand end asc nulls last,
    case when p_sort='stock_high' then p.total_stock end desc nulls last,
    case when p_sort='sales_high' then (p.catalog_payload->'years'->'2026'->>'total')::numeric end desc nulls last,
    p.last_mrn_date desc,p.item_code,p.warehouse) from page p),'[]'::jsonb),
  'total',(select count(*) from data),'snapshot_at',token.version,
  'summary',(select jsonb_build_object('items',count(*),'no_stock',count(*) filter(where stock_status='no_stock'),
    'low_cover',count(*) filter(where stock_status='low_cover'),'no_sales',count(*) filter(where stock_status='no_sales')) from data),
  'meta',coalesce((select payload->'meta' from public.stock_catalog_snapshot limit 1),'{}'::jsonb)||jsonb_build_object(
    'source','mrn_cd_apg_2026','snapshot_at',token.version,
    'mrn_through',(select max(mrn_date) from public.mrn_cd_apg_2026 where lower(btrim(status))='approved')),
  'categories',coalesce((select jsonb_agg(v order by v) from (select distinct coalesce(catalog_payload->>'category',category) v from data)q where nullif(btrim(v),'') is not null),'[]'::jsonb),
  'suppliers',coalesce((select jsonb_agg(v order by v) from (select distinct coalesce(catalog_payload->>'supplier',supplier) v from data)q where nullif(btrim(v),'') is not null),'[]'::jsonb))
from token;
$$;
create function public.get_stock_mrn_cd_register_batch(p_offset integer default 0,p_limit integer default 5000)
returns jsonb language sql stable security invoker set search_path='' as $$
  select public.get_stock_mrn_cd_page('','','','',null,null,'latest_mrn',p_offset,p_limit);
$$;

create function public.get_stock_mrn_cd_item(p_item_code text,p_warehouse text)
returns jsonb language sql stable security invoker set search_path='' as $$
with r as materialized (select * from stock_management_private.mrn_cd_register where item_code=btrim(p_item_code) and warehouse=btrim(p_warehouse)),
details as materialized (select stock_management_private.mrn_cd_payload(r::stock_management_private.mrn_cd_register)||
  stock_management_private.receipt_details(r.item_code,r.last_mrn_date,'cd',r.warehouse)||jsonb_build_object(
    'receipt_history_summary',stock_management_private.receipt_summary(r.item_code,'cd',r.warehouse)) value from r),
catalog as materialized (select public.get_stock_catalog_item(p_item_code)-'_cache_version' value)
select coalesce(catalog.value,'{}'::jsonb)||details.value||jsonb_build_object('mrn_details',details.value,
  'catalog_unavailable',catalog.value is null) from details cross join catalog;
$$;
create function public.get_stock_mrn_cd_receipt_history(p_item_code text,p_warehouse text,p_offset integer default 0,p_limit integer default 5000)
returns jsonb language sql stable security invoker set search_path='' as $$
  select stock_management_private.receipt_history(p_item_code,'cd',p_warehouse,p_offset,p_limit);
$$;
create function public.get_stock_mrn_cd_refresh_state()
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('status','complete','completed_at',updated_at) from stock_management_private.mrn_cd_revision;
$$;
revoke all on function public.get_stock_mrn_cd_page(text,text,text,text,date,date,text,integer,integer),
  public.get_stock_mrn_cd_register_batch(integer,integer),public.get_stock_mrn_cd_item(text,text),
  public.get_stock_mrn_cd_receipt_history(text,text,integer,integer),public.get_stock_mrn_cd_refresh_state() from public,anon;
grant execute on function public.get_stock_mrn_cd_page(text,text,text,text,date,date,text,integer,integer),
  public.get_stock_mrn_cd_register_batch(integer,integer),public.get_stock_mrn_cd_item(text,text),
  public.get_stock_mrn_cd_receipt_history(text,text,integer,integer),public.get_stock_mrn_cd_refresh_state() to authenticated,service_role;

do $cache$
declare definition text; body text;
begin
  select pg_get_functiondef(p.oid),p.prosrc into definition,body from pg_proc p
    where p.oid='public.get_stock_workspace_cache_state()'::regprocedure;
  execute replace(definition,body,format('select case when state.value is null then null else state.value||
    jsonb_build_object(''mrn_cd'',stock_management_private.mrn_cd_version()) end
    from (%s) state(value);',regexp_replace(body,';[[:space:]]*$','')));
end $cache$;
update public.stock_workspace_cache_revisions set revision=revision+1 where source='mrn_receipts';
notify pgrst,'reload schema';
