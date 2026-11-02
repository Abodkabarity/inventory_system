const assert=require('node:assert/strict');
const fs=require('node:fs');
const {PGlite}=require(process.env.STOCK_CACHE_PGLITE_MODULE||'@electric-sql/pglite');
(async()=>{
  const db=new PGlite();
  const source=fs.readFileSync('supabase/migrations/20261023061551_stock_effective_branch_balances.sql','utf8');
  const cte=source.slice(source.indexOf('order_branches as materialized ('),source.indexOf('), distribution as ('))+')';
  const updated=cte.replace("max(coalesce((s.branch_stock->a.branch_key->>'stock')::numeric,0)) stock",'max(coalesce(s.qty,0)) stock')
    .replace('left join stock s on s.item_code=c.item_code','left join ledger s on s.item_code=c.item_code and s.branch_key=a.branch_key');
  assert.notEqual(updated,cte);
  await db.exec(`
    create function public._norm_text(text) returns text language sql immutable as $$ select lower(btrim($1)) $$;
    create table catalog(item_code text); insert into catalog values('A'),('B'),('C');
    create table active(branch_key text); insert into active values('alpha'),('beta'),('missing');
    create table order_expected as select * from active;
    create table order_run(run_date date); insert into order_run values(current_date);
    create table formulary_rules(item_code text,branch_key text,formulary text);
    insert into formulary_rules values('A','beta','NON');
    create table ledger(item_code text,branch_key text,qty numeric);
    insert into ledger values('A','alpha',12.5),('A','beta',-3),('B','alpha',0),('B','beta',null);
    create table branches(branch_name text,branch_group text);
    insert into branches values('Alpha','APG'),('Beta','71');
    create view stock as select item_code,jsonb_object_agg(branch_key,jsonb_build_object('stock',qty)) branch_stock from ledger group by item_code;
    create table public.daily_order(item_code text,branch text,run_date date,reorder_qty_num numeric,
      total_final_reorder_today numeric,reason text,tma_qty numeric,branch_formulary text,
      reorder_qty text,final_reorder_qty_store_stock_gt_0 text);
    insert into daily_order values
      (' A ',' Alpha ',current_date,4,2,'NEW ITEM',0,'YES','4','2'),
      ('A','alpha',current_date,8,3,'',0,'YES','8','3'),
      ('A','Beta',current_date,2,0,'',0,'YES','2','0'),
      ('B','Alpha',current_date,null,null,null,null,null,null,null),
      ('B','Beta',current_date,-1,-1,'',0,'YES','1','1'),
      ('C','Missing',current_date,2,1,'',0,'YES','2','1'),
      ('A','Alpha',current_date-1,999,999,'NEW ITEM',999,'YES','999','999');
  `);
  const old=(await db.query('with '+cte+' select * from order_branches order by item_code,branch_key')).rows;
  const next=(await db.query('with '+updated+' select * from order_branches order by item_code,branch_key')).rows;
  assert.deepEqual(next,old);
  assert.equal(next.length,5);
  assert.equal(next.find(r=>r.item_code==='A'&&r.branch_key==='alpha').stock,'12.5');
  assert.equal(next.find(r=>r.item_code==='A'&&r.branch_key==='beta').stock,'-3');
  assert.equal(next.find(r=>r.item_code==='C').stock,'0');
  assert.equal(next.find(r=>r.branch_key==='beta').branch_key,'beta');
  console.log('Stock refresh: exact distribution parity for normalized branches, group 71 raw keys, duplicate orders, overrides, negative/zero/null/missing stock and old runs.');
  await db.close();
})().catch(e=>{console.error(e);process.exit(1)});
