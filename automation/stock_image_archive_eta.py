"""Estimate remaining active runtime from recent completed worker batches."""
from datetime import datetime, timezone
import json
import math
from pathlib import Path

WINDOW_SECONDS = 15 * 60
MAX_GAP_SECONDS = 180

def timestamp(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()
    except (ValueError, TypeError):
        return None

def estimate_from_lines(lines, progress, job, now):
    remaining = max(0, int(progress['total']) - int(progress['processed']))
    if job.get('status') == 'complete':
        return {'state': 'complete', 'minutes': 0}
    if job.get('status') == 'paused':
        return {'state': 'paused', 'minutes': None}
    heartbeat = timestamp(job.get('heartbeat_at'))
    next_run = timestamp(job.get('next_run_at'))
    if next_run and next_run > now:
        return {'state': 'waiting', 'minutes': None}
    if heartbeat is None or now - heartbeat > MAX_GAP_SECONDS:
        return {'state': 'inactive', 'minutes': None}
    samples = []
    for line in lines:
        try:
            date, body = line.split(' ', 1)
            moment = timestamp(date)
            row = json.loads(body)
            # busy/error log lines do not represent completed batches.
            if moment is None or 'total' not in row or 'processed' not in row:
                continue
            if moment > now or moment < now - WINDOW_SECONDS:
                continue
            count = int(row['processed'])
            if row['total'] != progress['total'] or count > progress['processed']:
                continue
            if samples and (moment - samples[-1][0] > MAX_GAP_SECONDS or
                            moment <= samples[-1][0] or count < samples[-1][1]):
                samples = []
            samples.append((moment, count))
        except (ValueError, TypeError, KeyError):
            continue
    if len(samples) < 2 or now - samples[-1][0] > MAX_GAP_SECONDS:
        return {'state': 'measuring', 'minutes': None}
    elapsed = samples[-1][0] - samples[0][0]
    completed = samples[-1][1] - samples[0][1]
    if elapsed < 60 or completed < 10:
        return {'state': 'measuring', 'minutes': None}
    rate = completed * 60 / elapsed
    return {
        'state': 'estimated',
        'minutes': math.ceil(remaining / rate),
        'products_per_minute': round(rate, 2),
        'sample_seconds': round(elapsed),
        'sample_products': completed,
    }

def recent_estimate(log: Path, data):
    try:
        with log.open('rb') as stream:
            stream.seek(0, 2)
            size = stream.tell()
            stream.seek(max(0, size - 262144))
            lines = stream.read().decode('utf-8', errors='replace').splitlines()
    except OSError:
        lines = []
    now = timestamp(data.get('server_time'))
    if now is None:
        now = datetime.now(timezone.utc).timestamp()
    return estimate_from_lines(lines, data['progress'], data['job'], now)
