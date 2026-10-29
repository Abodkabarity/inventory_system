// Isolated SQL regression: no production data is modified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');
(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create table public.mrn_apg_2026(item_code text,mrn_date date,mrn_no text,
      warehouse text,expiry_date date,ordered_quantity numeric,received_quantity numeric,
      vendor text,reference text,status text);
    create table public.stock_workspace_cache_revisions(source text primary key,revision bigint);
    insert into stock_workspace_cache_revisions values('mrn_receipts',1);
    grant usage on schema public to authenticated,service_role,anon;
    grant select on all tables in schema public to authenticated,service_role;
    insert into mrn_apg_2026 values
      ('A','2026-10-26','NEW','main virtual','2027-04-01',2,2,'rafed healthcare','R-NEW','approved'),
      ('A','2026-10-22','EARLIER','new virtual','2027-05-01',50,50,'vendor','R-OLD','approved'),
      (' A ','2026-01-13','OLD','store','2027-04-01',100,100,'vendor','R-1','approved'),
      ('A','2026-01-13','OLD','store','2027-05-01',50,50,'vendor','R-2','approved'),
      ('A','2026-01-13','OLD','store','2027-05-01',0,-2,'vendor','R-2','approved'),
      ('A','2026-02-01','OTHER',null,null,1,1,'vendor',null,'approved'),
      ('A','2026-03-01','FUTURE','future routing',null,3,3,'vendor',null,'approved'),
      ('A','2026-10-27','REJECTED','store','2027-04-01',999,999,'vendor','BAD','rejected'),
      ('B','2026-10-27','OTHER-PRODUCT','store','2027-04-01',999,999,'vendor','BAD','approved');
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261028064713_stock_mrn_complete_receipt_history.sql','utf8'));
  await db.exec('create schema stock_management_private; grant usage on schema stock_management_private to authenticated,service_role');
  const detailsMigration=fs.readFileSync('supabase/migrations/20261022114605_stock_mrn_complete_receipt_totals.sql','utf8');
  await db.exec(detailsMigration.slice(
    detailsMigration.indexOf('create or replace function stock_management_private.mrn_receipt_details'),
    detailsMigration.indexOf('CREATE OR REPLACE FUNCTION stock_management_private.refresh_snapshot')));
  await db.exec(`create function public.get_stock_management_item(p_item_code text)
    returns jsonb language sql stable security invoker set search_path='' as $$
      with snapshot as (select p_item_code item_code,date '2026-10-26' last_mrn_date)
      select jsonb_build_object('item_code',snapshot.item_code) ||
        stock_management_private.mrn_receipt_details(snapshot.item_code,snapshot.last_mrn_date)
      from snapshot
    $$`);
  await db.exec(fs.readFileSync('supabase/migrations/20261028121554_stock_mrn_receipt_summary_in_product_details.sql','utf8'));
  const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0]??{})[0];
  const history=(code,offset=0,limit=5000)=>scalar('select public.get_stock_management_receipt_history($1,$2,$3)',[code,offset,limit]);
  const all=await history('A');
  const summary=await scalar("select stock_management_private.mrn_receipt_history_summary('A')");
  assert.deepEqual(summary,{mrn_count:5,day_count:5,received_qty:204,from:'2026-01-13',through:'2026-10-26'});
  const detail=await scalar("select public.get_stock_management_item('A')");
  assert.deepEqual(detail.receipt_history_summary,summary,'existing details request carries the header summary');
  assert.equal(detail.received_quantity,2,'latest-day cards do not become all-time totals');
  assert.equal(detail.receipt_lines.length,1,'complete history rows are still loaded only on expansion');
  assert.equal(JSON.stringify(summary).length<160,true,'summary stays a small metadata-only payload');
  assert.equal(all.total,6);assert.equal(all.mrn_count,5);assert.equal(all.day_count,5);
  assert.equal(all.rows.length,6);assert.equal(all.received_qty,204);
  assert.equal(all.rows[0].mrn_no,'NEW');assert.equal(all.rows.at(-1).mrn_date,'2026-01-13');
  assert.equal(all.rows[0].vendor,'RAFED HEAL');
  assert.equal(all.rows.some(r=>r.mrn_no==='REJECTED'||r.mrn_no==='OTHER-PRODUCT'),false);
  assert.equal(all.rows.find(r=>r.expiry_date==='2027-05-01'&&r.mrn_no==='OLD').received_qty,48);
  assert.equal(new Set(all.rows.map(r=>r.line_id)).size,6,'expiry splits keep distinct identities');
  const partial=await history('A',2,2);
  assert.equal(partial.total,6);assert.equal(partial.rows.length,2);
  assert.deepEqual(partial.rows,all.rows.slice(2,4));
  assert.equal(partial.snapshot_version,all.snapshot_version);
  assert.equal((await history('A',99)).rows.length,0);
  assert.equal((await history('MISSING')).total,0);
  await db.exec("update stock_workspace_cache_revisions set revision=revision+1 where source='mrn_receipts'");
  assert.notEqual((await history('A')).snapshot_version,all.snapshot_version);
  await db.exec(`insert into mrn_apg_2026(item_code,mrn_date,mrn_no,received_quantity,status,warehouse)
    select 'LARGE','2026-10-20',i::text,1,'approved','new routing' from generate_series(1,5001)i`);
  assert.equal((await history('LARGE',0,99999)).rows.length,5000);
  assert.equal((await history('LARGE',5000)).rows.length,1);
  await db.exec(`alter table mrn_apg_2026 enable row level security;
    create policy inventory_read on mrn_apg_2026 for select to authenticated
      using (current_setting('test.role',true) in ('inventory','view'));
    set role authenticated; set test.role='branch';`);
  assert.equal((await history('A')).total,0);
  assert.equal((await scalar("select stock_management_private.mrn_receipt_history_summary('A')")).received_qty,0);
  await db.exec("set test.role='inventory'");
  assert.equal((await history('A')).received_qty,204);
  assert.equal((await scalar("select public.get_stock_management_item('A')")).receipt_history_summary.received_qty,204);
  await db.exec("set test.role='view'");
  assert.equal((await history('A')).total,6);
  await db.exec('reset role; set role anon');
  await assert.rejects(()=>history('A'),/permission denied/);
  await assert.rejects(()=>scalar("select stock_management_private.mrn_receipt_history_summary('A')"),/permission denied/);
  await db.close();
  console.log('MRN history SQL passed: all dates/warehouses, grouping, signed returns, expiry splits, 5000-row pages, revisions, and inventory/view/branch/anon RLS.');
})().catch(error=>{console.error(error);process.exit(1);});
