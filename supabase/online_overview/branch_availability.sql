-- LOCAL ONLY. Small summary over the pinned, prepared online stock matrix.
-- This never reads sales sources, STORE or Retail stock.
create or replace function online_overview_private.branch_availability(p_generation text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare snapshot_meta jsonb; summaries jsonb; complete boolean;
begin
 perform online_overview_private.assert_access();
 select meta into snapshot_meta from online_overview_private.state
 where singleton and generation=p_generation;
 if snapshot_meta is null or not online_overview_private.roster_is_allowed(snapshot_meta)
 then raise exception 'Online snapshot changed. Reload.' using errcode='PT409';end if;
 with branches as materialized (
  select b->>'name' branch from jsonb_array_elements(snapshot_meta->'branches') b
 ), ranks as (select unnest(array['a','b','c']) rank),
 totals as materialized (
  select payload->>'rank' rank,count(*) total from online_overview_private.classification
  where generation=p_generation and payload->>'rank' in ('a','b','c') group by 1
 ), counts as materialized (
  select r.branch,c.payload->>'rank' rank,count(*) observed,
   count(*) filter(where (r.payload->>'online_stock')::numeric>0) available,
   count(*) filter(where r.payload->>'online_stock' is null) unknown
  from online_overview_private.results r join online_overview_private.classification c
    on c.generation=r.generation and c.item_code=r.item_code
  join branches b on b.branch=r.branch
  where r.generation=p_generation and r.scope='onlineOnly' and c.payload->>'rank' in ('a','b','c')
  group by r.branch,c.payload->>'rank'
 ), facts as (
  select b.branch,k.rank,coalesce(t.total,0) total,coalesce(c.observed,0) observed,
   coalesce(c.available,0) available,coalesce(c.unknown,0) unknown
  from branches b cross join ranks k left join totals t using(rank)
  left join counts c on c.branch=b.branch and c.rank=k.rank
 ) select bool_and(observed=total),jsonb_agg(jsonb_build_object(
   'branch_name',branch,'rank',rank,'total',total,'available',available,'unknown',unknown
  ) order by branch,rank) into complete,summaries from facts;
 if complete is distinct from true then raise exception 'Incomplete online availability snapshot';end if;
 return jsonb_build_object('generation',p_generation,'stock_day',snapshot_meta->'stock_day','rows',summaries);
end $$;
revoke all on function online_overview_private.branch_availability(text) from public,anon,service_role;
grant execute on function online_overview_private.branch_availability(text) to authenticated;

create or replace function public.get_local_online_overview_availability(p_generation text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select online_overview_private.branch_availability(p_generation)
$$;
revoke all on function public.get_local_online_overview_availability(text) from public,anon,service_role;
grant execute on function public.get_local_online_overview_availability(text) to authenticated;
notify pgrst,'reload schema';
