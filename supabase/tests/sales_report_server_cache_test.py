"""Rollback-only integration checks; fixtures never modify source sales/branches.

Set DATABASE_URL or SUPABASE_DB_* in the test environment. --migration validates
the deployment SQL and its permissions inside the same rollback transaction.
"""
from __future__ import annotations

import argparse
import base64
import csv
import io
import json
import os
import re
from pathlib import Path
from datetime import timedelta

import psycopg


def raw_csv_month(value):
    """Decode the validated Excel display expression for source comparisons."""
    if re.fullmatch(r'="(?:0[1-9]|1[0-2])/[0-9]{4}"', value):
        return value[2:-1]
    return value


def connect():
    if os.environ.get('DATABASE_URL'):
        return psycopg.connect(os.environ['DATABASE_URL'], connect_timeout=15)
    return psycopg.connect(
        host=os.environ['SUPABASE_DB_HOST'], user=os.environ['SUPABASE_DB_USER'],
        password=os.environ['SUPABASE_DB_PASSWORD'], port=os.environ.get('SUPABASE_DB_PORT', '5432'),
        dbname='postgres', sslmode='require', connect_timeout=15,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--migration', required=True)
    args = parser.parse_args()
    with connect() as conn:
        def scoped(sql):
            for old,new in (
                ('sales_report_private','sales_report_test_private'),
                ('public.get_sales_report','public.get_sales_report_test'),
                ('public.get_sales_45_report','public.get_sales_45_report_test'),
                ('public.sales_report_worker','public.sales_report_test_worker'),
                ('sales_report_worker_token','sales_report_test_worker_token'),
                ('sales-report-exports','sales-report-test-exports'),
                ('sales-report-server-cache','sales-report-test-cache'),
                ('sales_report_inventory_download','sales_report_test_inventory_download'),
            ):
                sql=sql.replace(old,new)
            return sql
        def execute(sql,params=None):
            return conn.execute(scoped(sql),params)
        try:
            execute('create temp table sales_report_fixture (like public.sales_history)')
            execute('create temp table sales_report_daily_fixture as select * from public.sales_last_45_days with no data')
            execute("alter table sales_report_daily_fixture alter column branch_name set default 'Alpha'")
            execute('create temp table sales_report_receipt_fixture(report_date date,result jsonb)')
            execute("insert into sales_report_daily_fixture(inv_date) values (date_trunc('month',statement_timestamp() at time zone 'Asia/Dubai')::date), (((statement_timestamp() at time zone 'Asia/Dubai')::date)+1)")
            execute('create temp table sales_report_branches (branch_name text, branch_group text,zone text,is_active boolean default true)')
            execute("insert into sales_report_branches values ('Alpha','71','ZoneA',true),('Beta','APG','ZoneB',true),('71 Gamma','71','ZoneA',true)")
            execute("""insert into sales_report_fixture(branch_name,item_code,item_name,month,cash,online,insurance,total_sales,retail,sales_value)
                values ('Alpha','001','Quoted "name", line' || chr(10) || 'two','01/2026',1,2,3,6,10,60),
                ('Alpha','001','Quoted "name", line' || chr(10) || 'two','01/2026',1,2,3,6,10,60),
                ('Beta','002','عربي','01/2026',-1,null,0,-1,9,-9),
                ('71 Gamma','003',null,'02/2026',0,0,0,0,0,0)""")
            zone_users = execute("select user_id from public.app_users where role='zone_manager' and is_active is not false order by user_id limit 2").fetchall()
            assert len(zone_users)==2
            zone_a,zone_b = [str(u[0]) for u in zone_users]
            execute('create temp table sales_report_zone_assignments(user_id uuid,zone text,expires_at timestamptz)')
            execute('insert into sales_report_zone_assignments(user_id,zone) values(%s,%s),(%s,%s)',(zone_a,'ZoneA',zone_b,'ZoneB'))
            execute("""create function pg_temp.sales_report_effective_zones() returns table(zone text)
                language sql stable as $$select z.zone from pg_temp.sales_report_zone_assignments z
                where z.user_id=auth.uid() and (z.expires_at is null or z.expires_at>now())$$""")
            migration = Path(args.migration).read_text(encoding='utf-8')
            migration = migration.replace('public.sales_history', 'pg_temp.sales_report_fixture')
            migration = migration.replace('public.branches', 'pg_temp.sales_report_branches')
            execute(migration)
            for name in ('20261102100742_sales_report_worker_timeout.sql','20261102100950_sales_report_nonblocking_prepare.sql','20261102103607_sales_report_current_month_last_day.sql','20261102104754_sales_report_remove_created_at_column.sql','20261102105233_sales_report_zone_scoped_exports.sql','20261102110911_sales_report_bounded_snapshot_memory.sql','20261102122752_sales_report_daily_45_export.sql'):
                followup=Path(args.migration).with_name(name)
                if followup.exists():
                    execute(followup.read_text(encoding='utf-8').replace('public.sales_history','pg_temp.sales_report_fixture').replace('public.branches','pg_temp.sales_report_branches').replace('public.sales_last_45_days','pg_temp.sales_report_daily_fixture').replace('public.get_my_effective_zones()','pg_temp.sales_report_effective_zones()').replace('sales_ingest_private.daily_runs','pg_temp.sales_report_receipt_fixture'))
            print('Migration parsed and applied within rollback transaction')
            execute("insert into sales_report_private.jobs(months,priority) values(array['01/2026'],0)")
            # Claim/prepare through exactly the gateway used by the Edge worker.
            claim = execute("select public.sales_report_worker('claim')").fetchone()[0]
            job = claim['job']
            params = {'lease': claim['lease'], 'id': job['id'], 'generation': job['generation']}
            def worker(action, **extra):
                active=dict(extra)
                for checkpoint in range(121):
                    result=execute('select public.sales_report_worker(%s,%s::jsonb)',
                        (action,json.dumps(params | active))).fetchone()[0]
                    if action!='prepare' or result['status']!='queued': return result
                    active.update(id=result['id'],generation=result['generation'])
                raise AssertionError('Too many monthly checkpoints')
            prepared = worker('prepare')
            body = worker('bytes', offset=0)
            payload = base64.b64decode(body['base64'])
            assert len(payload) == prepared['byte_size'] == body['length']
            rows = list(csv.reader(io.StringIO(payload.decode('utf-8-sig'), newline='')))
            assert len(rows[0]) == 10 and 'created_at' not in rows[0]
            assert all(len(row) == 10 for row in rows)
            assert len(rows) - 1 == prepared['row_count'] == 3
            assert rows[1] == rows[2], 'Duplicate source rows must remain in export'
            assert rows[1][0] == '71 Alpha' and rows[3][0] == 'Beta'
            assert rows[1][2] == 'Quoted "name", line\ntwo'
            assert rows[3][2] == 'عربي' and rows[3][4] == '-1'
            assert execute("select sales_report_private.display_branch('71 Gamma','{\"71 GAMMA\":\"71\"}')").fetchone()[0] == '71 Gamma'
            assert worker('complete') is False, 'An absent/incomplete upload must never become ready'
            # Verify byte-range reassembly, including boundaries inside UTF-8 text.
            for offset in (1, 3, 91, len(payload)-1):
                assert base64.b64decode(worker('bytes', offset=offset)['base64']) == payload[offset:]
            # Cross both the 5,000-row boundary and the 6 MiB upload boundary.
            execute("""insert into sales_report_fixture(branch_name,item_code,item_name,month,cash)
                select 'Alpha',n::text,repeat('مرحبا',160),'03/2026',n from generate_series(1,5101) n""")
            execute("update sales_report_private.state set metadata_version=null")
            execute("insert into sales_report_private.jobs(months,priority) values(array['03/2026'],-1)")
            worker('release')
            claim = execute("select public.sales_report_worker('claim')").fetchone()[0]
            job = claim['job']
            params = {'lease': claim['lease'], 'id': job['id'], 'generation': job['generation']}
            large = worker('prepare')
            assert large['row_count'] == 5101
            assert execute('select count(*) from sales_report_private.pieces where job_id=%s', (job['id'],)).fetchone()[0] == 3
            parts = []
            for offset in range(0,large['byte_size'],6291456):
                part = base64.b64decode(worker('bytes',offset=offset)['base64'])
                assert len(part) == min(6291456,large['byte_size']-offset)
                parts.append(part)
            assert len(parts)>1
            large_rows = list(csv.reader(io.StringIO(b''.join(parts).decode('utf-8-sig'),newline='')))
            assert len(large_rows)-1 == 5101
            assert all(r[0]=='71 Alpha' and r[2]=='مرحبا'*160 for r in large_rows[1:])
            print('PASS: 5,101 rows, multiple SQL pieces and exact 6 MiB TUS boundaries')
            inventory = execute("select user_id from public.app_users where lower(btrim(role::text))='inventory' and is_active is not false limit 1").fetchone()
            assert inventory, 'An inventory role fixture is required'
            execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({'role':'authenticated','sub':str(inventory[0])}),))
            execute('set local role authenticated')
            api = execute('select public.get_sales_report(%s,false)', (['01/2026'],)).fetchone()[0]
            assert api['job']['row_count'] == 3 and api['job']['storage_path'] is None
            expected_day = execute("select date_trunc('month',statement_timestamp() at time zone 'Asia/Dubai')::date").fetchone()[0]
            assert api['current_month_last_day'] == expected_day.isoformat(), 'Future invoices must not advance the last available day'
            assert api['current_month'] == expected_day.strftime('%m/%Y')
            execute('reset role')
            execute('delete from sales_report_daily_fixture')
            execute('set local role authenticated')
            assert execute('select public.get_sales_report()').fetchone()[0]['current_month_last_day'] is None
            execute('reset role')
            print('PASS: real invoice-date metadata, Dubai current month, future-date exclusion and absent-data handling')
            # Two real role identities, isolated fixture assignments and raw data.
            def login(uid):
                execute('reset role')
                execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({'role':'authenticated','sub':uid}),))
                execute('set local role authenticated')
            login(zone_a)
            scoped_a=execute("select public.get_sales_report(array['01/2026'],true)").fetchone()[0]
            assert scoped_a['scope_kind']=='zone' and scoped_a['scope_label']=='ZoneA'
            assert {m['month'] for m in scoped_a['months']}=={'01/2026','02/2026','03/2026'}
            a_job=scoped_a['job']
            execute('reset role')
            a_args={'id':a_job['id'],'generation':a_job['generation']}
            a_prepared=worker('prepare',**a_args)
            a_csv=list(csv.reader(io.StringIO(base64.b64decode(worker('bytes',offset=0,**a_args)['base64']).decode('utf-8-sig'),newline='')))
            assert a_prepared['row_count']==2 and len(a_csv)==3
            assert 'created_at' not in a_csv[0] and len(a_csv[0])==10
            assert all(row[0]=='71 Alpha' for row in a_csv[1:]), 'Zone CSV must contain only authorized branches'
            execute("update sales_report_private.jobs set status='ready',storage_path='zone-a-fixture.csv' where id=%s",(a_job['id'],))
            execute("update sales_report_private.jobs set status='ready',storage_path='global-fixture.csv' where scope_key='inventory' and months=array['01/2026']")
            login(zone_a)
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0] is True
            assert execute("select sales_report_private.can_download('global-fixture.csv')").fetchone()[0] is False
            login(zone_b)
            scoped_b=execute("select public.get_sales_report(array['01/2026'],true)").fetchone()[0]
            assert {m['month'] for m in scoped_b['months']}=={'01/2026'}, 'Other zones months must not leak'
            assert scoped_b['current_month_last_day'] is None, 'Other zones invoice dates must not leak'
            assert scoped_b['job']['id'] != a_job['id']
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0] is False
            assert execute("select sales_report_private.can_download('global-fixture.csv')").fetchone()[0] is False
            execute('reset role')
            b_args={'id':scoped_b['job']['id'],'generation':scoped_b['job']['generation']}
            b_prepared=worker('prepare',**b_args)
            b_csv=list(csv.reader(io.StringIO(base64.b64decode(worker('bytes',offset=0,**b_args)['base64']).decode('utf-8-sig'),newline='')))
            assert b_prepared['row_count']==1 and b_csv[1][0]=='Beta'
            # Revocation/expired delegations immediately invalidate the old scope.
            execute("update sales_report_zone_assignments set expires_at=now()-interval '1 second' where user_id=%s",(zone_a,))
            login(zone_a)
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0] is False
            empty_scope=execute('select public.get_sales_report()').fetchone()[0]
            assert empty_scope['months']==[] and empty_scope['job'] is None
            execute('reset role')
            # Multi-zone access follows only effective assignments, with its own cache.
            execute("insert into sales_report_zone_assignments values(%s,'ZoneA',now()+interval '1 hour')",(zone_b,))
            login(zone_b)
            combined=execute("select public.get_sales_report(array['01/2026','02/2026'],true)").fetchone()[0]
            assert combined['scope_label']=='ZoneA + ZoneB'
            assert combined['job']['id'] not in (a_job['id'],scoped_b['job']['id'])
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0] is False
            execute('reset role')
            print('PASS: disjoint zonal CSVs, scoped month/date metadata, global/cross-zone download denial, expired scope revocation and multi-zone assignments')
            # Daily mode is separate, date-bounded, scoped, and invalidated by
            # the existing source publication transaction without monthly churn.
            execute('truncate sales_report_daily_fixture')
            expected_day=execute('select sales_report_private.daily_expected_day()').fetchone()[0]
            today=execute("select (statement_timestamp() at time zone 'Asia/Dubai')::date").fetchone()[0]
            assert execute("select sales_report_private.daily_expected_day('2026-11-03 03:59:59+00')").fetchone()[0].isoformat()=='2026-11-01'
            assert execute("select sales_report_private.daily_expected_day('2026-11-03 04:00:00+00')").fetchone()[0].isoformat()=='2026-11-02'
            execute("delete from sales_report_zone_assignments")
            execute("insert into sales_report_zone_assignments(user_id,zone) values(%s,'ZoneA'),(%s,'ZoneB')",(zone_a,zone_b))
            fixture=[
                (1,'Alpha',expected_day-timedelta(days=44),'D01','Boundary',1,'Cash','Retail',''),
                (2,'Alpha',expected_day,'D02','Quoted \"item\", عربي',2,'Delivery Invoice','Retail','عميل'),
                (3,'Alpha',expected_day,'D02','Quoted \"item\", عربي',2,'Delivery Invoice','Retail','عميل'),
                (4,'Alpha',expected_day-timedelta(days=45),'OLD','Outside',999,'Cash','Retail',''),
                (5,'Beta',expected_day,'D03','Other zone',4,'Cash','Retail',''),
                (6,'Beta',today+timedelta(days=1),'FUTURE','Future',888,'Cash','Retail',''),
                (7,'Alpha',expected_day-timedelta(days=20),'D04','Return',-1,None,None,None),
            ]
            with conn.cursor() as cur:
                cur.executemany("insert into sales_report_daily_fixture(id,branch_name,inv_date,item_code,item_name,qty,sales_type,inv_type,customer_name) values(%s,%s,%s,%s,%s,%s,%s,%s,%s)",fixture)
            execute("update sales_report_private.daily_revision set changed_at=statement_timestamp()-interval '2 minutes'")
            login(zone_a)
            # Date coverage alone is insufficient before the atomic morning publish.
            assert execute('select public.get_sales_45_report()').fetchone()[0]['awaiting_update']
            execute("reset role")
            execute("insert into sales_report_receipt_fixture values(%s,'{\"published\":true}')",(expected_day,))
            execute("set local role authenticated")
            daily_a=execute('select public.get_sales_45_report(true)').fetchone()[0]
            assert daily_a['awaiting_update'] is False
            assert daily_a['period_through']==expected_day.isoformat()
            assert daily_a['period_from']==(expected_day-timedelta(days=44)).isoformat()
            assert len(daily_a['days'])==3
            execute('reset role')
            daily_args={'id':daily_a['job']['id'],'generation':daily_a['job']['generation']}
            daily_prepared=worker('prepare',**daily_args)
            daily_csv=list(csv.reader(io.StringIO(base64.b64decode(worker('bytes',offset=0,**daily_args)['base64']).decode('utf-8-sig'),newline='')))
            assert daily_prepared['row_count']==4 and len(daily_csv)==5
            assert daily_csv[0]==['branch_name','inv_date','item_code','item_name','qty','sales_type','inv_type','customer_name']
            assert daily_csv[-1]==daily_csv[-2], 'Daily duplicates must be preserved'
            assert all(r[0]=='71 Alpha' and r[2] not in ('OLD','FUTURE') for r in daily_csv[1:])
            execute("update sales_report_private.jobs set status='ready',storage_path='daily-a-fixture.csv' where id=%s",(daily_args['id'],))
            login(zone_a)
            assert execute("select sales_report_private.can_download('daily-a-fixture.csv')").fetchone()[0]
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0]
            login(zone_b)
            assert not execute("select sales_report_private.can_download('daily-a-fixture.csv')").fetchone()[0]
            daily_b=execute('select public.get_sales_45_report()').fetchone()[0]
            assert daily_b['days']==[expected_day.isoformat()]
            assert daily_b['job']['id']!=daily_a['job']['id']
            execute('reset role')
            monthly_version=execute('select sales_report_private.source_version()').fetchone()[0]
            # A source correction instantly revokes the cached daily file, and
            # the stability window prevents publishing a partially loaded file.
            execute("update sales_report_daily_fixture set qty=qty+1 where id=2")
            assert execute('select sales_report_private.source_version()').fetchone()[0]==monthly_version
            login(zone_a)
            assert not execute("select sales_report_private.can_download('daily-a-fixture.csv')").fetchone()[0]
            updating=execute('select public.get_sales_45_report()').fetchone()[0]
            assert updating['awaiting_update'] and updating['job']['storage_path'] is None
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0]
            execute('reset role')
            # Simulate delayed morning data without touching production sources.
            execute('delete from sales_report_daily_fixture where inv_date=%s',(expected_day,))
            execute("update sales_report_private.daily_revision set changed_at=statement_timestamp()-interval '2 minutes'")
            login(zone_a)
            waiting=execute('select public.get_sales_45_report()').fetchone()[0]
            assert waiting['awaiting_update'] and waiting['job']['storage_path'] is None
            execute('reset role')
            # Both companies' committed receipt plus live rows make the new
            # version eligible after the quiet period. Staging alone does not.
            execute("insert into sales_report_receipt_fixture values(%s,'{\"published\":false}')",(expected_day,))
            execute("select sales_report_private.sync_daily()")
            assert not execute('select sales_report_private.daily_fresh()').fetchone()[0]
            execute("insert into sales_report_daily_fixture(id,branch_name,inv_date,item_code,qty) values(20,'Alpha',%s,'NEW',5),(21,'Beta',%s,'NEW',7)",(expected_day,expected_day))
            execute("update sales_report_receipt_fixture set result='{\"published\":true}'")
            execute("update sales_report_private.daily_revision set changed_at=statement_timestamp()-interval '2 minutes'")
            login(zone_a)
            refreshed=execute('select public.get_sales_45_report(true)').fetchone()[0]
            assert not refreshed['awaiting_update'] and refreshed['job']['generation']!=daily_a['job']['generation']
            execute('reset role')
            print('PASS: separate daily CSV, exact 45-day boundaries, 08:00 UAE cutoff, source-correction invalidation, quiet-period/morning-load gating, zonal isolation and unchanged monthly cache')
            # Apply the monthly-current upgrade after all legacy contracts above.
            upgrade=Path(args.migration).with_name('20261103042214_sales_report_current_month_daily_sales.sql')
            execute(upgrade.read_text(encoding='utf-8').replace('public.sales_history','pg_temp.sales_report_fixture').replace('public.branches','pg_temp.sales_report_branches').replace('public.sales_last_45_days','pg_temp.sales_report_daily_fixture').replace('public.get_my_effective_zones()','pg_temp.sales_report_effective_zones()').replace('sales_ingest_private.daily_runs','pg_temp.sales_report_receipt_fixture'))
            first=execute('select sales_report_private.current_month_start()').fetchone()[0]
            month=first.strftime('%m/%Y')
            assert expected_day>=first, 'Run the current-month fixture after the first completed morning in the month'
            execute('truncate sales_report_daily_fixture')
            fixture=[
                (30,'Alpha',first,'M01','Current',10,'Cash','Retail',''),
                (31,'Alpha',expected_day,'M01','Current',2,'Delivery Invoice','Retail',''),
                (32,'Alpha',expected_day,'M01','Current',-1,'Return Delivery Invoice','Retail',''),
                (33,'Alpha',expected_day,'M01','Current',3,'Delivery Invoice','Insurance',''),
                (34,'Alpha',expected_day,'M01','Current',4,'Cash',' DiRiCt   Insurance ',''),
                (35,'Alpha',expected_day,'M01','Current',-2,'Cash','Direct Insurance',''),
                (36,'Alpha',expected_day,'M01','Current',2,'Cash','Retail',''),
                (37,'Alpha',expected_day,'M01','Current',2,'Cash','Retail',''),
                (38,'Beta',expected_day,'OTHER','Other zone',99,'Cash','Retail',''),
                (39,'Alpha',today+timedelta(days=1),'FUTURE','Future',999,'Cash','Retail',''),
                (40,'Alpha',first-timedelta(days=1),'OLD','Prior month',888,'Cash','Retail',''),
            ]
            with conn.cursor() as cur:
                cur.executemany("insert into sales_report_daily_fixture(id,branch_name,inv_date,item_code,item_name,qty,sales_type,inv_type,customer_name) values(%s,%s,%s,%s,%s,%s,%s,%s,%s)",fixture)
            execute("insert into sales_report_fixture(branch_name,item_code,month,cash,total_sales,sales_value) values('Alpha','M01',%s,700,700,700)",(month,))
            execute("update sales_report_private.daily_revision set changed_at=statement_timestamp()-interval '2 minutes'")
            execute("update sales_report_private.state set lease_until=now()+interval '15 minutes'")
            login(zone_a)
            combined=execute('select public.get_sales_report(%s,true)',(['01/2026',month],)).fetchone()[0]
            assert not combined['awaiting_update'] and combined['metadata_current']
            assert next(m for m in combined['months'] if m['month']==month)['source']=='daily'
            assert combined['current_month_last_day']==expected_day.isoformat()
            execute('reset role')
            combo_args={'id':combined['job']['id'],'generation':combined['job']['generation']}
            combo_job=worker('prepare',**combo_args)
            combo_csv=list(csv.reader(io.StringIO(base64.b64decode(worker('bytes',offset=0,**combo_args)['base64']).decode('utf-8-sig'),newline='')))
            assert len(combo_csv)==4 and combo_job['row_count']==3
            assert combo_csv[1]==combo_csv[2], 'Historical duplicates must stay unchanged in a combined export'
            current=[r for r in combo_csv[1:] if r[3]==month]
            assert len(current)==1 and current[0][0]=='71 Alpha' and current[0][1]=='M01'
            assert list(map(float,current[0][4:8]))==[14,1,5,20]
            assert current[0][8:]==['',''], 'Unavailable retail/value must be empty, never fabricated'
            assert all(r[0]=='71 Alpha' for r in combo_csv[1:])
            execute("update sales_report_private.jobs set status='ready',storage_path='current-combined-fixture.csv' where id=%s",(combo_args['id'],))
            login(zone_a)
            assert execute("select sales_report_private.can_download('current-combined-fixture.csv')").fetchone()[0]
            login(zone_b)
            assert not execute("select sales_report_private.can_download('current-combined-fixture.csv')").fetchone()[0]
            other=execute('select public.get_sales_report(%s,true)',([month],)).fetchone()[0]
            assert next(m for m in other['months'] if m['month']==month)['row_count']==1
            execute('reset role')
            old_version=execute("select sales_report_private.monthly_version(array['01/2026'])").fetchone()[0]
            current_version=execute('select sales_report_private.monthly_version(%s)',(['01/2026',month],)).fetchone()[0]
            execute('update sales_report_daily_fixture set qty=qty+1 where id=30')
            assert execute("select sales_report_private.monthly_version(array['01/2026'])").fetchone()[0]==old_version
            assert execute('select sales_report_private.monthly_version(%s)',(['01/2026',month],)).fetchone()[0]!=current_version
            login(zone_a)
            wait=execute('select public.get_sales_report(%s,false)',(['01/2026',month],)).fetchone()[0]
            assert wait['awaiting_update'] and not wait['job']['is_current'] and wait['job']['storage_path'] is None
            assert not execute("select sales_report_private.can_download('current-combined-fixture.csv')").fetchone()[0]
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0]
            execute('reset role')
            # Date coverage does not release the month until the import receipt is committed.
            execute("update sales_report_private.daily_revision set changed_at=statement_timestamp()-interval '2 minutes'")
            execute("update sales_report_receipt_fixture set result='{\"published\":false}'")
            login(zone_a)
            assert execute('select public.get_sales_report(%s,false)',([month],)).fetchone()[0]['awaiting_update']
            execute('reset role')
            execute("update sales_report_receipt_fixture set result='{\"published\":true}'")
            # API refresh happens before worker claim: stale current-month jobs must still reset.
            login(zone_a)
            assert not execute('select public.get_sales_report(%s,false)',([month],)).fetchone()[0]['awaiting_update']
            execute('reset role')
            worker('release')
            claim=execute("select public.sales_report_worker('claim')").fetchone()[0]
            params={'lease':claim['lease'],'id':claim['job']['id'],'generation':claim['job']['generation']}
            reset=execute('select status,generation from sales_report_private.jobs where id=%s',(combo_args['id'],)).fetchone()
            assert reset[0]=='queued' and str(reset[1])!=combo_args['generation']
            # Calendar rollover must drop the daily month instead of returning a silently incomplete file.
            next_month=(first.replace(day=28)+timedelta(days=4)).replace(day=1)
            execute("create or replace function sales_report_private.current_month_start() returns date language sql stable security invoker set search_path='' as $$select date '"+next_month.isoformat()+"'$$")
            assert execute('select sales_report_private.monthly_version(%s)',([month],)).fetchone()[0]==old_version
            execute("select sales_report_private.refresh_monthly_metadata('inventory',null)")
            # Remove the intentionally conflicting source fixture: no completed monthly publication yet.
            execute('delete from sales_report_fixture where month=%s',(month,))
            execute("update sales_report_private.state set metadata_version=null")
            execute("select sales_report_private.refresh_monthly_metadata('inventory',null)")
            assert not execute('select sales_report_private.monthly_selection_available(%s)',([month],)).fetchone()[0]
            print('PASS: daily current month + unchanged history in one CSV, channel precedence, signed returns, empty prices, scope denial, fresh import gating, independent cache versions and calendar rollover')
            # Archive fixtures and revision counters are isolated too: no writes
            # to the live 2025 table, revision table or its existing RLS policies.
            legacy_26_version=execute("select sales_report_private.monthly_version(array['01/2026'])").fetchone()[0]
            execute('create temp table sales_report_2025_fixture (like public.sales_history_2025)')
            execute('create temp table sales_report_revision_fixture as select * from public.stock_catalog_cache_revisions')
            execute("""insert into sales_report_2025_fixture(branch_name,item_code,item_name,month,cash,online,insurance,total_sales,retail,sales_value) values
                ('Alpha','001','2025 quoted "item", عربي','01/2025',4,5,6,15,3,45),
                ('Alpha','001','2025 quoted "item", عربي','01/2025',4,5,6,15,3,45),
                ('Alpha','DEC','Year end','12/2025',1,0,0,1,2,2),
                ('Beta','OTHER','Other zone','01/2025',-2,0,0,-2,5,-10),
                ('Beta','ONLYB','Only zone B month','02/2025',2,0,0,2,5,10),
                ('Alpha','WRONGYEAR','Ignore a misplaced archive row','03/2026',999,0,0,999,1,999)""")
            execute("insert into sales_report_fixture(branch_name,item_code,month,cash,total_sales) values('Alpha','WRONGSOURCE','01/2025',777,777)")
            execute("create or replace function sales_report_private.current_month_start() returns date language sql stable security invoker set search_path='' as $$select date '"+first.isoformat()+"'$$")
            archive_upgrade=Path(args.migration).with_name('20261103055641_sales_report_include_2025_history.sql')
            execute(archive_upgrade.read_text(encoding='utf-8').replace('public.sales_history_2025','pg_temp.sales_report_2025_fixture').replace('public.sales_history','pg_temp.sales_report_fixture').replace('public.branches','pg_temp.sales_report_branches').replace('public.sales_last_45_days','pg_temp.sales_report_daily_fixture').replace('public.stock_catalog_cache_revisions','pg_temp.sales_report_revision_fixture'))
            incremental=Path(args.migration).with_name('20261103062635_sales_report_incremental_month_prepare.sql')
            execute(incremental.read_text(encoding='utf-8').replace('public.branches','pg_temp.sales_report_branches'))
            assert execute("select sales_report_private.monthly_version(array['01/2026'])").fetchone()[0]==legacy_26_version
            login(zone_a)
            archived=execute('select public.get_sales_report(%s,true)',(['01/2025','01/2026',month],)).fetchone()[0]
            a25months={m['month'] for m in archived['months'] if m['month'].endswith('/2025')}
            assert a25months=={'01/2025','12/2025'}, 'Archive month availability must remain scoped'
            assert next(m for m in archived['months'] if m['month']=='01/2025')['source']=='history_2025'
            assert not archived['awaiting_update']
            execute('reset role')
            archive_args={'id':archived['job']['id'],'generation':archived['job']['generation']}
            archived_job=worker('prepare',**archive_args)
            archived_csv=list(csv.reader(io.StringIO(base64.b64decode(worker('bytes',offset=0,**archive_args)['base64']).decode('utf-8-sig'),newline='')))
            assert archived_job['row_count']==5 and len(archived_csv)==6
            old=[r for r in archived_csv[1:] if r[3]=='01/2025']
            assert len(old)==2 and old[0]==old[1] and old[0][0]=='71 Alpha'
            assert old[0][4:]==['4','5','6','15','3','45']
            assert old[0][2]=='2025 quoted "item", عربي'
            assert all(r[0]=='71 Alpha' and r[1] not in ('WRONGYEAR','WRONGSOURCE') for r in archived_csv[1:])
            assert {r[3] for r in archived_csv[1:]}=={'01/2025','01/2026',month}
            assert len(archived_csv[0])==10 and 'created_at' not in archived_csv[0]
            # Multi-year combinations are only created when explicitly requested.
            scope=execute('select sales_report_private.current_scope()').fetchone()[0]
            assert execute("select count(*) from sales_report_private.jobs where scope_key=%s and report_kind='monthly' and exists(select 1 from unnest(months) m where right(m,4)='2025') and exists(select 1 from unnest(months) m where right(m,4)<>'2025')",(scope['key'],)).fetchone()[0]==1
            execute("update sales_report_private.jobs set status='ready',storage_path='archive-combined-fixture.csv' where id=%s",(archive_args['id'],))
            login(zone_a)
            assert execute("select sales_report_private.can_download('archive-combined-fixture.csv')").fetchone()[0]
            login(zone_b)
            assert not execute("select sales_report_private.can_download('archive-combined-fixture.csv')").fetchone()[0]
            b25=execute("select public.get_sales_report(array['01/2025'],true)").fetchone()[0]
            assert {m['month'] for m in b25['months'] if m['month'].endswith('/2025')}=={'01/2025','02/2025'}
            execute('reset role')
            # An archive correction invalidates only archive-dependent exports.
            v25=execute("select sales_report_private.monthly_version(array['01/2025'])").fetchone()[0]
            mixed_version=execute("select sales_report_private.monthly_version(array['01/2025','01/2026'])").fetchone()[0]
            execute("update sales_report_revision_fixture set revision=revision+1 where source='sales_2025'")
            assert execute("select sales_report_private.monthly_version(array['01/2025'])").fetchone()[0]!=v25
            assert execute("select sales_report_private.monthly_version(array['01/2025','01/2026'])").fetchone()[0]!=mixed_version
            assert execute("select sales_report_private.monthly_version(array['01/2026'])").fetchone()[0]==legacy_26_version
            login(zone_a)
            assert not execute("select sales_report_private.can_download('archive-combined-fixture.csv')").fetchone()[0]
            assert execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0]
            execute('reset role')
            print('PASS: 2025 + 2026 + current month in one CSV, scoped archive month metadata and downloads, raw duplicates/prices, authoritative year sources and independent archive invalidation')
            # Resume between month checkpoints, then restart safely after a
            # source correction. No partially prepared file can be downloaded.
            staged=execute("insert into sales_report_private.jobs(months,priority) values(array['01/2025','12/2025'],-1000) on conflict(scope_key,months) do update set status='queued',source_version=null,generation=gen_random_uuid() returning id,generation").fetchone()
            staged_args={'id':str(staged[0]),'generation':str(staged[1])}
            partial=execute('select public.sales_report_worker(%s,%s::jsonb)',('prepare',json.dumps(params|staged_args))).fetchone()[0]
            assert partial['status']=='queued' and partial['prepared_months']==1 and partial['row_count']==3
            first_lease=params['lease']
            worker('release')
            resumed=execute("select public.sales_report_worker('claim')").fetchone()[0]
            assert resumed['lease']!=first_lease and resumed['job']['id']==staged_args['id']
            params={'lease':resumed['lease'],'id':resumed['job']['id'],'generation':resumed['job']['generation']}
            execute("update sales_report_2025_fixture set cash=cash+1 where branch_name='Alpha' and month='01/2025'")
            execute("update sales_report_revision_fixture set revision=revision+1 where source='sales_2025'")
            restarted=execute('select public.sales_report_worker(%s,%s::jsonb)',('prepare',json.dumps(params))).fetchone()[0]
            assert restarted['status']=='queued' and restarted['prepared_months']==1
            assert restarted['generation']!=staged_args['generation']
            params.update(generation=restarted['generation'])
            final=worker('prepare')
            staged_csv=list(csv.reader(io.StringIO(base64.b64decode(worker('bytes',offset=0)['base64']).decode('utf-8-sig'),newline='')))
            assert final['status']=='uploading' and final['prepared_months']==2 and final['row_count']==4
            assert [r[4] for r in staged_csv[1:] if r[0]=='71 Alpha' and r[3]=='01/2025']==['5','5']
            assert execute('select count(*) from sales_report_private.pieces where job_id=%s and part=0',(staged_args['id'],)).fetchone()[0]==1
            # Cross both the month checkpoint and the 6 MiB TUS byte boundary.
            big=execute("insert into sales_report_private.jobs(months) values(array['01/2025','03/2026']) returning id,generation").fetchone()
            big_args={'id':str(big[0]),'generation':str(big[1])}
            big_job=worker('prepare',**big_args)
            pieces=[base64.b64decode(worker('bytes',offset=offset,**big_args)['base64']) for offset in range(0,big_job['byte_size'],6291456)]
            big_csv=list(csv.reader(io.StringIO(b''.join(pieces).decode('utf-8-sig'),newline='')))
            assert len(pieces)>1 and big_job['row_count']==5104 and len(big_csv)==5105
            print('PASS: durable month checkpoints, lease reacquisition, correction-safe restart, one header, and multi-month exact 6 MiB byte ranges')
            # Excel must show the month literally, while all identifiers and
            # source month values remain unchanged. The only allowed expression
            # is a whitelisted constant, never arbitrary spreadsheet input.
            daily_before=execute('select sales_report_private.daily_version()').fetchone()[0]
            format_migration=Path(args.migration).with_name('20261103065242_sales_report_excel_month_display.sql')
            execute(format_migration.read_text(encoding='utf-8').replace('public.branches','pg_temp.sales_report_branches'))
            assert execute("select sales_report_private.excel_month('06/2025')").fetchone()[0]=='="06/2025"'
            assert execute("select sales_report_private.excel_month('01/2027')").fetchone()[0]=='="01/2027"'
            assert execute('select sales_report_private.daily_version()').fetchone()[0]==daily_before
            assert execute("select sales_report_private.monthly_version(array['01/2026'])").fetchone()[0].endswith(':excel-month-v1')
            for invalid in ('00/2025','13/2025','6/2025','06/25','=1+1','06/2025"&NOW()'):
                execute('savepoint invalid_excel_month')
                try:
                    execute('select sales_report_private.excel_month(%s)',(invalid,))
                    raise AssertionError('Unsafe month must be rejected')
                except psycopg.errors.InvalidParameterValue:
                    execute('rollback to savepoint invalid_excel_month')
            execute("insert into sales_report_2025_fixture(branch_name,item_code,item_name,month,cash,online,insurance,total_sales,retail,sales_value) values('Alpha','JUNE','June item','06/2025',4,5,6,15,3,45)")
            execute("update sales_report_revision_fixture set revision=revision+1 where source='sales_2025'")
            login(zone_a)
            june=execute("select public.get_sales_report(array['06/2025'],true)").fetchone()[0]
            assert '06/2025' in {m['month'] for m in june['months']}, 'API/filter months must stay raw'
            assert not execute("select sales_report_private.can_download('zone-a-fixture.csv')").fetchone()[0], 'Old-format cache must be invalidated'
            execute('reset role')
            june_args={'id':june['job']['id'],'generation':june['job']['generation']}
            worker('prepare',**june_args)
            june_csv=list(csv.reader(io.StringIO(base64.b64decode(worker('bytes',offset=0,**june_args)['base64']).decode('utf-8-sig'),newline='')))
            assert june_csv[1]==['71 Alpha','JUNE','June item','="06/2025"','4','5','6','15','3','45']
            assert execute("select month from sales_report_2025_fixture where item_code='JUNE'").fetchone()[0]=='06/2025'
            print('PASS: Excel literal MM/YYYY display, unchanged raw API/source months and numeric values, safe constant validation, old-format invalidation and unchanged daily revision')
            for role in ('anon','authenticated'):
                assert not execute('select has_function_privilege(%s,%s,%s)',
                    (role, 'public.sales_report_worker(text,jsonb)', 'execute')).fetchone()[0]
                assert not execute('select has_table_privilege(%s,%s,%s)',
                    (role, 'sales_report_private.pieces', 'select')).fetchone()[0]
            execute("select set_config('request.jwt.claims','{\"role\":\"authenticated\"}',true)")
            execute('savepoint unauthorized')
            try:
                execute('set local role authenticated')
                execute('select public.get_sales_report()')
                raise AssertionError('Missing user identity must be rejected')
            except psycopg.errors.InsufficientPrivilege:
                execute('rollback to savepoint unauthorized')
            print('PASS: snapshot counts, duplicate preservation, all columns, CSV escaping, Unicode, byte ranges, group 71, incomplete uploads, RPC authorization')
        finally:
            conn.rollback()
            print('Rolled back; source tables, jobs, Storage and cron were not changed')


if __name__ == '__main__':
    main()
