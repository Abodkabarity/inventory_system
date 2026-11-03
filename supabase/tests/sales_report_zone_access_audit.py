"""Audit all active zonal identities against live database permissions.

All API/prewarm side effects are rolled back. --candidate also validates a
proposed security migration inside that rollback transaction. No source data,
user profile or branch assignment is modified by this test.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from sales_report_server_cache_test import connect


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate')
    parser.add_argument('--output')
    args = parser.parse_args()
    results = []
    with connect() as conn:
        try:
            if args.candidate:
                conn.execute(Path(args.candidate).read_text(encoding='utf-8'))
            conn.execute("set local statement_timeout='40s'")
            users = conn.execute("""select user_id from public.app_users
                where lower(btrim(role))='zone_manager' and is_active is not false
                order by user_id""").fetchall()
            assert users, 'No active zone manager identities found'
            inventory_baseline = conn.execute('select count(*) from public.sales_history').fetchone()[0]
            inventory_2025_baseline = conn.execute('select count(*) from public.sales_history_2025').fetchone()[0]
            view_options = dict(conn.execute("""select relname,reloptions from pg_class where oid in
                ('public.availability_sales_monthly'::regclass,'public.availability_branch_master'::regclass)"""))
            assert all('security_invoker=true' in (options or []) for options in view_options.values())
            for (user_id,) in users:
                conn.execute("select set_config('request.jwt.claims',%s,true)",
                    (json.dumps({'sub':str(user_id),'role':'authenticated'}),))
                zones = [row[0] for row in conn.execute('select distinct zone from public.get_my_effective_zones()')]
                expected_branches = {row[0] for row in conn.execute("""select distinct btrim(branch_name)
                    from public.branches where is_active is true and zone=any(%s)
                    and nullif(btrim(branch_name),'') is not null""", (zones,))}
                scope = conn.execute('select sales_report_private.current_scope()').fetchone()[0]
                assert scope and scope['kind']=='zone' and set(scope['branches'])==expected_branches
                expected_months = {row[0] for row in conn.execute("""select distinct month
                    from (select month,branch_name from public.sales_history where right(month,4)<>'2025'
                      union all select month,branch_name from public.sales_history_2025 where right(month,4)='2025') history where btrim(branch_name)=any(%s)
                    and month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$'
                    and month<>to_char(statement_timestamp() at time zone 'Asia/Dubai','MM/YYYY')""", (list(expected_branches),))}
                current = conn.execute("select to_char(statement_timestamp() at time zone 'Asia/Dubai','MM/YYYY') where exists(select 1 from public.sales_last_45_days where btrim(branch_name)=any(%s) and inv_date between date_trunc('month',statement_timestamp() at time zone 'Asia/Dubai')::date and sales_report_private.daily_expected_day())",(list(expected_branches),)).fetchone()
                if current: expected_months.add(current[0])
                conn.execute("set local statement_timeout='40s'")
                conn.execute('select 1 from sales_report_private.state where singleton for update')
                ready_jobs = conn.execute("""select scope_key,scope_user_id,branch_names,storage_path
                from sales_report_private.jobs where status='ready' and source_version=sales_report_private.export_version(report_kind,months)
                  and (not sales_report_private.needs_daily(report_kind,months) or sales_report_private.daily_fresh())
                  and (report_kind<>'monthly' or sales_report_private.monthly_selection_available(months))
                  and storage_path is not null""").fetchall()
                allowed_files = {path for key,owner,branches,path in ready_jobs
                    if key==scope['key'] and owner==user_id and set(branches or [])==expected_branches}
                foreign_branch = conn.execute("""select branch_name from public.sales_history
                    where btrim(branch_name)<>all(%s) limit 1""", (list(expected_branches),)).fetchone()
                conn.execute('set local role authenticated')
                for table in ('sales_history','sales_last_45_days'):
                    visible = {row[0] for row in conn.execute(f'select distinct btrim(branch_name) from public.{table}')}
                    assert visible <= expected_branches, f'{table} leaks outside-zone sales'
                    for privilege in ('insert','update','delete','truncate'):
                        assert not conn.execute('select has_table_privilege(current_user,%s,%s)',
                            (f'public.{table}',privilege)).fetchone()[0]
                archive_visible = {row[0] for row in conn.execute('select distinct btrim(branch_name) from public.sales_history_2025')}
                assert archive_visible <= expected_branches, '2025 source RLS leaks outside-zone rows'
                if foreign_branch:
                    assert conn.execute("""select 1 from public.availability_sales_monthly
                        where branch_name=%s limit 1""", (foreign_branch[0],)).fetchone() is None
                report = conn.execute('select public.get_sales_report()').fetchone()[0]
                assert report['scope_kind']=='zone' and set(m['month'] for m in report['months'])==expected_months
                assert 'branches' not in report and 'scope_key' not in report
                daily = conn.execute('select public.get_sales_45_report()').fetchone()[0]
                assert daily['scope_kind']=='zone' and 'branches' not in daily and 'scope_key' not in daily
                through = conn.execute('select max(inv_date) from public.sales_last_45_days where inv_date<=%s',(daily['expected_through'],)).fetchone()[0]
                assert daily['period_through']==(through.isoformat() if through else None)
                if through:
                    expected_days = [r[0].isoformat() for r in conn.execute('select distinct inv_date from public.sales_last_45_days where inv_date between %s::date-44 and %s::date order by inv_date',(through,through))]
                    assert daily['days']==expected_days
                if daily['job'] and daily['job']['storage_path']:
                    assert daily['job']['storage_path'] in allowed_files
                visible_files = {row[0] for row in conn.execute("""select name from storage.objects
                    where bucket_id='sales-report-exports'""")}
                assert visible_files==allowed_files, 'Storage RLS permits a foreign/global file or denies an authorized file'
                for table in ('app_users','app_user_zones'):
                    for privilege in ('insert','update','delete','truncate'):
                        assert not conn.execute('select has_table_privilege(current_user,%s,%s)',
                            (f'public.{table}',privilege)).fetchone()[0], f'Client can edit authority in {table}'
                assert conn.execute('select public.item_tracker_my_role()').fetchone()[0] != 'inventory'
                assert not conn.execute("select has_table_privilege(current_user,'public.branches','truncate')").fetchone()[0]
                assert not conn.execute("select has_function_privilege(current_user,'public.truncate_sales_last_45_days()','execute')").fetchone()[0]
                assert not conn.execute("select has_function_privilege(current_user,'public.sales_report_worker(text,jsonb)','execute')").fetchone()[0]
                assert not conn.execute("select has_table_privilege(current_user,'sales_report_private.jobs','select')").fetchone()[0]
                conn.execute('reset role')
                results.append({'scope':scope['label'],'raw_monthly_sales':'scoped','raw_daily_sales':'scoped',
                    'monthly_view_foreign_branch':'denied','report_month_metadata':'scoped','daily_report_dates':'scoped','archive_2025_outside_zone':'denied',
                    'global_and_cross_zone_storage':'denied','role_or_zone_self_escalation':'denied',
                    'maintenance_and_worker_rpc':'denied'})
                print(f'PASS zonal identity {len(results)}/{len(users)}: {scope["label"]}',flush=True)
                if not args.candidate:
                    conn.rollback()  # Release report locks and rollback this user's prewarm before the next user.
            inventory = conn.execute("""select user_id from public.app_users
                where lower(btrim(role))='inventory' and is_active is not false limit 1""").fetchone()[0]
            conn.execute("select set_config('request.jwt.claims',%s,true)",
                (json.dumps({'sub':str(inventory),'role':'authenticated'}),))
            conn.execute('set local role authenticated')
            assert conn.execute('select count(*) from public.sales_history').fetchone()[0]==inventory_baseline
            assert conn.execute('select count(*) from public.sales_history_2025').fetchone()[0]==inventory_2025_baseline
            assert conn.execute("select public.item_tracker_my_role()='inventory'").fetchone()[0]
            assert conn.execute("select has_table_privilege(current_user,'public.branches','update')").fetchone()[0]
            assert conn.execute('select public.get_sales_report()').fetchone()[0]['scope_kind']=='inventory'
            assert conn.execute('select public.get_sales_45_report()').fetchone()[0]['scope_kind']=='inventory'
            assert not conn.execute("select has_function_privilege('anon','public.get_sales_45_report(boolean)','execute')").fetchone()[0]
            conn.execute('reset role')
            for table in ('sales_history','sales_last_45_days','app_users','branches'):
                assert not conn.execute('select has_table_privilege(%s,%s,%s)',('anon',f'public.{table}','select')).fetchone()[0]
            conn.execute('set local role anon')
            assert conn.execute('select 1 from public.sales_history_2025 limit 1').fetchone() is None
            conn.execute('reset role')
            for table in ('sales_history','sales_last_45_days'):
                assert conn.execute('select has_table_privilege(%s,%s,%s)',('service_role',f'public.{table}','insert')).fetchone()[0]
            conn.execute("select set_config('request.jwt.claims','{\"role\":\"authenticated\"}',true)")
            conn.execute('set local role authenticated')
            assert conn.execute('select 1 from public.sales_history limit 1').fetchone() is None
            conn.execute('reset role')
            evidence={'verified_at_utc':datetime.now(timezone.utc).isoformat(),
                'candidate_only':bool(args.candidate),'zone_managers_tested':len(results),'checks':results,
                'anonymous_raw_sales_access':'denied','unidentified_session_raw_sales':'denied',
                'inventory_read_and_branch_settings':'preserved','server_ingestion_privileges':'preserved',
                'source_data_changed':False}
            if args.output:
                Path(args.output).write_text(json.dumps(evidence,indent=2,ensure_ascii=False),encoding='utf-8')
            print('PASS all zonal identities, raw sources, report metadata, Storage, authority protection and Inventory compatibility',flush=True)
        finally:
            conn.rollback()
            print('Rolled back all test-only metadata and prewarm side effects',flush=True)


if __name__=='__main__':
    main()
