-- Explicitly authorized Online Overview update for the same single active Inventory user.
-- Keep existing source data, Overview caches/jobs and prepared product results unchanged.

-- actual_sales_preview.sql
-- Single-user recorded-sales rollout. Existing snapshots, jobs and RPCs stay intact.
create schema if not exists online_overview_preview_private;
revoke all on schema online_overview_preview_private from public,anon,authenticated,service_role;
grant usage on schema online_overview_preview_private to authenticated;
create table if not exists online_overview_preview_private.snapshot (
 singleton boolean primary key default true check(singleton),
 generation text not null unique, base_generation text not null, meta jsonb not null
);
create table if not exists online_overview_preview_private.rows (
 generation text not null, item_code text not null, payload jsonb not null,
 primary key(generation,item_code)
);
create table if not exists online_overview_preview_private.read_pages (
 generation text not null, branch text not null, page_offset integer not null,
 payload jsonb not null, primary key(generation,branch,page_offset)
);
alter table online_overview_preview_private.snapshot enable row level security;
alter table online_overview_preview_private.rows enable row level security;
alter table online_overview_preview_private.read_pages enable row level security;
revoke all on all tables in schema online_overview_preview_private from public,anon,authenticated,service_role;

create or replace function online_overview_preview_private.read(
 p_action text,p_generation text,p_branch text,p_scope text,p_offset integer,p_limit integer,p_item_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare preview online_overview_preview_private.snapshot; base jsonb; result jsonb;
 summaries jsonb; complete boolean; matched integer; expected integer; batch_total integer;
begin
 perform online_overview_private.assert_access();
 base:=online_overview_private.read_state();
 select * into preview from online_overview_preview_private.snapshot where singleton;
 if preview.generation is null or preview.base_generation is distinct from base->>'generation'
 then
  if p_action='state' then return jsonb_build_object('status','needs_update');end if;
  raise exception 'The local preview needs an update. Reload.' using errcode='40001';
 end if;
 if p_action in ('state','refresh') then
  return base || jsonb_build_object('status','complete','generation',preview.generation,
   'meta',((base->'meta')-'forecast'-'model') || preview.meta);
 end if;
 if p_generation is distinct from preview.generation then
  raise exception 'Online snapshot changed. Reload.' using errcode='40001';end if;
 if p_branch is null or p_scope is distinct from 'onlineOnly'
  or (p_branch<>'' and not exists(select 1 from jsonb_array_elements(base#>'{meta,branches}') b
     where b->>'name'=p_branch)) then
  raise insufficient_privilege using message='Only online branches and online sales are available';end if;
 if p_action in ('stock','monthly_sales','recent_sales','forecast') and not exists(
  select 1 from online_overview_preview_private.rows r
  where r.generation=preview.generation and r.item_code=p_item_code)
 then raise insufficient_privilege using message='Unknown online product';end if;
 if p_action='batch' then
  select count(*) into batch_total from online_overview_private.results
   where generation=preview.base_generation and branch=p_branch and scope=p_scope;
  if batch_total<>(base#>>'{meta,items}')::integer then raise exception 'Incomplete local preview';end if;
  if p_limit=5000 then
   select p.payload into result from online_overview_preview_private.read_pages p
    where p.generation=preview.generation and p.branch=p_branch and p.page_offset=greatest(p_offset,0);
   if found then return result;end if;
  end if;
  -- Merge the pinned prepared facts once, before aggregation. Do not build the
  -- legacy 5,000-row JSON document and expand it again to replace its ranks.
  with page as materialized (
   select r.item_code,r.ordinal,r.payload from online_overview_private.results r
   where r.generation=preview.base_generation and r.branch=p_branch and r.scope=p_scope
   order by r.ordinal limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)
  ), merged as (
   select r.ordinal,r.payload || original.payload || c.payload ||
    case when p_branch<>'' then jsonb_build_object(
     'known_online_stock',r.payload->'online_stock',
     'reported_branches',case when r.payload->>'online_stock' is null then 0 else 1 end,
     'stocked_branches',case when (r.payload->>'online_stock')::numeric>0 then 1 else 0 end,
     'missing_branches',case when r.payload->>'online_stock' is null then jsonb_build_array(p_branch) else '[]'::jsonb end
    ) else '{}'::jsonb end ||
    jsonb_build_object('item',online_overview_private.display_item(i.payload)) payload
   from page r
   join online_overview_private.classification original
    on original.generation=preview.base_generation and original.item_code=r.item_code
   join online_overview_preview_private.rows c on c.generation=preview.generation and c.item_code=r.item_code
   join online_overview_private.items i on i.generation=preview.base_generation and i.item_code=r.item_code
  ) select (select count(*) from page),count(*),coalesce(jsonb_agg(payload order by ordinal),'[]'::jsonb)
    into expected,matched,summaries from merged;
  if matched<>expected then raise exception 'Incomplete local preview';end if;
  return jsonb_build_object('generation',preview.generation,'total',batch_total,'rows',summaries);
 elsif p_action='stock' then
  return online_overview_private.stock_breakdown(preview.base_generation,p_item_code);
 elsif p_action='monthly_sales' then
  return online_overview_preview_private.monthly_sales(preview.base_generation,p_item_code,p_branch);
 elsif p_action='recent_sales' then
  return online_overview_preview_private.recent_sales(preview.base_generation,p_item_code,p_branch);
 elsif p_action='forecast' then
  return '{}'::jsonb; -- Actual sales determine these ranks; no forecast is presented as their cause.
 elsif p_action='availability' then
  with branches as materialized (
   select b->>'name' branch from jsonb_array_elements(base#>'{meta,branches}') b
  ), ranks as (select unnest(array['a','b','c']) rank),
  totals as materialized (
   select payload->>'rank' rank,count(*) total from online_overview_preview_private.rows
   where generation=preview.generation and payload->>'rank' in ('a','b','c') group by 1
  ), counts as materialized (
   select r.branch,c.payload->>'rank' rank,count(*) observed,
    count(*) filter(where (r.payload->>'online_stock')::numeric>0) available,
    count(*) filter(where r.payload->>'online_stock' is null) unknown
   from online_overview_private.results r join online_overview_preview_private.rows c
    on c.generation=preview.generation and c.item_code=r.item_code
   join branches b on b.branch=r.branch
   where r.generation=preview.base_generation and r.scope='onlineOnly'
    and c.payload->>'rank' in ('a','b','c') group by r.branch,c.payload->>'rank'
  ), facts as (
   select b.branch,k.rank,coalesce(t.total,0) total,coalesce(c.observed,0) observed,
    coalesce(c.available,0) available,coalesce(c.unknown,0) unknown
   from branches b cross join ranks k left join totals t using(rank)
   left join counts c on c.branch=b.branch and c.rank=k.rank
  ) select bool_and(observed=total),jsonb_agg(jsonb_build_object(
   'branch_name',branch,'rank',rank,'total',total,'available',available,'unknown',unknown
  ) order by branch,rank) into complete,summaries from facts;
  if complete is distinct from true then raise exception 'Incomplete online availability snapshot';end if;
  return jsonb_build_object('generation',preview.generation,'stock_day',base#>'{meta,stock_day}','rows',summaries);
 end if;
 raise invalid_parameter_value using message='Unknown preview request';
end $$;
revoke all on function online_overview_preview_private.read(text,text,text,text,integer,integer,text)
 from public,anon,service_role;
grant execute on function online_overview_preview_private.read(text,text,text,text,integer,integer,text) to authenticated;

create or replace function public.get_local_online_overview_preview(
 p_action text,p_generation text default null,p_branch text default '',p_scope text default 'onlineOnly',
 p_offset integer default 0,p_limit integer default 5000,p_item_code text default '')
returns jsonb language sql stable security invoker set search_path='' as $$
 select online_overview_preview_private.read(p_action,p_generation,p_branch,p_scope,p_offset,p_limit,p_item_code)
$$;
revoke all on function public.get_local_online_overview_preview(text,text,text,text,integer,integer,text)
 from public,anon,service_role;
grant execute on function public.get_local_online_overview_preview(text,text,text,text,integer,integer,text) to authenticated;

-- current_month_sales.sql
-- Single-user Online Overview. Match Overview: completed history plus calendar-current
-- signed daily online sales, replacing current-month history rather than adding.
create or replace function online_overview_preview_private.monthly_sales(
 p_generation text,p_item_code text,p_branch text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare snapshot_meta jsonb; result jsonb;
 today date := (now() at time zone 'Asia/Dubai')::date;
 current_month date := date_trunc('month',today)::date;
 daily_end date;
begin
 perform online_overview_private.assert_access();
 select meta into snapshot_meta from online_overview_private.state where singleton and generation=p_generation;
 if snapshot_meta is null or not online_overview_private.roster_is_allowed(snapshot_meta)
 then raise exception 'Online snapshot changed. Reload.' using errcode='40001';end if;
 if not exists(select 1 from online_overview_private.items where generation=p_generation and item_code=p_item_code)
  or p_branch is null or (p_branch<>'' and not exists(
   select 1 from jsonb_array_elements(snapshot_meta->'branches') b where b->>'name'=p_branch))
 then raise insufficient_privilege using message='Unknown online product or branch';end if;
 select max(inv_date) into daily_end from public.sales_last_45_days;
 with branches as materialized (
  select b->>'name' branch_name from jsonb_array_elements(snapshot_meta->'branches') b
  where p_branch='' or b->>'name'=p_branch
 ), sales as (
  select to_date(h.month,'MM/YYYY') month_start,coalesce(h.online,0) qty
  from public.sales_history_2025 h join branches b using(branch_name)
  where btrim(h.item_code)=p_item_code and h.month ~ '^(0[1-9]|1[0-2])/2025$'
   and to_date(h.month,'MM/YYYY')<current_month
  union all
  select to_date(h.month,'MM/YYYY'),coalesce(h.online,0)
  from public.sales_history h join branches b using(branch_name)
  where btrim(h.item_code)=p_item_code and h.month ~ '^(0[1-9]|1[0-2])/(20[2-9][0-9])$'
   and to_date(h.month,'MM/YYYY')>=date '2026-01-01'
   and to_date(h.month,'MM/YYYY')<current_month
  union all
  select current_month,coalesce(sum(s.qty),0)
  from public.sales_last_45_days s
  where btrim(s.item_code)=p_item_code and s.inv_date between current_month and today
   and exists(select 1 from branches b where public._norm_text(b.branch_name)=public._norm_text(s.branch_name))
   and lower(btrim(coalesce(s.sales_type,''))) in ('delivery invoice','return delivery invoice')
   and lower(regexp_replace(btrim(coalesce(s.inv_type,'')), '[[:space:]]+', ' ', 'g'))
    not in ('insurance','direct insurance','dirict insurance')
 ), totals as (select month_start,sum(qty) qty from sales group by month_start)
 select coalesce(jsonb_agg(jsonb_build_object(
  'month',to_char(m.month_start,'MM/YYYY'),'total',coalesce(t.qty,0),
  'source',case when m.month_start=current_month then 'sales_last_45_days' else 'sales_history' end,
  'through',case when m.month_start=current_month then case when daily_end>=current_month then least(daily_end,today) end
    else (m.month_start+interval '1 month'-interval '1 day')::date end,
  'partial',m.month_start=current_month) order by m.month_start),'[]'::jsonb) into result
 from generate_series(date '2025-01-01',current_month,interval '1 month') m(month_start)
 left join totals t on t.month_start=m.month_start;
 return result;
end $$;
revoke all on function online_overview_preview_private.monthly_sales(text,text,text) from public,anon,authenticated,service_role;

-- recent_sales.sql
-- Signed online Qty; absent sales return 0. Access is checked by the shared account guard.
create or replace function online_overview_preview_private.recent_sales(p_generation text,p_item_code text,p_branch text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare snapshot_meta jsonb; stock_day date; first_day date; last_day date; sold numeric;
begin
 perform online_overview_private.assert_access();
 select meta into snapshot_meta from online_overview_private.state where singleton and generation=p_generation;
 if snapshot_meta is null or not online_overview_private.roster_is_allowed(snapshot_meta)
 then raise exception 'Online snapshot changed. Reload.' using errcode='40001'; end if;
 if not exists(select 1 from online_overview_private.items where generation=p_generation and item_code=p_item_code)
  or p_branch is null
  or (p_branch<>'' and not exists(select 1 from jsonb_array_elements(snapshot_meta->'branches') b where b->>'name'=p_branch))
 then raise insufficient_privilege using message='Unknown online product or branch'; end if;
 stock_day := (snapshot_meta->>'stock_day')::date;
 -- A moving sales import can start after this stock snapshot's 45-day window.
 -- Count the recorded online sales instead of hiding all product totals.
 -- No matching sales (including an empty import) means 0 Qty.
 select max(inv_date) into last_day from public.sales_last_45_days;
 last_day := coalesce(least(last_day,stock_day),stock_day);
 first_day := last_day-44;
 select coalesce(sum(s.qty),0) into sold from public.sales_last_45_days s
 join jsonb_array_elements(snapshot_meta->'branches') b
  on public._norm_text(s.branch_name)=public._norm_text(b->>'name')
 where s.inv_date between first_day and last_day and btrim(s.item_code)=p_item_code
   and (p_branch='' or b->>'name'=p_branch)
   and lower(btrim(coalesce(s.sales_type,''))) in ('delivery invoice','return delivery invoice')
   and lower(regexp_replace(btrim(coalesce(s.inv_type,'')), '[[:space:]]+', ' ', 'g'))
       not in ('insurance','direct insurance','dirict insurance');
 return jsonb_build_object('from',first_day,'through',last_day,'stock_day',stock_day,'qty',sold);
end $$;
revoke all on function online_overview_preview_private.recent_sales(text,text,text) from public,anon,authenticated,service_role;

-- restricted_user.sql
-- Explicit user-scoped Online Overview release, approved 2026-11-19.
-- System jobs keep service access; every authenticated client must match the
-- approved user AND the active Inventory role. No user_metadata authorization.
create or replace function online_overview_private.assert_access()
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')='service_role' or
    (coalesce(current_setting('request.jwt.claims',true),'')='' and session_user in ('postgres','service_role')) then
  return;
 end if;
 if auth.uid() is distinct from '94c7aa76-bc23-40e4-8c9a-f2cb9636c821'::uuid
    or coalesce(auth.role(),'')<>'authenticated'
    or not exists(select 1 from public.app_users u where u.user_id=auth.uid()
      and lower(btrim(u.role::text))='inventory' and u.is_active is true)
 then raise insufficient_privilege using message='Online Overview is not available for this account';end if;
end $$;
revoke all on function online_overview_private.assert_access() from public,anon,service_role;
grant execute on function online_overview_private.assert_access() to authenticated;
notify pgrst,'reload schema';


-- The scoped UI must never switch to an absent, stale or incomplete prepared generation.
do $$
declare base text; snap online_overview_preview_private.snapshot; items integer; branches integer;
begin
 select generation,(meta->>'items')::integer,jsonb_array_length(meta->'branches') into base,items,branches
 from online_overview_private.state where singleton;
 select * into snap from online_overview_preview_private.snapshot where singleton;
 if snap.generation is null or snap.base_generation is distinct from base
  or snap.meta#>>'{actual_sales,status}' is distinct from 'ready'
  or (select count(*) from online_overview_preview_private.rows where generation=snap.generation)<>items
  or (select count(*) from online_overview_preview_private.read_pages where generation=snap.generation)<>
     (branches+1)*ceil(items/5000.0)::integer
 then raise exception 'Online Overview prepared generation is not ready for the scoped rollout';end if;
end $$;
notify pgrst,'reload schema';
