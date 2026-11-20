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
