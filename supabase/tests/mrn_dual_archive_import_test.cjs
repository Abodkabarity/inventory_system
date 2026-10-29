// Isolated PostgreSQL/WASM regression: never connects to the live database.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');

(async () => {
  const db = new PGlite();
  const day = '2026-10-29';
  const fixedClock = sql => sql.replaceAll("(now() at time zone 'Asia/Dubai')::date", `date '${day}'`);
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema stock_management_private;
    create function public.item_tracker_my_role() returns text language sql as $$ select 'inventory'::text; $$;
    create function stock_management_private.is_view_user() returns boolean language sql as $$ select false; $$;
    create table public.mrn_apg_2026 (
      id uuid primary key default gen_random_uuid(), warehouse text,status text,item_code text,item_name text,
      mrn_no text,mrn_date date,vendor text,reference text,ordered_quantity numeric,received_quantity numeric,
      expiry_date date,category_1 text,supplier text,company text,total_qty numeric,bonus numeric,prepared_by text,
      source_month date not null,source_row_number integer not null,created_at timestamptz default now(),
      unique(source_month,source_row_number),check(item_code<>'bad-store')
    );
    create table public.mrn_cd_apg_2026(like public.mrn_apg_2026 including all);
    alter table public.mrn_cd_apg_2026 add check(item_code<>'bad-cd');
    alter table public.mrn_apg_2026 enable row level security;
    alter table public.mrn_cd_apg_2026 enable row level security;
    create table public.stock_management_refresh_state(singleton boolean,status text,requested_at timestamptz,completed_at timestamptz,error text);
    insert into public.stock_management_refresh_state values(true,'complete',now(),now(),null);
    create table public.stock_management_snapshot(updated_at timestamptz);
    insert into public.stock_management_snapshot values(now()-interval '1 day');
    create table public.test_expiry_calls(n integer);
    create function public.refresh_stock_management_snapshot() returns jsonb language sql as $$
      update public.stock_management_refresh_state set status='queued',requested_at=clock_timestamp()
      returning jsonb_build_object('status',status); $$;
    create function public.refresh_stock_expiry_watch() returns jsonb language sql as $$
      insert into public.test_expiry_calls values(1) returning jsonb_build_object('changed',1); $$;
    grant all on all tables in schema public to service_role;
    grant execute on function public.refresh_stock_management_snapshot(),public.refresh_stock_expiry_watch() to service_role;
  `);
  const old = fs.readFileSync('supabase/migrations/20261027043932_mrn_apg_hourly_today_and_refresh_status.sql','utf8');
  await db.exec(fixedClock(old.split('-- Include same-day receipts')[0]));
  await db.exec(fixedClock(fs.readFileSync('supabase/migrations/20261029081837_mrn_dual_archive_daily_hourly_sync.sql','utf8')));

  const query = async (sql,args=[]) => (await db.query(sql,args)).rows;
  const scalar = async (sql,args=[]) => Object.values((await query(sql,args))[0])[0];
  const row = (warehouse='store', code='A', date=day, changes={}) => ({
    warehouse,status:'approved',item_code:code,item_name:'Product '+code,mrn_no:'MRN-'+code,mrn_date:date,
    vendor:'V',reference:'00123',ordered_quantity:9,received_quantity:9,expiry_date:'2027-01-01',
    category_1:'MED',supplier:'Supplier',company:'APG',total_qty:7,bonus:2,prepared_by:'Actual preparer',...changes,
  });
  const saved = () => query(`select 'store' scope,to_jsonb(t) data from public.mrn_apg_2026 t
    union all select 'cd',to_jsonb(t) from public.mrn_cd_apg_2026 t order by scope,data`);
  const sync = rows => scalar('select public.sync_mrn_apg_2026_archives($1::jsonb)',[JSON.stringify(rows)]);
  const begin = id => scalar('select public.begin_mrn_apg_2026_hourly($1,$2)',[id,day]);
  const replace = (id,rows,date=day) => scalar('select public.replace_mrn_apg_2026_archives_today($1,$2,$3::jsonb)',[id,date,JSON.stringify(rows)]);
  const seed = async (table,r) => scalar(`insert into public.${table}
    select r.* from jsonb_populate_record(null::public.mrn_apg_2026,$1::jsonb) r returning item_code`,[JSON.stringify({
      ...r,id:await scalar('select gen_random_uuid()'),source_month:r.mrn_date.slice(0,7)+'-01',
      source_row_number:await scalar(`select coalesce(max(source_row_number),0)+1 from public.${table}`),
    })]);
  await seed('mrn_apg_2026',row('store','old-month','2026-09-30'));
  await seed('mrn_cd_apg_2026',row('alpha','old-month','2026-09-30'));
  await seed('mrn_apg_2026',row('store','older','2026-10-24'));
  await seed('mrn_cd_apg_2026',row('alpha','older','2026-10-24'));
  await seed('mrn_apg_2026',row('store','withdrawn','2026-10-28'));
  await seed('mrn_cd_apg_2026',row('alpha','withdrawn','2026-10-28'));
  await seed('mrn_apg_2026',row('store','A',day,{total_qty:null,bonus:null}));
  await seed('mrn_cd_apg_2026',row('alpha','withdrawn',day));
  const untouched = (await saved()).filter(r=>['2026-09-30','2026-10-24'].includes(r.data.mrn_date));
  const rows = [row(),row(),row('main virtual','MV'),row('new virtual','NV'),row('alpha','CD'),
    row('beta','CD2','2026-10-28'),row('store','missing','2026-10-27'),row('store','ignored','2026-10-24')];
  await db.exec('set role service_role');
  let result = await sync(rows);
  assert.deepEqual(result.source_counts,{mrn_apg_2026:6,mrn_cd_apg_2026:2});
  assert.equal(result.source_rows,8); assert.equal(result.inserted_rows,7);
  assert.equal(result.sync_policy,'dual_archive_snapshot_v2');
  assert.equal(await scalar("select count(*)::int from public.mrn_apg_2026 where mrn_date=$1 and item_code='A'",[day]),2);
  assert.deepEqual((await query("select total_qty,bonus,prepared_by,reference from public.mrn_apg_2026 where item_code='A'"))[0],
    {total_qty:'7',bonus:'2',prepared_by:'Actual preparer',reference:'00123'});
  assert.equal(await scalar("select count(*)::int from public.mrn_apg_2026 where item_code='ignored'"),0);
  assert.equal(await scalar("select count(*)::int from public.mrn_apg_2026 where item_code='withdrawn'"),0);
  assert.equal(await scalar("select count(*)::int from public.mrn_cd_apg_2026 where item_code='withdrawn'"),0);
  assert.deepEqual((await saved()).filter(r=>['2026-09-30','2026-10-24'].includes(r.data.mrn_date)),untouched);
  const countBefore = (await saved()).length;
  await sync(rows); assert.equal((await saved()).length,countBefore,'retry must preserve duplicate multiplicity');

  // Failure after the STORE write must roll both archives back.
  let before = await saved();
  await assert.rejects(()=>sync([row('store','new'),row('alpha','bad-cd'),row('beta','CD2','2026-10-28')]),/check constraint/);
  assert.deepEqual(await saved(),before);
  await assert.rejects(()=>sync([row()]),/missing yesterday/);
  assert.deepEqual(await saved(),before);
  for (const invalid of [row('store','A',day,{total_qty:null}),row('store','A',day,{total_qty:'7'}),
    row('', 'A'),row('store','A','2026-10-30'),row('store','A','2026-10-01'),row('store','A',day,{status:'draft'})]) {
    await assert.rejects(()=>sync([invalid])); assert.deepEqual(await saved(),before);
  }
  await assert.rejects(()=>sync(Array(10001).fill(row())),/at most 10000/);
  assert.deepEqual(await saved(),before);

  // A complete day with branch receipts and no STORE receipts clears only the
  // STORE snapshot of that same day, rather than leaving old STORE quantities.
  result=await sync([row('alpha','CD-Y','2026-10-28'),row('alpha','CD-T')]);
  assert.equal(await scalar("select count(*)::int from public.mrn_apg_2026 where mrn_date in ('2026-10-28','2026-10-29')"),0);
  assert.equal(result.source_counts.mrn_apg_2026,0);

  const run='11111111-1111-1111-1111-111111111111';
  await begin(run);
  result=await replace(run,[row('store','RESTORED'),row('store','RESTORED'),row('alpha','CD-T')]);
  assert.equal(result.last_rows,2); assert.equal(result.last_cd_rows,1); assert.equal(result.source_rows,3);
  before=await saved();
  await replace(run,[row('store','retry-must-not-write')]);
  assert.deepEqual(await saved(),before);
  await assert.rejects(()=>replace('22222222-2222-2222-2222-222222222222',[]),/Stale/);
  await assert.rejects(()=>replace(run,[],'2026-10-28'),/another day/);
  result=await scalar('select public.complete_mrn_apg_2026_hourly($1)',[run]);
  assert.equal(result.ready,false);
  await db.exec("update public.stock_management_refresh_state set status='complete'; update public.stock_management_snapshot set updated_at=now()-interval '1 day'");
  assert.equal((await scalar('select public.complete_mrn_apg_2026_hourly($1)',[run])).needs_refresh,true);
  await db.exec("update public.stock_management_snapshot set updated_at=clock_timestamp()+interval '1 minute'");
  result=await scalar('select public.complete_mrn_apg_2026_hourly($1)',[run]);
  assert.equal(result.ready,true); assert.equal(result.last_success_rows,2); assert.equal(result.last_success_cd_rows,1);
  await scalar('select public.complete_mrn_apg_2026_hourly($1)',[run]);
  assert.equal(await scalar('select count(*)::int from public.test_expiry_calls'),1);

  const zeroRun='33333333-3333-3333-3333-333333333333';
  await begin(zeroRun);
  before=await saved();
  await assert.rejects(()=>replace(zeroRun,[row('store','valid'),row('alpha','bad-cd')]),/check constraint/);
  assert.deepEqual(await saved(),before);
  await replace(zeroRun,[]);
  assert.equal(await scalar("select count(*)::int from public.mrn_apg_2026 where mrn_date=$1",[day]),0);
  assert.equal(await scalar("select count(*)::int from public.mrn_cd_apg_2026 where mrn_date=$1",[day]),0);
  assert.deepEqual((await saved()).filter(r=>['2026-09-30','2026-10-24'].includes(r.data.mrn_date)),untouched);
  await db.exec("update public.mrn_apg_2026_hourly_state set status='complete'");
  const bulkRun='44444444-4444-4444-4444-444444444444';
  await begin(bulkRun);
  const bulk=Array.from({length:5001},(_,i)=>row(i%2 ? 'alpha':'store','B'+i));
  result=await replace(bulkRun,bulk);
  assert.equal(result.source_rows,5001);
  assert.equal(result.last_rows,2501); assert.equal(result.last_cd_rows,2500);
  assert.equal(await scalar('select count(*)::int from public.mrn_apg_2026 where total_qty=7 and mrn_date=$1',[day]),2501);
  assert.equal(await scalar('select count(*)::int from public.mrn_cd_apg_2026 where total_qty=7 and mrn_date=$1',[day]),2500);

  // A month boundary allocates each table's independent source-row numbers.
  await db.exec('reset role');
  const current = fs.readFileSync('supabase/migrations/20261029081837_mrn_dual_archive_daily_hourly_sync.sql','utf8');
  const syncDefinition = current.match(/create or replace function public\.sync_mrn_apg_2026_archives[\s\S]*?\$function\$;/)[0];
  await db.exec(syncDefinition.replaceAll("(now() at time zone 'Asia/Dubai')::date", "date '2026-11-01'"));
  await db.exec('set role service_role');
  await sync([row('store','MONTH','2026-10-31'),row('alpha','MONTH','2026-10-31'),row('store','NOV','2026-11-01')]);
  assert.equal(await scalar("select source_month::text from public.mrn_apg_2026 where item_code='NOV'"),'2026-11-01');
  await db.exec('reset role');
  assert.ok((await query("select prosecdef from pg_proc where proname in ('sync_mrn_apg_2026_archives','replace_mrn_apg_2026_archives_today','replace_mrn_archive_days','validate_mrn_import_rows')")).every(r=>r.prosecdef===false));
  for(const role of ['anon','authenticated']) {
    await db.exec(`set role ${role}`);
    await assert.rejects(()=>sync([row()]),/permission denied/);
    await assert.rejects(()=>replace(run,[]),/permission denied/);
    await db.exec('reset role');
  }
  assert.deepEqual((await saved()).filter(r=>['2026-09-30','2026-10-24'].includes(r.data.mrn_date)),untouched);
  await db.close();
  console.log('Dual MRN import SQL passed: exact totals, routing, duplicates, retries, rollback, zero day, 5001 rows, month boundary and permissions.');
})().catch(error => { console.error(error.message); process.exitCode=1; });
