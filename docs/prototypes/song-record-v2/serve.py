"""Loopback-only preview; serves an exact allowlist, never the repository tree."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
ASSETS = {'/': ('index.html', 'text/html'), '/index.html': ('index.html', 'text/html'),
          '/preview.css': ('preview.css', 'text/css'), '/preview.js': ('preview.js', 'text/javascript'),
          '/coverage.md': ('coverage.md', 'text/plain')}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = ASSETS.get(urlsplit(self.path).path)
        if not route or not (ROOT / route[0]).is_file():
            self.send_error(404)
            return
        content = (ROOT / route[0]).read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', route[1] + '; charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data:; connect-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    print('UI preview: http://127.0.0.1:63142', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 63142), Handler).serve_forever()
