#!/usr/bin/env python3
"""Exercise the real upstream Autopilot Godot bridge without inference services.

This is a deterministic local driver, NOT an Aura/Jev autonomous-model run.
Only loopback traffic is used. Run with --help for reproducible commands.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import tempfile
import threading
import time
import traceback

from websockets.sync.server import serve


ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "1818cc337b20762cd50102bc774a8e45eb7c4dc7"


def source_fingerprint():
    paths = [ROOT / "project.godot", ROOT / "export_presets.cfg", ROOT / "tools/autopilot_local.py", ROOT / "tools/autopilot_bootstrap.gd"]
    paths += list((ROOT / "scripts").glob("*.gd")) + list((ROOT / "scenes").glob("*.tscn"))
    paths += [path for path in (ROOT / "assets").rglob("*") if path.suffix in (".ttf", ".otf", ".svg", ".png", ".gdshader")]
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths) if path.is_file()}


class BridgeError(RuntimeError):
    def __init__(self, frame):
        self.frame = frame
        super().__init__(f"{frame.get('status')}: {frame.get('error')}")


class LocalBridge:
    """Small protocol-1 server. It never imports Autopilot's paid model runtime."""

    def __init__(self, trace: Path):
        self.ready = threading.Event()
        self.hello = None
        self.ws = None
        self.pending = {}
        self.events = []
        self.sequence = 0
        self.lock = threading.Lock()
        self.trace_file = gzip.open(trace, "wt", encoding="utf-8", compresslevel=9)
        self.started = time.monotonic()
        self.server = serve(self.handle, "127.0.0.1", 0, max_size=16 * 1024 * 1024)
        self.port = self.server.socket.getsockname()[1]
        self.url = f"ws://127.0.0.1:{self.port}/v1/bridge"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def record(self, direction, frame):
        with self.lock:
            self.trace_file.write(json.dumps({"elapsed": round(time.monotonic() - self.started, 4),
                                              "direction": direction, "frame": frame}) + "\n")
            self.trace_file.flush()

    def send(self, frame):
        self.record("to_game", frame)
        self.ws.send(json.dumps(frame))

    def handle(self, ws):
        if self.ws is not None:
            ws.close(1008, "Only the launched game may connect")
            return
        try:
            hello = json.loads(ws.recv(timeout=20))
            self.record("from_game", hello)
            if hello.get("type") != "hello" or hello.get("protocol") != 1:
                ws.close(1002, "Expected protocol-1 hello")
                return
            self.ws, self.hello = ws, hello
            self.send({"type": "welcome", "role": "cli", "session": "ddgodot-local-driver", "features": []})
            self.ready.set()
            for message in ws:
                frame = json.loads(message)
                self.record("from_game", frame)
                if frame.get("type") == "response":
                    receiver = self.pending.get(frame.get("id"))
                    if receiver:
                        receiver.put(frame)
                elif frame.get("type") == "events":
                    self.events.extend(frame.get("events", []))
        except Exception as exc:
            for receiver in list(self.pending.values()):
                receiver.put({"ok": False, "status": 503, "error": str(exc)})

    def request(self, op, args=None, timeout=10):
        self.sequence += 1
        identity = self.sequence
        receiver = queue.Queue()
        self.pending[identity] = receiver
        try:
            self.send({"type": "request", "id": identity, "op": op, "args": args or {}})
            frame = receiver.get(timeout=timeout)
            if not frame.get("ok"):
                raise BridgeError(frame)
            return frame.get("result")
        finally:
            self.pending.pop(identity, None)

    def close(self):
        if self.ws:
            self.ws.close()
        self.server.shutdown()
        self.thread.join(timeout=5)
        self.trace_file.close()


class Checks:
    def __init__(self):
        self.results = []

    def check(self, name, ok, detail=None):
        result = {"name": name, "passed": bool(ok)}
        if detail is not None:
            result["detail"] = compact_detail(detail) if ok else detail
        self.results.append(result)
        print(f"{'PASS' if ok else 'FAIL'} {name}", flush=True)
        if not ok:
            raise AssertionError(f"{name}: {detail}")


def compact_detail(value):
    """The compressed wire trace retains full states; keep summaries reviewable."""
    if isinstance(value, dict):
        return {key: (len(item) if key in ("controls", "facts") else compact_detail(item))
                for key, item in value.items() if key != "result"}
    if isinstance(value, list):
        if value and isinstance(value[0], dict) and "id" in value[0]:
            return [item.get("id") for item in value]
        return [compact_detail(item) for item in value]
    return value


def call(bridge, function, parameters=None, object_path="/root/Main"):
    result = bridge.request("rc", {"verb": "call", "body": {
        "objectPath": object_path, "functionName": function, "parameters": parameters or {}}})
    return result["ReturnValue"]


def snapshot(bridge):
    return call(bridge, "get_snapshot")


def key(bridge, name):
    # Upstream keeps a key down 0.05 seconds AND two frames. Sequential typing
    # therefore waits for release to avoid synthetic repeat-dependent behavior.
    bridge.request("key", {"key": name, "mode": "press"})
    time.sleep(0.07)


def answer(bridge, value):
    digits = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
    current = str(snapshot(bridge).get("input", ""))
    for _ in current:
        key(bridge, "BackSpace")
    for digit in str(int(value)):
        key(bridge, digits[int(digit)] if digit.isdigit() else "Minus")
    key(bridge, "Enter")


def button(bridge, name):
    elements = bridge.request("ui")["elements"]
    matches = [item for item in elements if item["id"].split(".")[-1] == name]
    if len(matches) != 1:
        raise AssertionError(f"Expected one visible {name}, got {matches}; controls={[e['id'] for e in elements]}")
    result = bridge.request("ui_act", {"id": matches[0]["id"], "action": "click"})
    time.sleep(0.08)
    return result


def select(bridge, name, index):
    elements = bridge.request("ui")["elements"]
    item = next(item for item in elements if item["id"].split(".")[-1] == name)
    bridge.request("ui_act", {"id": item["id"], "action": "click", "option": item["options"][index]})
    time.sleep(0.05)


def until(probe, timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = probe()
        if value:
            return value
        time.sleep(0.05)
    raise TimeoutError("Expected game state was not reached")


def verify_vendor(checks):
    folder = ROOT / "addons/autopilot"
    manifest = json.loads((folder / "UPSTREAM.json").read_text())
    changed = [name for name, digest in manifest["files"].items()
               if not (folder / name).is_file() or hashlib.sha256((folder / name).read_bytes()).hexdigest() != digest]
    checks.check("actual upstream addon, pinned revision, unchanged files",
                 manifest["commit"] == UPSTREAM and not changed,
                 {"commit": manifest["commit"], "files": len(manifest["files"]), "changed": changed})


def bridge_checks(bridge, checks):
    hello = bridge.hello
    checks.check("actual Godot addon handshake", hello.get("engine") == "godot" and hello.get("host") == "game", hello)
    checks.check("upstream data sharing explicitly disabled", hello.get("share") is False)
    checks.check("Godot 4.7 runtime", str(hello.get("engine_version", "")).startswith("4.7"), hello.get("engine_version"))
    context = bridge.request("context")
    checks.check("real main scene available through instrumentation", context.get("world") == "/root/Main", context)
    screen = bridge.request("screen")
    checks.check("upstream screen reader sees actual game UI", len(screen.get("texts", {})) > 0, screen)
    elements = bridge.request("ui")["elements"]
    checks.check("upstream UI enumeration sees actual controls", len(elements) >= 3, elements)
    before = bridge.request("ping")["game_time"]
    time.sleep(0.16)
    after = bridge.request("ping")["game_time"]
    checks.check("runtime clock advances while running", after > before, {"before": before, "after": after})
    bridge.request("pause", {"paused": True})
    paused = bridge.request("ping")["game_time"]
    time.sleep(0.2)
    paused_after = bridge.request("ping")["game_time"]
    checks.check("native pause freezes upstream active game clock", abs(paused_after - paused) < 0.015,
                 {"before": paused, "after": paused_after})
    bridge.request("pause", {"paused": False})
    try:
        bridge.request("ddgodot_unknown_operation")
        checks.check("invalid protocol operation fails visibly", False)
    except BridgeError as exc:
        checks.check("invalid protocol operation fails visibly", exc.frame.get("status") == 400)
    try:
        bridge.request("capture", {})
        checks.check("headless capture reports no picture", False)
    except BridgeError as exc:
        checks.check("headless capture reports no picture", exc.frame.get("status") == 409)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="Godot 4.7.2 executable")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/autopilot")
    parser.add_argument("--scenario", choices=["bridge", "goals"], default="bridge")
    parser.add_argument("--seed", type=int, default=73, help="Reproducible arithmetic/course seed")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    checks = Checks()
    bridge = None
    game = None
    game_log = None
    started = time.monotonic()
    source_before = source_fingerprint()
    error = None
    with tempfile.TemporaryDirectory(prefix="ddgodot-autopilot-") as state_dir:
        try:
            verify_vendor(checks)
            executable = shutil.which(args.godot) or (args.godot if Path(args.godot).is_file() else None)
            if not executable:
                raise RuntimeError("Godot not found; pass --godot /path/to/Godot_v4.7.2-stable")
            bridge = LocalBridge(args.output / "trace.jsonl.gz")
            game_log = (args.output / "godot.log").open("w", encoding="utf-8")
            command = [executable, "--headless", "--path", str(ROOT), "--script", "res://tools/autopilot_bootstrap.gd",
                       "--", f"--playtest-url={bridge.url}", "--playtest-share=0", "--playtest-connect-timeout=20",
                       f"--dd-seed={args.seed}"]
            game = subprocess.Popen(command, stdout=game_log, stderr=subprocess.STDOUT,
                                    env={**os.environ, "XDG_DATA_HOME": state_dir, "GODOT_SILENCE_ROOT_WARNING": "1"})
            if not bridge.ready.wait(25):
                raise RuntimeError("Godot did not connect to local instrumentation; inspect godot.log")
            bridge_checks(bridge, checks)
            if args.scenario == "goals":
                gameplay_checks(bridge, checks, args.seed)
            errors = [event for event in bridge.events if event.get("kind") == "finding"
                      and (event.get("finding") or {}).get("severity") in ("error", "critical", "fatal")]
            checks.check("no error findings from upstream runtime detectors", not errors, errors)
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"
            if not checks.results or checks.results[-1]["passed"]:
                checks.results.append({"name": "driver completed", "passed": False, "detail": error})
            traceback.print_exc()
        finally:
            if game:
                game.terminate()
                try:
                    game.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    game.kill()
                    game.wait(timeout=5)
            if bridge:
                bridge.close()
            if game_log:
                game_log.close()
    log_path = args.output / "godot.log"
    if log_path.exists():
        log_text = log_path.read_text(errors="replace")
        runtime_errors = [line for line in log_text.splitlines() if re.search(r"(?:SCRIPT ERROR|ERROR):", line)]
        checks.results.append({"name": "Godot output contains no engine or script errors", "passed": not runtime_errors,
                               "detail": runtime_errors})
        if runtime_errors and error is None:
            error = "Godot emitted runtime errors; inspect godot.log"
    source_after = source_fingerprint()
    source_unchanged = source_before == source_after
    checks.results.append({"name": "executed project source remains unchanged throughout run",
                           "passed": source_unchanged,
                           "detail": [name for name in sorted(set(source_before) | set(source_after))
                                      if source_before.get(name) != source_after.get(name)]})
    if not source_unchanged and error is None:
        error = "Project source changed during execution; rerun against a frozen build"
    passed = sum(item["passed"] for item in checks.results)
    report = {"runner": "DDGodot deterministic local driver using upstream Autopilot instrumentation",
              "not_a_model_inference_run": True, "paid_services_used": [], "upstream_commit": UPSTREAM,
              "scenario": args.scenario, "seed": args.seed, "elapsed_seconds": round(time.monotonic() - started, 3),
              "source_hashes": source_before, "source_unchanged_during_run": source_unchanged,
              "passed": passed, "total": len(checks.results), "checks": checks.results, "error": error}
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{passed}/{len(checks.results)} checks passed; report: {args.output / 'report.json'}")
    return 0 if error is None and passed == len(checks.results) else 1


def gameplay_checks(bridge, checks, seed):
    """The game's explicit playable-goal contract. Implemented with UI and keys."""
    state = snapshot(bridge)
    checks.check("game exposes a read-only test snapshot", isinstance(state, dict) and state.get("screen") == "menu", state)
    cases = [("practice", "addition", 0), ("classic", "subtraction", 1),
             ("cadence", "multiplication", 2), ("practice", "division", 3), ("practice", "mixed", 4)]
    for mode, operation, operation_index in cases:
        label = f"{mode}/{operation}"
        make_mistake = operation == "addition"
        wait_for_timeout = mode == "classic"
        button(bridge, "Play")
        until(lambda: snapshot(bridge).get("screen") == "modes")
        button(bridge, mode.title())
        until(lambda: snapshot(bridge).get("screen") == "setup")
        select(bridge, "Operation", operation_index)
        select(bridge, "SessionLength", 0)
        if mode != "practice":
            select(bridge, "Pace", 2 if wait_for_timeout else 0)
        button(bridge, "StartRun")
        state = until(lambda: (s if (s := snapshot(bridge)).get("screen") == "playing" else None))
        checks.check(f"{label}: starts from real menu controls", state.get("mode") == mode
                     and state.get("operation") == operation, state)
        checks.check(f"{label}: configured seed is used", state.get("seed") == seed, state.get("seed"))
        target = int(state["target"])
        checks.check(f"{label}: playable nonempty session target", target == 6, target)

        # Pause through the player's control, then exercise the actual key path.
        button(bridge, "Pause")
        before = until(lambda: (s if (s := snapshot(bridge)).get("paused") else None))
        key(bridge, "Nine")
        time.sleep(0.18)
        during = snapshot(bridge)
        checks.check(f"{label}: pause excludes answer input and active time",
                     during.get("input") == before.get("input")
                     and during.get("completed") == before.get("completed")
                     and abs(float(during["elapsed"]) - float(before["elapsed"])) < 0.04,
                     {"before": before, "during": during})
        button(bridge, "Resume")
        until(lambda: snapshot(bridge).get("screen") == "playing")

        # A deliberate mistake must not complete a gate. Hint marks assisted work.
        if make_mistake:
            before = snapshot(bridge)
            key(bridge, "SpaceBar")
            jumped = snapshot(bridge)
            checks.check("manual jump responds to real keyboard input", jumped["course"]["jumps"] > before["course"]["jumps"]
                         and jumped["course"]["y"] < before["course"]["y"], jumped["course"])
            question = before["question"]
            answer(bridge, int(question["answer"]) + 1)
            after = snapshot(bridge)
            checks.check("practice: wrong answer does not clear gate", after["completed"] == before["completed"], after)
            button(bridge, "Hint")
            checks.check("practice: hint preserves question", snapshot(bridge)["question"]["key"] == question["key"])
        if wait_for_timeout:
            before = snapshot(bridge)
            timed_out = until(lambda: (s if (s := snapshot(bridge)).get("timed_out") else None), timeout=10)
            checks.check("classic: real deadline records timeout without auto-completing gate",
                         timed_out["completed"] == before["completed"] and timed_out["stats"]["timeouts"] == 1, timed_out)

        wall_deadline = time.monotonic() + 180
        submitted = 0
        while True:
            state = snapshot(bridge)
            if state.get("gate_solved") and state.get("screen") == "playing":
                state = until(lambda: (s if ((s := snapshot(bridge)).get("screen") == "results"
                                            or not s.get("gate_solved")) else None), timeout=5)
            if state.get("screen") == "results":
                break
            if time.monotonic() >= wall_deadline:
                raise TimeoutError(f"{label}: goal session did not finish")
            if state.get("screen") != "playing":
                raise AssertionError(f"{label}: unexpected screen {state.get('screen')}")
            completed = int(state["completed"])
            answer(bridge, state["question"]["answer"])
            submitted += 1
            until(lambda: (s if ((s := snapshot(bridge)).get("screen") == "results"
                                 or int(s.get("completed", 0)) > completed) else None), timeout=20)
            if submitted == 1:
                key(bridge, "Enter")
                checks.check(f"{label}: rapid repeat submit cannot count the same gate twice",
                             snapshot(bridge)["completed"] == completed + 1)
        checks.check(f"{label}: full goal reached by typed answers", int(state["completed"]) == target,
                     {"completed": state["completed"], "target": target, "typed_correct_answers": submitted,
                      "stats": state.get("stats")})
        stats = state.get("stats", {})
        expected_first = target - (1 if make_mistake or wait_for_timeout else 0)
        checks.check(f"{label}: first-attempt evidence stays distinct from eventual success",
                     stats.get("first_try_opportunities") == target
                     and stats.get("first_try_correct") == expected_first
                     and stats.get("eventual_correct") == target
                     and stats.get("assisted") == (1 if make_mistake or wait_for_timeout else 0)
                     and stats.get("timeouts") == (1 if wait_for_timeout else 0), stats)
        checks.check(f"{label}: results retain measured active time", float(state["elapsed"]) > 0,
                     {"elapsed": state["elapsed"], "stats": state.get("stats")})
        checks.check(f"{label}: session evidence saved successfully", not state.get("save_error"), state.get("save_error"))
        button(bridge, "Home")
        until(lambda: snapshot(bridge).get("screen") == "menu")
        checks.check(f"{label}: results return to menu", True)


if __name__ == "__main__":
    raise SystemExit(main())
