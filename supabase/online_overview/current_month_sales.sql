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
 then raise exception 'Online snapshot changed. Reload.' using errcode='PT409';end if;
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
