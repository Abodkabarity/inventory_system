const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { PGlite } = require(
  process.env.DAILY_ORDER_FILTERS_PGLITE_MODULE || '@electric-sql/pglite'
);

async function main() {
  const migration = readFileSync(
    join(__dirname, '../migrations/20261111165627_inventory_daily_order_excel_filters.sql'),
    'utf8'
  );
  const recordedMaxMigration = readFileSync(
    join(__dirname, '../migrations/20261112093245_inventory_daily_order_recorded_max.sql'),
    'utf8'
  );
  const schema = Object.entries(JSON.parse(
    migration.match(/v_types constant jsonb := '(\{[\s\S]+?\})'/)[1]
  )).map(([column, type]) => `${column} ${type}`).join(', ');
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create role service_role;
      create function public._norm_text(value text) returns text
        language sql immutable as $norm$ select lower(trim(coalesce(value, ''))) $norm$;
      create table public.daily_order (
        run_date date not null,
        reorder_qty text,
        ${schema},
        primary key(run_date, branch, item_code)
      );
      create table public.max_adj (
        id bigint primary key,
        branch_name text not null,
        item_code text not null,
        max_adjustment_30d numeric,
        update_date date,
        created_at timestamptz not null
      );
      insert into public.daily_order (run_date,branch,item_code,item_name,category,branch_stock)
      select '2026-11-11', 'Alpha', 'CODE-' || lpad(i::text,3,'0'),
        'Product ' || i,
        case when i = 1 then null when i = 2 then '' else 'Category ' || i end,
        case when i = 1 then null when i % 2 = 0 then 2 else 10 end
      from generate_series(1, 250) i;
      insert into public.daily_order (run_date,branch,item_code,item_name,category,branch_stock)
      values ('2026-11-11','Beta','CODE-001','Paracetamol','Quoted "name", (A)',2),
             ('2026-11-11','Hidden','CODE-001','Restricted','Private',1),
             ('2026-11-10','Alpha','CODE-001','Prior date','Prior date',5);
      alter table public.daily_order enable row level security;
      grant select on public.daily_order to authenticated;
      grant select on public.max_adj to authenticated;
      create policy test_inventory_reads on public.daily_order for select to authenticated
        using (branch <> 'Hidden');
    `);
    await db.exec(migration);
    const grants = await db.query(`
      select has_function_privilege('anon','public.inventory_daily_order_filter_read(jsonb)','execute') as anon
    `);
    assert.equal(grants.rows[0].anon, false);
    await db.exec('set role authenticated');

    const read = async (params) => {
      const result = await db.query(
        'select public.inventory_daily_order_filter_read($1::jsonb) as result',
        [JSON.stringify({ run_date: '2026-11-11', ...params })],
      );
      return result.rows[0].result;
    };
    assert.deepEqual(await read({ facet: 'branch' }), ['Alpha', 'Beta']);
    assert.deepEqual(await read({
      facet: 'branch', lookup: '71 Alpha', lookup_branches: ['ALPHA'],
    }), ['Alpha']);
    assert.deepEqual(await read({
      facet: 'branch_stock', branch: 'Alpha',
      filters: [{ column: 'branch_stock', values: ['2'] }],
    }), ['2', '10', null]);
    assert.deepEqual(await read({
      facet: 'category', lookup: 'blanks',
    }), [null]);
    assert.deepEqual(await read({
      facet: 'category', search: 'Paracetamol',
      filters: [{ column: 'branch_stock', rules: [{ operator: 'atLeast', value: '2' }] }],
    }), ['Quoted "name", (A)']);

    const values = await read({ facet: 'category', branch: 'Alpha' });
    assert.equal(values.length, 101);
    const following = await read({
      facet: 'category', branch: 'Alpha', value_after: values[99],
    });
    assert.equal(following[0], values[100]);

    const exact = await read({
      filters: [{ column: 'category', values: [null, 'Quoted "name", (A)'] }],
    });
    assert.deepEqual(exact.map((row) => row.branch), ['Alpha', 'Beta', 'Alpha']);
    const excluded = await read({
      filters: [{ column: 'branch_stock', values: ['2'], exclude: true }],
    });
    assert.equal(excluded[0].branch_stock, null);
    assert.ok(excluded.every((row) => row.branch_stock !== 2));

    const first = await read({ sort: 'branch_stock', ascending: false });
    assert.equal(first.length, 121);
    const last = first[119];
    const next = await read({
      sort: 'branch_stock', ascending: false,
      cursor: { branch_stock: last.branch_stock, item_code: last.item_code, branch: last.branch },
    });
    assert.deepEqual(next[0], first[120]);
    assert.ok(next.every((row) => row.run_date == null && row.branch !== 'Hidden'));
    await assert.rejects(
      read({ facet: 'branch; delete from public.daily_order' }),
      /Invalid daily order filter request/,
    );

    await db.exec(`
      reset role;
      update public.daily_order set max_adjustment_30d=0, demand_for_30_days=30;
      insert into public.max_adj values
        (1,'Alpha','CODE-001',9,'2026-11-10','2026-11-10 08:00Z'),
        (2,' alpha ','CODE-001',0,'2026-11-11','2026-11-11 08:00Z'),
        (3,'Alpha','CODE-002',12,'2026-11-11','2026-11-11 08:00Z'),
        (4,'Beta','CODE-001',null,'2026-11-11','2026-11-11 08:00Z');
    `);
    await db.exec(recordedMaxMigration);
    await db.exec('set role authenticated');
    assert.deepEqual(await read({ facet: 'max_adjustment_30d' }), ['0', '12', null]);
    const zero = await read({ filters: [{ column: 'max_adjustment_30d', values: ['0'] }] });
    assert.deepEqual(zero.map((row) => [row.branch, row.item_code, row.max_adjustment_30d, row.demand_for_30_days]),
      [['Alpha', 'CODE-001', 0, 30]]);
    const blanks = await read({ filters: [{ column: 'max_adjustment_30d', values: [null] }] });
    assert.ok(blanks.some((row) => row.item_code === 'CODE-003'));
    assert.ok(blanks.every((row) => row.max_adjustment_30d === null));
    const direct = await db.query(`
      select max_adjustment_30d from public.inventory_daily_order_rows
      where run_date='2026-11-11' and branch='Alpha' and item_code in ('CODE-001','CODE-002','CODE-003')
      order by item_code
    `);
    assert.deepEqual(direct.rows.map((row) => row.max_adjustment_30d), ['0', '12', null]);
    console.log('Daily Order Excel filters passed');
  } finally {
    await db.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
