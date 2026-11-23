create or replace function online_overview_private.stock_breakdown(p_generation text,p_item_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; snapshot_meta jsonb;
begin
 perform online_overview_private.assert_access();
 select meta into snapshot_meta from online_overview_private.state where singleton and generation=p_generation;
 if snapshot_meta is null or not online_overview_private.roster_is_allowed(snapshot_meta)
 then raise exception 'Online snapshot changed. Reload.' using errcode='PT409'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('branch_name',branch,
   'stock',(payload->>'online_stock')::numeric,'stocked_days',(payload->>'stocked_days')::integer,
   'sales_2025',payload->'sales25','sales_2026',payload->'sales26',
   'recent_sales',payload->'recent_qty','history_through',snapshot_meta->'history_through',
   'reported',payload->>'online_stock' is not null) order by branch),'[]') into result
 from online_overview_private.results where generation=p_generation and scope='onlineOnly'
   and item_code=p_item_code and exists(select 1 from jsonb_array_elements(snapshot_meta->'branches') b where b->>'name'=branch);
 return result;
end $$;
revoke all on function online_overview_private.stock_breakdown(text,text) from public,anon;
grant execute on function online_overview_private.stock_breakdown(text,text) to authenticated;
create or replace function public.get_local_online_overview_stock(p_generation text,p_item_code text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select online_overview_private.stock_breakdown(p_generation,p_item_code) $$;
revoke all on function public.get_local_online_overview_stock(text,text) from public,anon;
grant execute on function public.get_local_online_overview_stock(text,text) to authenticated;

create or replace function online_overview_private.monthly_sales(p_generation text,p_item_code text,p_branch text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare snapshot_meta jsonb;
declare cutoff date;
declare result jsonb;
begin
 perform online_overview_private.assert_access();
 select meta into snapshot_meta from online_overview_private.state where singleton and generation=p_generation;
 if snapshot_meta is null or not online_overview_private.roster_is_allowed(snapshot_meta) then
  raise exception 'Online snapshot changed. Reload.' using errcode='PT409';
 end if;
 if not exists(select 1 from online_overview_private.items where generation=p_generation and item_code=p_item_code)
  or p_branch is null
  or (p_branch<>'' and not exists(select 1 from jsonb_array_elements(snapshot_meta->'branches') b where b->>'name'=p_branch))
 then raise insufficient_privilege using message='Unknown online product or branch'; end if;
 cutoff := (snapshot_meta->>'classification_through')::date;
 with branches as (
  select b->>'name' branch_name from jsonb_array_elements(snapshot_meta->'branches') b
  where p_branch='' or b->>'name'=p_branch
 ), sales as (
  select to_date(h.month,'MM/YYYY') month_start,h.online qty
  from public.sales_history_2025 h join branches b using(branch_name)
  where btrim(h.item_code)=p_item_code and h.month ~ '^(0[1-9]|1[0-2])/2025$'
  union all
  select to_date(h.month,'MM/YYYY'),h.online
  from public.sales_history h join branches b using(branch_name)
  where btrim(h.item_code)=p_item_code and h.month ~ '^(0[1-9]|1[0-2])/2026$'
 ), totals as (
  select month_start,sum(qty) qty from sales group by month_start
 )
 select coalesce(jsonb_agg(jsonb_build_object('month',to_char(m.month_start,'MM/YYYY'),
   'total',coalesce(t.qty,0)) order by m.month_start),'[]') into result
 from generate_series(date '2025-01-01',date_trunc('month',cutoff),interval '1 month') m(month_start)
 left join totals t on t.month_start=m.month_start;
 return result;
end $$;
revoke all on function online_overview_private.monthly_sales(text,text,text) from public,anon,service_role;
grant execute on function online_overview_private.monthly_sales(text,text,text) to authenticated;
create or replace function public.get_local_online_overview_monthly_sales(p_generation text,p_item_code text,p_branch text default '')
returns jsonb language sql stable security invoker set search_path='' as $$
 select online_overview_private.monthly_sales(p_generation,p_item_code,p_branch) $$;
revoke all on function public.get_local_online_overview_monthly_sales(text,text,text) from public,anon;
grant execute on function public.get_local_online_overview_monthly_sales(text,text,text) to authenticated;

create or replace function online_overview_private.recent_sales(p_generation text,p_item_code text,p_branch text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare snapshot_meta jsonb; stock_day date; first_day date; last_day date; sold numeric;
begin
 perform online_overview_private.assert_access();
 select meta into snapshot_meta from online_overview_private.state where singleton and generation=p_generation;
 if snapshot_meta is null or not online_overview_private.roster_is_allowed(snapshot_meta)
 then raise exception 'Online snapshot changed. Reload.' using errcode='PT409'; end if;
 if not exists(select 1 from online_overview_private.items where generation=p_generation and item_code=p_item_code)
  or p_branch is null
  or (p_branch<>'' and not exists(select 1 from jsonb_array_elements(snapshot_meta->'branches') b where b->>'name'=p_branch))
 then raise insufficient_privilege using message='Unknown online product or branch'; end if;
 stock_day := (snapshot_meta->>'stock_day')::date;
 select min(inv_date),max(inv_date) into first_day,last_day from public.sales_last_45_days;
 last_day := least(last_day,stock_day);
 if first_day is null or stock_day is null or first_day>last_day-44 then
  return jsonb_build_object('stock_day',stock_day,'qty',null);
 end if;
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
revoke all on function online_overview_private.recent_sales(text,text,text) from public,anon,service_role;
grant execute on function online_overview_private.recent_sales(text,text,text) to authenticated;
create or replace function public.get_local_online_overview_recent_sales(p_generation text,p_item_code text,p_branch text default '')
returns jsonb language sql stable security invoker set search_path='' as $$
 select online_overview_private.recent_sales(p_generation,p_item_code,p_branch) $$;
revoke all on function public.get_local_online_overview_recent_sales(text,text,text) from public,anon;
grant execute on function public.get_local_online_overview_recent_sales(text,text,text) to authenticated;
notify pgrst,'reload schema';
