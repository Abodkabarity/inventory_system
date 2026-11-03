"""Rollback-only checks of View/Category/Inventory parity and zonal separation.

Uses the database connection environment documented in the server cache test.
--candidate tests an unapplied access migration without publishing it.
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
    candidate = Path(args.candidate).read_text(encoding='utf-8') if args.candidate else None
    checks = []
    with connect() as conn:
        def start():
            if candidate:
                conn.execute(candidate)
            conn.execute("set local statement_timeout='45s'")

        def login(user_id):
            conn.execute('reset role')
            conn.execute("select set_config('request.jwt.claims',%s,true)",
                (json.dumps({'sub': str(user_id), 'role': 'authenticated'}),))

        def files():
            return {row[0] for row in conn.execute("""select name from storage.objects
                where bucket_id='sales-report-exports'""")}

        try:
            users = conn.execute("""select user_id,lower(btrim(role)),is_active from public.app_users
                where lower(btrim(role)) in ('inventory','view','category','zone_manager') order by user_id""").fetchall()
            inventory = next(uid for uid, role, active in users if role == 'inventory' and active is not False)
            viewers = [(uid, role) for uid, role, active in users if role in ('view','category') and active is not False]
            assert {role for _, role in viewers} == {'view','category'}, 'Active View and Category identities required'
            conn.rollback()
            for viewer, viewer_role in viewers:
                start()
                login(inventory)
                scope = conn.execute('select sales_report_private.current_scope()').fetchone()[0]
                conn.execute('set local role authenticated')
                monthly = conn.execute('select public.get_sales_report()').fetchone()[0]
                daily = conn.execute('select public.get_sales_45_report()').fetchone()[0]
                inventory_files = files()
                assert inventory_files, 'Need at least one actual ready global Storage object'
                selections = [[m['month']] for m in monthly['months'] if m['month'].endswith('/2025')][:1]
                selections += [[m['month']] for m in monthly['months'] if not m['month'].endswith('/2025')][:1]
                assert len(selections) == 2, 'Need historical 2025 and another year'
                selections.append([m['month'] for m in monthly['months'] if m['month'].endswith('/2025')])
                selected = [conn.execute('select public.get_sales_report(%s,true)', (months,)).fetchone()[0]
                    for months in selections]
                login(viewer)
                assert conn.execute('select sales_report_private.current_scope()').fetchone()[0] == scope
                conn.execute('set local role authenticated')
                assert conn.execute('select public.get_sales_report()').fetchone()[0] == monthly
                assert conn.execute('select public.get_sales_45_report()').fetchone()[0] == daily
                assert conn.execute('select public.get_sales_45_report(true)').fetchone()[0]['scope_kind'] == 'inventory'
                for months, expected in zip(selections, selected):
                    actual = conn.execute('select public.get_sales_report(%s,true)', (months,)).fetchone()[0]
                    assert actual == expected, 'Global readers must share the exact Inventory job and download path'
                assert files() == inventory_files, 'Global reader Storage policy must match Inventory exactly'
                # Existing tracker roles stay unchanged; neither reader becomes Inventory.
                tracker_role = 'category' if viewer_role == 'category' else None
                assert conn.execute('select public.item_tracker_my_role()').fetchone()[0] == tracker_role
                for table in ('sales_history','sales_last_45_days','app_users','app_user_zones'):
                    for privilege in ('insert','update','delete','truncate'):
                        assert not conn.execute('select has_table_privilege(current_user,%s,%s)',
                            (f'public.{table}', privilege)).fetchone()[0], f'{viewer_role} gained {table} {privilege}'
                assert not conn.execute("select has_function_privilege(current_user,'public.sales_report_worker(text,jsonb)','execute')").fetchone()[0]
                assert not conn.execute("select has_table_privilege(current_user,'sales_report_private.jobs','select')").fetchone()[0]
                checks.append({'role':viewer_role,'global_monthly_2025_and_other_years':'matches_inventory',
                    'annual_2025_job':'matches_inventory','current_month_metadata':'matches_inventory',
                    'daily_45_report':'matches_inventory','ready_storage_objects':'matches_inventory',
                    'source_and_authority_writes':'denied'})
                print(f'PASS {viewer_role}: global monthly/2025/annual/current-month/45-day APIs and real Storage access match Inventory', flush=True)
                conn.rollback()
            for uid, role, active in users:
                if role != 'zone_manager' or active is False:
                    continue
                start()
                login(uid)
                scope = conn.execute('select sales_report_private.current_scope()').fetchone()[0]
                assert scope and scope['kind'] == 'zone' and scope['key'] != 'inventory'
                assert not conn.execute('select bool_or(sales_report_private.can_download(path)) from unnest(%s::text[]) path',
                    (list(inventory_files),)).fetchone()[0]
                conn.execute('set local role authenticated')
                assert not files().intersection(inventory_files), 'Zone can see global files'
                assert conn.execute('select public.get_sales_report()').fetchone()[0]['scope_kind'] == 'zone'
                assert conn.execute('select public.get_sales_45_report()').fetchone()[0]['scope_kind'] == 'zone'
                print(f'PASS zone {scope["label"]}: monthly/daily remain scoped and global files denied', flush=True)
                checks.append({'role':'zone_manager','scope':scope['label'],'global_files':'denied','report_scope':'zone'})
                conn.rollback()
            # Inactive and unrelated roles cannot adopt View's global report scope.
            start()
            denied = conn.execute("""select count(*) from public.app_users
                where is_active is false or lower(btrim(role)) not in ('inventory','view','category','zone_manager')""").fetchone()[0]
            conn.execute("""do $$ declare uid uuid; path text; begin
                select storage_path into path from sales_report_private.jobs where storage_path is not null limit 1;
                for uid in select user_id from public.app_users where is_active is false
                    or lower(btrim(role)) not in ('inventory','view','category','zone_manager') loop
                    perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
                    if sales_report_private.current_scope() is not null or sales_report_private.can_download(path) then
                        raise exception 'Inactive or unrelated identity acquired report access';
                    end if;
                end loop;
            end $$""")
            conn.execute("select set_config('request.jwt.claims','{\"role\":\"authenticated\"}',true)")
            assert conn.execute('select sales_report_private.current_scope()').fetchone()[0] is None
            assert not conn.execute("select has_function_privilege('anon','public.get_sales_report(text[],boolean)','execute')").fetchone()[0]
            assert not conn.execute("select has_function_privilege('anon','public.get_sales_45_report(boolean)','execute')").fetchone()[0]
            evidence = {'verified_at_utc':datetime.now(timezone.utc).isoformat(),'candidate_only':bool(candidate),
                'checks':checks,'other_or_inactive_users_denied':denied,'source_data_changed':False}
            if args.output:
                Path(args.output).write_text(json.dumps(evidence,indent=2,ensure_ascii=False),encoding='utf-8')
            print('PASS inactive, unrelated and anonymous access denied; no source data or profiles changed', flush=True)
        finally:
            conn.rollback()


if __name__ == '__main__':
    main()
