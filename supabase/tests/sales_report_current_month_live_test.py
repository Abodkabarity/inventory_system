"""Read-only source comparison of actual server-prepared combined CSV files.

Requires SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and the database environment
used by sales_report_server_cache_test. No source rows or report jobs are written.
Only summary verification evidence is saved; downloaded sales stay in memory.
"""
from __future__ import annotations

import csv
import io
import json
import os
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

import requests

from sales_report_server_cache_test import connect, raw_csv_month


def main():
    base = os.environ['SUPABASE_URL'].rstrip('/')
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    headers = {'apikey': key, 'Authorization': 'Bearer ' + key}
    evidence = []
    with connect() as conn:
        conn.execute('set transaction read only')
        conn.execute("set local statement_timeout='45s'")
        current, previous, first, last = conn.execute("""select
            to_char(statement_timestamp() at time zone 'Asia/Dubai','MM/YYYY'),
            to_char((statement_timestamp() at time zone 'Asia/Dubai')-interval '1 month','MM/YYYY'),
            date_trunc('month',statement_timestamp() at time zone 'Asia/Dubai')::date,
            sales_report_private.daily_expected_day()""").fetchone()
        assert conn.execute('select sales_report_private.daily_fresh()').fetchone()[0]
        jobs = conn.execute("""select scope_key,branch_names,storage_path,byte_size
            from sales_report_private.jobs where report_kind='monthly' and status='ready'
            and source_version=sales_report_private.monthly_version(months) and months=%s
            order by (scope_key='inventory') desc,byte_size limit 3""", ([previous, current],)).fetchall()
        assert len(jobs) == 3 and jobs[0][0] == 'inventory'
        groups = dict(conn.execute('select upper(btrim(branch_name)),btrim(branch_group::text) from public.branches'))

        def display(name):
            name = (name or '').strip()
            return '71 ' + name if groups.get(name.upper()) == '71' and not name.startswith('71 ') else name

        def numeric(value):
            return None if value is None or value == '' else Decimal(value)

        for scope, branches, path, size in jobs:
            historical = Counter()
            for row in conn.execute("""select branch_name,item_code,item_name,month,
                cash,online,insurance,total_sales,retail,sales_value from public.sales_history
                where month=%s and (%s::text[] is null or btrim(branch_name)=any(%s))""", (previous, branches, branches)):
                historical[(display(row[0]), row[1] or '', row[2] or '', row[3], *row[4:])] += 1
            totals = defaultdict(lambda: [Decimal(0), Decimal(0), Decimal(0), Decimal(0)])
            names = defaultdict(set)
            for branch, code, name, qty, invoice, sales in conn.execute("""select branch_name,item_code,item_name,qty,inv_type,sales_type
                from public.sales_last_45_days where inv_date between %s and %s
                and (%s::text[] is null or btrim(branch_name)=any(%s))""", (first, last, branches, branches)):
                group = (display(branch), code or '')
                qty = qty or Decimal(0)
                invoice = re.sub(r'\s+', ' ', (invoice or '').strip()).lower()
                sales = (sales or '').strip().lower()
                channel = 2 if invoice in ('insurance', 'direct insurance', 'dirict insurance') else (
                    1 if sales in ('delivery invoice', 'return delivery invoice') else 0)
                totals[group][channel] += qty
                totals[group][3] += qty
                names[group].add(name or '')
            signed = requests.post(base + '/storage/v1/object/sign/sales-report-exports/' + path,
                headers=headers, json={'expiresIn': 60}, timeout=30)
            assert signed.status_code == 200
            link = signed.json().get('signedURL') or signed.json().get('signedUrl')
            assert link
            url = link if link.startswith('http') else base + '/storage/v1' + link
            downloaded = requests.get(url, timeout=90)
            assert downloaded.status_code == 200
            raw = downloaded.content
            assert len(raw) == size and raw.startswith(b'\xef\xbb\xbf')
            reader = csv.reader(io.StringIO(raw.decode('utf-8-sig'), newline=''))
            assert next(reader) == ['branch_name', 'item_code', 'item_name', 'month', 'cash', 'online',
                'insurance', 'total_sales', 'retail', 'sales_value']
            seen_history = Counter()
            seen_current = set()
            for row in reader:
                row[3] = raw_csv_month(row[3])
                assert len(row) == 10
                if row[3] == previous:
                    seen_history[(*row[:4], *map(numeric, row[4:]))] += 1
                else:
                    assert row[3] == current
                    group = (row[0], row[1])
                    assert group not in seen_current and group in totals
                    seen_current.add(group)
                    assert row[2] in names[group]
                    assert list(map(numeric, row[4:8])) == totals[group]
                    assert row[8:] == ['', '']
            assert seen_history == historical and seen_current == set(totals)
            evidence.append({'scope': 'inventory' if branches is None else 'zone',
                'months': [previous, current], 'current_month_through': str(last),
                'historical_rows_and_duplicates': 'unchanged', 'current_month_channels_and_returns': 'exact',
                'current_month_prices': 'empty', 'branch_group_71': 'verified', 'single_csv': True})
            print('PASS live combined CSV:', evidence[-1]['scope'], previous, '+', current, flush=True)
        baseline = Path('outputs/sales_report/current_month_cache_baseline.json')
        if baseline.exists():
            for job_id, generation, path in json.loads(baseline.read_text(encoding='utf-8')):
                job = conn.execute('select generation,storage_path,status from sales_report_private.jobs where id=%s', (job_id,)).fetchone()
                assert job and str(job[0]) == generation and job[1] == path and job[2] == 'ready'
            print('PASS existing historical caches retain their generations and files', flush=True)
        conn.rollback()
    Path('outputs/sales_report/current_month_verification.json').write_text(json.dumps({
        'verified_at_utc': datetime.now(timezone.utc).isoformat(), 'reports': evidence,
        'existing_historical_files': 'unchanged', 'source_data_modified': False}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
