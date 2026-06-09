# Serve a Flutter web build with cross-origin isolation headers (COOP/COEP)
# and the correct application/wasm mime, for local verification of the WASM build.
# Usage: python serve_web_isolated.py [port] [dir]
import sys, http.server, socketserver, os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8753
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.mjs': 'text/javascript',
                      '.js': 'text/javascript', '.json': 'application/json'}
    def __init__(self, *a, **k):
        super().__init__(*a, directory=DIRECTORY, **k)
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'cross-origin')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    print(f"Serving {DIRECTORY} on http://127.0.0.1:{PORT} (COOP/COEP isolated)")
    httpd.serve_forever()
