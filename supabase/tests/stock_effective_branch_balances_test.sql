-- Rollback-only regression fixtures; no uploaded source data is retained.
begin;
do $test$
declare apg text; apg_fallback text; b71 text; run_day date;
begin
  select branch_name into apg from public.branches where is_active and branch_group='APG'
    and public._norm_text(branch_name) not in ('store','main virtual','new virtual','store - expired item','store-ws')
    order by branch_name limit 1;
  select branch_name into apg_fallback from public.branches where is_active and branch_group='APG'
    and branch_name<>apg and public._norm_text(branch_name) not in ('store','main virtual','new virtual','store - expired item','store-ws')
    order by branch_name limit 1;
  select branch_name into b71 from public.branches where is_active and branch_group='71' order by branch_name limit 1;
  select max(run_date) into run_day from public.daily_order;
  if apg is null or apg_fallback is null or b71 is null or run_day is null then
    raise exception 'Tests require uploaded orders and active APG/71 branches';
  end if;
  if exists(select 1 from public.daily_order where item_code like '__effective_stock_test_%')
    or exists(select 1 from public.stk_ledger where item_code like '__effective_stock_test_%') then
    raise exception 'Fixture codes already exist';
  end if;
  insert into public.stk_ledger(branch_name,item_code,actual_qty) values
    (apg,'__effective_stock_test_a',99),(apg_fallback,'__effective_stock_test_a',2),
    ('STORE','__effective_stock_test_a',10),(apg,'__effective_stock_test_c',5);
  insert into public.daily_order(run_date,branch,item_code,branch_stock,total_final_reorder_today,created_at) values
    (run_day,apg,'__effective_stock_test_a',0,4,now()),
    (run_day,' '||apg||' ',' __effective_stock_test_a ',1,5,now()-interval '1 hour'),
    (run_day-1,apg,'__effective_stock_test_a',0,900,now()),
    (run_day,b71,'__effective_stock_test_a',0,3,now()),
    (run_day,'STORE','__effective_stock_test_a',999,100,now()),
    (run_day,apg,'__effective_stock_test_b',-3,2,now()),
    (run_day,apg,'__effective_stock_test_c',null,2,now()),
    (run_day,apg,'__effective_stock_test_d',6,-2,now());
  create temporary table effective_fixture on commit drop as
    select * from stock_management_private.effective_stock_balances()
      where item_code like '__effective_stock_test_%';
  if (select count(*) from effective_fixture)<>7 then raise exception 'Duplicate or missing balances'; end if;
  if not exists(select 1 from effective_fixture where item_code='__effective_stock_test_a'
      and branch_key=public._norm_text(apg) and base_qty=0 and final_qty=4 and qty=4) then
    raise exception 'Zero-stock final reorder, latest run, Daily Order priority or duplicate normalization failed';
  end if;
  if not exists(select 1 from effective_fixture where item_code='__effective_stock_test_a'
      and branch_group='71' and qty=3) then raise exception 'Order-only group 71 branch omitted'; end if;
  if not exists(select 1 from effective_fixture where item_code='__effective_stock_test_a'
      and branch_key=public._norm_text(apg_fallback) and qty=2 and final_qty=0) then
    raise exception 'Missing Daily Order row must retain ledger stock'; end if;
  if not exists(select 1 from effective_fixture where branch_key='store' and qty=10 and final_qty=0) then
    raise exception 'STORE must remain its ledger quantity'; end if;
  if (select sum(qty) from effective_fixture where item_code='__effective_stock_test_a' and branch_key<>'store')<>9
    or (select count(*) from effective_fixture where item_code='__effective_stock_test_a' and branch_key<>'store' and qty>0)<>3 then
    raise exception 'Effective totals or stocked branch count failed'; end if;
  if not exists(select 1 from effective_fixture where item_code='__effective_stock_test_b' and qty=-1)
    or not exists(select 1 from effective_fixture where item_code='__effective_stock_test_c' and qty=7)
    or not exists(select 1 from effective_fixture where item_code='__effective_stock_test_d' and qty=6) then
    raise exception 'Signed stock, null stock fallback or negative allocation handling failed'; end if;
  if has_function_privilege('authenticated','stock_management_private.effective_stock_balances()','EXECUTE')
    or has_function_privilege('anon','stock_management_private.effective_stock_balances()','EXECUTE') then
    raise exception 'Internal source helper must not be callable by clients'; end if;
end;
$test$;
select 'zero stock, order-only branches, latest run, normalized duplicates, ledger fallback, STORE isolation, signed/null quantities and private helper passed' result;
rollback;
