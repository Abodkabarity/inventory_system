// Isolated PostgreSQL regression: run both complete builders against equivalent
// catalogs, then test APG eligibility, latest import precedence and atomic failure.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');

(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema stock_management_private;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function public.item_tracker_my_role() returns text language sql stable as
      $$ select current_setting('test.inventory_role',true) $$;
    create function public._norm_text(text) returns text language sql immutable as
      $$ select lower(btrim(coalesce($1,''))) $$;
    create table public.item_report_apg (
      item_code text,item_name text,category text,supplier text,company text,
      main_ingredient text,indication text,sub_category text,item_status text,
      is_block text,status text,added_date_time timestamptz,created_at timestamptz,all_barcode jsonb);
    create table public.item_report(like public.item_report_apg);
    create table public.stock_catalog_snapshot (
      item_code text primary key,item_name text,category text,supplier text,
      total_stock numeric,days_on_hand numeric,sales_2026 numeric,demand_surge boolean,
      payload jsonb,updated_at timestamptz default now());
    create table public.branches(branch_name text,branch_group text,is_active boolean,branch_type text);
    create table public.stk_ledger(item_code text,branch_name text,actual_qty numeric,created_at timestamptz);
    create table public.sales_last_45_days(item_code text,branch_name text,inv_date date,qty numeric);
    create table public.sales_history(item_code text,branch_name text,month text,cash numeric,insurance numeric,online numeric);
    create table public.sales_history_2025(like public.sales_history);
    create table public.mrn_apg_2026(item_code text,mrn_date date,mrn_no text,status text,warehouse text,received_quantity numeric);
    create table public.daily_order(run_date date,item_code text,branch text,reorder_qty_num numeric,
      reorder_qty text,final_reorder_qty_store_stock_gt_0 text,reason text,tma_qty numeric,branch_formulary text);
    create table public.branch_formulary(item_code text,branch_name text,revised_branch_formulary text,
      revised_date date,created_at timestamptz,id bigint);
    insert into public.branches values ('Alpha','APG',true,'Retail'),('Beta','71',true,'Retail'),
      ('Ghost','APG',false,'Retail'),('STORE','STORE',true,'Warehouse');
    insert into public.stk_ledger values ('A','STORE',50,now()),(' A ','Alpha',5,now()),
      ('A','Alpha',7,now()),('A','Beta',3,now()),('A','Ghost',999,now());
    insert into public.sales_last_45_days values
      ('A','Alpha',current_date-44,42),('A','Alpha',current_date,12),
      ('A','Beta',current_date,-1),('A','Ghost',current_date,999);
    insert into public.sales_history_2025 values ('A','Alpha','01/2025',10,2,1),('A','Beta','02/2025',-2,0,0);
    insert into public.sales_history values ('A','Alpha','01/2026',20,4,2),('A','Beta','02/2026',-3,0,0);
    insert into public.daily_order values (current_date,'A','Alpha',5,'5','4','',0,'FORMULARY'),
      (current_date,'A','Beta',2,'2','1','',0,'FORMULARY');
    insert into public.mrn_apg_2026 values ('A',current_date,'MRN1','approved','STORE',50);
    set request.jwt.claims='{"role":"service_role"}';
  `);
  const base = {item_name:'APG product',category:'Category A',supplier:'Supplier A',company:'Company A',
    main_ingredient:'Ingredient A',indication:'Indication A',sub_category:'Sub-category A',
    item_status:'1#NORMAL PURCHASE',is_block:'unchecked',status:'active',
    added_date_time:'2026-10-01T23:30:00Z',created_at:'2026-10-20T00:00:00Z',all_barcode:['123']};
  const insert = async (code,patch={}) => {
    const row={...base,item_code:code,...patch};
    const keys=Object.keys(row);
    await db.query(`insert into public.item_report_apg (${keys.join(',')}) values (${keys.map((_,i)=>'$'+(i+1)).join(',')})`,
      keys.map(k=>k==='all_barcode'?JSON.stringify(row[k]):row[k]));
  };
  await insert(' A ');
  await insert('B',{item_status:'2#DIRECT PURCHASE'});
  await insert('C',{item_status:' 3#DELISTED ',status:' ACTIVE ',is_block:' UNCHECKED '});
  // Equivalent old source gives a full-payload reference for all calculations.
  await db.exec('insert into public.item_report select * from public.item_report_apg');
  const oldSource=fs.readFileSync('supabase/migrations/20261019111452_stock_catalog_participating_order_branches.sql','utf8');
  const oldBuilder=oldSource.match(/CREATE OR REPLACE FUNCTION stock_management_private\.refresh_catalog\(\).*?\$function\$\s*;/s)[0]
    .replace("to_jsonb(i)-'created_at'", "to_jsonb(i)-'created_at'-'all_barcode'");
  await db.exec(oldBuilder);
  await db.exec('select stock_management_private.refresh_catalog()');
  const reference=(await db.query("select item_code,payload-'meta' payload from stock_catalog_snapshot order by item_code")).rows;
  for(const [code,patch] of [
    ['BLOCKED',{is_block:'checked'}],['INACTIVE',{status:'inactive'}],['NULL_ACTIVE',{status:null}],
    ['NULL_BLOCK',{is_block:null}],['NULL_STATUS',{item_status:null}],['FOUR',{item_status:'4#SERVICE'}],
    ['TEN',{item_status:'10#OTHER'}],['THIRTY',{item_status:'30#OTHER'}],['EMPTY_CODE',{item_code:' '}],
    ['OLD_ALLOWED',{created_at:'2026-10-19'}],['OLD_ALLOWED',{is_block:'checked'}],
    ['TIE_BLOCKED',{}],['TIE_BLOCKED',{is_block:'checked'}],
    ['TIE_INACTIVE',{}],['TIE_INACTIVE',{status:'inactive'}],
    ['TIE_FOUR',{}],['TIE_FOUR',{item_status:'4#SERVICE'}],
  ]) await insert(code,patch);
  const migration=fs.readFileSync('supabase/migrations/20261021082126_stock_catalog_apg_eligible_products.sql','utf8');
  await db.exec(migration);
  await db.exec(fs.readFileSync('supabase/migrations/20261021083257_stock_catalog_apg_refresh_plan.sql','utf8'));
  await db.exec(`alter table sales_last_45_days add column inv_type text,add column sales_type text,add column customer_name text;
    update sales_last_45_days set sales_type='POS Invoice',inv_type='Cash';
    update sales_last_45_days set inv_type='Insurance',customer_name='National Health Insurance Company - Daman Basic'
      where item_code='A' and branch_name='Alpha' and inv_date=current_date;
    update sales_last_45_days set inv_type=' Direct Insurance ',customer_name=' National Health Insurance Company - Daman Thiqa '
      where branch_name='Beta';
    insert into sales_last_45_days values
      ('A','Alpha',current_date-1,2.25,'Delivery (Cash)','Delivery Invoice',null),
      ('A','Alpha',current_date-1,-2.25,'Return Delivery (Cash)','Return Delivery Invoice',null),
      ('A','Alpha',current_date-3,0.5,'insurance','POS Invoice','Other company'),
      ('A','Alpha',current_date-4,-0.5,'dirict insurance','Return POS Invoice',null),
      ('A','Alpha',current_date-5,0.75,'Insurance','POS Invoice','NATIONAL HEALTH INSURANCE COMPANY - DAMAN BASIC'),
      ('A','Alpha',current_date-5,-0.75,'Cash Prescription','Return POS Invoice',null);
    create function stock_management_private.catalog_cache_version(boolean) returns text
      language sql stable as $$ select 'test-version'::text $$;`);
  await db.exec(fs.readFileSync('supabase/migrations/20261021115546_stock_catalog_daily_sales_mix.sql','utf8'));
  const plannerBefore=(await db.query('show enable_nestloop')).rows;
  await db.exec('select stock_management_private.refresh_catalog()');
  assert.deepEqual((await db.query('show enable_nestloop')).rows,plannerBefore,'planner setting is restored outside the builder');
  assert.deepEqual((await db.query("select item_code,payload-'meta'-'daily_sales_45d'-'daily_sales_45d_available' payload from stock_catalog_snapshot order by item_code")).rows,reference,
    'APG selection preserves exact stock, signed sales, distribution, dates and monthly analytics');
  const a=(await db.query("select payload from stock_catalog_snapshot where item_code='A'")).rows[0].payload;
  assert.equal(a.total_stock,60); assert.equal(a.apg_stock,60); assert.equal(a.stock_71,3);
  assert.equal(a.recent_sales,53); assert.equal(a.last_3_sales,11); assert.equal(a.baseline_sales,42);
  assert.equal(a.years['2025'].total,11); assert.equal(a.years['2026'].total,23);
  assert.equal(a.distribution.reorder,2); assert.equal(a.distribution.final_qty,5);
  assert.equal(a.added_date_time,'2026-10-02'); assert.equal(a.meta.catalog_source,'item_report_apg');
  assert.equal(a.all_barcode,undefined);
  assert.equal(a.daily_sales_45d_available,true);
  const daily=a.daily_sales_45d;
  const totals=key=>daily.reduce((n,d)=>n+Number(d[key]),0);
  assert.equal(totals('total'),a.recent_sales);
  assert.equal(totals('cash'),41.25);
  assert.equal(totals('insurance_basic'),12.75);
  assert.equal(totals('insurance_thiqa'),-1);
  assert.equal(totals('online'),0);
  assert.equal(totals('other_insurance'),0);
  assert.equal(daily.filter(d=>d.other_insurance<0).length,1);
  assert.deepEqual(daily.map(d=>d.date),daily.map(d=>d.date).sort());
  const noSales=(await db.query("select payload from stock_catalog_snapshot where item_code='B'")).rows[0].payload;
  assert.deepEqual(noSales.daily_sales_45d,[]);
  const page=(await db.query('select public.get_stock_catalog_page(p_limit=>1) data')).rows[0].data;
  const batch=(await db.query('select public.get_stock_catalog_register_batch(0,5000) data')).rows[0].data;
  assert.equal(page.rows.some(r=>'daily_sales_45d' in r),false);
  assert.equal(batch.rows.some(r=>'daily_sales_45d' in r),false);
  for(const field of ['category','supplier','main_ingredient','indication','sub_category'])assert.equal(a[field],base[field]);
  // APG is authoritative, even if Item Report contains unrelated identities/facts.
  await db.exec("update item_report set item_name='Legacy name'; insert into item_report(item_code) values('LEGACY_ONLY')");
  await db.exec('select stock_management_private.refresh_catalog()');
  assert.equal((await db.query("select item_name from stock_catalog_snapshot where item_code='A'")).rows[0].item_name,'APG product');
  await insert('NEW_ALLOWED',{created_at:'2026-10-19',is_block:'checked'});
  await insert('NEW_ALLOWED',{});
  await db.exec('select stock_management_private.refresh_catalog()');
  assert.equal((await db.query("select count(*)::int n from stock_catalog_snapshot where item_code='NEW_ALLOWED'")).rows[0].n,1);
  // Atomic empty-source failure must retain the previously published snapshot.
  const before=(await db.query('select * from stock_catalog_snapshot order by item_code')).rows;
  await db.exec("update item_report_apg set status='inactive'");
  await assert.rejects(db.exec('select stock_management_private.refresh_catalog()'),/No eligible active APG products/);
  assert.deepEqual((await db.query('select * from stock_catalog_snapshot order by item_code')).rows,before);
  await db.exec("set request.jwt.claims='{}'; set test.inventory_role='branch'");
  await assert.rejects(db.exec('select stock_management_private.refresh_catalog()'),/Inventory access required/);
  await db.exec('grant usage on schema stock_management_private to authenticated,anon,service_role; set role authenticated');
  await assert.rejects(db.exec('select stock_management_private.refresh_catalog()'),/permission denied/);
  await db.exec('reset role; set role anon');
  await assert.rejects(db.exec('select stock_management_private.refresh_catalog()'),/permission denied/);
  await db.exec('reset role'); await db.close();
  console.log('APG catalog: exact analytics equivalence, metadata, eligibility, duplicate precedence, atomic rollback and permissions passed.');
})().catch(error=>{console.error(error);process.exitCode=1;});
