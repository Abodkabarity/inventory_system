// Local PostgreSQL regression: no production review notes are changed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');

(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema stock_management_private;
    create table auth.users(id uuid primary key);
    insert into auth.users values ('00000000-0000-0000-0000-000000000001');
    create function auth.uid() returns uuid language sql stable as
      $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function public.item_tracker_my_role() returns text language sql stable as
      $$select current_setting('test.role',true)$$;
    create function stock_management_private.is_view_user() returns boolean language sql stable as
      $$select public.item_tracker_my_role()='view'$$;
    create table public.stock_management_snapshot(item_code text primary key,payload jsonb,updated_at timestamptz default now());
    create table public.stock_expiry_alert_receipts(
      item_code text,expiry_date date,mrn_date date,mrn_no text,warehouse text,
      received_qty numeric,ordered_qty numeric,vendor text,product_data jsonb default '{}'::jsonb,
      first_detected_at timestamptz default now(),last_changed_at timestamptz default now(),
      primary key(item_code,expiry_date,mrn_date,mrn_no,warehouse));
    create table public.stock_expiry_reviews(
      item_code text,expiry_date date,note text default '',is_reviewed boolean default false,
      reviewed_fingerprint text,reviewed_at timestamptz,reviewed_by uuid,
      updated_at timestamptz default now(),updated_by uuid,primary key(item_code,expiry_date));
    create table public.stock_supply_insights(item_code text,detail jsonb,summary jsonb,updated_at timestamptz);
    create table public.item_report(item_code text,added_date_time timestamptz,created_at timestamptz);
    create table public.stock_expiry_watch_state(singleton boolean,receipt_start date,last_scanned_at timestamptz);
    insert into public.stock_expiry_watch_state values(true,'2026-10-01',now());
    create table public.stock_workspace_cache_revisions(source text primary key,revision bigint default 0);
    insert into public.stock_workspace_cache_revisions values ('expiry_reviews',0),('expiry_receipts',0);
    insert into public.stock_management_snapshot values
      ('A','{"item_code":"A","item_name":"Product A","total_stock":923,"store_stock":516,"branches_stock":407,"meta":{}}',now());
    insert into public.stock_expiry_alert_receipts(item_code,expiry_date,mrn_date,mrn_no,warehouse,received_qty,ordered_qty,vendor) values
      ('A','2027-01-01','2026-10-02','104784','store',1000,1000,'OLDER VENDOR'),
      ('A','2027-01-01','2026-10-24','106834','store',500,500,'ALPHAMED'),
      ('A','2027-01-01','2026-10-24','106835','store',25,25,'ALPHAMED'),
      ('A','2027-02-01','2026-10-24','106836','store',10,10,'OTHER EXPIRY');
    set test.uid='00000000-0000-0000-0000-000000000001'; set test.role='inventory';
  `);
  const original = fs.readFileSync('supabase/migrations/20261022101225_stock_workspaces_current_month_from_daily_sales.sql','utf8');
  await db.exec(original.match(/CREATE OR REPLACE VIEW public\.stock_expiry_candidates[\s\S]*?;/)[0]);
  await db.exec(`insert into public.stock_expiry_reviews(item_code,expiry_date,note,is_reviewed,reviewed_fingerprint)
    select item_code,expiry_date,'Existing note',true,receipt_fingerprint
    from public.stock_expiry_candidates where expiry_date='2027-01-01';
    grant usage on schema public,auth,stock_management_private to authenticated,anon,service_role;
    grant select on all tables in schema public to authenticated;
  `);
  const legacy = (await db.query('select * from public.stock_expiry_reviews')).rows;
  if (process.env.EXPIRY_WITHOUT_SUPPLY === '1') {
    await db.exec('drop table public.stock_supply_insights');
  }
  await db.exec(fs.readFileSync('supabase/migrations/20261026070131_stock_expiry_group_by_receipt_day.sql','utf8'));
  const scalar = async (sql,params=[]) => Object.values((await db.query(sql,params)).rows[0])[0];
  const rows = (await db.query(`select last_receipt_date,received_qty,ordered_qty,receipt_count
    from public.stock_expiry_candidates where item_code='A' and expiry_date='2027-01-01' order by last_receipt_date`)).rows;
  assert.equal(rows.length,2);
  assert.deepEqual(rows.map(r=>Number(r.received_qty)),[1000,525]);
  assert.deepEqual(rows.map(r=>Number(r.ordered_qty)),[1000,525]);
  assert.deepEqual(rows.map(r=>Number(r.receipt_count)),[1,2]);
  assert.deepEqual((await db.query('select * from public.stock_expiry_reviews')).rows,legacy,'legacy notes preserved exactly');
  assert.equal(Number(await scalar('select count(*) from public.stock_expiry_receipt_reviews where is_reviewed')),2,'valid old review copied to existing days');
  const get = date => scalar("select public.get_stock_expiry_item('A','2027-01-01',$1::date)",[date]);
  const older = await get('2026-10-02'); const recent = await get('2026-10-24');
  assert.equal(recent.vendor,'ALPHAMED'); assert.equal(older.vendor,'OLDER VEND');
  assert.equal(recent.receipts.length,2); assert.equal(older.receipts.length,1);
  assert.equal(recent.mrn_numbers,'106834 · 106835'); assert.equal(older.mrn_numbers,'104784');
  assert.ok(recent.receipts.every(r=>r.mrn_date==='2026-10-24'));
  assert.equal(Number(recent.product_data.total_stock),923,'whole-product stock remains separate');
  await assert.rejects(scalar("select public.get_stock_expiry_item('A','2027-01-01')"),/separate MRN dates/);
  const save = (alert,action,note='Changed note') => scalar(`select public.save_stock_expiry_review(
    'A','2027-01-01',$1,$2,$3,$4::timestamptz,$5::date)`,
    [alert.receipt_fingerprint,note,action,alert.review_updated_at,alert.last_receipt_date]);
  await db.exec('set role authenticated');
  await save(recent,'reopen');
  assert.equal((await get('2026-10-02')).note,'Existing note');
  assert.equal((await get('2026-10-02')).is_reviewed,true);
  assert.equal((await get('2026-10-24')).is_reviewed,false);
  await assert.rejects(save(recent,'note'),/Another user changed/);
  let current=await get('2026-10-24'); await save(current,'review');
  assert.equal((await get('2026-10-24')).is_reviewed,true);
  const beforeRevision=Number(await scalar("select revision from public.stock_workspace_cache_revisions where source='expiry_reviews'"));
  current=await get('2026-10-24'); await save(current,'note','Recent receipt only');
  assert.ok(Number(await scalar("select revision from public.stock_workspace_cache_revisions where source='expiry_reviews'"))>beforeRevision);
  await db.exec(`reset role; insert into public.stock_expiry_alert_receipts
    (item_code,expiry_date,mrn_date,mrn_no,warehouse,received_qty,ordered_qty,vendor)
    values('A','2027-01-01','2026-10-25','106900','store',7,7,'NEW VENDOR')`);
  const newest=await get('2026-10-25');
  assert.equal(newest.is_reviewed,false); assert.equal(newest.note,'');
  assert.equal((await get('2026-10-24')).is_reviewed,true,'new day does not reopen another day');
  await db.exec("update public.stock_expiry_alert_receipts set received_qty=30 where mrn_no='106835'");
  assert.equal((await get('2026-10-24')).is_reviewed,false,'same-day changed quantity reopens only this day');
  assert.equal((await get('2026-10-24')).note,'Recent receipt only');
  assert.equal((await get('2026-10-02')).is_reviewed,true);
  await assert.rejects(save(current,'review'),/Receipt data changed/);
  const page=await scalar("select public.get_stock_expiry_page('', 'all', '',0,5000)");
  assert.equal(page.total,4); assert.equal(page.rows[0].last_receipt_date,'2026-10-25');
  assert.equal(page.meta.grouping,'item_expiry_mrn_date');
  assert.equal(Number(page.rows.find(r=>r.last_receipt_date==='2026-10-24'&&r.expiry_date==='2027-01-01').received_qty),530);
  await db.exec("set role authenticated; set test.role='view'");
  assert.equal((await scalar("select public.get_stock_expiry_page('', 'all','',0,5000)")).total,4,'View read parity');
  await assert.rejects(save(await get('2026-10-24'),'review'),/Inventory access required/);
  await db.exec("set test.role='branch'");
  assert.equal(Number(await scalar('select count(*) from public.stock_expiry_receipt_reviews')),0,'unrelated role cannot read notes');
  await assert.rejects(save(await get('2026-10-24'),'review'),/Inventory access required/);
  await db.exec('reset role');
  assert.equal(await scalar("select has_function_privilege('anon','public.get_stock_expiry_item(text,date,date)','execute')"),false);
  assert.equal(await scalar("select has_function_privilege('anon','public.save_stock_expiry_review(text,date,text,text,text,timestamptz,date)','execute')"),false);
  assert.equal(await scalar("select has_table_privilege('authenticated','public.stock_expiry_receipt_reviews','insert')"),false);
  await db.close(); console.log('PASS: receipt-day grouping, notes, concurrency, cache, totals and permissions');
})().catch(e=>{console.error(e);process.exitCode=1});
