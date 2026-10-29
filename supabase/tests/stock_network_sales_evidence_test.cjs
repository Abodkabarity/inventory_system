const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');
(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema stock_management_private;
    grant usage on schema stock_management_private,public to authenticated,service_role;
    create function public.item_tracker_my_role() returns text language sql as
      $$select current_setting('test.role',true)$$;
    create function stock_management_private.is_view_user() returns boolean language sql as
      $$select current_setting('test.role',true)='view'$$;
    create function public._norm_text(text) returns text language sql immutable as $$select lower(btrim($1))$$;
    create table public.branches(branch_name text,branch_group text,is_active boolean);
    create table public.stk_ledger(item_code text,branch_name text,company text,actual_qty numeric,created_at timestamptz);
    create table public.stk_ledger_history(item_code text,branch_name text,company text,actual_qty numeric,
      stock_date date,report_from_date date,report_to_date date,source_branch_missing boolean);
    create table public.stk_statement_history_load_progress(company text,from_date date,to_date date,
      complete boolean,committed_rows integer,expected_rows integer);
    create table public.stk_statement_history_2026(branch_name text,item_code text,trans_date date,company text,
      qty numeric,mode text,trans_type text);
    create table public.stk_statement(branch_name text,item_code text,trans_date date,company text,qty numeric,mode text);
    create table public.sales_last_45_days(branch_name text,item_code text,inv_date date,qty numeric,inv_type text);
    create table public.mrn_apg_2026(item_code text,mrn_date date,received_quantity numeric,status text,warehouse text);
    create table public.daily_order(item_code text,branch text,run_date date,branch_stock numeric,
      extra_qty_more_than_month numeric,demand_for_30_days numeric,reorder_max numeric,reorder_qty text,
      final_reorder_qty_store_stock_gt_0 text,pending_stock_received numeric,assortment_qty_base_stock numeric,
      item_minimum_order_unit numeric,total_sales_last_90_days numeric,branch_formulary text);
    insert into public.daily_order values ('A','Alpha','2026-10-23',8,3,1,0,'0','0',0,0,1,3,'SALES'),
      ('A','Alpha','2026-10-22',9,4,1,0,'0','0',0,0,1,3,'SALES');
    insert into public.branches values ('Alpha','APG',true),('Beta','71',true),('STORE','STORE',true),('Ghost','APG',false);
    insert into public.stk_ledger values ('A','Alpha','APG',8,'2026-10-22 16:00Z'),
      ('A','Beta','71 Pharmacy L.L.C.',3,'2026-10-22 16:00Z'),('A','STORE','APG',0,'2026-10-22 16:00Z');
    insert into public.stk_ledger_history values
      ('A','Alpha','APG',10,'2026-01-01','2026-01-01','2026-01-01',false),
      ('A','Beta','71 Pharmacy L.L.C.',4,'2026-01-01','2026-01-01','2026-01-01',false),
      ('A','STORE','APG',0,'2026-01-01','2026-01-01','2026-01-01',false);
    insert into public.stk_statement_history_load_progress values
      ('APG','2026-01-01','2026-10-21',true,1,1),
      ('71 Pharmacy L.L.C.','2026-01-01','2026-10-21',true,1,1);
    insert into public.stk_statement_history_2026 values
      ('Alpha','A','2026-10-20','APG',-2,'Out','Sales'),
      ('Beta','A','2026-10-20','71 Pharmacy L.L.C.',-1,'Out','Sales');
    insert into public.stk_statement values ('Alpha','A','2026-10-20',null,-2,'Out'),
      ('Alpha','OTHER','2026-10-22',null,1,'IN'),
      ('Beta','OTHER','2026-10-22','71 Pharmacy L.L.C.',1,'IN');
    insert into public.sales_last_45_days values ('Alpha','A','2026-10-22',2,'Cash'),
      ('Ghost','A','2026-10-22',999,'Cash'),('Beta','A','2026-10-22',1,'Insurance');
    insert into public.mrn_apg_2026 values ('A','2026-10-03',6,'Approved','STORE'),
      ('A','2026-10-03',4,'Approved','STORE'),('A','2026-10-10',999,'Rejected','STORE'),
      ('A','2026-10-20',999,'Approved','Main Virtual');
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261023111043_stock_network_sales_diagnosis.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261023111930_stock_network_evidence_snapshot_alignment.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261023114734_stock_network_mrn_source_scope.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261023115146_stock_network_branch_extra_redistribution.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261023120533_stock_network_latest_receipt_metadata.sql','utf8'));
  await db.exec(`set request.jwt.claims='{"role":"authenticated"}'; set test.role='inventory'; set role authenticated;`);
  const read = async () => (await db.query(`select public.get_stock_network_sales_evidence('A') result`)).rows[0].result;
  let r = await read();
  assert.equal(r.status,'ready'); assert.equal(r.branches.length,3);
  assert.equal(r.daily_order_day,'2026-10-23');assert.equal(r.daily_order_rows.length,1);
  assert.equal(r.daily_order_rows[0].extra_qty_more_than_month,3);
  const alpha = r.branches.find(b=>b.branch_name==='Alpha');
  assert.equal(alpha.reconciled,true); assert.equal(alpha.movements.length,1,'overlap is not counted twice');
  assert.equal(r.branches.find(b=>b.branch_name==='Beta').reconciled,true);
  assert.equal(r.latest_mrn.qty,999,'approved virtual receipts belong to STORE supply too');
  assert.equal(r.latest_mrn.day,'2026-10-20');
  assert.equal(r.latest_mrn_movement_qty,null,'physical MRN ledger absence does not invalidate virtual receipts');
  await db.exec(`reset role;
    insert into public.mrn_apg_2026 values (' A ','2026-10-20',1,'Approved','New Virtual'),
      ('A','2026-10-20',2,'Approved','STORE');
    set role authenticated;`);
  assert.equal((await read()).latest_mrn.qty,1002,'sum the complete latest receipt day across warehouse routes');
  await db.exec(`reset role;
    insert into public.mrn_apg_2026 values('A',(now() at time zone 'Asia/Dubai')::date,42,'Approved','New Virtual');
    set role authenticated;`);
  assert.equal((await read()).latest_mrn.qty,42,'new receipt metadata is not hidden behind the older sales cutoff');
  await db.exec(`reset role; update public.stk_ledger set actual_qty=7 where branch_name='Alpha'; set role authenticated;`);
  r=await read(); assert.equal(r.branches.find(b=>b.branch_name==='Alpha').reconciled,false);
  await db.exec(`reset role;
    delete from public.stk_ledger where item_code='A' and branch_name='Beta';
    insert into public.stk_ledger values ('OTHER','Beta','71 Pharmacy L.L.C.',1,'2026-10-22 16:00Z');
    update public.stk_statement_history_2026 set qty=-4 where branch_name='Beta';
    set role authenticated;`);
  r=await read();
  const beta=r.branches.find(b=>b.branch_name==='Beta');
  assert.equal(beta.current_qty,0);assert.equal(beta.current_assumed_zero,true);
  assert.equal(beta.branch_group,'71');assert.equal(beta.reconciled,true);
  await db.exec(`reset role;
    update public.stk_ledger_history set report_from_date=null where branch_name='Beta';
    set role authenticated;`);
  assert.equal((await read()).branches.find(b=>b.branch_name==='Beta').reconciled,false,
    'malformed opening is not reinterpreted as an omitted zero opening');
  await db.exec(`set test.role='view';`); assert.equal((await read()).status,'ready');
  await db.exec(`set test.role='branch';`); await assert.rejects(read,/requires Inventory or View/);
  await db.exec(`reset role; set role anon;`); await assert.rejects(read,/permission denied/);
  await db.close(); console.log('Network sales evidence: PASS');
})().catch(e=>{console.error(e.message);process.exit(1);});
