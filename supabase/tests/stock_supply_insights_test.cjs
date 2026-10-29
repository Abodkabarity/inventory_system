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
  await db.exec(`
    create function stock_management_private.is_view_user() returns boolean language sql stable as $$select coalesce(current_setting('test.inventory_role',true)='view',false)$$;
    create schema cron;
    create function cron.schedule(text,text,text) returns bigint language sql as $$ select 1::bigint $$;
    create table stk_ledger_history(stock_date date,company text,branch_name text,item_code text,actual_qty numeric,
      report_from_date date,report_to_date date,source_branch_missing boolean,imported_at timestamptz default now());
    create table stk_statement_history_2026(branch_name text,item_code text,trans_date date,qty numeric,
      mode text,company text,trans_type text);
    create table stk_statement(branch_name text,item_code text,trans_date date,qty numeric,mode text,
      company text,created_at timestamptz default now());
    create table stk_statement_history_load_progress(company text,from_date date,to_date date,
      complete boolean,committed_rows bigint,expected_rows bigint,updated_at timestamptz default now());
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261022114605_stock_mrn_complete_receipt_totals.sql','utf8').replaceAll('now()','public.fixture_now()'));
  const migration=fs.readFileSync('supabase/migrations/20261023070245_stock_availability_evidence_and_demand.sql','utf8');
  await db.exec(migration.replaceAll('now()','public.fixture_now()'));
  const base={through:'2026-10-21',today:'2026-10-22',baseline_count:1,opening_qty:10,
    current_count:1,current_qty:100,stock_day:'2026-10-21',prior_sales:50,
    days:[{date:'2026-05-01',net:-10,incoming:0},{date:'2026-10-15',net:100,incoming:100,mrn_qty:100}],
    mrns:[{date:'2026-10-15',qty:100,numbers:['M1','M2']}],
    monthly_sales:[{month:'01/2025',total:300},{month:'01/2026',total:100},{month:'10/2026',total:5}]};
  const analyze=p=>scalar('select stock_management_private.analyze_supply($1::jsonb)',[JSON.stringify(p)]);
  const a=await analyze(base);
  assert.equal(a.summary.status,'back_in_store');assert.equal(a.summary.confidence,'verified');
  assert.equal(a.summary.returned_at,'2026-10-15');assert.equal(a.summary.gap_days,166);
  assert.equal(a.summary.received_qty,100);assert.equal(a.detail.monthly[0].prior_year_sales_qty,300);
  assert.equal(a.detail.monthly[4].empty_days,30,'depletion day is partial, not a full empty day');
  assert.equal(a.detail.monthly[9].empty_days,14);assert.equal(a.detail.monthly[9].available_days,6);
  assert.equal(a.detail.monthly[9].partial_days,1);
  assert.equal(a.detail.forecast_status,'branch_availability_required');
  const missing=await analyze({...base,baseline_count:0,opening_qty:null});
  assert.equal(missing.summary.status,'history_needed');assert.equal(missing.summary.gap_days,null);
  assert.equal(missing.detail.issues.includes('opening_missing'),true);
  assert.equal((await analyze({...base,baseline_count:2})).summary.status,'history_needed');
  assert.equal((await analyze({...base,through:null})).summary.status,'history_needed');
  assert.equal((await analyze({...base,bad_company:true})).summary.status,'history_needed');
  assert.equal((await analyze({...base,opening_movements:1})).summary.status,'history_needed');
  const mismatch=await analyze({...base,current_qty:101});
  assert.equal(mismatch.detail.issues.includes('balance_mismatch'),true);
  assert.equal((await analyze({...base,current_count:0})).summary.status,'history_needed');
  assert.equal((await analyze({...base,stock_day:'2026-10-22',bridge_through:'2026-10-21'})).summary.status,'history_needed');
  assert.equal((await analyze({...base,stock_day:'2026-10-22',current_qty:95,bridge_through:'2026-10-22',bridge_net:-5})).summary.status,'back_in_store');
  assert.equal((await analyze({...base,mrns:[{date:'2026-10-15',qty:99}]})).summary.status,'in_store');
  const adjusted=await analyze({...base,days:[base.days[0],{...base.days[1],adjustment:true,mrn_qty:0}]});
  assert.equal(adjusted.summary.status,'in_store','an inventory adjustment is not evidence of a receipt');
  const sameDay=await analyze({...base,days:[base.days[0],{date:'2026-06-10',net:0,incoming:50},base.days[1]]});
  assert.equal(sameDay.summary.gap_days,126,'same-day receipt/outgoing breaks a continuous zero spell');
  const newItem=await analyze({...base,opening_qty:0,prior_sales:0,days:[base.days[1]]});
  assert.equal(newItem.summary.status,'in_store','first observed availability is not a return from a known prior stockout');
  const older=await analyze({...base,today:'2026-12-01'});
  assert.equal(older.summary.status,'in_store','an old receipt is not permanently shown as newly returned');
  const lower=await analyze({...base,opening_qty:0,days:[base.days[1]]});
  assert.equal(lower.summary.at_least,true);
  const negative=await analyze({...base,opening_qty:9,current_qty:99});
  assert.equal(negative.detail.issues.includes('negative_balance'),true);
  assert.equal(negative.summary.status,'history_needed');
  const empty=await analyze({...base,current_qty:0,days:[base.days[0]],mrns:[]});
  assert.equal(empty.summary.status,'store_empty');assert.equal(empty.summary.gap_days,173);
  assert.equal((await analyze({...base,current_qty:100,bridge_net:100,stock_day:'2026-10-22',bridge_through:'2026-10-22',days:[base.days[0]]})).summary.status,'receipt_pending');
  const badSign=await analyze({...base,days:[{...base.days[0],bad_sign:true},base.days[1]]});
  assert.equal(badSign.summary.status,'history_needed');
  // Full refresh, published RPCs, cache generations and rollback on local fixtures.
  await db.exec(`
    truncate stk_ledger;
    insert into stk_statement_history_load_progress values('APG','2026-01-01','2026-10-21',true,2,2,now());
    insert into stk_statement values('Alpha','DUMMY','2026-10-21',0,'IN','APG',now());
    insert into stk_ledger_history values('2026-01-01','Al Ain Pharmacy Group (APG)','STORE','RETURN',10,'2026-01-01','2026-01-01',false,now());
    insert into stk_ledger values('RETURN','STORE',100,'Company','2026-10-21T12:00:00Z');
    insert into stk_statement_history_2026 values
      ('STORE','RETURN','2026-05-01',-10,'Out','APG','StockTransferFrom'),
      ('STORE','RETURN','2026-10-15',100,'IN','APG','MRN');
    insert into mrn_apg_2026(item_code,mrn_date,mrn_no,received_quantity,status,warehouse)
      values('RETURN','2026-10-15','M1',100,'approved','STORE');
    insert into stock_catalog_snapshot(item_code,item_name,payload) values('RETURN','Returned product',
      '{"item_code":"RETURN","item_name":"Returned product","years":{"2025":{"total":50}},"monthly_sales":[{"month":"10/2026","total":5}]}');
  `);
  const refresh=()=>scalar('select stock_management_private.refresh_supply_insights()');
  const before=await scalar('select public.get_stock_workspace_cache_state()');
  const rebuilt=await refresh();assert.equal(rebuilt.status,'complete');
  assert.equal((await scalar("select detail from stock_supply_insights where item_code='RETURN'")).status,'back_in_store');
  assert.equal((await scalar("select public.get_stock_catalog_item('RETURN')")).supply_insight.status,'back_in_store');
  const batch=await scalar('select public.get_stock_catalog_register_batch(0,5000)');
  const list=batch.rows.find(r=>r.item_code==='RETURN');
  assert.equal(list.supply_insight.gap_days,166);assert.equal('monthly' in list.supply_insight,false);
  assert.equal((await scalar("select public.get_stock_catalog_page(p_search=>'RETURN')")).rows[0].supply_insight.status,'back_in_store');
  const priorPayloads=[];
  for(const rpc of ['get_stock_catalog_register_batch','get_stock_management_register_batch']) {
    for(const [offset,limit] of [[0,5000],[1,1],[99999,5000]])
      priorPayloads.push({rpc,offset,limit,value:await scalar(`select public.${rpc}($1,$2)`,[offset,limit])});
  }
  await db.exec(fs.readFileSync('supabase/migrations/20261023073622_stock_supply_bulk_reads_optimized.sql','utf8'));
  for(const p of priorPayloads) assert.deepEqual(await scalar(`select public.${p.rpc}($1,$2)`,[p.offset,p.limit]),p.value,'optimized bulk payload/order/date/cap stays identical');
  const mrnBatch=await scalar('select public.get_stock_management_register_batch(0,5000)');
  assert.equal(mrnBatch.rows.every(r=>r.supply_insight!=null),true);
  const expired=await scalar("select public.get_stock_expiry_page(p_review_state=>'all',p_limit=>5000)");
  assert.equal(expired.rows.every(r=>r.supply_insight!=null),true);
  const version=await scalar('select public.get_stock_workspace_cache_state()');
  assert.notEqual(version.mrn,before.mrn);assert.notEqual(version.expiry,before.expiry);
  assert.equal(version.discovery,before.discovery,'supply analysis must not trigger receipt rediscovery');
  assert.equal((await refresh()).status,'unchanged');

  // v2: an omitted opening is an explicit, qualified business assumption;
  // recent receipts can precede the statement without delaying the return badge.
  await db.exec(fs.readFileSync('supabase/migrations/20261023084336_stock_supply_return_detection_and_month_markers.sql','utf8').replaceAll('now()','public.fixture_now()'));
  await db.exec(fs.readFileSync('supabase/migrations/20261023085238_stock_supply_legacy_rolling_company.sql','utf8').replaceAll('now()','public.fixture_now()'));
  await db.exec(fs.readFileSync('supabase/migrations/20261023091500_stock_supply_known_product_gap_scope.sql','utf8').replaceAll('now()','public.fixture_now()'));
  const assumed=await analyze({...base,baseline_count:0,opening_qty:null,assume_missing_opening:true,
    days:[base.days[1]]});
  assert.equal(assumed.summary.status,'back_in_store');
  assert.equal(assumed.summary.confidence,'inferred');
  assert.equal(assumed.summary.opening_basis,'assumed_zero');
  assert.equal(assumed.summary.at_least,true);
  assert.equal(assumed.detail.opening_qty,0);
  assert.equal((await analyze({...base,baseline_count:2,assume_missing_opening:true})).summary.status,'history_needed');
  assert.equal((await analyze({...base,baseline_count:0,raw_opening_count:1,assume_missing_opening:true})).summary.status,'history_needed');
  assert.equal((await analyze({...base,baseline_count:0,assume_missing_opening:true})).summary.status,'history_needed','assumed zero never overrides negative movements or a mismatched ledger');
  const fresh=await analyze({...base,baseline_count:0,opening_qty:null,prior_sales:0,assume_missing_opening:true,days:[base.days[1]]});
  assert.equal(fresh.summary.status,'in_store');
  assert.equal(fresh.detail.monthly[0].empty_days,0,'pre-introduction unknown months never become outage annotations');
  const notIntroduced=await analyze({...base,opening_qty:0,prior_sales:0,current_qty:0,days:[],mrns:[]});
  assert.equal(notIntroduced.summary.status,'store_empty');
  assert.equal(notIntroduced.summary.gap_days,null,'no invented pre-introduction gap');
  const oldGap=await analyze({...base,today:'2026-12-01'});
  assert.equal(oldGap.summary.status,'in_store');
  assert.equal(oldGap.detail.monthly[5].empty_days,30,'historical gap persists when the product is available again');
  await db.exec(`
    set test.now='2026-10-23T06:00:00Z';
    update stk_ledger set created_at='2026-10-22T12:00:00Z';
    insert into stk_statement values('Alpha','DUMMY','2026-10-22',0,'IN','APG',now());
    insert into stock_catalog_snapshot(item_code,item_name,payload) values
      ('METROLAG','Returned yesterday','{"item_code":"METROLAG","years":{"2025":{"total":404}},"monthly_sales":[{"month":"06/2026","total":4}]}'),
      ('VIRTUAL','Virtual-only receipt','{"item_code":"VIRTUAL","years":{"2025":{"total":10}}}'),
      ('BAD-END','Bad current balance','{"item_code":"BAD-END","years":{"2025":{"total":10}}}'),
      ('DUP-MOVE','Receipt already in statement','{"item_code":"DUP-MOVE","years":{"2025":{"total":10}}}'),
      ('INVALID-OPEN','Malformed source row','{"item_code":"INVALID-OPEN","years":{"2025":{"total":10}}}');
    insert into stk_ledger_history values('2026-01-01','APG','STORE','INVALID-OPEN',10,'2026-01-02','2026-01-02',false,now());
    insert into stk_ledger values
      ('METROLAG','STORE',232,'APG','2026-10-22T12:00:00Z'),
      ('VIRTUAL','STORE',100,'APG','2026-10-22T12:00:00Z'),
      ('BAD-END','STORE',101,'APG','2026-10-22T12:00:00Z'),
      ('DUP-MOVE','STORE',100,'APG','2026-10-22T12:00:00Z'),
      ('INVALID-OPEN','STORE',100,'APG','2026-10-22T12:00:00Z');
    insert into stk_statement_history_2026 values
      ('STORE','METROLAG','2026-06-27',3,'IN','APG','StockTransferTo'),
      ('STORE','METROLAG','2026-06-29',-3,'Out','APG','DVN');
    insert into stk_statement values('STORE','DUP-MOVE','2026-10-22',100,'IN','APG',now());
    insert into mrn_apg_2026(item_code,mrn_date,mrn_no,received_quantity,status,warehouse) values
      ('METROLAG','2026-10-22','106632',160,'approved','STORE'),
      ('METROLAG','2026-10-22','106633',72,'approved','STORE'),
      ('VIRTUAL','2026-10-22','V1',100,'approved','main virtual'),
      ('BAD-END','2026-10-22','B1',100,'approved','STORE'),
      ('DUP-MOVE','2026-10-22','D1',100,'approved','STORE'),
      ('INVALID-OPEN','2026-10-22','I1',100,'approved','STORE');
  `);
  await db.exec('update stk_statement set company=null'); // ordinary APG rolling source
  assert.equal((await refresh()).status,'complete');
  const product=code=>scalar('select detail from stock_supply_insights where item_code=$1',[code]);
  const metrolag=await product('METROLAG');
  assert.equal(metrolag.status,'back_in_store');assert.equal(metrolag.confidence,'inferred');
  assert.equal(metrolag.returned_at,'2026-10-22');assert.equal(metrolag.received_qty,232);
  assert.equal(metrolag.gap_days,114);assert.equal(metrolag.through,'2026-10-22');
  assert.equal(metrolag.events.at(-1).from,'2026-06-30');
  assert.equal(metrolag.monthly.find(m=>m.month==='07/2026').empty_days,31);
  assert.equal(metrolag.history_qty,232);
  assert.equal((await product('VIRTUAL')).status,'history_needed','virtual receipts are not physical STORE returns');
  assert.equal((await product('BAD-END')).status,'history_needed','pending MRN must exactly reconcile the ledger');
  assert.equal((await product('DUP-MOVE')).history_qty,100,'rolling receipt is never counted again as a pending MRN');
  assert.equal((await product('INVALID-OPEN')).status,'history_needed','an invalid source row is not an omitted item');
  for(const rpc of ["get_stock_catalog_item('METROLAG')","get_stock_management_item('A')"])
    assert.equal((await scalar('select public.'+rpc)).supply_insight.through,'2026-10-22');
  const resultList=await scalar('select public.get_stock_catalog_register_batch(0,5000)');
  assert.equal(resultList.rows.find(r=>r.item_code==='METROLAG').supply_insight.received_qty,232);
  const beforeArchive=await product('METROLAG');
  // When the archive catches up, the same receipt is counted once and the result
  // switches from provisional receipt evidence to actual archived movements.
  await db.exec(`
    update stk_statement_history_load_progress set to_date='2026-10-22';
    insert into stk_statement_history_2026 values
      ('STORE','METROLAG','2026-10-22',232,'IN','APG','MRN'),
      ('STORE','DUP-MOVE','2026-10-22',100,'IN','APG','MRN');
  `);
  assert.equal((await refresh()).status,'complete');
  const afterArchive=await product('METROLAG');
  assert.equal(afterArchive.history_qty,beforeArchive.history_qty);
  assert.equal(afterArchive.gap_days,beforeArchive.gap_days);
  assert.equal(afterArchive.returned_at,beforeArchive.returned_at);
  assert.equal(afterArchive.received_qty,232);assert.equal(afterArchive.provisional,false);
  assert.equal((await refresh()).status,'unchanged');


  // Learned demand and continuous effective-supply gaps.
  await db.exec(fs.readFileSync('supabase/migrations/20261023095712_stock_supply_learned_demand_and_continuous_gaps.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261027093853_stock_supply_chart_return_timeline.sql','utf8'));
  const history2025=[151,45,8,10,3,1,41,60,38,16,18,13].map((total,i)=>({month:`${String(i+1).padStart(2,'0')}/2025`,total}));
  const fit=monthly=>scalar('select stock_management_private.fit_supply_demand($1::jsonb)',[JSON.stringify({monthly_sales:monthly})]);
  const fitted=await fit(history2025);
  assert.equal(fitted.status,'ready');assert.equal(fitted.months,12);assert.equal(fitted.validation_months,7);assert.equal(fitted.holdout_months,2);assert.ok(fitted.holdout_mae_qty<fitted.holdout_benchmark_mae_qty);
  assert.ok(fitted.recovery_qty>3);assert.ok(fitted.validation_mae_qty<=fitted.benchmark_mae_qty);
  assert.deepEqual(await fit([...history2025,{month:'01/2026',total:999999}]),fitted,'suspected-shortage year cannot leak into the prior baseline');
  assert.equal((await fit(history2025.map((r,i)=>i>=10?{...r,total:999999}:r))).method,fitted.method,'reserved holdout months cannot choose the method');
  assert.equal((await fit(history2025.slice(0,3))).status,'insufficient_history');
  assert.equal((await fit([...history2025,history2025[0]])).status,'ambiguous_history');
  const monthlyRate=rate=>Array.from({length:12},(_,i)=>({month:`${String(i+1).padStart(2,'0')}/2025`,total:new Date(Date.UTC(2025,i+1,0)).getUTCDate()*rate}));
  const example={...base,through:'2026-10-22',today:'2026-10-23',stock_day:'2026-10-22',current_qty:232,
    baseline_count:0,assume_missing_opening:true,opening_qty:null,prior_sales:404,monthly_sales:history2025,
    days:[{date:'2026-01-24',net:1,incoming:1},{date:'2026-01-26',net:-1,incoming:0},
      {date:'2026-02-07',net:1,incoming:1},{date:'2026-02-09',net:-1,incoming:0},
      {date:'2026-02-14',net:1,incoming:1},{date:'2026-02-17',net:-1,incoming:0},
      {date:'2026-02-21',net:1,incoming:1},{date:'2026-02-23',net:-1,incoming:0},
      {date:'2026-05-23',net:1,incoming:1},{date:'2026-05-25',net:-1,incoming:0},
      {date:'2026-06-20',net:1,incoming:1},{date:'2026-06-22',net:-1,incoming:0},
      {date:'2026-06-27',net:3,incoming:3},{date:'2026-06-29',net:-3,incoming:0},
      {date:'2026-10-22',net:232,incoming:232,mrn_qty:232}],mrns:[{date:'2026-10-22',qty:232}]};
  const smart=await analyze(example);
  assert.equal(smart.summary.gap_days,114,'raw zero-balance gap remains a separate factual measure');
  const effective=smart.detail.effective_supply;
  assert.equal(effective.status,'supply_restored');assert.equal(effective.confidence,'estimated');
  assert.equal(effective.periods.length,1);assert.equal(effective.latest_period.from,'2026-01-02');
  assert.equal(effective.latest_period.days,293);assert.equal(effective.latest_period.months,9);
  assert.equal(effective.latest_period.remaining_days,20);assert.equal(effective.latest_period.small_arrivals,7);
  assert.equal(effective.latest_period.small_arrival_qty,9);assert.equal(effective.latest_period.received_qty,232);
  assert.equal(smart.detail.monthly.find(m=>m.month==='02/2026').empty_days,18);
  assert.equal(smart.detail.monthly.find(m=>m.month==='02/2026').limited_days,28);
  assert.equal('periods' in smart.summary.effective_supply,false,'thin bulk summary');
  const unreconciled=await analyze({...example,current_qty:233});
  assert.equal(unreconciled.detail.effective_supply.status,'history_required');
  assert.equal('latest_period' in unreconciled.detail.effective_supply,false);
  assert.equal(unreconciled.detail.chart_timeline.review_required,true);
  assert.equal(unreconciled.detail.chart_timeline.periods[0].days,293,'endpoint mismatch retains estimated past shortage');
  assert.equal(unreconciled.summary.confidence,'unavailable','chart never upgrades current stock evidence');
  assert.equal('chart_timeline' in unreconciled.summary,false,'timeline remains detail-only, outside 5000-row loading');
  assert.deepEqual(smart.detail.chart_timeline.arrivals.map(r=>[r.date,r.kind,r.qty]),[['2026-10-22','restored',232]],'only physical matched MRNs are return markers');
  const smallDelivery=await analyze({...example,current_qty:3,
    days:[{date:'2026-04-02',net:3,incoming:3,mrn_qty:3}],mrns:[{date:'2026-04-02',qty:3}]});
  assert.equal(smallDelivery.detail.chart_timeline.arrivals[0].kind,'limited');
  assert.equal(smallDelivery.detail.chart_timeline.periods[0].through,'2026-10-22','small delivery does not end the shortage');
  const largeAfterSmall=await analyze({...example,current_qty:235,
    days:[{date:'2026-04-02',net:3,incoming:3,mrn_qty:3},example.days.at(-1)],
    mrns:[{date:'2026-04-02',qty:3},...example.mrns]});
  assert.deepEqual(largeAfterSmall.detail.chart_timeline.arrivals.map(r=>r.kind),['limited','restored']);
  assert.equal(largeAfterSmall.detail.chart_timeline.periods.length,1);
  const missingOpening=await analyze({...example,baseline_count:0,assume_missing_opening:false});
  assert.equal(missingOpening.detail.chart_timeline,undefined,'missing opening is not silently treated as an outage');
  const badMovement=await analyze({...example,days:example.days.map((r,i)=>i===0?{...r,bad_sign:true}:r)});
  assert.equal(badMovement.detail.chart_timeline,undefined,'ambiguous history never produces return claims');
  const large=await analyze({...base,monthly_sales:monthlyRate(2),opening_qty:0,days:[{date:'2026-10-15',net:100,incoming:100,mrn_qty:100}]});
  assert.equal(large.detail.effective_supply.model.recovery_qty,28);
  const slow=await analyze({...base,monthly_sales:monthlyRate(.02),opening_qty:0,current_qty:1,days:[{date:'2026-10-15',net:1,incoming:1,mrn_qty:1}],mrns:[{date:'2026-10-15',qty:1}]});
  assert.equal(slow.detail.effective_supply.model.recovery_qty,1);
  assert.equal(slow.detail.effective_supply.status,'supply_restored','a small receipt can restore a genuinely slow seller');
  const ongoing=await analyze({...example,current_qty:3,days:example.days.slice(0,-2),mrns:[]});
  assert.equal(ongoing.detail.effective_supply.status,'limited_supply');
  assert.equal(ongoing.detail.effective_supply.latest_period.returned_at,null);
  const recoveredOld=await analyze({...example,today:'2026-12-10'});
  assert.equal(recoveredOld.detail.effective_supply.status,'adequate_supply');
  assert.equal(recoveredOld.detail.effective_supply.periods.length,1,'historical span remains after recovery ages');
  const newShortage=await analyze({...example,baseline_count:1,assume_missing_opening:false,opening_qty:20,current_qty:2,
    days:[{date:'2026-02-01',net:-20,incoming:0},{date:'2026-03-20',net:232,incoming:232,mrn_qty:232},{date:'2026-10-20',net:-230,incoming:0}],mrns:[{date:'2026-03-20',qty:232}]});
  assert.equal(newShortage.detail.effective_supply.latest_period.from,'2026-10-21');
  assert.equal(newShortage.detail.effective_supply.latest_period.days,2,'current shortage is not replaced with an unrelated old long gap');
  const lowUnknown=await analyze({...base,monthly_sales:history2025.slice(0,2)});
  assert.equal(lowUnknown.detail.effective_supply.status,'insufficient_history');
  const adjustedEffective=await analyze({...example,days:example.days.map((r,i)=>i===example.days.length-1?{...r,adjustment:true}:r)});
  assert.equal(adjustedEffective.detail.effective_supply.status,'limited_supply','an inventory adjustment cannot certify meaningful replenishment');
  await db.query("update stock_catalog_snapshot set payload=jsonb_set(payload,'{monthly_sales}',$1::jsonb) where item_code='METROLAG'",[JSON.stringify(history2025)]);
  assert.equal((await scalar('select stock_management_private.refresh_supply_insights(true)')).status,'complete');
  const smartFull=await product('METROLAG');
  assert.equal(smartFull.effective_supply.latest_period.days,293);
  assert.equal((await scalar("select public.get_stock_catalog_item('METROLAG')")).supply_insight.effective_supply.status,'supply_restored');
  const smartBatch=await scalar('select public.get_stock_catalog_register_batch(0,5000)');
  assert.equal(smartBatch.rows.find(r=>r.item_code==='METROLAG').supply_insight.effective_supply.latest_period.months,9);
  console.log('METROLAG learned baseline:',JSON.stringify(fitted));

  // Every approved warehouse is STORE supply. Historical chart evidence may
  // survive a missing current row, without inventing a current STORE balance.
  await db.exec(fs.readFileSync('supabase/migrations/20261027124657_stock_supply_all_warehouse_receipts_and_historical_review.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261027125211_stock_supply_virtual_receipt_movement_correlation.sql','utf8'));
  const noCurrent=await analyze({...example,current_count:0,current_qty:null});
  assert.deepEqual(noCurrent.detail.issues,['current_stock_missing']);
  assert.equal(noCurrent.detail.current_qty,null);
  assert.equal(noCurrent.summary.confidence,'unavailable');
  assert.equal(noCurrent.detail.effective_supply.status,'history_required');
  assert.equal(noCurrent.detail.chart_timeline.review_required,true);
  assert.equal(noCurrent.detail.chart_timeline.periods[0].days,293);
  assert.equal(noCurrent.detail.chart_timeline.arrivals[0].qty,232);
  assert.equal('chart_timeline' in noCurrent.summary,false);
  for(const changes of [
    {current_count:2},
    {current_count:0,current_qty:null,stock_day:null},
    {current_count:0,current_qty:null,baseline_count:0,assume_missing_opening:false},
    {current_count:0,current_qty:null,days:example.days.map((r,i)=>i===0?{...r,bad_sign:true}:r)},
  ]) assert.equal((await analyze({...example,...changes})).detail.chart_timeline,undefined);
  await db.exec(`
    set test.now='2026-10-24T06:00:00Z';
    insert into stk_statement values('Alpha','DUMMY','2026-10-23',0,'IN','APG',now());
    insert into stock_catalog_snapshot(item_code,item_name,payload) values
      ('ALL-WAREHOUSES','All routing values','{"item_code":"ALL-WAREHOUSES","years":{"2025":{"total":100}}}'),
      ('ARCHIVED-VIRTUAL','Matched virtual receipt','{"item_code":"ARCHIVED-VIRTUAL","years":{"2025":{"total":100}}}'),
      ('ARCHIVED-MISMATCH','Different receipt total','{"item_code":"ARCHIVED-MISMATCH","years":{"2025":{"total":100}}}');
    insert into stk_ledger values
      ('ALL-WAREHOUSES','STORE',55,'APG','2026-10-23T12:00:00Z'),
      ('ARCHIVED-VIRTUAL','STORE',40,'APG','2026-10-23T12:00:00Z'),
      ('ARCHIVED-MISMATCH','STORE',40,'APG','2026-10-23T12:00:00Z');
    insert into stk_statement_history_2026 values
      ('STORE','ARCHIVED-VIRTUAL','2026-10-22',40,'IN','APG','StockTransferTo'),
      ('STORE','ARCHIVED-MISMATCH','2026-10-22',40,'IN','APG','StockTransferTo');
    insert into mrn_apg_2026(item_code,mrn_date,mrn_no,received_quantity,status,warehouse) values
      ('ALL-WAREHOUSES','2026-10-23','W1',10,'approved','STORE'),
      ('ALL-WAREHOUSES','2026-10-23','W2',10,'approved','main virtual'),
      ('ALL-WAREHOUSES','2026-10-23','W3',10,'approved','new virtual'),
      ('ALL-WAREHOUSES','2026-10-23','W4',10,'approved','future warehouse'),
      ('ALL-WAREHOUSES','2026-10-23','W5',15,'approved',null),
      ('ALL-WAREHOUSES','2026-10-23','W6',1000,'pending','store'),
      ('ARCHIVED-VIRTUAL','2026-10-22','AV1',40,'approved','new virtual'),
      ('ARCHIVED-MISMATCH','2026-10-22','AM1',30,'approved','new virtual');
  `);
  assert.equal((await scalar('select stock_management_private.refresh_supply_insights(true)')).status,'complete');
  const routed=await product('ALL-WAREHOUSES');
  assert.equal(routed.history_qty,55,'all approved routing warehouses are counted once');
  assert.equal(routed.received_qty,55);
  assert.equal(routed.status,'back_in_store');
  assert.equal((await product('ARCHIVED-VIRTUAL')).history_qty,40,'archived physical receipt is never added twice');
  assert.equal((await product('ARCHIVED-VIRTUAL')).events.at(-1).mrn_linked,true,'virtual MRN links to its physical receipt');
  assert.equal((await product('ARCHIVED-MISMATCH')).events.at(-1).mrn_linked,false,'a different inbound amount is not proof of the MRN');
  await db.query("update stock_catalog_snapshot set payload=jsonb_set(payload,'{monthly_sales}',$1::jsonb) where item_code='ARCHIVED-VIRTUAL'",[JSON.stringify(history2025)]);
  await scalar('select stock_management_private.refresh_supply_insights(true)');
  assert.equal((await product('ARCHIVED-VIRTUAL')).chart_timeline.arrivals[0].qty,40);

  const saved=await db.query('select * from stock_supply_insights order by item_code');
  const state=await db.query('select * from stock_supply_insight_state');
  await db.exec('alter table stock_supply_insights add constraint force_failure check(false) not valid');
  await assert.rejects(()=>scalar('select stock_management_private.refresh_supply_insights(true)'),/force_failure/);
  assert.deepEqual(await db.query('select * from stock_supply_insights order by item_code'),saved);
  assert.deepEqual(await db.query('select * from stock_supply_insight_state'),state);
  await db.exec(`set role authenticated; set test.inventory_role='branch'`);
  assert.equal(Number(await scalar('select count(*) from stock_supply_insights')),0);
  await assert.rejects(()=>refresh(),/permission denied/);
  await assert.rejects(()=>analyze(base),/permission denied/);
  await db.exec("set test.inventory_role='view'");
  assert.ok(Number(await scalar('select count(*) from stock_supply_insights'))>0);
  await assert.rejects(()=>refresh(),/permission denied/);
  await db.exec('reset role; set role anon');
  await assert.rejects(()=>scalar('select * from stock_supply_insights'),/permission denied/);
  await db.close();
  console.log('Supply evidence SQL passed: bounded daily gaps, MRN correlation, missing/negative/adjusted/ambiguous histories, endpoint reconciliation, separate sales scopes, all workspaces, thin 5000-row payloads, cache revisions, unchanged discovery, atomic rollback and inventory RLS.');
})().catch(error=>{console.error(error.stack?.split("\n").slice(0,6).join("\n"));process.exit(1);});
