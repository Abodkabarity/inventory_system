// Isolated PostgreSQL regression; no production writes.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {PGlite}=require(process.env.STOCK_CACHE_PGLITE_MODULE||'@electric-sql/pglite');
(async()=>{
  const db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create schema stock_management_private;
    grant usage on schema public,stock_management_private to authenticated,service_role;
    create table mrn_apg_2026(item_code text,mrn_date date,mrn_no text,expiry_date date,status text,reference text);
    create table stock_workspace_cache_revisions(source text primary key,revision bigint);
    create table purchase_status_options(id bigint primary key,name text,is_active boolean);
    create table purchase_status_items(item_code text,status_id bigint,purchase_status text);
    insert into purchase_status_options values(3,'AVAILABLE',true),(5,'NOT AVAILABLE',false);
    insert into purchase_status_items values(' A ',3,'WRONG LEGACY FIELD'),('B',null,'WRONG LEGACY FIELD');
    create view availability_kpi_purchase_status as
      select btrim(i.item_code) item_code,i.status_id,o.name status_name
      from public.purchase_status_items i left join public.purchase_status_options o on o.id=i.status_id
      where nullif(btrim(i.item_code),'') is not null;
    create function public.get_stock_workspace_cache_state() returns jsonb language sql stable as $$
      select '{"mrn":"mrn-v1","expiry":"expiry-v1","details":"details-v1","discovery":"discovery-v1"}'::jsonb;
    $$;
    insert into stock_workspace_cache_revisions values('mrn_receipts',1);
    create table fixtures(scope text primary key,rows jsonb);
    insert into fixtures values
      ('catalog','[{"item_code":"A","qty":7},{"item_code":"B"},{"item_code":"Z"}]'),
      ('mrn','[{"item_code":"A","last_mrn_date":"2026-10-26","received_quantity":7}]'),
      ('expiry','[{"item_code":"A","last_receipt_date":"2026-10-01","expiry_date":"2027-02-01","product_data":{"reference":"UNRELATED","total_stock":9}},{"item_code":"A","last_receipt_date":"2026-10-26","expiry_date":"2027-02-01","product_data":{"reference":"UNRELATED","total_stock":9}},{"item_code":"A","last_receipt_date":"2026-10-26","expiry_date":"2027-03-01"}]');
    insert into mrn_apg_2026 values
      ('A','2026-10-01','OLD','2027-02-01','approved','OLD-REF'),
      ('A','2026-10-26','1','2027-02-01','approved','00017'),
      (' A ','2026-10-26','1','2027-02-01','approved','00017'),
      ('A','2026-10-26','2','2027-02-01','approved',' NEW-2 '),
      ('A','2026-10-26','3','2027-03-01','approved','PO-X'),
      ('A','2026-10-27','BAD','2027-02-01','rejected','BAD'),
      ('B','2026-10-25','OLD','2027-02-01','approved','B-OLD'),
      ('B','2026-10-26','NEW','2027-02-01','approved',null);
    grant select on all tables in schema public to authenticated,service_role;
    create function stock_management_private.catalog_cache_version(boolean) returns text language sql stable as $$select 'original-v1'::text; $$;
    create function public.fixture_page(scope text,p_offset integer,p_limit integer)
    returns jsonb language sql stable security invoker set search_path='' as $$
      select jsonb_build_object('rows',(select coalesce(jsonb_agg(row),'[]'::jsonb) from
        (select row from public.fixtures f cross join lateral jsonb_array_elements(f.rows)r(row)
          where f.scope=$1 limit least(greatest(p_limit,1),5000) offset p_offset)page),
        'total',(select jsonb_array_length(rows) from public.fixtures where scope=$1),
        'summary',jsonb_build_object('unchanged',true),'snapshot_at','2026-10-28',
        'meta',jsonb_build_object('refreshed_at','2026-10-28'));
    $$;
    create function public.get_stock_catalog_register_batch(integer,integer) returns jsonb language sql stable as $$select public.fixture_page('catalog',$1,$2); $$;
    create function public.get_stock_catalog_page(text,text,text,text,text,integer,integer) returns jsonb language sql stable as $$select public.fixture_page('catalog',$6,$7); $$;
    create function public.get_stock_management_register_batch(integer,integer) returns jsonb language sql stable as $$select public.fixture_page('mrn',$1,$2); $$;
    create function public.get_stock_management_page(text,text,text,text,date,date,text,integer,integer) returns jsonb language sql stable as $$select public.fixture_page('mrn',$8,$9); $$;
    create function public.get_stock_expiry_page(text,text,text,integer,integer) returns jsonb language sql stable as $$select public.fixture_page('expiry',$4,$5); $$;
    create function public.get_stock_catalog_item(text) returns jsonb language sql stable as $$select row from fixtures f cross join lateral jsonb_array_elements(f.rows)r(row) where scope='catalog' and row->>'item_code'=$1 limit 1; $$;
    create function public.get_stock_management_item(text) returns jsonb language sql stable as $$select row from fixtures f cross join lateral jsonb_array_elements(f.rows)r(row) where scope='mrn' and row->>'item_code'=$1 limit 1; $$;
    create function public.get_stock_expiry_item(text,date,date) returns jsonb language sql stable as $$select row from fixtures f cross join lateral jsonb_array_elements(f.rows)r(row) where scope='expiry' and row->>'item_code'=$1 and (row->>'expiry_date')::date=$2 and (row->>'last_receipt_date')::date=$3 limit 1; $$;
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261028122315_stock_management_reference_columns.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261028123730_stock_reference_bulk_payload_optimization.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261028124638_stock_management_purchase_status_columns.sql','utf8'));
  const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0]??{})[0];
  const catalog=await scalar('select get_stock_catalog_register_batch(0,5000)');
  assert.deepEqual(catalog.rows.map(r=>r.item_code),['A','B','Z']);
  assert.equal(catalog.rows[0].reference,'00017 · NEW-2 · PO-X');
  assert.equal(catalog.rows[0].qty,7);
  assert.equal(catalog.rows[1].reference,'','latest blank references never fall back to an older receipt');
  assert.equal(catalog.rows[2].reference,'');
  assert.equal(catalog.total,3);assert.equal(catalog.summary.unchanged,true);
  assert.equal(catalog.reference_version,catalog.meta.reference_version);
  const mrn=await scalar('select get_stock_management_register_batch(0,5000)');
  assert.equal(mrn.rows[0].reference,catalog.rows[0].reference);
  assert.equal(mrn.rows[0].received_quantity,7);
  assert.equal(catalog.rows[0].purchase_status_items,'AVAILABLE');
  assert.equal(catalog.rows[1].purchase_status_items,'Not assigned');
  assert.equal(catalog.rows[2].purchase_status_items,'Not assigned');
  assert.equal(mrn.rows[0].purchase_status_items,'AVAILABLE');
  const near=await scalar("select get_stock_expiry_page('','','',0,5000)");
  assert.deepEqual(near.rows.map(r=>r.reference),['OLD-REF','00017 · NEW-2','PO-X']);
  assert.equal(near.rows[0].product_data.reference,'OLD-REF');
  assert.equal(near.rows[0].product_data.total_stock,9);
  assert.ok(near.rows.every(r=>r.purchase_status_items==='AVAILABLE'));
  assert.equal(near.rows[0].product_data.purchase_status_items,'AVAILABLE');
  assert.equal(near.rows.length,3,'same product/expiry on different MRN dates stays separate');
  assert.equal((await scalar("select get_stock_catalog_page('','','','','',0,1)")).rows[0].reference,catalog.rows[0].reference);
  assert.equal((await scalar("select get_stock_management_page('','','','',null,null,'',0,1)")).rows[0].reference,catalog.rows[0].reference);
  assert.equal((await scalar("select get_stock_catalog_item('A')")).reference,catalog.rows[0].reference);
  assert.equal((await scalar("select get_stock_management_item('A')")).reference,catalog.rows[0].reference);
  assert.equal((await scalar("select get_stock_expiry_item('A','2027-02-01','2026-10-01')")).reference,'OLD-REF');
  for(const query of [
    "select get_stock_catalog_page('','','','','',0,1)",
    "select get_stock_management_page('','','','',null,null,'',0,1)",
    "select get_stock_catalog_item('A')",
    "select get_stock_management_item('A')",
    "select get_stock_expiry_item('A','2027-02-01','2026-10-01')"
  ]){
    const result=await scalar(query);
    assert.equal((result.rows?.[0]??result).purchase_status_items,'AVAILABLE');
  }
  assert.equal(await scalar("select get_stock_catalog_item('MISSING')"),null);
  assert.deepEqual((await scalar('select get_stock_catalog_register_batch(99,5000)')).rows,[]);
  const version=await scalar('select stock_management_private.catalog_cache_version(false)');
  await db.exec("update stock_workspace_cache_revisions set revision=revision+1 where source='mrn_receipts'");
  assert.notEqual(await scalar('select stock_management_private.catalog_cache_version(false)'),version);
  const cache=()=>scalar('select get_stock_workspace_cache_state()');
  const purchaseVersion=()=>scalar('select stock_management_private.reference_version()');
  let prior=await cache(), priorToken=await purchaseVersion();
  await db.exec("update purchase_status_items set status_id=5 where btrim(item_code)='A'");
  assert.equal((await scalar("select get_stock_catalog_item('A')")).purchase_status_items,'NOT AVAILABLE',
    'an inactive option still names an assigned status');
  let current=await cache();
  for(const key of ['mrn','expiry','details']) assert.notEqual(current[key],prior[key]);
  assert.equal(current.discovery,prior.discovery,'status edits must not force MRN discovery');
  assert.notEqual(await purchaseVersion(),priorToken);
  priorToken=await purchaseVersion();
  await db.exec("update purchase_status_options set name='Delivery in 3 days' where id=5");
  assert.equal((await scalar("select get_stock_management_item('A')")).purchase_status_items,'Delivery in 3 days');
  assert.notEqual(await purchaseVersion(),priorToken,'option renames invalidate cached labels');
  await db.exec("insert into purchase_status_items values('A',5,'wrong');");
  assert.equal((await scalar('select get_stock_catalog_register_batch(0,5000)')).rows.length,3,
    'normalized duplicate assignments must not duplicate stock rows');
  await db.exec("delete from purchase_status_items where btrim(item_code)='A'");
  assert.equal((await scalar("select get_stock_catalog_item('A')")).purchase_status_items,'Not assigned');
  await db.exec("insert into purchase_status_items values('A',3,'wrong');");
  await db.exec(`alter table mrn_apg_2026 enable row level security;
    create policy inventory_read on mrn_apg_2026 for select to authenticated
      using (current_setting('test.role',true) in ('inventory','view'));
    set role authenticated;set test.role='branch';`);
  assert.equal((await scalar('select get_stock_catalog_register_batch(0,5000)')).rows[0].reference,'');
  await db.exec("set test.role='view'");
  assert.equal((await scalar('select get_stock_catalog_register_batch(0,5000)')).rows[0].reference,catalog.rows[0].reference);
  await db.exec('reset role;set role anon');
  await assert.rejects(()=>scalar("select stock_management_private.add_reference_columns('[]','catalog')"),/permission denied/);
  await db.close();
  console.log('Reference and Purchase Status SQL passed: all list/detail paths, ID-to-name mapping, inactive/null/missing options, edits/renames/removals, cache versions, receipt scope, unchanged counts/KPIs/order and RLS.');
})().catch(e=>{console.error(e);process.exit(1);});
