#!/usr/bin/env python3
"""Serve a Godot export with correct WASM MIME type; no cross-origin isolation needed."""
import argparse, http.server, functools, pathlib
p = argparse.ArgumentParser()
p.add_argument('--directory', default='build/web')
p.add_argument('--port', default=8060, type=int)
p.add_argument('--bind', default='127.0.0.1')
args = p.parse_args()
class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.js': 'application/javascript'}
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()
server = http.server.ThreadingHTTPServer((args.bind, args.port), functools.partial(Handler, directory=str(pathlib.Path(args.directory).resolve())))
print(f'Diagnostic Dash: http://{args.bind}:{args.port}', flush=True)
server.serve_forever()
