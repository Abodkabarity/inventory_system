-- LOCAL ONLY. Only a product total leaves this private aggregate; no retail
-- branch identity or individual balance is returned by the Online page RPCs.
create or replace function online_overview_private.other_branch_stock(p_stock_day date)
returns table(item_code text,qty numeric)
language sql stable security definer set search_path='' as $$
 with balances as (
  select btrim(l.item_code) item_code,l.branch_name,
   case when count(*)=1 and bool_and(l.actual_qty is not null
      and (l.created_at at time zone 'Asia/Dubai')::date=p_stock_day
      and (l.company=case when b.branch_group='71' then '71 Pharmacy L.L.C.' else 'APG' end
        or (coalesce(b.branch_group,'APG')<>'71' and l.company='Al Ain Pharmacy Group (APG)')))
     then sum(l.actual_qty) else 0 end qty
  from public.stk_ledger l join public.branches b on b.branch_name=l.branch_name
  where b.is_active and lower(btrim(b.branch_type))='retail'
  group by btrim(l.item_code),l.branch_name
 ) select item_code,coalesce(sum(qty),0) from balances group by item_code
$$;
revoke all on function online_overview_private.other_branch_stock(date)
 from public,anon,authenticated,service_role;
