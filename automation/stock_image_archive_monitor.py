"""Read-only loopback gateway for the image archive monitor.

Avoid file-preview/browser cross-origin network restrictions. No service keys,
worker controls, arbitrary proxy targets, or network-facing listening socket.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import threading
import time
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen
from stock_image_archive_eta import recent_estimate

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'https://rzvxjkbraufqbfhvftcy.supabase.co'
ENDPOINT = PROJECT + '/functions/v1/stock-image-archive'
PORT = 8769
HTML_FILE = ROOT / 'exports' / 'stock_image_archive_monitor.html'
CACHE = {}
LOCK = threading.Lock()

def read_page():
    html = HTML_FILE.read_text(encoding='utf-8')
    match = re.search(r"get\('token'\)\|\|'([^']+)'", html)
    if not match:
        raise RuntimeError('Monitor token is missing')
    token = match.group(1)
    html = html.replace("const endpoint='" + ENDPOINT + "';",
                        "const endpoint=location.origin+'/api';")
    return html.encode('utf-8'), token

def remote_state(token, search, offset):
    cache_key = (search, offset)
    with LOCK:
        entry = CACHE.get(cache_key)
        if entry and time.monotonic() - entry[0] < 5:
            return entry[1]
    query = urlencode({'token': token, 'q': search, 'offset': offset})
    req = Request(ENDPOINT + '?' + query, headers={'Accept': 'application/json'})
    with urlopen(req, timeout=25) as response:
        data = json.load(response)
    data['estimate'] = recent_estimate(
        ROOT / '.dart_tool' / 'stock_image_archive' / 'worker.log', data)
    for image in data.get('previews', []):
        url = image.get('url')
        if url:
            image['url'] = '/image?' + urlencode({'url': url})
    body = json.dumps(data).encode('utf-8')
    with LOCK:
        CACHE[cache_key] = (time.monotonic(), body)
        if len(CACHE) > 100:
            CACHE.pop(next(iter(CACHE)))
    return body

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log read capabilities or signed image URLs.

    def send(self, status, body, content_type):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy',
                         "default-src 'self'; script-src 'self' 'unsafe-inline'; "
                         "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
                         "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.headers.get('Host') not in (f'127.0.0.1:{PORT}', f'localhost:{PORT}'):
            return self.send(403, b'Forbidden host', 'text/plain')
        origin = self.headers.get('Origin')
        if origin and origin not in (f'http://127.0.0.1:{PORT}', f'http://localhost:{PORT}'):
            return self.send(403, b'Forbidden origin', 'text/plain')
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        try:
            if parsed.path == '/':
                return self.send(200, read_page()[0], 'text/html; charset=utf-8')
            if parsed.path == '/api':
                search = re.sub(r'[^A-Za-z0-9._-]', '', query.get('q', [''])[0])[:64]
                offset = min(20000, max(0, int(query.get('offset', ['0'])[0])))
                return self.send(200, remote_state(read_page()[1], search, offset), 'application/json')
            if parsed.path == '/image':
                raw = query.get('url', [''])[0]
                image = urlparse(raw)
                if image.scheme != 'https' or image.netloc != urlparse(PROJECT).netloc or not image.path.startswith('/storage/v1/object/sign/stock-product-images/'):
                    return self.send(403, b'Invalid image', 'text/plain')
                with urlopen(raw, timeout=20) as response:
                    content_type = response.headers.get('Content-Type', '')
                    if not content_type.startswith('image/'):
                        raise ValueError('Not an image')
                    body = response.read(15728641)
                if len(body) > 15728640:
                    raise ValueError('Image too large')
                return self.send(200, body, content_type)
            return self.send(404, b'Not found', 'text/plain')
        except Exception:
            return self.send(502, b'{"error":"Monitor gateway temporarily unavailable; retry shortly"}', 'application/json')

if __name__ == '__main__':
    read_page()
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
