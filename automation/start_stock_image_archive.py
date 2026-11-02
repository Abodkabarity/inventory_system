"""Launch the image worker using existing local automation credentials.

Read assignments using AST; never import or execute the ERP automation module.
The service credential is passed through the child environment, never URLs,
arguments, logs, monitor files, or source files created for this feature.
"""
import ast
import os
from pathlib import Path
import shutil
import subprocess
import msvcrt

ROOT = Path(__file__).resolve().parents[1]

def main():
    runtime = ROOT / '.dart_tool' / 'stock_image_archive'
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'worker.lock').open('a+b') as lock:
        lock.seek(0)
        if not lock.read(1):
            lock.write(b'0')
            lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise SystemExit('Image archive worker is already running')
        credentials = {}
        tree = ast.parse((ROOT / 'automation' / 'main.py').read_text(encoding='utf-8-sig'))
        for node in tree.body:
            if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant):
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id in ('SUPABASE_URL', 'SUPABASE_KEY'):
                        credentials[target.id] = node.value.value
        endpoint = credentials.get('SUPABASE_URL', '')
        if endpoint != 'https://rzvxjkbraufqbfhvftcy.supabase.co':
            raise SystemExit('Unexpected Supabase project')
        env = os.environ.copy()
        env['SUPABASE_URL'] = endpoint
        env['SUPABASE_SERVICE_ROLE_KEY'] = credentials['SUPABASE_KEY']
        command = [shutil.which('deno') or 'deno', 'run',
                   '--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY',
                   '--allow-net=rzvxjkbraufqbfhvftcy.supabase.co,alainpharmacy.ae,alainpharmacy-ae.gumlet.io',
                   str(ROOT / 'automation' / 'stock_image_archive_worker.ts')]
        with (runtime / 'worker.log').open('a', encoding='utf-8') as log:
            subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=log, check=True)

if __name__ == '__main__':
    main()
