#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p build/web
touch build/.gdignore
"$GODOT_BIN" --headless --editor --import --quit
"$GODOT_BIN" --headless --export-release Web build/web/index.html
python3 tools/finalize_web.py
echo 'Web export ready: build/web/index.html'
