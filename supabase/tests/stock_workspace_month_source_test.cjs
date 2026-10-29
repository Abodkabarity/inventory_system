// Local PostgreSQL/WASM regression suite. Set STOCK_CACHE_PGLITE_MODULE to an
// isolated installation of @electric-sql/pglite; no production DB is modified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');

(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create schema stock_management_private;
    create function public.item_tracker_my_role() returns text language sql stable
      as $$ select current_setting('test.inventory_role',true) $$;
    create function public._norm_text(text) returns text language sql immutable
      as $$ select lower(btrim(coalesce($1,''))) $$;
    create table public.stock_catalog_snapshot (
      item_code text primary key,item_name text default '',category text default '',
      supplier text default '',total_stock numeric default 0,days_on_hand numeric,
      sales_2026 numeric default 0,demand_surge boolean default false,payload jsonb not null,
      updated_at timestamptz default now());
    create table public.sales_history(item_code text,branch_name text,month text,cash numeric,insurance numeric,online numeric);
    create table public.sales_history_2025(like public.sales_history);
    create table public.branches(branch_name text,branch_group text,is_active boolean);
    grant usage on schema public to authenticated,anon,service_role;
    grant select on all tables in schema public to authenticated;
    alter table public.stock_catalog_snapshot enable row level security;
    create policy inventory_read on public.stock_catalog_snapshot for select to authenticated
      using ((select public.item_tracker_my_role())='inventory');
    insert into public.branches values ('Alpha','APG',true),('Beta','71',true),
      ('Ghost','APG',false),('STORE','STORE',true);
    insert into public.sales_history_2025 values
      (' A ',' alpha ','01/2025',10,2,1),('A','Alpha','02/2025',-2,0,0),
      ('A','Beta','03/2025',4,0,0),('A','Ghost','01/2025',500,0,0),
      ('A','Alpha','13/2025',999,0,0),('A','Alpha','01/2026',999,0,0);
    insert into public.sales_history values (' A ','alpha','01/2026',20,1,2),
      ('A','Beta','02/2026',-3,0,0),('A','Beta','14/2026',999,0,0);
  `);
  for (const code of ['A','B']) {
    await db.query(`insert into public.stock_catalog_snapshot(item_code,item_name,payload)
      values ($1,$1,$2::jsonb)`, [code, JSON.stringify({
      item_code: code, item_name: code, total_stock: 15, added_date_time: '2026-10-01',
      meta: {refreshed_at: 'snapshot-1'}, monthly_sales: [], years: {},
      branch_stock: {alpha: {stock: 10}, beta: {stock: 5}},
      branch_demand: {alpha: {recent_sales: 3,last_3_sales: 1,baseline_sales: 2}},
      distribution_orders: {alpha: {eligible: true,reorder_qty: 2,final_qty: 1}},
    })]);
  }
  const oldSource = fs.readFileSync('supabase/migrations/20261015094404_stock_catalog_new_product_distribution.sql','utf8');
  const old = oldSource.match(/CREATE OR REPLACE FUNCTION public\.get_stock_catalog_item\(.*?\$function\$;/s)[0];
  await db.exec(old);
  await db.exec(old.replace('public.get_stock_catalog_item(', 'public.stock_cache_test_reference('));
  await db.exec(`revoke all on function public.get_stock_catalog_item(text) from public,anon;
    grant execute on function public.get_stock_catalog_item(text) to authenticated,service_role;`);
  await db.exec(fs.readFileSync('supabase/migrations/20261019125348_stock_catalog_fast_details_and_validated_memory_cache.sql','utf8'));


  await db.exec(`
    create table public.stock_management_snapshot(
      item_code text primary key,last_mrn_date date,payload jsonb,item_name text default '',
      category text default '',supplier text default '',company text default '',total_stock numeric default 0,
      days_on_hand numeric,stock_status text default 'healthy',sales_2026 numeric default 0,updated_at timestamptz default now());
    create table public.mrn_apg_2026(item_code text,mrn_date date,mrn_no text,reference text,
      expiry_date date,ordered_quantity numeric,received_quantity numeric,status text,warehouse text,
      vendor text,item_name text,supplier text,company text,category_1 text);
    create table public.stock_expiry_alert_receipts(
      item_code text,expiry_date date,mrn_date date,mrn_no text,warehouse text,
      ordered_qty numeric,received_qty numeric,product_data jsonb,
      first_detected_at timestamptz default now(),last_changed_at timestamptz default now(),
      primary key(item_code,expiry_date,mrn_date,mrn_no,warehouse));
    create table public.stock_expiry_reviews(item_code text,expiry_date date,note text,
      updated_at timestamptz,reviewed_at timestamptz,is_reviewed boolean,reviewed_fingerprint text);
    create table public.item_report(item_code text,added_date_time timestamptz,created_at timestamptz);
    create table public.stock_expiry_watch_state(singleton boolean,receipt_start date,last_scanned_at timestamptz,scanned_through date);
    insert into public.stock_expiry_watch_state values(true,current_date-7,null,null);
    create function public.refresh_stock_expiry_watch() returns jsonb language sql as $$ select '{}'::jsonb $$;
    grant select on all tables in schema public to authenticated;
    alter table public.stock_management_snapshot enable row level security;
    create policy inventory_read on public.stock_management_snapshot for select to authenticated
      using ((select public.item_tracker_my_role())='inventory');
    insert into public.stock_management_snapshot(item_code,last_mrn_date,payload) values
      ('A',current_date-1,jsonb_build_object('item_code','A','item_name','Product A','total_stock',100,
       'store_stock',25,'branches_stock',75,'last_mrn_no','M1','last_mrn_qty',7,'meta','{}'::jsonb,'branches','[]'::jsonb));
    insert into public.mrn_apg_2026(item_code,mrn_date,mrn_no,reference,expiry_date,
      ordered_quantity,received_quantity,status,warehouse,vendor,item_name) values
      ('A',current_date-1,'M1','REF-1',current_date+40,12,7,'Approved','STORE','abcdefghijk-latest','Product A'),
      ('A',current_date-2,'OLD','OLD-REF',current_date+20,8,4,'Approved','STORE','older-vendor-name','Product A'),
      ('A',current_date-1,'M1','REF-1',current_date+40,99,99,'Rejected','STORE','BAD','Product A');
    insert into public.stock_expiry_alert_receipts(item_code,expiry_date,mrn_date,mrn_no,warehouse,
      ordered_qty,received_qty,product_data)
      select item_code,expiry_date,mrn_date,mrn_no,'store',ordered_quantity,received_quantity,
        (select payload from public.stock_management_snapshot where item_code='A')
      from public.mrn_apg_2026 where status='Approved';
    set test.inventory_role='inventory';
  `);
  const ordered = fs.readFileSync('supabase/migrations/20261009122950_near_expiry_ordered_quantity.sql','utf8');
  await db.exec(ordered.slice(ordered.indexOf('create or replace view public.stock_expiry_candidates')));
  await db.exec(fs.readFileSync('supabase/migrations/20261009145730_stock_management_branch_sales_totals.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261020105108_stock_workspaces_validated_cache_and_shared_details.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261020122615_stock_mrn_expiry_vendor_and_stock_share.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261020124301_stock_mrn_register_set_based_receipts.sql','utf8'));
  await db.exec(`
    create schema auth;
    create function auth.role() returns text language sql stable as $$
      select current_setting('test.auth_role',true) $$;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function public.fixture_now() returns timestamptz language sql stable as $$
      select current_setting('test.now')::timestamptz $$;
    create table public.stk_ledger(item_code text,branch_name text,actual_qty numeric,company text,created_at timestamptz);
    create table public.sales_last_45_days(item_code text,branch_name text,inv_date date,qty numeric,
      sales_type text,inv_type text,customer_name text);
    grant select on all tables in schema public to authenticated;
    set test.auth_role='service_role';
    set test.now='2026-10-22T06:00:00Z';
    truncate sales_history,sales_history_2025;
    insert into sales_history_2025 values ('A','Alpha','01/2025',10,0,0);
    insert into sales_history values
      ('A','Alpha','09/2026',87,0,22),('A','Alpha','10/2026',68,0,41),
      ('A','Alpha','11/2026',999,0,0),('A','Alpha','13/2026',999,0,0),
      ('A','Alpha','bad date',999,0,0),('ZERO','Alpha','10/2026',999,0,0),
      ('ORPHAN','Beta','09/2026',10,0,0),('ORPHAN','Beta','10/2026',999,0,0);
    insert into stk_ledger values
      ('A','STORE',416,'Company',now()),('A','Alpha',349,'Company',now()),
      ('A','Beta',14,'Company',now()),('A','Ghost',1000,'Company',now());
    insert into sales_last_45_days values
      ('A','Alpha','2026-09-07',109,'POS Invoice','Cash',null),
      ('A','Alpha','2026-10-01',90,'POS Invoice','Cash',null),
      ('A','Beta','2026-10-01',10,'POS Invoice','Cash',null),
      ('A','Alpha','2026-10-02',40,'Delivery Invoice','Delivery (Online)',null),
      ('A','Alpha','2026-10-21',10,'POS Invoice','Insurance','National Health Insurance Company - Daman Basic'),
      ('A','Alpha','2026-10-21',-1,'Return POS Invoice','Cash',null),
      ('ORPHAN','Beta','2026-10-21',7,'POS Invoice','Dirict Insurance','Other insurer'),
      ('OUTSIDE','Ghost','2026-10-21',12,'POS Invoice','Cash',null);
    insert into mrn_apg_2026(item_code,mrn_date,mrn_no,status,warehouse,item_name)
      values ('ZERO',current_date-1,'ZERO-MRN','Approved','STORE','No daily sales'),
        ('OUTSIDE',current_date-1,'OTHER-MRN','Approved','STORE','Inactive source sales');
    insert into stock_expiry_alert_receipts(item_code,expiry_date,mrn_date,mrn_no,warehouse,
      ordered_qty,received_qty,product_data) values
      ('ORPHAN',current_date+30,current_date-2,'REMOVED','store',10,8,
       '{"item_code":"ORPHAN","item_name":"Saved product","total_stock":15,"store_stock":5,
         "branches_stock":10,"branches":[{"branch":"Beta","stock":10,"sales_2026":999}],
         "meta":{"stock_updated_at":"2026-10-19","keep":"saved"},
         "monthly_sales":[{"month":"10/2026","total":999}],"years":{"2026":{"total":999}}}');
    insert into stock_expiry_reviews
      select item_code,expiry_date,'Keep review',now(),now(),true,receipt_fingerprint
      from stock_expiry_candidates where item_code='ORPHAN';
  `);
  const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0]??{})[0];
  const receipts=()=>db.query(`select to_jsonb(e)-'product_data' evidence
    from stock_expiry_alert_receipts e order by item_code,expiry_date,mrn_date,mrn_no,warehouse`);
  const review=()=>db.query('select * from stock_expiry_reviews order by item_code,expiry_date');
  const fingerprints=()=>db.query('select item_code,expiry_date,receipt_fingerprint from stock_expiry_candidates order by item_code,expiry_date');
  const evidenceBefore=await receipts(),reviewsBefore=await review(),fingerprintsBefore=await fingerprints();
  const versionBefore=await scalar('select public.get_stock_workspace_cache_state()');
  const migration=fs.readFileSync('supabase/migrations/20261022101225_stock_workspaces_current_month_from_daily_sales.sql','utf8');
  await db.exec(migration.replaceAll('now()','public.fixture_now()'));
  const rebuild=()=>scalar('select stock_management_private.refresh_snapshot()');
  const product=code=>scalar('select payload from stock_management_snapshot where item_code=$1',[code]);
  const detail=code=>scalar('select public.get_stock_management_product_details($1)',[code]);
  const month=(p,m)=>p.monthly_sales.find(r=>r.month===m);
  await rebuild();
  const a=await product('A');
  assert.equal(a.total_stock,779);assert.equal(a.recent_sales,258);
  assert.equal(month(a,'09/2026').total,109);
  assert.deepEqual(month(a,'10/2026'),{month:'10/2026',cash:99,online:40,insurance:10,total:149,source:'sales_last_45_days',through:'2026-10-21'});
  assert.equal(month(a,'11/2026'),undefined);
  assert.equal(a.years['2026'].total,258);assert.equal(a.years['2026'].best_month,'10/2026');
  assert.equal(Number(await scalar("select sales_2026 from stock_management_snapshot where item_code='A'")),258);
  assert.equal(month(await product('ZERO'),'10/2026').total,0);
  const outside=await product('OUTSIDE');
  assert.equal(outside.recent_sales,0);assert.equal(outside.years['2026'].total,12,'monthly scope retains all source branches');
  const mrn=await scalar("select public.get_stock_management_item('A')");
  assert.equal(mrn.branches.find(r=>r.branch==='Alpha').sales_2026,248);
  assert.equal(mrn.branches.find(r=>r.branch==='Beta').sales_2026,10);
  assert.equal('branch_year_sales' in mrn,false);
  // Catalog is deliberately stale: MRN table, shared dialog and branches agree.
  await db.exec(`update stock_catalog_snapshot set payload=payload||
    '{"monthly_sales":[{"month":"10/2026","total":9999}],"years":{"2026":{"total":9999}},
      "meta":{"monthly_current_source":"sales_last_45_days","monthly_current_month":"2026-09-01"}}'
    where item_code='A'`);
  const shared=await detail('A');
  assert.equal(shared.years['2026'].total,258);assert.equal(shared.mrn_details.years['2026'].total,258);
  assert.equal(shared.meta.monthly_current_month,'2026-10-01');
  assert.equal(shared.branches.find(r=>r.branch==='Alpha').sales_2026,248);
  assert.equal(shared.branches.find(r=>r.branch==='Beta').sales_2026,10);
  assert.equal(shared.branches.find(r=>r.branch==='Beta').branch_group,'71');
  assert.equal(shared.reference,'REF-1');assert.equal(shared.vendor,'ABCDEFGHIJ');
  assert.equal(shared.received_quantity,7);
  const fallback=await detail('ZERO');
  assert.equal(fallback.catalog_unavailable,true);assert.equal(month(fallback,'10/2026').total,0);
  assert.equal(fallback.mrn_details.last_mrn_no,'ZERO-MRN');
  const batch=await scalar('select public.get_stock_management_register_batch(0,5000)');
  assert.equal(batch.rows.find(r=>r.item_code==='A').years['2026'].total,258);
  assert.equal(batch.rows.some(r=>'branch_year_sales' in r),false);
  const page=await scalar("select public.get_stock_management_page(p_sort=>'sales_high',p_limit=>5000)");
  assert.equal(page.rows[0].item_code,'A');assert.equal(page.rows.some(r=>'branch_year_sales' in r),false);
  const expiry=await scalar("select public.get_stock_expiry_page(p_review_state=>'all',p_limit=>5000)");
  assert.equal(expiry.rows.find(r=>r.item_code==='A').product_data.years['2026'].total,258);
  assert.equal(expiry.rows.find(r=>r.item_code==='ORPHAN').product_data.years['2026'].total,17);
  assert.equal(expiry.rows.some(r=>'branch_year_sales' in r.product_data),false);
  const orphan=await scalar("select public.get_stock_expiry_item('ORPHAN',current_date+30)");
  assert.equal(orphan.stock_snapshot_missing,true);assert.equal(orphan.is_reviewed,true);
  assert.equal(orphan.note,'Keep review');assert.equal(orphan.product_data.total_stock,15);
  assert.equal(orphan.product_data.meta.keep,'saved');assert.equal(orphan.product_data.meta.stock_updated_at,'2026-10-19');
  assert.equal(month(orphan.product_data,'10/2026').insurance,7);
  assert.equal(orphan.product_data.branches[0].sales_2026,17);
  assert.equal(await product('ORPHAN'),undefined,'saved expiry sales do not create a spurious MRN product');
  assert.deepEqual(await receipts(),evidenceBefore);assert.deepEqual(await review(),reviewsBefore);
  assert.deepEqual(await fingerprints(),fingerprintsBefore);
  const version=await scalar('select public.get_stock_workspace_cache_state()');
  assert.notEqual(version.mrn,versionBefore.mrn);assert.notEqual(version.expiry,versionBefore.expiry);
  const cached=await scalar('select public.get_stock_workspace_cache_state()');
  assert.equal((await scalar('select public.get_stock_workspace_cache_state()')).details,cached.details);
  // Dubai November 1 at October 31 UTC: October closes onto monthly history.
  await db.exec(`set test.now='2026-10-31T20:30:00Z'; insert into sales_last_45_days values
    ('A','Alpha','2026-11-01',15,'POS Invoice','Cash',null),
    ('A','Alpha','2026-11-01',5,'Delivery Invoice','Delivery (Cash)',null),
    ('A','Alpha','2026-11-01',10,'POS Invoice','Direct Insurance','Other insurer'),
    ('A','Alpha','2026-11-01',-2,'Return POS Invoice','Cash',null);`);
  await rebuild();
  const nov=await product('A');
  assert.equal(nov.meta.monthly_current_month,'2026-11-01');
  assert.equal(month(nov,'10/2026').total,109);assert.equal(month(nov,'11/2026').total,28);
  assert.equal(nov.years['2026'].total,246);
  assert.equal((await detail('A')).branches.find(r=>r.branch==='Alpha').sales_2026,246);
  const newer=await scalar('select public.get_stock_workspace_cache_state()');
  assert.notEqual(newer.details,cached.details);
  assert.equal((await scalar("select public.get_stock_expiry_item('ORPHAN',current_date+30)")).product_data.years['2026'].total,1009);
  await db.exec(`set test.now='2026-12-31T20:30:00Z';
    insert into sales_history values ('A','Alpha','12/2026',50,0,0),('A','Alpha','01/2027',9999,0,0);
    insert into sales_last_45_days values ('A','Alpha','2027-01-01',8,'POS Invoice','Cash',null);`);
  await rebuild();
  const jan=await product('A');
  assert.equal(month(jan,'12/2026').total,50);assert.equal(month(jan,'01/2027').total,8);
  assert.equal(jan.years['2027'].total,8);assert.equal((await detail('A')).years['2027'].total,8);
  await db.exec("delete from sales_last_45_days where inv_date='2027-01-01'");
  await rebuild();
  assert.equal(month(await product('A'),'01/2027').total,0,'stale raw dates never substitute history for the current month');
  // An empty source rolls back both the snapshot and saved-analytics update.
  await db.exec('truncate mrn_apg_2026');
  const savedBefore=await db.query('select * from stock_expiry_alert_receipts order by item_code,expiry_date');
  const snapshotBefore=await db.query('select * from stock_management_snapshot order by item_code');
  const revisionsBefore=await scalar('select public.get_stock_workspace_cache_state()');
  await assert.rejects(rebuild,/No MRN products found/);
  assert.deepEqual(await db.query('select * from stock_expiry_alert_receipts order by item_code,expiry_date'),savedBefore);
  assert.deepEqual(await db.query('select * from stock_management_snapshot order by item_code'),snapshotBefore);
  assert.deepEqual(await scalar('select public.get_stock_workspace_cache_state()'),revisionsBefore);
  assert.equal(await scalar('show enable_nestloop'),'on');
  await db.exec(`alter table stock_expiry_alert_receipts enable row level security;
    create policy inventory_read on stock_expiry_alert_receipts for select to authenticated
      using ((select public.item_tracker_my_role())='inventory');
    set role authenticated; set test.inventory_role='branch'; set test.auth_role='authenticated';`);
  assert.equal(await detail('A'),null);
  assert.equal((await scalar('select public.get_stock_management_register_batch(0,5000)')).rows.length,0);
  assert.equal((await scalar("select public.get_stock_expiry_page(p_review_state=>'all',p_limit=>5000)")).rows.length,0);
  await assert.rejects(rebuild,/permission denied|Inventory access required/);
  await db.exec('reset role; set role anon');
  await assert.rejects(()=>detail('A'),/permission denied/);
  await db.close();
  console.log('MRN/Near month-source SQL passed: daily current month, completed history, annual/branch totals, shared and saved details, Dubai rollover, reviews/evidence, atomic rollback, cache, RLS and 5000-row limits.');
})().catch(error=>{console.error(error);process.exit(1);});
