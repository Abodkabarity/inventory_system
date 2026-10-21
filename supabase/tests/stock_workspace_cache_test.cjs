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
    create table public.stock_management_snapshot(item_code text primary key,last_mrn_date date,payload jsonb);
    create table public.mrn_apg_2026(item_code text,mrn_date date,mrn_no text,reference text,
      expiry_date date,ordered_quantity numeric,received_quantity numeric,status text,warehouse text);
    create table public.stock_expiry_alert_receipts(item_code text);
    create table public.stock_expiry_reviews(item_code text);
    create table public.item_report(item_code text);
    create table public.stock_expiry_watch_state(scans int default 0);
    insert into public.stock_expiry_watch_state values(0);
    create function public.refresh_stock_expiry_watch() returns jsonb language plpgsql as $$
      begin update public.stock_expiry_watch_state set scans=scans+1; return '{}'::jsonb; end; $$;
    create function public.get_stock_management_item(text) returns jsonb language sql stable as $$
      select payload from public.stock_management_snapshot where item_code=$1 $$;
    grant select on all tables in schema public to authenticated;
    alter table public.stock_management_snapshot enable row level security;
    create policy inventory_read on public.stock_management_snapshot for select to authenticated
      using ((select public.item_tracker_my_role())='inventory');
    insert into public.stock_management_snapshot values
      ('A','2026-10-19','{"item_code":"A","item_name":"MRN A","total_stock":999,"last_mrn_no":"M1","last_mrn_qty":7}'),
      ('SAVED','2026-10-19','{"item_code":"SAVED","item_name":"Saved only","last_mrn_no":"M2"}');
    insert into public.mrn_apg_2026 values
      ('A','2026-10-19','M1',' Ref-42 ','2026-12-01',12,7,'Approved','STORE'),
      ('A','2026-10-19','M1','Ref-42','2026-12-01',2,1,'Approved','STORE'),
      ('A','2026-10-19','M0','WRONG','2026-11-01',999,999,'Approved','STORE');
    set test.inventory_role='inventory';
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261020105108_stock_workspaces_validated_cache_and_shared_details.sql','utf8'));
  const scalar = async (sql,params=[]) => Object.values((await db.query(sql,params)).rows[0])[0];
  const state = () => scalar('select public.get_stock_workspace_cache_state()');
  const item = code => scalar('select public.get_stock_management_product_details($1)',[code]);
  const before = await state();
  assert.ok(before.mrn && before.expiry && before.details && before.discovery);
  const unified = await item('A');
  assert.equal(unified.total_stock,15,'same stock as Overview, not older MRN stock');
  assert.equal(unified.reference,'Ref-42');
  assert.equal(unified.mrn_details.total_stock,999,'MRN evidence preserved separately');
  assert.equal(unified.mrn_details.ordered_quantity,14);
  assert.equal(unified.mrn_details.received_quantity,8);
  assert.equal(unified.mrn_details.expiry_date,'2026-12-01');
  const overview = await scalar("select public.get_stock_catalog_item('A')-'_cache_version'");
  for(const [key,value] of Object.entries(overview)) assert.deepEqual(unified[key],value,key);
  assert.equal((await item('SAVED')).catalog_unavailable,true);
  assert.equal(await item('MISSING'),null);
  const prep = known => scalar('select public.prepare_stock_expiry_workspace($1)',[known]);
  let prepared = await prep(null);
  assert.equal(await scalar('select scans from public.stock_expiry_watch_state'),1);
  await prep(prepared.discovery);
  assert.equal(await scalar('select scans from public.stock_expiry_watch_state'),1,'unchanged cache validation skips discovery');
  const sources = [
    ['stock_management_snapshot',"update public.stock_management_snapshot set payload=payload",['mrn','details','expiry','discovery']],
    ['mrn_apg_2026',"update public.mrn_apg_2026 set reference='New reference'",['mrn','details','expiry','discovery']],
    ['stock_expiry_reviews',"insert into public.stock_expiry_reviews values('A')",['expiry']],
    ['stock_expiry_alert_receipts',"insert into public.stock_expiry_alert_receipts values('A')",['expiry']],
    ['item_report',"insert into public.item_report values('A')",['expiry']],
    ['sales_history',"update public.sales_history set cash=cash+1",['details']],
  ];
  for(const [name,write,changed] of sources) {
    const prior = await state(); await db.exec(write); const next = await state();
    for(const key of ['mrn','expiry','details','discovery']) {
      assert.equal(prior[key]!==next[key],changed.includes(key),name+' '+key);
    }
  }
  prepared = await prep(prepared.discovery);
  assert.equal(await scalar('select scans from public.stock_expiry_watch_state'),2,'receipt source changes rescan');
  const committed = await state();
  await db.exec("begin; update public.mrn_apg_2026 set reference='Rollback'; rollback;");
  assert.deepEqual(await state(),committed);
  const rev = await scalar("select revision::int from public.stock_workspace_cache_revisions where source='item_report'");
  await db.exec("insert into public.item_report select g::text from generate_series(1,5000) g");
  assert.equal(await scalar("select revision::int from public.stock_workspace_cache_revisions where source='item_report'"),rev+1);
  await db.exec('set role authenticated');
  assert.ok((await state()).mrn);
  assert.equal((await item('A')).reference,'New reference');
  await db.exec("set test.inventory_role='branch'");
  assert.equal(await state(),null);
  assert.equal(await item('A'),null);
  await assert.rejects(prep(null),/Inventory access required/);
  await db.exec("reset role; set test.inventory_role='inventory'; revoke select on public.sales_history from authenticated; set role authenticated");
  assert.equal(await state(),null,'privilege revocation disables every memory reuse');
  await db.exec('reset role; set role anon');
  await assert.rejects(state(),/permission denied/);
  await assert.rejects(()=>item('A'),/permission denied/);
  await db.close();
  console.log('Workspace PostgreSQL regression passed: shared Overview payload, MRN evidence/reference, conditional discovery, source revisions, 5000-row statements, rollback, RLS and revocations.');
})().catch(error => { console.error(error); process.exitCode = 1; });
