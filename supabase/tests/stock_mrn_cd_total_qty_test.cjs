const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');
(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema stock_management_private;
    grant usage on schema stock_management_private,public to authenticated,service_role;
    create function public.item_tracker_my_role() returns text language sql stable as $$ select current_setting('test.role',true); $$;
    create function stock_management_private.is_view_user() returns boolean language sql stable as $$ select current_setting('test.role',true)='view'; $$;
    create function stock_management_private.catalog_cache_version(boolean) returns text language sql stable as $$ select 'catalog-v1'::text; $$;
    create table public.mrn_apg_2026(id uuid default gen_random_uuid(),item_code text,warehouse text,mrn_date date,mrn_no text,
      expiry_date date,ordered_quantity numeric,received_quantity numeric,total_qty numeric,bonus numeric,reference text,
      vendor text,item_name text,category_1 text,supplier text,company text,status text);
    create table public.mrn_cd_apg_2026(like public.mrn_apg_2026 including defaults);
    create table public.stock_catalog_snapshot(item_code text primary key,payload jsonb);
    create table public.availability_kpi_purchase_status(item_code text,status_id bigint,status_name text);
    insert into availability_kpi_purchase_status values('A',3,'AVAILABLE');
    create table stock_workspace_cache_revisions(source text,revision bigint);
    insert into stock_workspace_cache_revisions values('mrn_receipts',1);
    create function public.get_stock_workspace_cache_state() returns jsonb language sql stable as $$ select '{"mrn":"store-v1","expiry":"expiry-v1","details":"details-v1"}'::jsonb; $$;
    create function public.get_stock_catalog_item(text) returns jsonb language sql stable as $$ select payload from public.stock_catalog_snapshot where item_code=$1; $$;
    create function stock_management_private.discover_expiry_receipts() returns void language sql as $$ select null::void; $$;
    create function public.get_stock_management_register_batch(integer,integer) returns jsonb language sql as $$ select '{}'::jsonb; $$;
    create function public.get_stock_management_item(text) returns jsonb language sql as $$ select '{}'::jsonb; $$;
    create function public.get_stock_expiry_page(text,text,text,integer,integer) returns jsonb language sql as $$ select '{}'::jsonb; $$;
    insert into public.stock_catalog_snapshot values('A','{"item_code":"A","item_name":"Product A","stock_status":"in_stock","total_stock":50,"store_stock":10,"branches_stock":40,"days_on_hand":20,"years":{"2026":{"total":90}},"meta":{"stock_updated_at":"2026-10-29"}}'),
      ('B','{"item_code":"B","item_name":"Product B","stock_status":"no_stock","total_stock":0}');
    insert into public.mrn_apg_2026(item_code,warehouse,mrn_date,mrn_no,expiry_date,received_quantity,total_qty,bonus,status) values
      ('A','store','2026-01-01','OLD','2027-01-01',100,100,0,'approved'),
      ('A','store','2026-10-28','1','2027-01-01',10,12,2,'approved'),
      ('A','main virtual','2026-10-28','2','2027-01-01',2,3,1,'approved'),
      ('A','store','2026-10-29','BAD','2027-01-01',500,500,0,'rejected'),
      ('B','store','2026-10-28','BONUS','2027-01-01',0,5,5,'approved'),
      ('C','store','2026-10-28','EXACT','2027-01-01',9,7,2,'approved');
    insert into public.mrn_cd_apg_2026(item_code,warehouse,mrn_date,mrn_no,expiry_date,received_quantity,total_qty,bonus,status) values
      ('A',' Alpha ','2026-10-28','CD-OLD','2027-01-01',18,20,2,'approved'),
      ('A','Alpha','2026-10-29','CD-1','2027-01-01',3,4,1,'approved'),
      ('A','Alpha','2026-10-29','CD-2','2027-02-01',6,6,0,'approved'),
      ('A','Beta','2026-10-27','CD-3','2027-01-01',8,8,0,'approved'),
      ('Z','Alpha','2026-10-29','MISSING','2027-01-01',1,1,0,'approved'),
      ('A','Alpha','2026-10-30','REJECTED','2027-01-01',500,500,0,'rejected');
    grant select on all tables in schema public to authenticated,service_role;
    alter table public.mrn_cd_apg_2026 enable row level security;
    alter table public.stock_catalog_snapshot enable row level security;
    create policy cd_read on public.mrn_cd_apg_2026 for select to authenticated using (current_setting('test.role',true) in ('inventory','view'));
    create policy catalog_read on public.stock_catalog_snapshot for select to authenticated using (current_setting('test.role',true) in ('inventory','view'));
  `);
  const prior = fs.readFileSync('supabase/migrations/20261028124638_stock_management_purchase_status_columns.sql','utf8');
  const helper = prior.match(/create or replace function stock_management_private\.add_reference_columns[\s\S]*?\$\$;/)[0];
  await db.exec(helper);
  await db.exec(fs.readFileSync('supabase/migrations/20261029060623_stock_mrn_total_qty_and_cd_workspace.sql','utf8'));
  const scalar = async (sql,args=[]) => Object.values((await db.query(sql,args)).rows[0] || {})[0];
  const details = await scalar("select stock_management_private.mrn_receipt_details('A','2026-10-28')");
  assert.equal(details.total_qty,15); assert.equal(details.received_quantity,15); assert.equal(details.bonus,3);
  assert.equal(details.receipt_lines[0].total_qty,details.receipt_lines[0].received_qty);
  const history = await scalar("select get_stock_management_receipt_history('A',0,5000)");
  assert.equal(history.total_qty,115); assert.equal(history.bonus,3); assert.equal(history.rows.length,3);
  const summary = await scalar("select stock_management_private.mrn_receipt_history_summary('A')");
  assert.equal(summary.total_qty,115); assert.equal(summary.bonus,3);
  for(const [scope,input] of [
    ['mrn',[{item_code:'A',last_mrn_date:'2026-10-28'}]],
    ['catalog',[{item_code:'A'}]],
    ['expiry',[{item_code:'A',last_receipt_date:'2026-10-28',expiry_date:'2027-01-01',product_data:{}}]]
  ]) {
    const rows = await scalar('select stock_management_private.add_reference_columns($1::jsonb,$2)',[JSON.stringify(input),scope]);
    assert.equal(rows[0].total_qty,15,scope); assert.equal(rows[0].bonus,3,scope);
    if(scope==='expiry') {
      assert.equal(rows[0].product_data.total_qty,15);
      assert.equal(rows[0].receipts.reduce((sum,r)=>sum+r.total_qty,0),15);
      assert.equal(rows[0].receipts.reduce((sum,r)=>sum+r.bonus,0),3);
    }
  }
  assert.equal((await scalar("select stock_management_private.mrn_receipt_details('C','2026-10-28')")).total_qty,7,'use reported total even when received + bonus differs');
  const page = await scalar('select get_stock_mrn_cd_register_batch(0,5000)');
  assert.equal(page.total,3); assert.equal(page.rows.length,3);
  assert.equal(new Set(page.rows.map(r=>r.register_key)).size,3);
  const alpha = page.rows.find(r=>r.item_code==='A' && r.warehouse==='Alpha');
  const beta = page.rows.find(r=>r.item_code==='A' && r.warehouse==='Beta');
  assert.equal(alpha.total_qty,10); assert.equal(alpha.bonus,1); assert.equal(alpha.purchase_status_items,'AVAILABLE');
  assert.equal(beta.total_qty,8); assert.equal(beta.last_mrn_date,'2026-10-27');
  assert.equal(page.rows.find(r=>r.item_code==='Z').stock_unavailable,true);
  const item = await scalar("select get_stock_mrn_cd_item('A','Alpha')");
  assert.equal(item.total_qty,10); assert.equal(item.bonus,1); assert.equal(item.warehouse,'Alpha');
  assert.equal(item.total_stock,50); assert.equal(item.mrn_details.receipt_history_summary.total_qty,30);
  const cdHistory = await scalar("select get_stock_mrn_cd_receipt_history('A','Alpha',0,5000)");
  assert.equal(cdHistory.total_qty,30); assert.equal(cdHistory.bonus,3); assert.equal(cdHistory.rows.length,3);
  assert.ok(cdHistory.rows.every(r=>r.warehouse==='Alpha' && r.mrn_no.startsWith('CD')));
  assert.equal((await scalar("select get_stock_mrn_cd_receipt_history('A','Beta',0,5000)")).total_qty,8);
  assert.equal(await scalar("select get_stock_mrn_cd_item('A','Missing')"),null);
  assert.equal((await scalar("select get_stock_mrn_cd_page('Alpha','','','',null,null,'latest_mrn',0,1)")).total,2);
  const before = await scalar('select stock_management_private.mrn_cd_version()');
  await db.exec("update mrn_cd_apg_2026 set total_qty=5 where mrn_no='CD-1'");
  assert.notEqual(await scalar('select stock_management_private.mrn_cd_version()'),before);
  await db.exec("set role authenticated;set test.role='view'");
  assert.equal((await scalar('select get_stock_mrn_cd_register_batch(0,5000)')).total,3);
  await db.exec("set test.role='branch'");
  assert.equal((await scalar('select get_stock_mrn_cd_register_batch(0,5000)')).total,0);
  await db.exec(`reset role;
    insert into mrn_cd_apg_2026(item_code,warehouse,mrn_date,mrn_no,total_qty,bonus,status)
    select 'BULK-'||i,'Alpha','2026-10-29','BULK-'||i,1,0,'approved' from generate_series(1,5002)i;`);
  const bulk=await scalar('select get_stock_mrn_cd_register_batch(0,9000)');
  const tail=await scalar('select get_stock_mrn_cd_register_batch(5000,5000)');
  assert.equal(bulk.rows.length,5000); assert.equal(tail.rows.length,5);
  assert.equal(new Set([...bulk.rows,...tail.rows].map(r=>r.register_key)).size,5005);
  assert.equal(bulk.snapshot_at,tail.snapshot_at);
  await db.exec('set role anon');
  await assert.rejects(()=>scalar('select get_stock_mrn_cd_register_batch(0,5000)'),/permission denied/);
  await db.close();
  console.log('MRN totals and CD SQL passed: exact totals, bonus, separate sources/warehouses, latest-day grouping, complete histories, missing products, revision invalidation and RLS.');
})().catch(error=>{console.error(error);process.exit(1);});
