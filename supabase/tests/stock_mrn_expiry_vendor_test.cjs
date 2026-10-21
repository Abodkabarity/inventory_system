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
  const scalar = async (sql,params=[]) => Object.values((await db.query(sql,params)).rows[0])[0];
  const before = await scalar('select public.get_stock_workspace_cache_state()');
  const fingerprints = await db.query('select receipt_fingerprint from public.stock_expiry_candidates order by expiry_date');
  await db.exec(fs.readFileSync('supabase/migrations/20261020122615_stock_mrn_expiry_vendor_and_stock_share.sql','utf8'));
  const current = await scalar('select public.get_stock_workspace_cache_state()');
  assert.notEqual(before.mrn,current.mrn,'migration invalidates previously cached list shapes');
  assert.deepEqual((await db.query('select receipt_fingerprint from public.stock_expiry_candidates order by expiry_date')).rows,fingerprints.rows,'vendor does not reset review fingerprints');
  const register = await scalar('select public.get_stock_management_register_batch(0,5000)');
  assert.equal(register.rows[0].vendor,'ABCDEFGHIJ');
  assert.equal(register.rows[0].received_quantity,7);
  const page = await scalar('select public.get_stock_management_page(p_limit=>5000)');
  assert.equal(page.rows[0].vendor,'ABCDEFGHIJ');
  const unified = await scalar("select public.get_stock_management_product_details('A')");
  assert.equal(unified.vendor,'ABCDEFGHIJ');
  assert.equal(unified.mrn_details.vendor,'ABCDEFGHIJ');
  assert.equal(unified.reference,'REF-1');
  let expiry = await scalar("select public.get_stock_expiry_page(p_review_state=>'all',p_limit=>5000)");
  assert.equal(expiry.rows[0].vendor,'OLDER-VEND','vendor belongs to that expiry receipt, not latest product MRN');
  const detail = await scalar("select public.get_stock_expiry_item('A',current_date+20)");
  assert.equal(detail.vendor,'OLDER-VEND');
  const fingerprint = detail.receipt_fingerprint;
  await db.exec("insert into public.stock_expiry_reviews values('A',current_date+20,'Preserve my note',now(),now(),true,'"+fingerprint+"')");
  await db.exec("update public.mrn_apg_2026 set vendor='corrected-vendor' where mrn_no='OLD'");
  await scalar('select stock_management_private.discover_expiry_receipts()');
  const corrected = await scalar("select public.get_stock_expiry_item('A',current_date+20)");
  assert.equal(corrected.vendor,'CORRECTED-');
  assert.equal(corrected.is_reviewed,true);
  assert.equal(corrected.note,'Preserve my note');
  await db.exec("delete from public.mrn_apg_2026 where mrn_no='OLD'");
  assert.equal((await scalar("select public.get_stock_expiry_item('A',current_date+20)")).vendor,'CORRECTED-','durable vendor survives source removal');

  await db.exec(`
    insert into public.stock_management_snapshot(item_code,last_mrn_date,payload) values
      ('NONE',current_date-1,'{"item_code":"NONE","last_mrn_no":"M3"}'),
      ('NOEXPIRY',current_date-1,'{"item_code":"NOEXPIRY","last_mrn_no":"M4"}'),
      ('NULLNO',current_date-1,'{"item_code":"NULLNO","last_mrn_no":""}');
    insert into public.mrn_apg_2026(item_code,mrn_date,mrn_no,expiry_date,
      ordered_quantity,received_quantity,status,warehouse,vendor) values
      ('NOEXPIRY',current_date-1,'M4',null,5,4,'Approved','STORE','fallback-vendor'),
      ('NULLNO',current_date-1,null,current_date+15,-2,3,'Approved','STORE','null-number-vendor'),
      ('NULLNO',current_date-1,'',current_date+15,8,2,'Approved','STORE','another-vendor'),
      ('NULLNO',current_date-1,'',current_date+15,999,-50,'Approved','STORE','exclude-return');
  `);
  const parameters=[[0,5000],[1,5000],[0,1],[-5,0],[0,null],[99999,5000]];
  const baseline=[];
  for(const p of parameters) baseline.push(await scalar('select public.get_stock_management_register_batch($1,$2)',p));
  await db.exec(fs.readFileSync('supabase/migrations/20261020124301_stock_mrn_register_set_based_receipts.sql','utf8'));
  for(let i=0;i<parameters.length;i++) {
    assert.deepEqual(await scalar('select public.get_stock_management_register_batch($1,$2)',parameters[i]),baseline[i],JSON.stringify(parameters[i]));
  }
  assert.equal(await scalar('show enable_nestloop'),'on','bulk function planner setting does not leak into other queries');
  console.log('Set-based register matches previous payloads for missing receipts, null expiry, vendor fallback, signed quantities, null MRN numbers, offsets and limits.');
  await db.exec("set role authenticated; set test.inventory_role='branch'");
  assert.equal((await scalar('select public.get_stock_management_register_batch(0,5000)')).rows.length,0,'optimized register retains inventory RLS');
  // The receipt table's real deployment RLS is inventory-only; assert it here too.
  await db.exec("reset role; alter table public.stock_expiry_alert_receipts enable row level security; create policy inventory_read on public.stock_expiry_alert_receipts for select to authenticated using ((select public.item_tracker_my_role())='inventory'); set role authenticated");
  assert.equal(await scalar("select stock_management_private.expiry_vendor('A',current_date+20)"),null);
  await db.exec('reset role; set role anon');
  await assert.rejects(()=>scalar("select stock_management_private.mrn_vendor('A',current_date-1,'M1')"),/permission denied/);
  await db.close();
  console.log('Vendor SQL regression passed: exact receipt matching, uppercase ten-character labels, durable history, review preservation, cache invalidation, RLS and 5000-row limits.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
