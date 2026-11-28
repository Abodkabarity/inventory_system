"""Pinned assets for the Max browser export tests (no external CDN)."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import shutil
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=8767)
args = parser.parse_args()
workers = Path(__file__).resolve().parents[1] / 'assets/workers'
flutter = Path(shutil.which('flutter') or 'C:/flutter/bin/flutter.bat').resolve().parent.parent
engine = flutter / 'bin/cache/flutter_web_sdk/canvaskit'

class Handler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = urllib.parse.urlparse(path).path
        root = engine if path.startswith('/canvaskit/') else workers
        relative = path[len('/canvaskit/'):] if path.startswith('/canvaskit/') else path.lstrip('/')
        target = (root / relative).resolve()
        return str(target if target.is_relative_to(root.resolve()) else workers / 'not-found')

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def log_message(self, *args):
        pass

print(f'Max test assets: http://127.0.0.1:{args.port}/', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
