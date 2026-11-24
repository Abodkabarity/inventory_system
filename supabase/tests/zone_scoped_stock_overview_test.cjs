// Isolated PostgreSQL/WASM test; does not connect to production.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { PGlite } = require(process.env.ZONE_OVERVIEW_PGLITE_MODULE || '@electric-sql/pglite');
const migration = 'supabase/migrations/20261124133948_zone_scoped_stock_overview.sql';

(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; grant usage on schema auth to authenticated,anon;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub' $$;
  `.replace("select nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub'",
    "select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid"));
  await db.exec(`
    create schema stock_management_private;
    create table public.stock_catalog_cache_revisions(source text,revision bigint);
    insert into public.stock_catalog_cache_revisions values('sales_2025',1),('sales_2026',1);
    create function public._norm_text(text) returns text language sql immutable as $$ select lower(btrim($1)) $$;
    create function stock_management_private.catalog_cache_version(boolean) returns text language sql stable
      as $$ select coalesce(nullif(current_setting('test.source_version',true),''),'r1') $$;
    create table public.app_users(user_id uuid primary key,role text,is_active boolean,zone text);
    create table public.app_user_zones(user_id uuid,zone text);
    create table public.zone_management_delegations(recipient_user_id uuid,status text,zones text[],start_at timestamptz,end_at timestamptz);
    create table public.branches(branch_name text,branch_group text,branch_type text,zone text,is_active boolean);
    create table public.stock_catalog_snapshot(item_code text primary key,payload jsonb);
    create table public.stock_catalog_refresh_state(singleton boolean,status text);
    create table public.sales_history(item_code text,branch_name text,month text,cash numeric,insurance numeric,online numeric);
    create table public.sales_history_2025(like public.sales_history);
    create table public.sales_last_45_days(item_code text,branch_name text,inv_date date,qty numeric,inv_type text,sales_type text,customer_name text);
    create table public.daily_order(branch text,run_date date);
    create table public.mrn_apg_2026(item_code text,status text,warehouse text,mrn_date date,reference text,total_qty numeric,bonus numeric);
    create table public.availability_kpi_purchase_status(item_code text,status_name text);
    create table public.stock_supply_insights(item_code text,detail jsonb);
    insert into public.app_users values
      ('00000000-0000-0000-0000-000000000001','zone_manager',true,'Wrong legacy zone'),
      ('00000000-0000-0000-0000-000000000002','zone_manager',true,'Zone2'),
      ('00000000-0000-0000-0000-000000000003','zone_manager',true,'Main'),
      ('00000000-0000-0000-0000-000000000004','zone_manager',false,'Zone1'),
      ('00000000-0000-0000-0000-000000000005','view',true,'Zone1'),
      ('00000000-0000-0000-0000-000000000006','zone_manager',true,'Zone1');
    insert into public.app_user_zones values('00000000-0000-0000-0000-000000000001','Zone1');
    insert into public.branches values
      ('Alpha','APG','Retail','Zone1',true),('Beta','71','Retail','Zone1',true),
      ('OUTSIDE SECRET BRANCH','APG','Retail','Zone2',true),
      ('Inactive','APG','Retail','Zone1',false),('STORE','STORE','Warehouse','Main',true);
    insert into public.daily_order values ('Alpha','2026-11-24'),('Beta','2026-11-24'),('OUTSIDE SECRET BRANCH','2026-11-24');
    insert into public.sales_history_2025 values ('A','Alpha','01/2025',2,0,0),('A','Beta','01/2025',1,0,0),('A','OUTSIDE SECRET BRANCH','01/2025',9000,0,0);
    insert into public.sales_history values ('A','Alpha','01/2026',10,0,0),('A','Beta','01/2026',0,0,4),('A','OUTSIDE SECRET BRANCH','01/2026',9000,0,0);
    insert into public.sales_last_45_days values
      ('A','Alpha','2026-10-11',24,'Cash','Cash',null),
      ('A','Alpha','2026-11-22',6,'Cash','Cash',null),
      ('A','Alpha','2026-11-23',-1,'Cash','Return',null),
      ('A','Beta','2026-11-20',2,'Insurance',null,'National Health Insurance Company - Daman Thiqa'),
      ('A','OUTSIDE SECRET BRANCH','2026-11-22',9000,'Cash','Cash',null);
    insert into public.mrn_apg_2026 values ('A','Approved','STORE','2026-11-01','STORE REF',5,1),
      ('A','Approved','OUTSIDE SECRET BRANCH','2026-11-23','OUTSIDE SECRET REF',9000,0);
    insert into public.availability_kpi_purchase_status values ('A','Normal');
    insert into public.stock_supply_insights values('A','{
      "scope":"STORE","status":"in_store","confidence":"verified","current_qty":100,
      "effective_supply":{"daily_qty":99999},"monthly":[{"sales_qty":99999}],
      "events":[{"from":"2026-01-01","days":3,"other_branch":"OUTSIDE SECRET BRANCH"}],
      "other_branch":"OUTSIDE SECRET BRANCH"}');
    grant usage on schema public to authenticated,anon;
    grant select on public.stock_catalog_snapshot to authenticated;
    alter table public.stock_catalog_snapshot enable row level security;
    create policy main_old_read on public.stock_catalog_snapshot for select to authenticated using
      (auth.uid()='00000000-0000-0000-0000-000000000003');
  `);
  const meta = {refreshed_at:'2026-11-24T08:30:00Z',demand_from:'2026-10-10',demand_through:'2026-11-23',
    recent_days:3,baseline_days:42,monthly_current_month:'2026-11-01',monthly_sales_through:'2026-11-01',order_run_date:'2026-11-24'};
  await db.query('insert into public.stock_catalog_snapshot values($1,$2)', ['A', {
    item_code:'A',item_name:'Product A',category:'Medicine',supplier:'Supplier',store_stock:100,
    branches_stock:99999,total_stock:100099,years:{2026:{total:99999}},added_date_time:'2026-11-01',
    unsafe_new_field:'OUTSIDE SECRET BRANCH',meta,
    branch_stock:{alpha:{stock:5,base_stock:3,final_reorder:2},beta:{stock:0},'outside secret branch':{stock:9999}},
    // Deliberately stale general demand: scoped metrics must use their daily rows.
    branch_demand:{alpha:{recent_sales:999,last_3_sales:99,baseline_sales:900},beta:{recent_sales:2,last_3_sales:0,baseline_sales:2},'outside secret branch':{recent_sales:9000,last_3_sales:9000}},
    distribution_orders:{alpha:{eligible:true,reorder_qty:3,final_qty:2},beta:{eligible:true,reorder_qty:2,final_qty:0},'outside secret branch':{eligible:true,reorder_qty:999,final_qty:999}}
  }]);
  await db.query('insert into public.stock_catalog_snapshot values($1,$2)', ['B', {item_code:'B',item_name:'Product B',store_stock:8,meta}]);
  const scalar = async (sql, p=[]) => Object.values((await db.query(sql,p)).rows[0])[0];
  const baseline = await scalar('select md5(string_agg(payload::text,\'|\' order by item_code)) from public.stock_catalog_snapshot');
  await db.exec(fs.readFileSync(migration,'utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261124134343_zone_overview_preparation_optimization.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261124134806_zone_overview_shared_history_cache.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261124135645_zone_overview_prepared_branch_facts.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261124140719_zone_overview_bounded_snapshot_build.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261124140857_zone_overview_shared_batch_work.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261124141730_zone_overview_maintenance_job.sql','utf8'));
  console.log('Migration compiled');
  const ready = async () => {
    for(let i=0;i<256;i++) {
      const result=await scalar('select zone_overview_private.work()');
      if(['complete','unchanged'].includes(result.status)) return result;
      assert.ok(['preparing_history','history_ready','preparing_scope','scope_ready'].includes(result.status),result.status);
    }
    assert.fail('Bounded preparation did not finish');
  };
  assert.equal((await ready()).status,'complete');
  assert.equal((await scalar('select zone_overview_private.prepare()')).status,'unchanged');
  const actor = async id => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:'00000000-0000-0000-0000-'+String(id).padStart(12,'0'),role:'authenticated'})]);
    await db.exec('set role authenticated');
  };
  const denied = async (sql, code='42501') => {
    try {await db.exec(sql);assert.fail('Request was allowed: '+sql);} catch(e){ assert.equal(e.code,code,e.message); }
  };
  await actor(1);
  assert.equal(await scalar('select public.can_read_zone_overview()'),true);
  const header=await scalar('select public.get_zone_overview_header()');
  const version=header.meta.catalog_cache_version;
  assert.equal(header.summary.items,2);
  const batch=await scalar('select public.get_zone_overview_batch(0,5000,$1)',[version]);
  const a=batch.rows.find(r=>r.item_code==='A');
  assert.equal(a.branches_stock,5); assert.equal(a.total_stock,105);
  assert.equal(a.recent_sales,31); assert.equal(a.last_3_sales,5); assert.equal(a.baseline_sales,26);
  assert.equal(a.years['2025'].total,3); assert.equal(a.years['2026'].total,21);
  assert.equal(a.reference,'STORE REF'); assert.equal(a.distribution.final_qty,2);
  assert.equal(a.distribution.active,2); assert.equal(a.distribution.eligible,2);
  assert.equal(a.distribution.covered,1); assert.equal(a.supply_insight.effective_supply.daily_qty,31/45);
  const detail=await scalar("select public.get_zone_overview_item('A',$1)",[version]);
  assert.deepEqual(detail.branches.map(b=>b.branch).sort(),['Alpha','Beta']);
  assert.equal(detail.branches.find(b=>b.branch==='Beta').branch_group,'71');
  assert.equal(detail.daily_sales_45d.reduce((s,r)=>s+r.total,0),31);
  assert.equal(detail.monthly_sales.find(m=>m.month==='11/2026').total,7);
  assert.equal(detail.monthly_sales.find(m=>m.month==='01/2026').total,14);
  assert.ok(!JSON.stringify([header,batch,detail]).includes('OUTSIDE SECRET'));
  assert.ok(!JSON.stringify(detail).includes('99999'));
  assert.equal(await scalar('select count(*)::int from public.stock_catalog_snapshot'),0);
  await denied('select * from zone_overview_private.items');
  await denied('select zone_overview_private.prepare()');
  await denied("select public.get_zone_overview_batch(0,5000,'forged-scope')",'PT409');
  await actor(2);
  await denied(`select public.get_zone_overview_item('A','${version}')`,'PT409');
  const own=await scalar("select public.get_zone_overview_item('A')");
  assert.deepEqual(own.branches.map(b=>b.branch),['OUTSIDE SECRET BRANCH']);
  assert.equal(own.branches_stock,9999);
  for(const id of [3,4,5]){
    await actor(id); assert.equal(await scalar('select public.can_read_zone_overview()'),false);
    await denied('select public.get_zone_overview_header()');
  }
  await actor(3);assert.equal(await scalar('select count(*)::int from public.stock_catalog_snapshot'),2);
  await db.exec('reset role');
  assert.equal(await scalar('select md5(string_agg(payload::text,\'|\' order by item_code)) from public.stock_catalog_snapshot'),baseline);
  await db.exec(`insert into public.zone_management_delegations values
    ('00000000-0000-0000-0000-000000000001','accepted',array['Zone2'],now()-interval '1 hour',now()+interval '1 hour')`);
  await ready();
  await actor(1);
  const delegated=await scalar('select public.get_zone_overview_header()');
  assert.notEqual(delegated.meta.catalog_cache_version,version);
  await db.exec('reset role');
  await db.exec("update public.zone_management_delegations set end_at=now()-interval '1 minute'");
  await actor(1);
  await denied(`select public.get_zone_overview_batch(0,5000,'${delegated.meta.catalog_cache_version}')`,'PT409');
  const restored=await scalar("select public.get_zone_overview_item('A')");
  assert.equal(restored.branches_stock,5);
  await db.exec('reset role');
  await db.exec("select set_config('test.source_version','r2',false)");
  await ready();
  await actor(1);
  await denied(`select public.get_zone_overview_batch(0,5000,'${version}')`,'PT409');
  await db.exec('reset role');
  await db.query(`insert into public.stock_catalog_snapshot
    select 'P'||lpad(i::text,6,'0'),jsonb_build_object('item_code','P'||lpad(i::text,6,'0'),
      'item_name','Product '||i,'store_stock',8,'meta',$1::jsonb)
    from generate_series(1,5005) i`,[meta]);
  await db.exec("select set_config('test.source_version','r3',false)");
  const started=Date.now();
  await ready();
  console.log('Prepared 5,007 products for isolated scopes in',Date.now()-started,'ms');
  await actor(1);
  const large=await scalar('select public.get_zone_overview_header()');
  assert.equal(large.summary.items,5007);
  const first=await scalar('select public.get_zone_overview_batch(0,99999,$1)',[large.meta.catalog_cache_version]);
  const rest=await scalar('select public.get_zone_overview_batch(5000,5000,$1)',[large.meta.catalog_cache_version]);
  assert.equal(first.rows.length,5000);assert.equal(rest.rows.length,7);
  assert.equal(new Set([...first.rows,...rest.rows].map(r=>r.item_code)).size,5007);
  await db.exec('reset role');
  await db.exec(`update public.stock_catalog_snapshot set payload=jsonb_set(
    jsonb_set(payload,'{item_name}','"Uncommitted new name"'),'{branch_stock,alpha,stock}','"invalid"')
    where item_code='A'; select set_config('test.source_version','r4',false)`);
  await denied('select zone_overview_private.prepare()','22P02');
  await actor(1);
  const preserved=await scalar('select public.get_zone_overview_header()');
  assert.equal(preserved.meta.catalog_cache_version,large.meta.catalog_cache_version);
  const preservedItem=await scalar("select public.get_zone_overview_item('A')");
  assert.equal(preservedItem.item_name,'Product A');
  assert.equal(preservedItem.branches_stock,5);
  await db.exec('reset role; set role anon');
  await denied('select public.can_read_zone_overview()');
  console.log('PASS: scopes, all metrics/channels, returns, references, 71 labels, privilege/forgery isolation, Main unchanged, source data unchanged, delegation expiry, pinned versions, 5000-row batches, atomic failed rebuilds');
  await db.close();
})().catch(e=>{console.error({message:e.message,code:e.code,where:e.where,detail:e.detail,position:e.position});process.exitCode=1;});
