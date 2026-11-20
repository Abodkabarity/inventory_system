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
