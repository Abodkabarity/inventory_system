"""Stream the actual checkpoint-prepared 2025 year and compare source totals.

Read-only. Requires the same environment as sales_report_2025_live_test. No
sales data is saved locally, and memory usage is independent of CSV file size.
"""
from __future__ import annotations

import codecs
import csv
import itertools
import json
import os
from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

import requests

from sales_report_server_cache_test import connect, raw_csv_month


def main():
    base = os.environ['SUPABASE_URL'].rstrip('/')
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    headers = {'apikey': key, 'Authorization': 'Bearer ' + key}
    columns = ['cash', 'online', 'insurance', 'total_sales', 'retail', 'sales_value']
    months = [f'{m:02d}/2025' for m in range(1, 13)]
    with connect() as conn:
        conn.execute('set transaction read only')
        conn.execute("set local statement_timeout='45s'")
        status, prepared, path, size, current = conn.execute("""select status,prepared_months,storage_path,byte_size,
            source_version=sales_report_private.monthly_version(months) from sales_report_private.jobs
            where scope_key='inventory' and report_kind='monthly' and months=%s""", (months,)).fetchone()
        assert status == 'ready' and prepared == 12 and current
        groups = dict(conn.execute('select upper(btrim(branch_name)),btrim(branch_group::text) from public.branches'))

        def display(name):
            name = (name or '').strip()
            return '71 ' + name if groups.get(name.upper()) == '71' and not name.startswith('71 ') else name

        expected = defaultdict(lambda: [0] + [Decimal(0)] * 6 + [0] * 6)
        fields = ','.join(['count(*)'] + [f'coalesce(sum({c}),0)' for c in columns] + [f'count({c})' for c in columns])
        for branch, month, *values in conn.execute(f"""select branch_name,month,{fields}
            from public.sales_history_2025 where month=any(%s) group by branch_name,month""", (months,)):
            target = expected[(display(branch), month)]
            for i, value in enumerate(values):
                target[i] += value
        signed = requests.post(base + '/storage/v1/object/sign/sales-report-exports/' + path,
            headers=headers, json={'expiresIn': 60}, timeout=30)
        assert signed.status_code == 200
        link = signed.json().get('signedURL') or signed.json().get('signedUrl')
        assert link
        url = link if link.startswith('http') else base + '/storage/v1' + link
        actual = defaultdict(lambda: [0] + [Decimal(0)] * 6 + [0] * 6)
        byte_count = 0
        with requests.get(url, timeout=90, stream=True) as response:
            assert response.status_code == 200

            def lines():
                nonlocal byte_count
                chunks = response.iter_content(chunk_size=65536)
                first = next(chunks)
                assert first.startswith(b'\xef\xbb\xbf')

                def counted():
                    nonlocal byte_count
                    for chunk in itertools.chain([first], chunks):
                        byte_count += len(chunk)
                        yield chunk

                pending = ''
                for text in codecs.iterdecode(counted(), 'utf-8-sig'):
                    pending += text
                    while '\n' in pending:
                        line, pending = pending.split('\n', 1)
                        yield line + '\n'
                if pending:
                    yield pending

            reader = csv.reader(lines())
            assert next(reader) == ['branch_name', 'item_code', 'item_name', 'month', *columns]
            for row in reader:
                row[3] = raw_csv_month(row[3])
                assert len(row) == 10 and row[3] in months
                target = actual[(row[0], row[3])]
                target[0] += 1
                for i, value in enumerate(row[4:]):
                    if value:
                        target[1 + i] += Decimal(value)
                        target[7 + i] += 1
        assert byte_count == size and dict(actual) == dict(expected)
        conn.rollback()
    Path('outputs/sales_report/archive_2025_annual_verification.json').write_text(json.dumps({
        'verified_at_utc': datetime.now(timezone.utc).isoformat(), 'prepared_months': prepared,
        'single_csv': True, 'source_counts_sums_and_nulls_by_branch_month': 'exact',
        'utf8_and_header': 'verified', 'byte_size': size, 'source_data_modified': False}, indent=2), encoding='utf-8')
    print('PASS complete 2025 CSV: twelve durable checkpoints, one file, exact source totals/nulls and streamed byte size', flush=True)


if __name__ == '__main__':
    main()
