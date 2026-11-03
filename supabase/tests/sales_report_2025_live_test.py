"""Compare real mixed-year CSV files with their authoritative read-only sources.

Uses the same environment as sales_report_current_month_live_test. Sales remain
in memory; only summary evidence is saved. No source data or report jobs change.
"""
from __future__ import annotations

import csv
import io
import json
import os
from collections import Counter
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

import requests

from sales_report_server_cache_test import connect, raw_csv_month


def main():
    base = os.environ['SUPABASE_URL'].rstrip('/')
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    headers = {'apikey': key, 'Authorization': 'Bearer ' + key}
    samples = json.loads(Path('outputs/sales_report/archive_2025_samples.json').read_text(encoding='utf-8'))
    baseline = json.loads(Path('outputs/sales_report/archive_2025_baseline.json').read_text(encoding='utf-8'))
    assert len(samples) == 3
    evidence = []
    with connect() as conn:
        conn.execute('set transaction read only')
        conn.execute("set local statement_timeout='45s'")
        groups = dict(conn.execute('select upper(btrim(branch_name)),btrim(branch_group::text) from public.branches'))

        def display(name):
            name = (name or '').strip()
            return '71 ' + name if groups.get(name.upper()) == '71' and not name.startswith('71 ') else name

        for sample in samples:
            path, size, branches, ready = conn.execute("""select storage_path,byte_size,branch_names,
                status='ready' and source_version=sales_report_private.monthly_version(months)
                from sales_report_private.jobs where id=%s""", (sample['job_id'],)).fetchone()
            assert ready and path, 'Mixed-year file is not ready yet'
            expected = Counter()
            for table, archive in (('sales_history_2025', True), ('sales_history', False)):
                months = [m for m in sample['months'] if m.endswith('/2025') == archive]
                assert months
                for row in conn.execute(f"""select branch_name,item_code,item_name,month,cash,online,insurance,
                    total_sales,retail,sales_value from public.{table} where month=any(%s)
                    and (%s::text[] is null or btrim(branch_name)=any(%s))""", (months, branches, branches)):
                    expected[(display(row[0]), row[1] or '', row[2] or '', row[3], *row[4:])] += 1
            signed = requests.post(base + '/storage/v1/object/sign/sales-report-exports/' + path,
                headers=headers, json={'expiresIn': 60}, timeout=30)
            assert signed.status_code == 200
            link = signed.json().get('signedURL') or signed.json().get('signedUrl')
            assert link
            downloaded = requests.get(link if link.startswith('http') else base + '/storage/v1' + link, timeout=90)
            assert downloaded.status_code == 200
            raw = downloaded.content
            assert len(raw) == size and raw.startswith(b'\xef\xbb\xbf')
            reader = csv.reader(io.StringIO(raw.decode('utf-8-sig'), newline=''))
            assert next(reader) == ['branch_name', 'item_code', 'item_name', 'month', 'cash', 'online',
                'insurance', 'total_sales', 'retail', 'sales_value']
            actual = Counter()
            for row in reader:
                row[3] = raw_csv_month(row[3])
                assert len(row) == 10 and row[3] in sample['months']
                actual[(*row[:4], *(None if v == '' else Decimal(v) for v in row[4:]))] += 1
            assert actual == expected, 'Source rows, duplicates, values or zone scope differ'
            evidence.append({'scope': sample['scope_kind'], 'months': sample['months'],
                'all_source_cells_and_duplicates': 'exact', 'branch_group_71': 'verified', 'single_csv': True})
            print('PASS actual mixed-year file:', sample['scope_kind'], sample['months'], flush=True)
        current_jobs = {str(job): (str(generation), path, status) for job, generation, path, status in conn.execute(
            'select id,generation,storage_path,status from sales_report_private.jobs')}
        for job, generation, path in baseline['jobs']:
            assert current_jobs.get(job) == (generation, path, 'ready')
        policies = [list(row) for row in conn.execute("""select policyname,roles::text,cmd,qual,with_check
            from pg_policies where schemaname='public' and tablename='sales_history_2025' order by policyname""")]
        assert policies == baseline['archive_policies']
        print('PASS existing 2026/daily files and archive RLS policies remain unchanged', flush=True)
        conn.rollback()
    Path('outputs/sales_report/archive_2025_verification.json').write_text(json.dumps({
        'verified_at_utc': datetime.now(timezone.utc).isoformat(), 'reports': evidence,
        'existing_ready_files': 'unchanged', 'archive_rls': 'unchanged', 'source_data_modified': False}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
