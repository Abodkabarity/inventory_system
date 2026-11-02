// Isolated PostgreSQL regression. No credentials or production writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {PGlite} = require(process.env.STOCK_CACHE_PGLITE_MODULE || '@electric-sql/pglite');
const catalogFile = 'supabase/migrations/20261030094656_stock_catalog_bulk_single_serialization.sql';
const mrnFile = 'supabase/migrations/20261030094953_stock_mrn_bulk_single_serialization.sql';
const baselineFile = 'supabase/tests/fixtures/stock_bulk_serialization_baseline.sql';

(async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema stock_management_private; create schema baseline;
      grant usage on schema public,stock_management_private,baseline to authenticated,service_role;
      create table stock_catalog_snapshot(item_code text primary key,payload jsonb);
      create table stock_management_snapshot(item_code text primary key,last_mrn_date date,payload jsonb,updated_at timestamptz);
      create table mrn_apg_2026(item_code text,mrn_date date,mrn_no text,expiry_date date,status text,
        warehouse text,total_qty numeric,received_quantity numeric,bonus numeric,ordered_quantity numeric,reference text,vendor text);
      create table stock_supply_insights(item_code text primary key,summary jsonb,updated_at timestamptz);
      create table stock_workspace_cache_revisions(source text primary key,revision bigint);
      insert into stock_workspace_cache_revisions values('mrn_receipts',1);
      create table purchase_status_items(item_code text,status_id bigint);
      create table purchase_status_options(id bigint primary key,name text,is_active boolean);
      create view availability_kpi_purchase_status with(security_invoker=true) as
        select btrim(i.item_code) item_code,i.status_id,o.name status_name
        from purchase_status_items i left join purchase_status_options o on o.id=i.status_id
        where nullif(btrim(i.item_code),'') is not null;
      create view stock_management_private.mrn_source_lines with(security_invoker=true) as
        select 'store'::text scope,btrim(item_code) item_code,btrim(warehouse) warehouse,
          mrn_date,coalesce(mrn_no,'') mrn_no,expiry_date,ordered_quantity,
          coalesce(total_qty,0) total_qty,coalesce(bonus,0) bonus,reference,vendor
        from public.mrn_apg_2026 where lower(btrim(status))='approved';
      create function stock_management_private.purchase_status_version() returns text language sql stable as $$
        select 'purchase-v1:'||md5(coalesce(string_agg(jsonb_build_array(item_code,status_id,status_name)::text,
          ',' order by item_code,status_id,status_name),'')) from public.availability_kpi_purchase_status;
      $$;
    `);
    const baseline = fs.readFileSync(baselineFile, 'utf8');
    const functions = baseline.match(/CREATE OR REPLACE FUNCTION[\s\S]*?\$function\$[\s\S]*?\$function\$;/g);
    assert.equal(functions.length, 4);
    for (const name of ['reference_version','add_reference_columns','get_stock_catalog_register_batch','get_stock_management_register_batch']) {
      await db.exec(functions.find(sql => sql.split('\n')[0].includes(`.${name}(`)));
    }
    for (const [publicName, oldName] of [
      ['get_stock_catalog_register_batch','catalog_batch'],
      ['get_stock_management_register_batch','mrn_batch'],
    ]) {
      const original = functions.find(sql => sql.startsWith(`CREATE OR REPLACE FUNCTION public.${publicName}(`));
      await db.exec(original.replace(`public.${publicName}(`, `baseline.${oldName}(`));
      await db.exec(`revoke all on function public.${publicName}(integer,integer) from public,anon;
        grant execute on function public.${publicName}(integer,integer) to authenticated,service_role;`);
    }
    await db.exec(`grant select on all tables in schema public,stock_management_private to authenticated,service_role;`);
    const scalar = async (sql, args = []) => Object.values((await db.query(sql, args)).rows[0])[0];
    const acl = () => scalar(`select string_agg(proname||':'||proacl::text,'|' order by proname)
      from pg_proc where oid in ('public.get_stock_catalog_register_batch(integer,integer)'::regprocedure,
        'public.get_stock_management_register_batch(integer,integer)'::regprocedure)`);
    const beforeAcl = await acl();
    for (const file of [catalogFile,mrnFile]) {
      await db.exec('begin'); await db.exec(fs.readFileSync(file, 'utf8')); await db.exec('commit');
    }
    assert.equal(await acl(), beforeAcl, 'CREATE OR REPLACE must retain ACLs');
    let comparisons = 0;
    async function compare(offset = 0, limit = 5000) {
      for (const [scope, rpc] of [['catalog','get_stock_catalog_register_batch'],['mrn','get_stock_management_register_batch']]) {
        assert.equal(await scalar(`select baseline.${scope}_batch($1,$2)=public.${rpc}($1,$2)`, [offset,limit]), true,
          `${scope}: offset=${offset}, limit=${limit}`);
        comparisons++;
      }
    }
    await compare(); // Empty snapshots retain totals, versions and [] rows.
    await db.exec(`
      insert into purchase_status_options values(1,'AVAILABLE',true),(2,'NOT AVAILABLE',false);
      insert into purchase_status_items values(' A ',1),('A',1),('A',2),('B',null),('C',999);
      insert into mrn_apg_2026 values
        (' A ','2026-10-25','001','2027-02-01',' Approved ',' STORE ',5,999,1,10,'00017','long vendor name'),
        ('A','2026-10-25','001','2027-02-01','approved','store',5,999,1,10,'00017','long vendor name'),
        ('A','2026-10-25','002','2027-03-01','approved','Main Virtual',7,999,2,20,'V1','another vendor'),
        ('A','2026-10-25',null,null,'approved','Other',11,999,null,99,'OTHER','excluded vendor'),
        ('A','2026-10-26','003',null,'approved','Other',2,999,0,2,'LATEST','different vendor'),
        ('A','2026-11-01','004',null,'pending','store',1000,999,0,1000,'PENDING','ignored'),
        ('B','2026-10-01','005',null,'approved','store',100,999,0,100,'OLD','vendor'),
        ('B','2026-10-25','006',null,'approved','store',null,999,null,null,'   ','vendor'),
        ('C','2026-10-25','007',null,'cancelled','store',1000,999,0,1000,'CANCELLED','ignored'),
        ('D',null,'008',null,'approved','store',5,999,1,10,'UNDATED','vendor'),
        ('NEG','2026-10-25','009','2027-01-01','approved','new virtual',-2,999,-1,-3,'NEGATIVE','vendor'),
        ('ONLY_OTHER','2026-10-25','010',null,'approved','Other',8,999,1,10,'OTHER-ONLY','excluded vendor');
      insert into stock_catalog_snapshot
      select k,jsonb_build_object('item_code',k,'item_name',k,'last_mrn_qty',999,'branch_name','BETA',
        'extra_fact',jsonb_build_object('keep',true),'years',jsonb_build_object('2026',jsonb_build_object('total',3)),
        'meta',jsonb_build_object('refreshed_at','2026-10-30T08:30:00Z'),
        'distribution_orders',jsonb_build_object('a',1),'branch_stock',jsonb_build_object('a',2),
        'branch_demand',jsonb_build_object('a',3),'monthly_sales',jsonb_build_array(1),
        'current_month_branch_sales',jsonb_build_object('a',4),'daily_sales_45d',jsonb_build_array(2),
        'daily_sales_45d_available',true)
      from unnest(array['A','B','C','D','NEG','NONE','MISSING_CODE','SPACED_CODE','NULL_DATE','ONLY_OTHER']) k;
      update stock_catalog_snapshot set payload=payload-'item_code' where item_code='MISSING_CODE';
      update stock_catalog_snapshot set payload=payload||'{"item_code":" A "}'::jsonb where item_code='SPACED_CODE';
      insert into stock_management_snapshot
        select item_code,'2026-10-25',payload||jsonb_build_object('last_mrn_date','2026-10-25',
          'branches',jsonb_build_array(1),'branch_year_sales',jsonb_build_object('a',2),
          'receipt_lines',jsonb_build_array(3)),'2026-10-30T08:16:00Z' from stock_catalog_snapshot;
      update stock_management_snapshot set payload=payload||'{"last_mrn_date":null}' where item_code='NULL_DATE';
      insert into stock_supply_insights values('A','{"status":"ready","custom_fact":1}','2026-10-30T08:22:00Z');
    `);
    for (const [offset,limit] of [[0,5000],[0,1],[1,2],[2,3],[99999,5000],[-5,-2],[null,null],[0,0],[0,9000]]) await compare(offset,limit);
    const cat = await scalar('select public.get_stock_catalog_register_batch(0,5000)');
    const mrn = await scalar('select public.get_stock_management_register_batch(0,5000)');
    const find = (rows,code) => rows.find(r => r.item_name===code);
    assert.equal(find(cat.rows,'A').total_qty,2, 'catalog latest day includes all approved warehouses');
    assert.equal(find(cat.rows,'A').reference,'LATEST');
    assert.equal(find(mrn.rows,'A').total_qty,28, 'reference totals retain all-approved warehouse scope');
    assert.equal(find(mrn.rows,'A').ordered_quantity,40, 'ordered quantity retains STORE/virtual scope');
    assert.equal(find(mrn.rows,'A').receipt_count,2);
    assert.equal(find(mrn.rows,'A').expiry_count,2);
    assert.equal(find(mrn.rows,'A').bonus,4);
    assert.equal(find(mrn.rows,'A').reference,'00017 · OTHER · V1');
    assert.equal(find(cat.rows,'B').reference,'', 'blank latest reference never falls back');
    assert.equal(find(cat.rows,'D').total_qty,0, 'undated receipts remain unmatched');
    assert.equal(find(cat.rows,'NEG').total_qty,-2);
    assert.equal(find(cat.rows,'C').purchase_status_items,'Not assigned');
    assert.equal(find(cat.rows,'A').purchase_status_items,'AVAILABLE · NOT AVAILABLE');
    assert.equal(find(cat.rows,'A').branch_name,'BETA', 'raw branch identity is never decorated in SQL');
    assert.equal(find(mrn.rows,'ONLY_OTHER').total_qty,8);
    assert.equal(find(mrn.rows,'ONLY_OTHER').receipt_count,null, 'no STORE receipts must stay null, not zero');
    assert.equal(find(mrn.rows,'ONLY_OTHER').ordered_quantity,null);
    assert.equal(find(mrn.rows,'ONLY_OTHER').vendor,null);
    assert.equal(cat.rows.length,10, 'duplicate purchases/receipt lines cannot duplicate products');
    assert.deepEqual(cat.meta,{reference_version:cat.reference_version});
    assert.equal('meta' in mrn,false);
    // Updates remain visible immediately; no new persistent cache is introduced.
    await db.exec("update purchase_status_options set name='Delivery in 3 days' where id=2"); await compare();
    await db.exec("delete from mrn_apg_2026 where mrn_date='2026-10-26'"); await compare();
    await db.exec(`
      insert into stock_catalog_snapshot select 'Z'||lpad(n::text,5,'0'),jsonb_build_object(
        'item_code','Z'||lpad(n::text,5,'0'),'last_mrn_date','2026-10-25') from generate_series(1,5005)n;
      insert into stock_management_snapshot select item_code,'2026-10-25',payload,'2026-10-30T08:16:00Z'
        from stock_catalog_snapshot where item_code like 'Z%';
    `);
    for (const args of [[0,5000],[5000,5000],[0,9000],[null,null],[0,1]]) await compare(...args);
    const head = await scalar('select get_stock_catalog_register_batch(0,5000)');
    const tail = await scalar('select get_stock_catalog_register_batch(5000,5000)');
    assert.equal(head.rows.length,5000); assert.equal(tail.rows.length,15);
    assert.equal(new Set([...head.rows,...tail.rows].map(r=>r.item_name??r.item_code)).size,5015);
    for (const table of ['stock_catalog_snapshot','stock_management_snapshot','mrn_apg_2026','stock_supply_insights']) {
      await db.exec(`alter table public.${table} enable row level security;
        create policy stock_read on public.${table} for select to authenticated
        using ((select current_setting('test.access',true)) in ('inventory','view'));`);
    }
    for (const access of ['inventory','view','branch']) {
      await db.exec(`set role authenticated; set test.access='${access}';`);
      await compare(0,20);
      const result = await scalar('select get_stock_catalog_register_batch(0,20)');
      assert.equal(result.rows.length,access==='branch'?0:20);
      await db.exec('reset role');
    }
    await db.exec('set role service_role'); await compare(0,20); await db.exec('reset role');
    await db.exec('set role anon');
    for (const name of ['get_stock_catalog_register_batch','get_stock_management_register_batch']) {
      await assert.rejects(()=>scalar(`select public.${name}(0,1)`),/permission denied/);
    }
    await db.exec('reset role');
    console.log(`Single serialization: ${comparisons} exact SQL comparisons passed; scopes, authoritative totals, duplicates, nulls, versions, 5,000-row boundaries, role access and unchanged ACLs.`);
  } finally { await db.close(); }
})().catch(error=>{console.error(error);process.exit(1);});
