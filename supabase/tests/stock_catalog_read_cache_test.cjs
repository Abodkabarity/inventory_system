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
  const scalar = async (sql, params = []) => Object.values((await db.query(sql,params)).rows[0])[0];
  const detail = code => scalar('select public.get_stock_catalog_item($1)',[code]);
  const conditional = (code,version) => scalar('select public.get_stock_catalog_item_if_changed($1,$2)',[code,version]);
  const revision = source => scalar('select revision::int from public.stock_catalog_cache_revisions where source=$1',[source]);
  const equivalent = async () => {
    for (const code of ['A','B','MISSING']) {
      assert.equal(await scalar(`select (public.get_stock_catalog_item($1)-'_cache_version')
        is not distinct from public.stock_cache_test_reference($1)`,[code]), true, code);
    }
  };
  await equivalent();
  let item = await detail('A');
  assert.equal(item.branches.length, 2);
  assert.equal(item.branches.find(b => b.branch === 'Alpha').sales_2025, 11);
  assert.equal(item.branches.find(b => b.branch === 'Beta').sales_2026, -3);
  assert.equal(item.branches.find(b => b.branch === 'Beta').branch_group, '71');
  assert.deepEqual(await conditional('A', item._cache_version), {
    _cache_not_modified: true, _cache_version: item._cache_version,
  });
  const version = async details => scalar('select stock_management_private.catalog_cache_version($1)',[details]);
  const overviewVersion = await version(false);
  await db.exec("update public.sales_history_2025 set cash=12 where branch_name=' alpha '");
  assert.equal(await version(false), overviewVersion, 'live annual sales do not invalidate unchanged overview rows');
  let updated = await conditional('A',item._cache_version);
  assert.equal(updated.branches.find(b => b.branch === 'Alpha').sales_2025, 13);
  assert.notEqual(updated._cache_version,item._cache_version);
  await equivalent();
  item = updated;
  await db.exec("update public.branches set branch_group='71' where branch_name='Alpha'");
  updated = await conditional('A',item._cache_version);
  assert.equal(updated.branches.find(b => b.branch === 'Alpha').branch_group, '71');
  assert.notEqual(updated._cache_version,item._cache_version);
  await equivalent();
  const header1 = await scalar('select public.get_stock_catalog_page(p_limit=>1)');
  await db.exec(`update public.stock_catalog_snapshot set payload=jsonb_set(payload,'{total_stock}','42') where item_code='A'`);
  const header2 = await scalar('select public.get_stock_catalog_page(p_limit=>1)');
  assert.notEqual(header1.meta.catalog_cache_version,header2.meta.catalog_cache_version);
  assert.equal((await detail('A')).total_stock,42);
  await equivalent();
  const beforeRollback = await version(true);
  await db.exec('begin');
  await db.exec("delete from public.sales_history where item_code='A'");
  assert.notEqual(await version(true),beforeRollback);
  await db.exec('rollback');
  assert.equal(await version(true),beforeRollback,'revisions commit/roll back with the actual data');
  const beforeBulk = await revision('sales_2026');
  await db.exec(`insert into public.sales_history select 'B','Beta','01/2026',1,0,0 from generate_series(1,5000)`);
  assert.equal(await revision('sales_2026'),beforeBulk+1,'one revision update per 5000-row statement');
  await equivalent();
  item = await detail('A');
  await db.exec("delete from public.stock_catalog_snapshot where item_code='A'");
  assert.equal(await conditional('A',item._cache_version),null,'removed products never reuse a cached body');
  const beforeTruncate = await revision('sales_2026');
  await db.exec('truncate public.sales_history');
  assert.equal(await revision('sales_2026'),beforeTruncate+1);
  await equivalent();
  item = await detail('B');
  await db.exec("set test.inventory_role='inventory'; set role authenticated");
  assert.equal((await conditional('B',item._cache_version))._cache_not_modified,true);
  await assert.rejects(db.exec("update public.stock_catalog_cache_revisions set revision=0"), /permission denied/);
  await db.exec("set test.inventory_role='branch'");
  assert.equal(await conditional('B',item._cache_version),null,'role changes block cached data immediately');
  await db.exec("set test.inventory_role='inventory'; reset role; revoke select on public.sales_history from authenticated; set role authenticated");
  await assert.rejects(conditional('B',item._cache_version), /permission denied/);
  await db.exec('reset role; set role anon');
  await assert.rejects(conditional('B',item._cache_version), /permission denied/);
  await db.exec('reset role');
  await db.close();
  console.log('PostgreSQL cache regression: exact payload equivalence, signed sales, source revisions, rollback, bulk writes, removal, RLS and permissions passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
