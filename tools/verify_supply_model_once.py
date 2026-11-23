"""Compare every product on one pinned snapshot, then roll the candidate back.

Use --originals with a pre-change pg_get_functiondef snapshot. Production data
and the published supply cache are never written. Candidate DDL and all test
fixtures live in a force-rollback transaction. Outputs contain metrics only.
"""
import argparse
import copy
import json
import re
import time
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb

from cleanup_duplicate_indexes import connect
from supply_model_once_sql import NAMES, SCHEMA, build, definition, replace_once

ROOT = Path(__file__).resolve().parents[1]


def capture_definition(original):
    body = original['prosrc']
    body = replace_once(body, "pg_try_advisory_xact_lock(hashtextextended('stock-supply-insights',0))", 'true')
    body = replace_once(body, 'delete from public.stock_supply_insights;', 'delete from pg_temp.supply_bench_inputs;')
    body = replace_once(body, 'insert into public.stock_supply_insights(item_code,summary,detail,source_version)',
                         'insert into pg_temp.supply_bench_inputs(item_code,payload)')
    needle = 'stock_management_private.analyze_supply('
    begin = body.index(needle)
    start = begin + len(needle)
    depth = 1
    quoted = False
    i = start
    while depth:
        char = body[i]
        if char == "'":
            if quoted and body[i:i+2] == "''":
                i += 2
                continue
            quoted = not quoted
        elif not quoted:
            depth += (char == '(') - (char == ')')
        i += 1
    body = body[:begin] + body[start:i-1] + body[i:]
    body = replace_once(body, "select item_code,result->'summary',result->'detail',version from analyzed;",
                         'select item_code,result from analyzed;')
    body, changed = re.subn(r'update public\.stock_supply_insight_state set[\s\S]*?where singleton;', 'null;', body)
    assert changed == 1
    result = definition(original, body)
    return replace_once(result, 'FUNCTION stock_management_private.refresh_supply_insights(',
                         'FUNCTION pg_temp.capture_supply_inputs(')


def legacy_definition(original):
    result = original['definition'].rstrip().removesuffix(';') + ';\n'
    for name in sorted(NAMES, key=len, reverse=True):
        result = result.replace(SCHEMA + name + '(', 'pg_temp.baseline_' + name + '(')
    return result


def function_stats(connection):
    return {r['funcname']: r for r in connection.execute('''select funcname,calls,total_time,self_time
      from pg_stat_xact_user_functions where funcname in
      ('fit_supply_demand','baseline_analyze_supply','analyze_supply')''').fetchall()}


def difference(after, before, name, field):
    return after.get(name, {}).get(field, 0) - before.get(name, {}).get(field, 0)


def outcome(connection, function, payload):
    try:
        with connection.transaction(force_rollback=True):
            row = connection.execute('select ' + function + '(%s)::text as result',
                                      (None if payload is None else Jsonb(payload),)).fetchone()
            return ('result', row['result'])
    except psycopg.Error as error:
        return ('error', error.sqlstate, error.diag.message_primary)


def edge_cases(connection):
    sample = connection.execute("""select payload from supply_bench_inputs
      where payload->>'baseline_count'='1' and jsonb_array_length(payload->'monthly_sales')>=6
      order by item_code limit 1""").fetchone()['payload']
    cases = [('null_input', None), ('empty_input', {})]
    changes = [
        ('omitted_store', {'current_count':0,'current_qty':None,'current_report_present':True}),
        ('missing_report', {'current_count':0,'current_qty':None,'current_report_present':False}),
        ('explicit_zero', {'current_count':1,'current_qty':0}),
        ('duplicate_current', {'current_count':2}),
        ('negative_current', {'current_qty':-5}),
        ('assumed_opening', {'baseline_count':0,'raw_opening_count':0,'assume_missing_opening':True}),
        ('unknown_opening', {'baseline_count':0,'assume_missing_opening':False}),
        ('missing_stock_day', {'stock_day':None}),
        ('empty_movements', {'days':[]}),
        ('empty_sales', {'monthly_sales':[],'prior_sales':0}),
        ('invalid_cutoff', {'through':'2026-01-01'}),
        ('invalid_qty', {'current_qty':'not-a-number'}),
    ]
    for name, update in changes:
        cases.append((name, {**copy.deepcopy(sample), **update}))
    duplicate_days = copy.deepcopy(sample)
    if duplicate_days.get('days'):
        duplicate_days['days'].append(copy.deepcopy(duplicate_days['days'][0]))
        cases.append(('duplicate_day_rejected', duplicate_days))
    for name, payload in cases:
        old = outcome(connection, 'pg_temp.baseline_analyze_supply', payload)
        new = outcome(connection, SCHEMA + 'analyze_supply', payload)
        assert old == new, 'Edge-case difference: ' + name
    return len(cases)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--originals', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--installed', action='store_true')
    args = parser.parse_args()
    originals = json.loads(args.originals.read_text(encoding='utf-8'))
    source = {f['proname']: f for f in originals}
    report = {'batch_size':500,'mismatches':0,'old_model_calls':0,'new_model_calls':0,
              'old_analysis_ms':0,'new_analysis_ms':0,'compared':0,'mode':'installed' if args.installed else 'candidate'}
    with connect() as connection, connection.transaction(force_rollback=True):
        connection.execute('set transaction isolation level repeatable read')
        connection.execute("set local application_name='inventory-supply-equivalence'")
        connection.execute("set local statement_timeout='240s'")
        connection.execute("set local lock_timeout='2s'")
        connection.execute("set local idle_in_transaction_session_timeout='60s'")
        connection.execute("set local max_parallel_workers_per_gather=0")
        connection.execute("set local track_functions='pl'")
        connection.execute('''create temp table supply_bench_inputs(item_code text primary key,payload jsonb);
          create temp table supply_bench_results(item_code text primary key,old_result jsonb,new_result jsonb);''')
        for name in NAMES:
            connection.execute(legacy_definition(source[name]))
        if not args.installed:
            connection.execute(build(originals))
        for name in ('fit_supply_demand','refresh_supply_insights'):
            actual = connection.execute('select pg_get_functiondef(%s::regprocedure) as definition',
                                         (source[name]['signature'],)).fetchone()['definition']
            assert actual == source[name]['definition'], name + ' business definition changed'
        for name in NAMES:
            actual = connection.execute('''select proacl,proowner,proconfig,prosecdef,provolatile
              from pg_proc where oid=%s::regprocedure''',(source[name]['signature'],)).fetchone()
            expected = {key: source[name][key] for key in actual}
            if isinstance(expected['proacl'],str):
                expected['proacl'] = expected['proacl'].strip('{}').split(',')
            assert actual == expected, name + ' privileges changed'
        for name in NAMES[:3]:
            signature = SCHEMA + name + '_cached(jsonb,jsonb,jsonb)'
            row = connection.execute('''select has_function_privilege('anon',%s,'EXECUTE') as anon,
              has_function_privilege('authenticated',%s,'EXECUTE') as authenticated,
              has_function_privilege('service_role',%s,'EXECUTE') as service''',
                (signature, signature, signature)).fetchone()
            assert row == {'anon':False,'authenticated':False,'service':True}, (signature, row)
        with connection.transaction(force_rollback=True):
            connection.execute('set local role service_role')
            connection.execute("select stock_management_private.analyze_supply('{}'::jsonb)")
        connection.execute(capture_definition(source['refresh_supply_insights']))
        captured = connection.execute('select pg_temp.capture_supply_inputs(true) as result').fetchone()['result']
        report['capture'] = captured
        report['input_snapshot'] = connection.execute('''select count(*) as products,
          md5(string_agg(item_code||md5(payload::text),'' order by item_code)) as fingerprint
          from supply_bench_inputs''').fetchone()
        report['edge_cases'] = edge_cases(connection)
        last = ''
        batch_no = 0
        while True:
            if args.limit and report['compared'] >= args.limit:
                break
            batch = connection.execute('''select item_code from supply_bench_inputs
              where item_code>%s order by item_code limit 500''',(last,)).fetchall()
            if not batch:
                break
            until = batch[-1]['item_code']
            batch_no += 1
            # Alternate execution order to reduce warm-cache/order bias.
            for variant in (('old','new') if batch_no % 2 else ('new','old')):
                function = 'pg_temp.baseline_analyze_supply' if variant=='old' else SCHEMA+'analyze_supply'
                before = function_stats(connection)
                connection.execute('''with batch as materialized (
                  select item_code,payload from supply_bench_inputs where item_code>%s and item_code<=%s
                ), calculated as materialized (select item_code,'''+function+'''(payload) as result from batch)
                insert into supply_bench_results(item_code,'''+variant+'''_result)
                select item_code,result from calculated on conflict(item_code) do update
                set '''+variant+'''_result=excluded.'''+variant+'''_result''',(last,until))
                after = function_stats(connection)
                report[variant+'_model_calls'] += difference(after,before,'fit_supply_demand','calls')
                analyzed = 'baseline_analyze_supply' if variant=='old' else 'analyze_supply'
                report[variant+'_analysis_ms'] += difference(after,before,analyzed,'total_time')
            mismatch = connection.execute('''select count(*) as n from supply_bench_results
              where item_code>%s and item_code<=%s
              and (old_result is distinct from new_result or old_result::text is distinct from new_result::text)''',
              (last,until)).fetchone()['n']
            report['mismatches'] += mismatch
            assert mismatch == 0, 'Full payload differs; refusing rollout'
            report['compared'] += len(batch)
            last = until
            if batch_no % 2 == 0:
                print(json.dumps({'progress':report['compared'],'differences':report['mismatches'],
                                  'old_ms':round(report['old_analysis_ms']),
                                  'new_ms':round(report['new_analysis_ms'])}),flush=True)
            time.sleep(0.15)
        report['output_hashes'] = connection.execute('''select
          md5(string_agg(item_code||md5(old_result::text),'' order by item_code)) as old,
          md5(string_agg(item_code||md5(new_result::text),'' order by item_code)) as new
          from supply_bench_results''').fetchone()
        assert report['output_hashes']['old'] == report['output_hashes']['new']
        if not args.limit:
            assert report['compared'] == report['input_snapshot']['products']
        assert report['new_model_calls'] <= report['old_model_calls']
        assert report['new_model_calls'] <= report['compared'], 'Model was evaluated more than once per product'
        report['analysis_reduction_percent'] = round(100*(1-report['new_analysis_ms']/report['old_analysis_ms']),2)
        report['model_call_reduction_percent'] = round(100*(1-report['new_model_calls']/report['old_model_calls']),2)
        report['production_rows_written'] = 0
        report['candidate_rolled_back'] = not args.installed
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,indent=2,default=str)+'\n',encoding='utf-8')
        print(json.dumps(report,default=str),flush=True)
        assert report['new_analysis_ms'] < report['old_analysis_ms'], 'Candidate did not improve analysis time; do not deploy'


if __name__ == '__main__':
    main()
