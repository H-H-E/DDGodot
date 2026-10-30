#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DD_ROOT="$PWD"
DD_TOOLS="$DD_ROOT/.tools/godot"
DD_DOWNLOADS="$DD_ROOT/.tools/downloads"
DD_DATA="${XDG_DATA_HOME:-$DD_ROOT/.tools/data}"
mkdir -p "$DD_TOOLS" "$DD_DOWNLOADS" "$DD_DATA/godot/export_templates/4.7.2.stable"
BASE='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable'
curl --fail --location --retry 3 "$BASE/Godot_v4.7.2-stable_linux.x86_64.zip" -o "$DD_DOWNLOADS/godot.zip"
curl --fail --location --retry 3 "$BASE/Godot_v4.7.2-stable_export_templates.tpz" -o "$DD_DOWNLOADS/templates.tpz"
python3 - "$DD_DOWNLOADS" "$DD_TOOLS" "$DD_DATA" <<'PY'
import hashlib, pathlib, sys, zipfile
downloads, tools, data = map(pathlib.Path, sys.argv[1:])
expected = {'godot.zip': 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4', 'templates.tpz': 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'}
for filename, checksum in expected.items():
    digest = hashlib.file_digest(open(downloads / filename, 'rb'), 'sha256').hexdigest()
    if digest != checksum: raise SystemExit(f'Checksum mismatch: {filename}; refusing to install')
with zipfile.ZipFile(downloads / 'godot.zip') as archive: archive.extractall(tools)
with zipfile.ZipFile(downloads / 'templates.tpz') as archive:
    for filename in ('web_nothreads_debug.zip', 'web_nothreads_release.zip'):
        (data / 'godot/export_templates/4.7.2.stable' / filename).write_bytes(archive.read('templates/' + filename))
binary = tools / 'Godot_v4.7.2-stable_linux.x86_64'
binary.chmod(0o755)
print(f'Godot installed: {binary}')
print(f'Export templates: {data}')
PY
