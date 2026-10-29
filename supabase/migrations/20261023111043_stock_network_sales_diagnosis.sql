-- Product-scoped evidence, loaded after the dialog opens. No register queries
-- or raw source balances are changed. Forecast fitting runs in the pure client
-- domain layer; this endpoint only supplies audited, bounded observations.
create or replace function stock_management_private.network_sales_evidence(p_item_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; sales_day date; stock_day date; through_day date;
begin
  if coalesce(current_setting('request.jwt.claims',true),'')::text <> '' then
    if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','') <> 'service_role'
      and coalesce(public.item_tracker_my_role(),'') <> 'inventory'
      and not coalesce(stock_management_private.is_view_user(),false) then
      raise insufficient_privilege using message='Stock analysis requires Inventory or View access';
    end if;
  elsif session_user not in ('postgres','service_role') then
    raise insufficient_privilege using message='Stock analysis requires an authenticated session';
  end if;
  if nullif(btrim(p_item_code),'') is null or length(p_item_code)>100 then
    raise exception 'Invalid item code'; end if;
  select max(inv_date) into sales_day from public.sales_last_45_days;
  select (max(created_at) at time zone 'Asia/Dubai')::date into stock_day from public.stk_ledger;
  through_day:=least(sales_day,stock_day,(now() at time zone 'Asia/Dubai')::date-1);
  if through_day is null then return jsonb_build_object('status','awaiting_data'); end if;
  with roster as materialized (
    select branch_name,coalesce(branch_group,'APG') branch_group,
      case when branch_group='71' then '71 Pharmacy L.L.C.' else 'APG' end company
    from public.branches where is_active and public._norm_text(branch_name) not in
      ('store','main virtual','new virtual','store - expired item','store-ws')
    union all select 'STORE','STORE','APG'
  ), progress as materialized (
    select company, min(from_date) first_day,max(to_date) last_day,
      -- Gaps, overlaps and uncommitted imports cannot certify daily availability.
      bool_and(complete and committed_rows=expected_rows) and
      sum(to_date-from_date+1)=max(to_date)-min(from_date)+1 complete
    from public.stk_statement_history_load_progress group by company
  ), observations as materialized (
    select b.*, c.qty current_qty,c.n current_rows,o.qty opening_qty,o.n opening_rows,
      coalesce(h.net,0) archive_net,coalesce(h.bad,false) archive_bad,
      coalesce(h.days,'[]'::jsonb) archive_days,
      coalesce(t.net,0) rolling_net,coalesce(t.bad,false) rolling_bad,
      coalesce(t.days,'[]'::jsonb) rolling_days,
      coalesce(s.days,'[]'::jsonb) sales_days,
      pr.last_day archive_through,pr.complete and pr.first_day='2026-01-01'::date
        and (pr.last_day>=stock_day or (r.first_day<=pr.last_day+1 and r.last_day>=stock_day)) history_covered,
      (o.n=1 or (o.n=0 and exists(select 1 from public.stk_ledger_history oh
        where oh.branch_name=b.branch_name and oh.stock_date='2026-01-01'
          and oh.report_from_date=oh.stock_date and oh.report_to_date=oh.stock_date
          and not oh.source_branch_missing))) opening_report
    from roster b left join progress pr using(company)
    left join lateral (
      select min(trans_date) first_day,max(trans_date) last_day from public.stk_statement
      where branch_name=b.branch_name and coalesce(company,'APG')=b.company
    )r on true
    left join lateral (
      select count(*) n,sum(actual_qty) qty from public.stk_ledger
      where item_code=p_item_code and branch_name=b.branch_name
        and (company=b.company or (b.company='APG' and company='Al Ain Pharmacy Group (APG)'))
    )c on true
    left join lateral (
      select count(*) n,sum(actual_qty) qty from public.stk_ledger_history
      where item_code=p_item_code and branch_name=b.branch_name and stock_date='2026-01-01'
        and report_from_date=stock_date and report_to_date=stock_date and not source_branch_missing
        and (company=b.company or (b.company='APG' and company='Al Ain Pharmacy Group (APG)'))
    )o on true
    left join lateral (
      select sum(x.net) net,bool_or(x.bad) bad,jsonb_agg(to_jsonb(x) order by x.day) days
      from (select trans_date as day,sum(qty) net,sum(greatest(qty,0)) incoming,
        sum(-least(qty,0)) outgoing,bool_or(qty is null or
          (upper(mode)='IN' and qty<0) or (upper(mode)='OUT' and qty>0)) bad,
        bool_or(trans_type ilike '%adjust%') adjustment
        from public.stk_statement_history_2026 where branch_name=b.branch_name and item_code=p_item_code
          and company=b.company and trans_date>'2026-01-01'::date and trans_date<=least(pr.last_day,stock_day)
        group by trans_date)x
    )h on true
    left join lateral (
      select sum(x.net) net,bool_or(x.bad) bad,jsonb_agg(to_jsonb(x) order by x.day) days
      from (select trans_date as day,sum(qty) net,sum(greatest(qty,0)) incoming,sum(-least(qty,0)) outgoing,
        bool_or(qty is null or (upper(mode)='IN' and qty<0) or (upper(mode)='OUT' and qty>0)) bad,
        false adjustment
        from public.stk_statement where branch_name=b.branch_name and item_code=p_item_code
          and coalesce(company,'APG')=b.company and trans_date>pr.last_day and trans_date<=stock_day
        group by trans_date)x
    )t on true
    left join lateral (
      select jsonb_agg(to_jsonb(x) order by x.day) days from (
        select inv_date as day,sum(qty) qty,sum(greatest(qty,0)) gross_qty,sum(-least(qty,0)) return_qty,
          sum(qty) filter(where lower(inv_type) like '%insurance%') insurance_qty,
          sum(qty) filter(where lower(inv_type) not like '%insurance%' or inv_type is null) other_qty
        from public.sales_last_45_days where branch_name=b.branch_name and item_code=p_item_code
          and inv_date between through_day-44 and through_day group by inv_date)x
    )s on true
  ) select jsonb_build_object('status','ready','version','network-evidence-v1',
    'through',through_day,'stock_day',stock_day,'sales_day',sales_day,
    'from',through_day-44,'generated_at',now(),
    'branches',coalesce((select jsonb_agg(to_jsonb(x)) from (
      select branch_name,branch_group,current_qty,current_rows,coalesce(opening_qty,0) opening_qty,
        opening_rows=0 assumed_opening,
        coalesce(history_covered and opening_report and opening_rows<=1 and current_rows=1
          and not archive_bad and not rolling_bad
          and abs(coalesce(opening_qty,0)+archive_net+rolling_net-current_qty)<0.000001,false) reconciled,
        current_qty-(coalesce(opening_qty,0)+archive_net+rolling_net) variance_qty,
        archive_through,archive_days||rolling_days movements,sales_days
      from observations)x),'[]'::jsonb),
    'latest_mrn',(select to_jsonb(x) from (
      select mrn_date as day,sum(received_quantity) qty from public.mrn_apg_2026
      where item_code=p_item_code and lower(btrim(status))='approved' and lower(btrim(warehouse))='store'
        and mrn_date<=through_day group by mrn_date order by mrn_date desc limit 1)x),
    'scope','Active branches; physical stock only; orders are excluded') into result;
  return result;
end $$;
revoke all on function stock_management_private.network_sales_evidence(text) from public,anon;
grant execute on function stock_management_private.network_sales_evidence(text) to authenticated,service_role;
create or replace function public.get_stock_network_sales_evidence(p_item_code text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select stock_management_private.network_sales_evidence(p_item_code);
$$;
revoke all on function public.get_stock_network_sales_evidence(text) from public,anon;
grant execute on function public.get_stock_network_sales_evidence(text) to authenticated,service_role;
