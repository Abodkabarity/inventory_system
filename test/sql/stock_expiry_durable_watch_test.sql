-- Run as database owner. All fixture data, reviews and state changes roll back.
begin;
create temporary table expiry_watch_assertions(name text,passed boolean);
grant select,insert on expiry_watch_assertions to authenticated,anon;
do $$
declare v_today date := (now() at time zone 'Asia/Dubai')::date; v_start date;
begin
  select receipt_start into strict v_start from public.stock_expiry_watch_state where singleton;
  if exists(select 1 from public.mrn_apg_2026 where item_code='__expiry_watch_regression__') then
    raise exception 'Regression fixture already exists; do not overwrite it';
  end if;
  insert into public.mrn_apg_2026(item_code,item_name,status,warehouse,mrn_date,mrn_no,
    expiry_date,received_quantity,source_month,source_row_number)
  select '__expiry_watch_regression__','Expiry watch regression',
    case when n=6 then 'draft' else 'approved' end,
    case when n=7 then 'another warehouse' else 'store' end,
    case when n=1 then v_start-1 when n=2 then v_start when n=4 then v_today
      when n=5 then v_today+1 else v_today-1 end,
    'regression-'||n,
    case when n=8 then (v_today+interval '6 months')::date else v_today+60 end,
    case when n=9 then 0 else 10 end,date_trunc('month',v_today)::date,-2147480000+n
  from generate_series(1,9) n;
  perform stock_management_private.discover_expiry_receipts();
  if (select count(*) from public.stock_expiry_alert_receipts where item_code='__expiry_watch_regression__')<>2 then
    raise exception 'Date/warehouse/status/quantity/expiry boundary failed';
  end if;
  insert into expiry_watch_assertions values('only launch-week receipts through yesterday; strict six months, approved warehouses, positive quantity',true);
end;
$$;
select set_config('request.jwt.claims',jsonb_build_object('sub',
  (select au.user_id from public.app_users au join auth.users u on u.id=au.user_id
   where lower(btrim(au.role::text))='inventory' and au.is_active is not false limit 1),
  'role','authenticated')::text,true);
set local role authenticated;
do $$
declare a jsonb; saved jsonb; rejected boolean:=false;
begin
  perform public.refresh_stock_expiry_watch();
  select public.get_stock_expiry_item('__expiry_watch_regression__',(now() at time zone 'Asia/Dubai')::date+60) into a;
  if a is null then raise exception 'Inventory cannot read persistent alert'; end if;
  saved:=public.save_stock_expiry_review(a->>'item_code',(a->>'expiry_date')::date,
    a->>'receipt_fingerprint','Keep this note','review',null);
  if not (public.get_stock_expiry_item(a->>'item_code',(a->>'expiry_date')::date)->>'is_reviewed')::boolean then
    raise exception 'Review did not hide active alarm';
  end if;
  begin
    perform public.save_stock_expiry_review(a->>'item_code',(a->>'expiry_date')::date,
      a->>'receipt_fingerprint','Overwrite with stale version','note',null);
  exception when serialization_failure then rejected:=true;
  end;
  if not rejected then raise exception 'Stale review version was accepted'; end if;
  insert into expiry_watch_assertions values('inventory read/write, review state, note persistence and stale-version rejection',true);
end;
$$;
reset role;
do $$
declare a jsonb; v_today date:=(now() at time zone 'Asia/Dubai')::date;
begin
  -- Source replacement/removal and stock snapshot absence cannot erase evidence.
  delete from public.mrn_apg_2026 where item_code='__expiry_watch_regression__';
  perform stock_management_private.discover_expiry_receipts();
  select public.get_stock_expiry_item('__expiry_watch_regression__',v_today+60) into a;
  if a is null or a->>'note'<>'Keep this note' or not (a->>'is_reviewed')::boolean then
    raise exception 'Source removal erased alert or changed fingerprint';
  end if;
  insert into expiry_watch_assertions values('source deletion and absent snapshot preserve review, note and evidence',true);
  -- A newly detected receipt reactivates this date without losing the note.
  insert into public.stock_expiry_alert_receipts(item_code,expiry_date,mrn_date,mrn_no,warehouse,received_qty,product_data)
  values('__expiry_watch_regression__',v_today+60,v_today-1,'new-receipt','store',2,a->'product_data');
  select public.get_stock_expiry_item('__expiry_watch_regression__',v_today+60) into a;
  if (a->>'is_reviewed')::boolean or not (a->>'new_receipts')::boolean or a->>'note'<>'Keep this note' then
    raise exception 'New receipt failed to reopen with retained note';
  end if;
  -- Simulate evidence aging past the rolling week. The durable view has no
  -- receipt-date, current-stock or expiry-age condition.
  update public.stock_expiry_alert_receipts set mrn_date=v_today-30
    where item_code='__expiry_watch_regression__' and mrn_no='new-receipt';
  select public.get_stock_expiry_item('__expiry_watch_regression__',v_today+60) into a;
  if a is null or (a->>'is_reviewed')::boolean then raise exception 'Aged unresolved alert vanished'; end if;
  insert into expiry_watch_assertions values('new receipt reopens; unresolved evidence older than seven days stays visible',true);
end;
$$;
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
do $$
declare v_code text; v_expiry date; a jsonb;
begin
  select c.item_code,c.expiry_date into strict v_code,v_expiry
    from public.stock_expiry_candidates c where c.item_code<>'__expiry_watch_regression__'
    order by c.item_code limit 1;
  delete from public.stock_management_snapshot where item_code=v_code;
  select public.get_stock_expiry_item(v_code,v_expiry) into a;
  if a is null or not (a->>'stock_snapshot_missing')::boolean
    or not (a->'product_data' ? 'monthly_sales') or not (a->'product_data' ? 'branches') then
    raise exception 'Missing snapshot lost the complete saved Overview payload';
  end if;
  insert into expiry_watch_assertions values('missing live snapshot retains complete saved charts and branch facts',true);
end;
$$;
set local role authenticated;
do $$
declare rejected boolean:=false; a jsonb;
begin
  select public.get_stock_expiry_page() into a;
  if (a->>'total')::integer<>0 then raise exception 'Unauthorized session can read expiry register'; end if;
  begin perform public.refresh_stock_expiry_watch();
  exception when insufficient_privilege then rejected:=true;
  end;
  if not rejected then raise exception 'Unauthorized discovery accepted'; end if;
  insert into expiry_watch_assertions values('unauthorized authenticated session sees no rows and cannot discover',true);
end;
$$;
reset role;
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
do $$
declare rejected boolean:=false;
begin
  begin perform public.get_stock_expiry_page(); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Anonymous API access accepted'; end if;
  insert into expiry_watch_assertions values('anonymous access denied',true);
end;
$$;
reset role;
select jsonb_agg(to_jsonb(a)) as regression_results from expiry_watch_assertions a;
rollback;
