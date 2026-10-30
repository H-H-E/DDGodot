#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
DD_EXPORT_DATA_HOME="${DD_EXPORT_DATA_HOME:-${XDG_DATA_HOME:-}}"
DD_QA_TMP="$(mktemp -d)"
export XDG_DATA_HOME="$DD_QA_TMP/data"
export XDG_CONFIG_HOME="$DD_QA_TMP/config"
export XDG_CACHE_HOME="$DD_QA_TMP/cache"
mkdir -p evidence/runs
# Preserve installed templates when the caller uses a standard Godot install.
# Export before isolating native learner records; tests create their own stores.
unset XDG_DATA_HOME
if [[ -n "${DD_EXPORT_DATA_HOME:-}" ]]; then export XDG_DATA_HOME="$DD_EXPORT_DATA_HOME"; fi
bash tools/export_web.sh
export XDG_DATA_HOME="$DD_QA_TMP/data"
python3 tools/serve.py --port 8060 > "$DD_QA_TMP/server.log" 2>&1 &
DD_SERVER_PID=$!
trap 'kill "$DD_SERVER_PID" 2>/dev/null || true' EXIT
for pass in 1 2; do
  for suite in learning game session; do
    log="evidence/runs/native-${suite}-${pass}.log"
    "$GODOT_BIN" --headless --path . --script "tests/test_${suite}.gd" > "$log" 2>&1
    cat "$log"
    python3 - "$log" <<'PY'
import pathlib, re, sys
if re.search(r'SCRIPT ERROR|^ERROR:', pathlib.Path(sys.argv[1]).read_text(), re.M):
    raise SystemExit('Godot reported an engine/script error')
PY
  done
  python3 tools/autopilot_local.py --godot "$GODOT_BIN" --scenario goals --seed 73 --output "evidence/runs/autopilot-${pass}"
  if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a env DD_FIREFOX_HEADED=1 LIBGL_ALWAYS_SOFTWARE=1 node tests/browser.mjs --engines chromium,firefox,webkit --run-id "release-${pass}"
  else
    node tests/browser.mjs --engines chromium,firefox,webkit --run-id "release-${pass}"
  fi
done
echo 'Both complete verification passes finished. Inspect platform status in browser reports.'
