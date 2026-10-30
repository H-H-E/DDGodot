#!/usr/bin/env python3
"""Create content-addressed offline caching and a portable verified web archive."""
import hashlib, json, pathlib, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'build' / 'web'
# Godot 4.7.2 requests Emscripten explicit-swap rendering. The emitted
# offscreen framebuffer blit produces INVALID_OPERATION in real WebKit 26.
# Use normal browser presentation; do not intercept GL calls or error logs.
# These version-specific, unique tokens are audited in WEB-COMPATIBILITY.md.
loader = out / 'index.js'
runtime = loader.read_text()
presentation_transforms = {
    'explicitSwapControl:HEAP8[attributes+25]': 'explicitSwapControl:false',
    'renderViaOffscreenBackBuffer:HEAP8[attributes+32]': 'renderViaOffscreenBackBuffer:false',
}
for original, replacement in presentation_transforms.items():
    if runtime.count(original) == 1:
        runtime = runtime.replace(original, replacement)
    elif runtime.count(original) != 0 or runtime.count(replacement) != 1:
        raise SystemExit('Unexpected Godot loader; re-audit browser presentation: ' + original)
loader.write_text(runtime)
files = sorted(p for p in out.iterdir() if p.is_file() and not p.name.endswith('.import') and p.name not in ('offline-worker.js', 'build-manifest.json'))
digest = hashlib.sha256(b''.join(hashlib.sha256(p.read_bytes()).digest() for p in files)).hexdigest()[:16]
assets = ['./'] + ['./' + p.name for p in files]
worker = """const CACHE='dd-%s';const ASSETS=%s;
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS))));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('dd-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{if(event.request.method!=='GET'||new URL(event.request.url).origin!==self.location.origin)return;event.respondWith(fetch(event.request).catch(()=>caches.match(event.request,{ignoreSearch:true})));});
""" % (digest, json.dumps(assets))
(out / 'offline-worker.js').write_text(worker)
manifest = {'engine': '4.7.2.stable', 'threads': False, 'renderer': 'Compatibility', 'runtime_presentation': 'browser implicit swap; Emscripten offscreen backbuffer disabled', 'build_id': digest, 'files': {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files}}
(out / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(root / 'dist').mkdir(exist_ok=True)
(root / 'dist' / '.gdignore').touch()
with zipfile.ZipFile(root / 'dist' / 'diagnostic-dash-web.zip', 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for p in sorted(out.iterdir()):
        if p.is_file() and not p.name.endswith('.import'): archive.write(p, p.name)
print(json.dumps({'build_id': digest, 'web_bytes': sum(p.stat().st_size for p in files), 'archive_bytes': (root / 'dist' / 'diagnostic-dash-web.zip').stat().st_size}))
