// Real PostgreSQL fixture: October screenshot, Dubai month/year rollover,
// stale overlapping history, signed sales, branch totals, cache and permissions.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {PGlite}=require(process.env.STOCK_CACHE_PGLITE_MODULE||'@electric-sql/pglite');
(async()=>{
 const db=new PGlite();
 await db.exec(`
  create role anon; create role authenticated; create role service_role;
  create schema auth; create schema stock_management_private;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('test.uid',true),'')::uuid $$;
  create function public.item_tracker_my_role() returns text language sql stable as $$
    select current_setting('test.inventory_role',true) $$;
  create function public._norm_text(text) returns text language sql immutable as $$
    select lower(btrim(coalesce($1,''))) $$;
  create function public.fixture_now() returns timestamptz language sql stable as $$
    select current_setting('test.now')::timestamptz $$;
  create table item_report_apg(item_code text,item_name text,category text,supplier text,company text,
    item_status text,status text,is_block text,added_date_time timestamptz,created_at timestamptz,all_barcode jsonb);
  create table stock_catalog_snapshot(item_code text primary key,item_name text,category text,supplier text,
    total_stock numeric,days_on_hand numeric,sales_2026 numeric,demand_surge boolean,payload jsonb,updated_at timestamptz default now());
  create table branches(branch_name text,branch_group text,is_active boolean,branch_type text);
  create table stk_ledger(item_code text,branch_name text,actual_qty numeric,created_at timestamptz);
  create table sales_last_45_days(item_code text,branch_name text,inv_date date,qty numeric,
    sales_type text,inv_type text,customer_name text);
  create table sales_history(item_code text,branch_name text,month text,cash numeric,insurance numeric,online numeric);
  create table sales_history_2025(like sales_history);
  create table mrn_apg_2026(item_code text,mrn_date date,mrn_no text,status text,warehouse text,received_quantity numeric);
  create table daily_order(run_date date,item_code text,branch text,reorder_qty_num numeric,reorder_qty text,
    final_reorder_qty_store_stock_gt_0 text,reason text,tma_qty numeric,branch_formulary text);
  create table branch_formulary(item_code text,branch_name text,revised_branch_formulary text,
    revised_date date,created_at timestamptz,id bigint);
  grant usage on schema public to authenticated,anon,service_role;
  grant select on all tables in schema public to authenticated;
  alter table stock_catalog_snapshot enable row level security;
  create policy inventory_read on stock_catalog_snapshot for select to authenticated
    using ((select public.item_tracker_my_role())='inventory');
  insert into branches values ('Alpha','APG',true,'Retail'),('Beta','71',true,'Retail'),('Ghost','APG',false,'Retail');
  insert into item_report_apg(item_code,item_name,item_status,status,is_block,added_date_time,created_at)
    select code,code,'1#NORMAL PURCHASE','active','unchecked','2026-01-01','2026-10-01' from unnest(array['A','B','C']) code;
  insert into stk_ledger values ('A','STORE',416,now()),('A','Alpha',349,now()),('A','Beta',14,now());
  insert into sales_history_2025 values ('A','Alpha','01/2025',10,0,0);
  insert into sales_history values ('A','Alpha','09/2026',87,0,22),
    ('A','Alpha','10/2026',68,0,41),('A','Alpha','11/2026',999,0,0),
    ('A','Alpha','13/2026',999,0,0),('A','Alpha','bad date',999,0,0),
    ('B','Alpha','09/2026',20,0,0),('B','Alpha','10/2026',999,0,0);
  insert into sales_last_45_days values
    ('A','Alpha','2026-09-07',109,'POS Invoice','Cash',null),
    ('A','Alpha','2026-10-01',90,'POS Invoice','Cash',null),
    ('A','Beta','2026-10-01',10,'POS Invoice','Cash',null),
    ('A','Alpha','2026-10-02',40,'Delivery Invoice','Delivery (Online)',null),
    ('A','Alpha','2026-10-21',10,'POS Invoice','Insurance','National Health Insurance Company - Daman Basic'),
    ('A','Alpha','2026-10-21',-1,'Return POS Invoice','Cash',null),
    ('C','Ghost','2026-10-21',7,'POS Invoice','Cash',null);
  set request.jwt.claims='{"role":"service_role"}';
  set test.now='2026-10-22T06:00:00Z';
 `);
 await db.exec(fs.readFileSync('supabase/migrations/20261019125348_stock_catalog_fast_details_and_validated_memory_cache.sql','utf8'));
 const migration=fs.readFileSync('supabase/migrations/20261022095416_stock_catalog_current_month_from_daily_sales.sql','utf8');
 // Inject a deterministic test clock, never a production session override.
 await db.exec(migration.replaceAll('now()','public.fixture_now()'));
 const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const rebuild=()=>db.exec('select stock_management_private.refresh_catalog()');
 const product=code=>scalar('select payload from stock_catalog_snapshot where item_code=$1',[code]);
 const detail=code=>scalar('select public.get_stock_catalog_item($1)',[code]);
 const month=(p,m)=>p.monthly_sales.find(r=>r.month===m);
 await rebuild();
 const a=await product('A');
 assert.equal(a.recent_sales,258); assert.equal(a.total_stock,779);
 assert.equal(month(a,'09/2026').total,109);
 assert.equal(month(a,'09/2026').source,'sales_history');
 assert.deepEqual(month(a,'10/2026'),{cash:99,online:40,insurance:10,total:149,month:'10/2026',source:'sales_last_45_days',through:'2026-10-21'});
 assert.equal(a.years['2026'].total,258); assert.equal(a.years['2026'].best_month,'10/2026');
 assert.equal(a.years['2025'].total,10);
 assert.equal(month(a,'11/2026'),undefined,'future monthly history is not displayed');
 assert.equal(month(await product('B'),'10/2026').total,0,'missing daily sales never falls back to stale current-month history');
 assert.equal((await product('B')).years['2026'].total,20);
 const c=await product('C');
 assert.equal(c.recent_sales,0);assert.equal(month(c,'10/2026').total,7,'annual/monthly retain all-source scope');
 const d=await detail('A');
 assert.equal(d.branches.find(r=>r.branch==='Alpha').sales_2026,248);
 assert.equal(d.branches.find(r=>r.branch==='Beta').sales_2026,10);
 assert.equal(d.branches.find(r=>r.branch==='Beta').branch_group,'71');
 assert.equal('current_month_branch_sales' in d,false);
 const batch=await scalar('select public.get_stock_catalog_register_batch(0,5000)');
 assert.equal(batch.rows.some(r=>'current_month_branch_sales' in r),false);
 assert.equal(batch.rows.some(r=>'daily_sales_45d' in r),false);
 assert.equal((await scalar('select public.get_stock_catalog_item_if_changed($1,$2)',['A',d._cache_version]))._cache_not_modified,true);
 // Dubai November 1 while UTC still October 31: October now comes from history.
 await db.exec(`set test.now='2026-10-31T20:30:00Z';
  insert into sales_last_45_days values
   ('A','Alpha','2026-11-01',15,'POS Invoice','Cash',null),
   ('A','Alpha','2026-11-01',5,'Delivery Invoice','Delivery (Cash)',null),
   ('A','Alpha','2026-11-01',10,'POS Invoice','Direct Insurance','Other insurer'),
   ('A','Alpha','2026-11-01',-2,'Return POS Invoice','Cash',null);`);
 await rebuild();
 const nov=await product('A');
 assert.equal(nov.meta.monthly_current_month,'2026-11-01');
 assert.equal(month(nov,'10/2026').total,109);
 assert.equal(month(nov,'10/2026').source,'sales_history');
 assert.equal(month(nov,'11/2026').total,28);
 assert.equal(nov.years['2026'].total,246);
 const fresh=await scalar('select public.get_stock_catalog_item_if_changed($1,$2)',['A',d._cache_version]);
 assert.notEqual(fresh._cache_version,d._cache_version);
 assert.equal(fresh.branches.find(r=>r.branch==='Alpha').sales_2026,246);
 // January rollover includes the new year and closes December onto history.
 await db.exec(`set test.now='2026-12-31T20:30:00Z';
  insert into sales_history values ('A','Alpha','12/2026',50,0,0),('A','Alpha','01/2027',9999,0,0);
  insert into sales_last_45_days values ('A','Alpha','2027-01-01',8,'POS Invoice','Cash',null);`);
 await rebuild();
 const jan=await product('A');
 assert.equal(jan.meta.monthly_current_month,'2027-01-01');
 assert.equal(jan.meta.monthly_sales_through,'2027-01-01');
 assert.equal(month(jan,'12/2026').total,50);
 assert.equal(month(jan,'01/2027').total,8);
 assert.equal(jan.years['2027'].total,8);
 assert.equal((await detail('A')).branches.find(r=>r.branch==='Alpha').sales_2026,jan.years['2026'].total);
 // Stale raw dates must not choose the previous month as the current one.
 await db.exec("delete from sales_last_45_days where inv_date='2027-01-01'");
 await rebuild();
 const stale=await product('A');
 assert.equal(month(stale,'01/2027').total,0);
 assert.equal(stale.meta.monthly_current_through,null);
 // Access checks and conditional cache reuse still honor the inventory role.
 await db.exec("set test.uid='00000000-0000-0000-0000-000000000001'; set test.inventory_role='inventory'; set role authenticated");
 assert.equal((await detail('A')).item_code,'A');
 await db.exec("set test.inventory_role='branch'"); assert.equal(await detail('A'),null);
 await db.exec('reset role;set role anon');await assert.rejects(detail('A'),/permission denied/);
 await db.exec('reset role');await db.close();
 console.log('Monthly sources: screenshot 109+149=258, October/November/January rollover, no double counting, signed channels, group 71, cache and RLS passed.');
})().catch(error=>{console.error(error);process.exitCode=1;});
