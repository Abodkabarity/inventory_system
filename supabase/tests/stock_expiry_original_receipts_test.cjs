// Isolated PostgreSQL regression. No credentials or production data writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');
const migration = 'supabase/migrations/20261102060736_stock_expiry_reconcile_original_receipts.sql';

(async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema stock_management_private;
      create table public.mrn_apg_2026(item_code text,item_name text,mrn_no text,mrn_date date,
        warehouse text,status text,expiry_date date,total_qty numeric,ordered_quantity numeric,
        supplier text,company text,category_1 text,vendor text);
      create table public.stock_management_snapshot(item_code text primary key,payload jsonb,updated_at timestamptz default now());
      create table public.stock_expiry_watch_state(singleton boolean,receipt_start date,
        last_scanned_at timestamptz,scanned_through date);
      insert into public.stock_expiry_watch_state values(true,(now() at time zone 'Asia/Dubai')::date-40,null,null);
      create table public.stock_expiry_alert_receipts(item_code text,expiry_date date,mrn_date date,
        mrn_no text,warehouse text,received_qty numeric check(received_qty>0),ordered_qty numeric,
        vendor text,product_data jsonb not null default '{}',first_detected_at timestamptz default now(),
        last_changed_at timestamptz default now(),primary key(item_code,expiry_date,mrn_date,mrn_no,warehouse));
      create table public.stock_expiry_receipt_reviews(item_code text,expiry_date date,mrn_date date,
        note text,is_reviewed boolean,primary key(item_code,expiry_date,mrn_date));
      create function stock_management_private.discover_expiry_receipts() returns jsonb
        language sql security definer set search_path='' as $$select '{}'::jsonb$$;
      revoke all on function stock_management_private.discover_expiry_receipts() from public,anon,authenticated,service_role;
      grant usage on schema public,stock_management_private to authenticated,anon,service_role;
      grant select on public.stock_expiry_alert_receipts,public.stock_management_snapshot to authenticated;
      alter table public.stock_expiry_alert_receipts enable row level security;
      create policy inventory_read on public.stock_expiry_alert_receipts to authenticated
        using(current_setting('test.role',true) in ('inventory','view'));
      set test.role='inventory';
      insert into public.stock_expiry_alert_receipts(item_code,expiry_date,mrn_date,mrn_no,warehouse,received_qty,ordered_qty)
      select code,(now() at time zone 'Asia/Dubai')::date+case when code='CORRECTED' then -154 else 30 end,
        (now() at time zone 'Asia/Dubai')::date-case when code='TODAY-WITHDRAWN' then 0 else 3 end,
        'original-'||code,'store',72,100
      from unnest(array['CORRECTED','KEEP','TWO-DATES','CANCELLED','ZERO','OTHER-WAREHOUSE','DATE-FIX','TODAY-WITHDRAWN']) code;
      insert into public.stock_expiry_receipt_reviews select item_code,expiry_date,mrn_date,'Original review note',true
        from public.stock_expiry_alert_receipts;
      insert into public.stock_management_snapshot
        select code,jsonb_build_object('item_code',code,'item_name','Product '||code,
          'total_stock',123,'store_stock',23,'branches_stock',100,'last_mrn_date',(now() at time zone 'Asia/Dubai')::date,
          'last_mrn_no','NEWER-MRN','expiry_date',(now() at time zone 'Asia/Dubai')::date+730)
        from unnest(array['CORRECTED','KEEP','TWO-DATES','CANCELLED','ZERO','OTHER-WAREHOUSE','DATE-FIX']) code;
      insert into public.mrn_apg_2026(item_code,mrn_no,mrn_date,warehouse,status,expiry_date,total_qty,ordered_quantity)
      select item_code,mrn_no,mrn_date,'store',case when item_code='CANCELLED' then 'cancelled' else 'approved' end,
        case when item_code='CORRECTED' then (now() at time zone 'Asia/Dubai')::date+730 else expiry_date end,
        case when item_code='ZERO' then 0 else 72 end,100
      from public.stock_expiry_alert_receipts where item_code in ('CORRECTED','CANCELLED','ZERO','TWO-DATES','DATE-FIX');
      update public.mrn_apg_2026 set mrn_date=mrn_date-1 where item_code='DATE-FIX';
      insert into public.mrn_apg_2026(item_code,mrn_no,mrn_date,warehouse,status,expiry_date,total_qty,ordered_quantity)
      select item_code,case when item_code='OTHER-WAREHOUSE' then mrn_no else 'NEWER-MRN' end,
        (now() at time zone 'Asia/Dubai')::date,
        case when item_code='OTHER-WAREHOUSE' then 'main virtual' else 'store' end,'approved',
        case when item_code='TWO-DATES' then expiry_date else (now() at time zone 'Asia/Dubai')::date+730 end,28,100
      from public.stock_expiry_alert_receipts where item_code in ('KEEP','TWO-DATES','OTHER-WAREHOUSE');
    `);
    const old = fs.readFileSync('supabase/migrations/20261026070131_stock_expiry_group_by_receipt_day.sql','utf8');
    await db.exec(old.match(/create or replace view public\.stock_expiry_candidates[\s\S]*?from enriched;/i)[0]);
    await db.exec('grant select on public.stock_expiry_candidates to authenticated');
    const scalar = async (sql,params=[]) => Object.values((await db.query(sql,params)).rows[0])[0];
    const sourceBefore = await scalar('select jsonb_agg(to_jsonb(m) order by item_code,mrn_no,mrn_date) from public.mrn_apg_2026 m');
    const notesBefore = await scalar('select jsonb_agg(to_jsonb(r) order by item_code) from public.stock_expiry_receipt_reviews r');
    const viewAcl = await scalar("select relacl::text from pg_class where oid='public.stock_expiry_candidates'::regclass");
    const functionAcl = await scalar("select proacl::text from pg_proc where oid='stock_management_private.discover_expiry_receipts()'::regprocedure");
    await db.exec(fs.readFileSync(migration,'utf8'));
    assert.deepEqual(await scalar('select jsonb_agg(to_jsonb(m) order by item_code,mrn_no,mrn_date) from public.mrn_apg_2026 m'),sourceBefore,'source dates and quantities never rewritten');
    assert.deepEqual(await scalar('select jsonb_agg(to_jsonb(r) order by item_code) from public.stock_expiry_receipt_reviews r'),notesBefore,'all original notes/reviews retained');
    assert.equal(await scalar("select count(*)::int from public.stock_expiry_alert_receipts where item_code in ('CORRECTED','CANCELLED','ZERO','TODAY-WITHDRAWN')"),0);
    assert.equal(await scalar('select count(*)::int from stock_management_private.expiry_receipt_corrections'),5);
    assert.equal(await scalar("select count(*)::int from stock_management_private.expiry_receipt_corrections where reason='today_receipt_withdrawn'"),1);
    const original = await scalar("select saved_receipt from stock_management_private.expiry_receipt_corrections where saved_receipt->>'item_code'='CORRECTED'");
    assert.equal(original.mrn_no,'original-CORRECTED');
    assert.equal(Number(original.received_qty),72);
    assert.equal(await scalar("select jsonb_array_length(source_receipts) from stock_management_private.expiry_receipt_corrections where saved_receipt->>'item_code'='CORRECTED'"),1);
    assert.equal(await scalar("select count(*)::int from public.stock_expiry_alert_receipts where item_code in ('KEEP','OTHER-WAREHOUSE')"),2,'new voucher or other warehouse cannot erase historical evidence');
    const dates=(await db.query("select last_receipt_date::text,product_data from public.stock_expiry_candidates where item_code='TWO-DATES' order by last_receipt_date")).rows;
    assert.equal(dates.length,2,'same product/expiry on distinct MRN days remains separate');
    assert.notEqual(dates[0].last_receipt_date,dates[1].last_receipt_date);
    for(const row of dates) {
      assert.equal(row.product_data.last_mrn_date,row.last_receipt_date,'latest snapshot must not replace original MRN date');
      assert.equal(row.product_data.total_stock,123,'whole-product stock remains current');
    }
    assert.equal(dates[0].product_data.last_mrn_no,'original-TWO-DATES');
    assert.equal(dates[1].product_data.last_mrn_no,'NEWER-MRN');
    const fixed=(await db.query("select a.mrn_date::text,m.mrn_date::text as actual from public.stock_expiry_alert_receipts a join public.mrn_apg_2026 m using(item_code,mrn_no,warehouse) where a.item_code='DATE-FIX'")).rows;
    assert.equal(fixed.length,1); assert.equal(fixed[0].mrn_date,fixed[0].actual,'corrected date is taken only from the same source MRN');
    const stable=await scalar("select jsonb_agg(to_jsonb(a) order by item_code,mrn_date) from public.stock_expiry_alert_receipts a");
    await scalar('select stock_management_private.discover_expiry_receipts()');
    assert.deepEqual(await scalar("select jsonb_agg(to_jsonb(a) order by item_code,mrn_date) from public.stock_expiry_alert_receipts a"),stable,'repeat discovery is idempotent');
    assert.equal(await scalar('select count(*)::int from stock_management_private.expiry_receipt_corrections'),5);
    assert.equal(await scalar("select relacl::text from pg_class where oid='public.stock_expiry_candidates'::regclass"),viewAcl);
    assert.equal(await scalar("select proacl::text from pg_proc where oid='stock_management_private.discover_expiry_receipts()'::regprocedure"),functionAcl);
    assert.equal(await scalar("select has_table_privilege('authenticated','stock_management_private.expiry_receipt_corrections','select')"),false);
    assert.equal(await scalar("select has_function_privilege('authenticated','stock_management_private.discover_expiry_receipts()','execute')"),false);
    assert.equal(await scalar("select relrowsecurity from pg_class where oid='stock_management_private.expiry_receipt_corrections'::regclass"),true);
    await db.exec('set role authenticated');
    assert.ok(await scalar('select count(*)::int from public.stock_expiry_candidates')>0);
    await db.exec("set test.role='unrelated'");
    assert.equal(await scalar('select count(*)::int from public.stock_expiry_candidates'),0,'view preserves caller RLS');
    await db.exec('reset role');
    // A failed audit insert rolls back invalidation rather than losing evidence.
    await db.exec(`insert into public.stock_expiry_alert_receipts(item_code,expiry_date,mrn_date,mrn_no,warehouse,received_qty)
      select 'CORRECTED',(now() at time zone 'Asia/Dubai')::date-154,mrn_date,mrn_no,warehouse,72
      from public.mrn_apg_2026 where item_code='CORRECTED';
      create function stock_management_private.fail_audit() returns trigger language plpgsql as $$begin raise exception 'audit unavailable'; end$$;
      create trigger audit_failure before insert on stock_management_private.expiry_receipt_corrections
        for each row execute function stock_management_private.fail_audit();`);
    await assert.rejects(scalar('select stock_management_private.discover_expiry_receipts()'),/audit unavailable/);
    assert.equal(await scalar("select count(*)::int from public.stock_expiry_alert_receipts where item_code='CORRECTED'"),1);
    console.log('PASS: original MRN identity, historical corrections, private atomic audit, durable missing history, separate receipt days, current stock, notes, idempotence, unchanged ACLs and RLS.');
  } finally { await db.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
