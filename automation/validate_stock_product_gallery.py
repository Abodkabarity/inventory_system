"""Verify gallery signing/download/idempotency without printing credentials."""
import ast
import os
from pathlib import Path
import shutil
import subprocess
root=Path(__file__).resolve().parents[1]
env=os.environ.copy()
for node in ast.parse((root/'automation/main.py').read_text(encoding='utf-8-sig')).body:
    if isinstance(node,ast.Assign) and isinstance(node.value,ast.Constant):
        for target in node.targets:
            if isinstance(target,ast.Name) and target.id in ('SUPABASE_URL','SUPABASE_KEY'):
                env['SUPABASE_SERVICE_ROLE_KEY' if target.id=='SUPABASE_KEY' else target.id]=node.value.value
if env.get('SUPABASE_URL')!='https://rzvxjkbraufqbfhvftcy.supabase.co':
    raise SystemExit('Unexpected project')
subprocess.run([shutil.which('deno') or 'deno','run',
    '--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY',
    '--allow-net=rzvxjkbraufqbfhvftcy.supabase.co',
    str(root/'automation/validate_stock_product_gallery.ts')],env=env,cwd=root,check=True)
