-- Transactional, statement-level revisions: no per-product trigger work and no
-- cross-source revision row shared with the long-running catalog refresh job.
create table public.stock_catalog_cache_revisions (
  source text primary key check (source in ('snapshot','sales_2025','sales_2026','branches')),
  revision bigint not null default 0
);
insert into public.stock_catalog_cache_revisions(source)
values ('snapshot'),('sales_2025'),('sales_2026'),('branches');
alter table public.stock_catalog_cache_revisions enable row level security;
revoke all on public.stock_catalog_cache_revisions from public, anon, authenticated;
grant select on public.stock_catalog_cache_revisions to authenticated;
grant all on public.stock_catalog_cache_revisions to service_role;
create policy stock_catalog_cache_inventory_read on public.stock_catalog_cache_revisions
  for select to authenticated using ((select public.item_tracker_my_role())='inventory');

create function stock_management_private.bump_catalog_cache_revision()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.stock_catalog_cache_revisions set revision=revision+1
  where source=case tg_table_name
    when 'stock_catalog_snapshot' then 'snapshot'
    when 'sales_history_2025' then 'sales_2025'
    when 'sales_history' then 'sales_2026'
    when 'branches' then 'branches' end;
  return null;
end;
$$;
revoke all on function stock_management_private.bump_catalog_cache_revision()
  from public,anon,authenticated,service_role;

create trigger stock_catalog_cache_snapshot_changed
after insert or update or delete or truncate on public.stock_catalog_snapshot
for each statement execute function stock_management_private.bump_catalog_cache_revision();
create trigger stock_catalog_cache_sales_2025_changed
after insert or update or delete or truncate on public.sales_history_2025
for each statement execute function stock_management_private.bump_catalog_cache_revision();
create trigger stock_catalog_cache_sales_2026_changed
after insert or update or delete or truncate on public.sales_history
for each statement execute function stock_management_private.bump_catalog_cache_revision();
create trigger stock_catalog_cache_branches_changed
after insert or update or delete or truncate on public.branches
for each statement execute function stock_management_private.bump_catalog_cache_revision();

create function stock_management_private.catalog_cache_version(p_details boolean)
returns text language sql stable security invoker set search_path='' as $$
  select case when count(*)=case when p_details then 4 else 1 end
    then 'v1:'||string_agg(source||':'||revision::text,',' order by source) end
  from public.stock_catalog_cache_revisions
  where p_details or source='snapshot';
$$;
revoke all on function stock_management_private.catalog_cache_version(boolean) from public,anon;
grant usage on schema stock_management_private to authenticated,service_role;
grant execute on function stock_management_private.catalog_cache_version(boolean)
  to authenticated,service_role;

-- Keep the original RPC and all existing calculations/payload keys compatible.
-- Normalize active branch names once, then join each year's aggregate once.
-- Existing item expression indexes already support both annual sales reads.
create or replace function public.get_stock_catalog_item(p_item_code text)
returns jsonb language sql stable security invoker set search_path='' as $$
  with snapshot as materialized (
    select payload from public.stock_catalog_snapshot where item_code=p_item_code
  ), active_branches as materialized (
    select branch_name branch,branch_group,public._norm_text(branch_name) branch_key
    from public.branches where is_active is true and public._norm_text(branch_name) not in
      ('store','main virtual','new virtual','store - expired item','store-ws')
  ), sales_2025 as (
    select public._norm_text(branch_name) branch_key,
      sum(coalesce(cash,0)+coalesce(insurance,0)+coalesce(online,0)) total
    from public.sales_history_2025
    where btrim(item_code)=p_item_code and month ~ '^(0[1-9]|1[0-2])/2025$'
    group by public._norm_text(branch_name)
  ), sales_2026 as (
    select public._norm_text(branch_name) branch_key,
      sum(coalesce(cash,0)+coalesce(insurance,0)+coalesce(online,0)) total
    from public.sales_history
    where btrim(item_code)=p_item_code and month ~ '^(0[1-9]|1[0-2])/2026$'
    group by public._norm_text(branch_name)
  ), branches as (
    select b.branch,b.branch_group,
      (s.payload->'distribution_orders'->b.branch_key->>'eligible')::boolean distribution_eligible,
      (s.payload->'distribution_orders'->b.branch_key->>'reorder_qty')::numeric reorder_qty,
      (s.payload->'distribution_orders'->b.branch_key->>'final_qty')::numeric final_qty,
      coalesce((s.payload->'branch_stock'->b.branch_key->>'stock')::numeric,0) stock,
      coalesce((s.payload->'branch_demand'->b.branch_key->>'recent_sales')::numeric,0) recent_sales,
      coalesce((s.payload->'branch_demand'->b.branch_key->>'last_3_sales')::numeric,0) last_3_sales,
      coalesce((s.payload->'branch_demand'->b.branch_key->>'baseline_sales')::numeric,0) baseline_sales,
      coalesce(y25.total,0) sales_2025,coalesce(y26.total,0) sales_2026
    from snapshot s cross join active_branches b
    left join sales_2025 y25 using(branch_key)
    left join sales_2026 y26 using(branch_key)
  ) select payload-'branch_stock'-'branch_demand'-'distribution_orders' || jsonb_build_object(
    'branches',coalesce((select jsonb_agg(to_jsonb(b)-'branch_key' order by recent_sales desc,branch)
      from branches b),'[]'::jsonb),
    '_cache_version',stock_management_private.catalog_cache_version(true)) from snapshot;
$$;

create function public.get_stock_catalog_item_if_changed(p_item_code text,p_known_version text)
returns jsonb language sql stable security invoker set search_path='' as $$
  with version as materialized (
    select stock_management_private.catalog_cache_version(true) token
  ) select case when token is not null and token=p_known_version
      and has_table_privilege(current_user,'public.sales_history','SELECT')
      and has_table_privilege(current_user,'public.sales_history_2025','SELECT')
      and has_table_privilege(current_user,'public.branches','SELECT')
      and exists(select 1 from public.stock_catalog_snapshot where item_code=p_item_code)
    then jsonb_build_object('_cache_not_modified',true,'_cache_version',token)
    else public.get_stock_catalog_item(p_item_code) end from version;
$$;
revoke all on function public.get_stock_catalog_item_if_changed(text,text) from public,anon;
grant execute on function public.get_stock_catalog_item_if_changed(text,text)
  to authenticated,service_role;


-- The existing one-row overview request also validates the in-memory register.
CREATE OR REPLACE FUNCTION public.get_stock_catalog_page(p_search text DEFAULT ''::text, p_signal text DEFAULT ''::text, p_category text DEFAULT ''::text, p_supplier text DEFAULT ''::text, p_sort text DEFAULT 'name'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with filtered as materialized (
    select * from public.stock_catalog_snapshot s where
      (coalesce(p_search,'')='' or strpos(lower(s.item_code||' '||s.item_name||' '||s.supplier||' '||coalesce(s.payload->>'company','')),lower(btrim(p_search)))>0)
      and (coalesce(p_category,'')='' or s.category=p_category) and (coalesce(p_supplier,'')='' or s.supplier=p_supplier)
      and (coalesce(p_signal,'')='' or
        (p_signal='surge' and (demand_surge or (payload->>'new_demand')::boolean)) or
        (p_signal='shortage' and (payload->>'recent_sales')::numeric>total_stock) or
        (p_signal='low_cover' and payload->>'stock_status'='low_cover') or
        (p_signal='no_stock' and total_stock<=0) or (p_signal='no_sales' and payload->>'stock_status'='no_sales'))
  ), page as (
    select * from filtered order by
      case when p_sort='stock' then total_stock end desc nulls last,
      case when p_sort='sales' then sales_2026 end desc nulls last,
      case when p_sort='cover' then days_on_hand end asc nulls last,
      case when p_sort='growth' then (payload->>'growth_percent')::numeric end desc nulls last,
      item_name,item_code limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'meta') from page),'[]'::jsonb),
    'summary',(select jsonb_build_object('items',count(*),'surge',count(*) filter(where demand_surge or (payload->>'new_demand')::boolean),
      'shortage',count(*) filter(where (payload->>'recent_sales')::numeric>total_stock),
      'low_cover',count(*) filter(where payload->>'stock_status'='low_cover'),
      'no_stock',count(*) filter(where total_stock<=0),'total_stock',coalesce(sum(total_stock),0)) from filtered),
    'meta',coalesce((select payload->'meta' from public.stock_catalog_snapshot limit 1),'{}'::jsonb) || jsonb_build_object('catalog_cache_version',stock_management_private.catalog_cache_version(false)),
    'categories',coalesce((select jsonb_agg(category order by category) from (select distinct category from public.stock_catalog_snapshot where category<>'') c),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(supplier order by supplier) from (select distinct supplier from public.stock_catalog_snapshot where supplier<>'') c),'[]'::jsonb)
  );
$function$;

NOTIFY pgrst, 'reload schema';
