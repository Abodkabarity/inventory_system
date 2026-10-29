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
  await db.exec(fs.readFileSync('supabase/migrations/20261022101225_stock_workspaces_current_month_from_daily_sales.sql','utf8').replaceAll('now()','public.fixture_now()'));
  await db.exec(fs.readFileSync('supabase/migrations/20261022114605_stock_mrn_complete_receipt_totals.sql','utf8').replaceAll('now()','public.fixture_now()'));
  await db.exec(`
    insert into stk_ledger values ('FOUR','STORE',230,'Company',now()),('FOUR','Beta',3,'Company',now());
    insert into mrn_apg_2026(item_code,mrn_date,mrn_no,reference,expiry_date,
      ordered_quantity,received_quantity,status,warehouse,vendor,item_name) values
      ('FOUR','2026-10-21','106402','REF-402','2028-09-01',15,15,'approved','STORE','unicare medical trading l.l.c','Example'),
      ('FOUR','2026-10-21','106403','REF-403','2028-09-01',300,100,'approved','STORE','unicare medical trading l.l.c','Example'),
      (' FOUR ','2026-10-21','106430','REF-430','2028-09-01',15,15,'approved','STORE','unicare medical trading l.l.c','Example'),
      ('FOUR','2026-10-21','106431','REF-431','2028-09-01',300,100,'approved','STORE','unicare medical trading l.l.c','Example'),
      ('FOUR','2026-10-20','OLD','OLD-REF','2028-02-01',999,999,'approved','STORE','Old vendor','Example'),
      ('FOUR','2026-10-22','REJECTED','BAD','2028-02-01',9999,9999,'rejected','STORE','Bad vendor','Example'),
      ('FOUR','2026-10-22','BRANCH','BAD','2028-02-01',9999,9999,'approved','Beta','Bad vendor','Example'),
      ('MULTI','2026-10-21','SAME','REF-1','2027-02-01',10,10,'approved','STORE','vendor','Multiple expiry'),
      ('MULTI','2026-10-21','SAME','REF-2','2027-03-01',20,20,'approved','NEW VIRTUAL','vendor','Multiple expiry'),
      ('MULTI','2026-10-21','SAME','REF-3',null,5,5,'approved','STORE','vendor','Multiple expiry'),
      ('MULTI','2026-10-21','SAME','REF-1','2027-02-01',0,-2,'approved','STORE','vendor','Multiple expiry');
    insert into mrn_apg_2026(item_code,mrn_date,mrn_no,reference,expiry_date,
      ordered_quantity,received_quantity,status,warehouse,vendor,item_name)
      select 'NEAR',mrn_date,mrn_no,reference,'2027-02-01',ordered_quantity,received_quantity,status,warehouse,vendor,'Near example'
      from mrn_apg_2026 where btrim(item_code)='FOUR' and mrn_date='2026-10-21';
    insert into mrn_apg_2026(item_code,mrn_date,mrn_no,reference,expiry_date,
      ordered_quantity,received_quantity,status,warehouse,vendor,item_name) values
      ('NEAR','2026-10-20','OLDER','REF-OLD','2027-02-01',9,9,'approved','MAIN VIRTUAL','vendor','Near example'),
      ('NEAR','2026-10-21','106431','REF-OTHER','2027-03-01',40,40,'approved','NEW VIRTUAL','vendor','Near example');
  `);
  const rebuild=()=>scalar('select stock_management_private.refresh_snapshot()');
  const item=code=>scalar('select public.get_stock_management_item($1)',[code]);
  const shared=code=>scalar('select public.get_stock_management_product_details($1)',[code]);
  await rebuild();
  assert.equal((await item('A')).years['2026'].total,258,'receipt aggregation preserves the monthly source correction');
  const four=await item('FOUR');
  assert.equal(four.last_mrn_qty,230);assert.equal(four.received_quantity,230);
  assert.equal(four.ordered_quantity,630);assert.equal(four.receipt_count,4);
  assert.equal(four.expiry_count,1);assert.equal(four.expiry_date,'2028-09-01');
  assert.equal(four.total_stock,233);assert.equal(four.store_stock,230);assert.equal(four.branches_stock,3);
  assert.equal(four.reference,'REF-431');assert.equal(four.vendor,'UNICARE ME');
  assert.equal(four.receipt_lines.length,4);assert.equal(four.receipt_lines.reduce((n,r)=>n+r.received_qty,0),230);
  assert.deepEqual(four.receipt_lines.map(r=>r.reference),['REF-431','REF-430','REF-403','REF-402']);
  assert.equal(four.receipt_lines.some(r=>['OLD','REJECTED','BRANCH'].includes(r.mrn_no)),false);
  const fallback=await shared('FOUR');
  assert.equal(fallback.catalog_unavailable,true);assert.equal(fallback.received_quantity,230);
  assert.equal(fallback.mrn_details.receipt_lines.length,4);
  // Catalog enrichment cannot overwrite the receipt totals used by the cards.
  await db.query(`insert into stock_catalog_snapshot(item_code,item_name,payload) values('FOUR','Example',$1::jsonb)`,[
    JSON.stringify({...four,receipt_lines:undefined,received_quantity:999,last_mrn_qty:999,
      branch_stock:{beta:{stock:3}},branch_demand:{},distribution_orders:{}})]);
  const unified=await shared('FOUR');
  assert.equal(unified.received_quantity,230);assert.equal(unified.last_mrn_qty,230);
  assert.equal(unified.mrn_details.received_quantity,230);assert.equal(unified.mrn_details.last_mrn_qty,230);
  assert.equal(unified.mrn_details.receipt_lines.length,4);assert.equal(unified.reference,'REF-431');
  const batch=await scalar('select public.get_stock_management_register_batch(0,5000)');
  const listFour=batch.rows.find(r=>r.item_code==='FOUR');
  assert.equal(listFour.received_quantity,230);assert.equal(listFour.last_mrn_qty,230);assert.equal(listFour.ordered_quantity,630);
  assert.equal(listFour.receipt_count,4);assert.equal('receipt_lines' in listFour,false);
  const page=await scalar("select public.get_stock_management_page(p_search=>'FOUR',p_limit=>5000)");
  assert.equal(page.rows[0].received_quantity,230);assert.equal(page.rows[0].receipt_count,4);
  const multi=await item('MULTI');
  assert.equal(multi.received_quantity,33);assert.equal(multi.ordered_quantity,35);
  assert.equal(multi.receipt_count,1);assert.equal(multi.expiry_count,2);
  assert.equal(multi.receipt_lines.length,3);assert.equal(multi.receipt_lines.find(r=>r.expiry_date==='2027-02-01').received_qty,8);
  assert.equal(batch.rows.find(r=>r.item_code==='MULTI').received_quantity,33,'null expiry and signed returns are retained');
  await scalar('select stock_management_private.discover_expiry_receipts()');
  const near=await scalar("select public.get_stock_expiry_item('NEAR','2027-02-01')");
  assert.equal(near.received_qty,239);assert.equal(near.ordered_qty,639);
  assert.equal(near.receipt_count,5);assert.equal(near.receipts.length,5);
  assert.equal(near.receipts.reduce((n,r)=>n+r.received_qty,0),239);
  const nearOther=await scalar("select public.get_stock_expiry_item('NEAR','2027-03-01')");
  assert.equal(nearOther.received_qty,40);assert.equal(nearOther.receipt_count,1);
  assert.equal((await item('NEAR')).received_quantity,270,'MRN is latest receipt day; expiry is per expiry date across all saved days');
  const nearPage=await scalar("select public.get_stock_expiry_page(p_search=>'NEAR',p_review_state=>'all',p_limit=>5000)");
  assert.equal(nearPage.rows.find(r=>r.expiry_date==='2027-02-01').received_qty,239);
  const before=await scalar('select public.get_stock_workspace_cache_state()');
  await db.query(`insert into stock_expiry_reviews values('NEAR','2027-02-01','Keep note',now(),now(),true,$1)`,[near.receipt_fingerprint]);
  await scalar('select stock_management_private.discover_expiry_receipts()');
  const repeated=await scalar("select public.get_stock_expiry_item('NEAR','2027-02-01')");
  assert.equal(repeated.received_qty,239,'rediscovery never adds the same receipts twice');
  assert.equal(repeated.is_reviewed,true);assert.equal(repeated.note,'Keep note');
  assert.equal(repeated.receipt_fingerprint,near.receipt_fingerprint);
  await db.exec("update mrn_apg_2026 set received_quantity=101 where item_code='NEAR' and mrn_no='106431' and warehouse='STORE'");
  await scalar('select stock_management_private.discover_expiry_receipts()');
  const changed=await scalar("select public.get_stock_expiry_item('NEAR','2027-02-01')");
  assert.equal(changed.received_qty,240);assert.equal(changed.is_reviewed,false);assert.equal(changed.note,'Keep note');
  assert.equal(changed.new_receipts,true);
  assert.notEqual((await scalar('select public.get_stock_workspace_cache_state()')).mrn,before.mrn);
  assert.equal((await item('NEAR')).received_quantity,271,'on-demand detail tracks corrected raw receipts');
  await rebuild();
  assert.equal((await scalar("select public.get_stock_management_page(p_search=>'NEAR')")).rows[0].received_quantity,271);
  await db.exec(`alter table mrn_apg_2026 enable row level security;
    create policy inventory_read on mrn_apg_2026 for select to authenticated
      using ((select public.item_tracker_my_role())='inventory');
    set role authenticated; set test.inventory_role='branch';`);
  assert.deepEqual(await scalar("select stock_management_private.mrn_receipt_details('FOUR','2026-10-21')"),{});
  assert.equal(await item('FOUR'),null);
  await db.exec('reset role; set role anon');
  await assert.rejects(()=>scalar("select stock_management_private.mrn_receipt_details('FOUR','2026-10-21')"),/permission denied/);
  await db.close();
  console.log('Receipt totals SQL passed: four MRNs = 230 Qty, latest-day scope, full ordered Qty, split expiry/warehouses, references, signed/null lines, Near totals, idempotence, review reactivation, cache, RLS and 5000-row bulk payloads.');
})().catch(error=>{console.error(error);process.exit(1);});
