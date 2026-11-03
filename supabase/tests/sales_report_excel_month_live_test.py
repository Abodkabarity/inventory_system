"""Verify actual monthly CSV display expressions and unchanged source cells.

Requires the database and Storage environment used by the other live report
checks. Sales stay in memory; this does not modify source data or report jobs.
"""
from __future__ import annotations

import csv
import io
import json
import os
import time
from collections import Counter
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

import requests

from sales_report_server_cache_test import connect


def main():
    base = os.environ['SUPABASE_URL'].rstrip('/')
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    headers = {'apikey': key, 'Authorization': 'Bearer ' + key}
    samples = json.loads(Path('outputs/sales_report/excel_month_samples.json').read_text(encoding='utf-8'))
    evidence = []
    with connect() as conn:
        conn.autocommit = True
        groups = dict(conn.execute('select upper(btrim(branch_name)),btrim(branch_group::text) from public.branches'))

        def display(name):
            name = (name or '').strip()
            return '71 ' + name if groups.get(name.upper()) == '71' and not name.startswith('71 ') else name

        for sample in samples:
            deadline = time.monotonic() + 120
            while True:
                status, path, size, branches, current = conn.execute("""select status,storage_path,byte_size,branch_names,
                    source_version=sales_report_private.monthly_version(months) from sales_report_private.jobs where id=%s""", (sample['job_id'],)).fetchone()
                if status == 'ready' and current:
                    break
                assert time.monotonic() < deadline and status != 'failed', 'Formatted cache did not become ready'
                time.sleep(2)
            expected = Counter()
            for table, year in (('sales_history_2025', '2025'), ('sales_history', '2026')):
                for row in conn.execute(f"""select branch_name,item_code,item_name,month,cash,online,insurance,total_sales,retail,sales_value
                    from public.{table} where month=any(%s) and right(month,4)=%s
                    and (%s::text[] is null or btrim(branch_name)=any(%s))""", (sample['months'], year, branches, branches)):
                    expected[(display(row[0]), row[1] or '', row[2] or '', row[3], *row[4:])] += 1
            signed = requests.post(base + '/storage/v1/object/sign/sales-report-exports/' + path,
                headers=headers, json={'expiresIn': 60}, timeout=30)
            assert signed.status_code == 200
            link = signed.json().get('signedURL') or signed.json().get('signedUrl')
            assert link
            downloaded = requests.get(link if link.startswith('http') else base + '/storage/v1' + link, timeout=90)
            assert downloaded.status_code == 200 and len(downloaded.content) == size
            assert downloaded.content.startswith(b'\xef\xbb\xbf')
            reader = csv.reader(io.StringIO(downloaded.content.decode('utf-8-sig'), newline=''))
            assert next(reader) == ['branch_name', 'item_code', 'item_name', 'month', 'cash', 'online', 'insurance', 'total_sales', 'retail', 'sales_value']
            actual = Counter()
            for row in reader:
                assert len(row) == 10 and row[3] in {f'="{month}"' for month in sample['months']}
                month = row[3][2:-1]
                actual[(row[0], row[1], row[2], month, *(None if v == '' else Decimal(v) for v in row[4:]))] += 1
            assert actual == expected
            evidence.append({'scope': sample['scope'], 'month_display': 'MM/YYYY', 'other_source_cells': 'exact', 'duplicates': 'preserved'})
            print('PASS formatted monthly CSV:', sample['scope'], '06/2025 and 06/2026; all other cells match source', flush=True)
        baseline = json.loads(Path('outputs/sales_report/excel_month_daily_baseline.json').read_text(encoding='utf-8'))
        current_daily = {str(job): (str(generation), path, status) for job, generation, path, status in conn.execute(
            "select id,generation,storage_path,status from sales_report_private.jobs where report_kind='daily45'")}
        assert all(current_daily.get(job) == (generation, path, 'ready') for job, generation, path in baseline)
    Path('outputs/sales_report/excel_month_verification.json').write_text(json.dumps({
        'verified_at_utc': datetime.now(timezone.utc).isoformat(), 'reports': evidence,
        'actual_excel_fixture_display': ['06/2025', '01/2027'], 'daily_files': 'unchanged', 'source_data_modified': False}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
