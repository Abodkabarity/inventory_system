"""Check reviewed duplicate indexes; --apply removes them concurrently.

Requires psycopg and SUPABASE_DB_PASSWORD. The default is read-only preflight.
No constraints, primary keys, replica identities or clustered indexes are removed.
"""
import argparse
import json
import os
from pathlib import Path
from urllib.parse import urlparse

import psycopg
from psycopg import sql
from psycopg.rows import dict_row

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'rzvxjkbraufqbfhvftcy'


def connect():
    pooler = os.environ.get('SUPABASE_DB_POOLER_URL')
    if not pooler:
        source = ROOT / 'supabase/.temp/pooler-url'
        if not source.exists():
            raise RuntimeError('Set SUPABASE_DB_POOLER_URL for the linked Inventory project')
        pooler = source.read_text().strip()
    parsed = urlparse(pooler)
    if parsed.username != 'postgres.' + PROJECT:
        raise RuntimeError('Unexpected database project; refusing to connect')
    return psycopg.connect(pooler, password=os.environ['SUPABASE_DB_PASSWORD'],
                           sslmode='require', connect_timeout=15,
                           autocommit=True, row_factory=dict_row,
                           application_name='inventory-cpu-hardening')


def validate(connection, pair):
    row = connection.execute('''
      select a.indexrelid::regclass::text as redundant, b.indexrelid::regclass::text as retained,
        pg_relation_size(a.indexrelid) as bytes,
        a.indrelid=b.indrelid and a.indnatts=b.indnatts and a.indnkeyatts=b.indnkeyatts
        and ac.relam=bc.relam and a.indisunique=b.indisunique
        and a.indnullsnotdistinct=b.indnullsnotdistinct and a.indkey=b.indkey
        and a.indclass=b.indclass and a.indcollation=b.indcollation and a.indoption=b.indoption
        and a.indexprs::text is not distinct from b.indexprs::text
        and a.indpred::text is not distinct from b.indpred::text
        and a.indisvalid and a.indisready and b.indisvalid and b.indisready
        and not a.indisprimary and not a.indisreplident and not a.indisclustered
        and ac.relkind='i' and bc.relkind='i'
        and not exists(select 1 from pg_constraint where conindid=a.indexrelid)
        and not exists(select 1 from pg_depend where refclassid='pg_class'::regclass
                        and refobjid=a.indexrelid) as safe
      from pg_index a join pg_index b on b.indexrelid=to_regclass(%s)
      join pg_class ac on ac.oid=a.indexrelid join pg_class bc on bc.oid=b.indexrelid
      where a.indexrelid=to_regclass(%s)
    ''', ('public.' + pair['keep'], 'public.' + pair['drop'])).fetchone()
    exists = connection.execute('select to_regclass(%s) as name',
                                 ('public.' + pair['drop'],)).fetchone()['name']
    if exists and (not row or not row['safe']):
        raise RuntimeError('Unsafe index pair: ' + pair['drop'])
    if not connection.execute('select to_regclass(%s) as name',
                               ('public.' + pair['keep'],)).fetchone()['name']:
        raise RuntimeError('Retained index missing: ' + pair['keep'])
    return row


def constraints(connection):
    return connection.execute('''select oid,conname,contype,conrelid,conindid,
      pg_get_constraintdef(oid) as definition from pg_constraint
      where connamespace='public'::regnamespace order by oid''').fetchall()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    pairs = json.loads((ROOT / 'supabase/maintenance/duplicate_index_cleanup_20261123.json').read_text())
    with connect() as connection:
        connection.execute("set lock_timeout='2s'")
        connection.execute("set statement_timeout='30s'")
        before_constraints = constraints(connection)
        checked = [validate(connection, pair) for pair in pairs]
        print(json.dumps({'checked_pairs': len(pairs), 'present_duplicates': sum(bool(x) for x in checked),
                          'reclaimable_mib': round(sum(x['bytes'] for x in checked if x) / 1048576, 2)}), flush=True)
        if args.apply:
            for pair in pairs:
                if not validate(connection, pair):
                    continue
                connection.execute(sql.SQL('drop index concurrently {}.{}').format(
                    sql.Identifier('public'), sql.Identifier(pair['drop'])))
                validate(connection, pair)
                print(json.dumps({'removed': pair['drop'], 'retained': pair['keep']}), flush=True)
            assert constraints(connection) == before_constraints, 'Constraint definitions changed'
            print(json.dumps({'constraints_unchanged': True, 'cleanup_complete': True}), flush=True)


if __name__ == '__main__':
    main()
