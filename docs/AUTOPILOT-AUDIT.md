# Autopilot integration and subscription-independent testing

## Decision

DDGodot vendors the **actual Godot addon from `ramenvr/autopilot`**, unchanged,
and uses its runtime instrumentation with a separate deterministic local driver.
It does **not** run the upstream Aura/Jev model-driven testing service. The game,
Godot editor, web export, native tests, browser tests, and local instrumentation
driver require no paid subscription, API key, hosted inference, or login.

The distinction is deliberate: an open-source client does not make its remote
decision model local. Reports label this workflow as a **deterministic local
driver using upstream Autopilot instrumentation**, never as an Aura/Jev agent run.

## Pinned source and compatibility

| Item | Value |
|---|---|
| Upstream repository | <https://github.com/ramenvr/autopilot> |
| Audited revision | `1818cc337b20762cd50102bc774a8e45eb7c4dc7` |
| Source folder | `plugin/godot/addons/autopilot/` |
| Vendored folder | `addons/autopilot/` |
| Addon changes | None; 64 original addon files, including original `.gdignore` files and fonts, plus the unchanged Apache license copied from the upstream repository root |
| Provenance | `addons/autopilot/UPSTREAM.json` contains original file SHA-256 hashes |
| Engine target | Godot **4.7.2 stable**, GDScript, Compatibility renderer |
| Upstream minimum | Godot 4.7; upstream explicitly reports testing 4.7.2 |
| Wire protocol | Autopilot protocol 1, game-initiated WebSocket connection |

The upstream editor plugin uses `EditorDock`; it is not suitable for silently
backporting to earlier Godot versions. The engine version is pinned rather than
patching away version-dependent functionality. The runtime addon uses Godot's
`Logger`, reflection, input events, viewport inspection, and optional capture.

The compatibility statement above is from the
[pinned Godot addon README](https://github.com/ramenvr/autopilot/blob/1818cc337b20762cd50102bc774a8e45eb7c4dc7/plugin/godot/README.md).
Actual execution evidence is recorded by the local test report, separately from
upstream's compatibility claim.

## What was inspected

The audit checked the repository README, CONTRIBUTING guide, `.env.example`,
Godot addon README, `autopilot/engines/godot.py`, its `godot.md` adapter notes,
`autopilot/runtime.py`, `autopilot/cli.py`, provider configuration in
`autopilot/agents/opencode.py`, the bridge protocol and the Godot smoke-test harness.
It also read the actual addon entry points, command-line parser, input bridge,
UI inspector, remote-control implementation, media implementation, and detectors.

## Which parts are local?

| Component | Runs locally? | External dependency in upstream's normal workflow | Used here? |
|---|---|---|---|
| GDScript addon and native scene inspection | Yes | None when driven by our loopback driver | Yes, original source |
| Input injection, UI inspection, pause, runtime error detectors | Yes | None | Yes |
| Screenshot/recording capture | Yes, when rendered | No capture in headless mode | Browser suite handles screenshots; headless refusal is checked |
| Python bridge and engine adapter | Yes | No inference for raw protocol operations | Protocol and adapter audited; our minimal server implements protocol 1 |
| Upstream code-reading/harness-writing agent | Local orchestration, model usually remote | Aura or a provider/agent configuration | Not executed |
| Jev gameplay decision runtime | Local orchestration, hosted inference | TypeSafe `TYPESAFE_API_KEY` or Aura relay | Not executed |
| `autopilot run saved_harness.py` | Local harness, **still hosted decisions** | It explicitly constructs `runtime.jev_client()` | Not used as a free fallback |
| DDGodot deterministic gameplay driver | Entirely local | Python `websockets` package; Godot executable | Yes |

Sources: [configuration and development guide](https://github.com/ramenvr/autopilot/blob/1818cc337b20762cd50102bc774a8e45eb7c4dc7/CONTRIBUTING.md),
[Jev runtime](https://github.com/ramenvr/autopilot/blob/1818cc337b20762cd50102bc774a8e45eb7c4dc7/autopilot/runtime.py),
and [CLI replay and key checks](https://github.com/ramenvr/autopilot/blob/1818cc337b20762cd50102bc774a8e45eb7c4dc7/autopilot/cli.py).

## Ollama / llama.cpp feasibility

The inspected OpenCode adapter accepts a provider-specific base URL such as
`OPENAI_BASE_URL`; its host passes the value as a provider `baseURL`. That is a
possible connection point for a local OpenAI-compatible server. It is **not** a
verified turnkey Ollama/llama.cpp implementation, and the upstream provider
configuration and tool-call capabilities would still need validation.

More importantly, this only concerns the harness-writing LLM. The gameplay
runtime imports `typesafe_sdk`, constructs `TypeSafeClient`, and requests the
versioned Jev decision model. The CLI checks for `TYPESAFE_API_KEY` without Aura.
There is no audited built-in Ollama or llama.cpp decision adapter in this revision.
Replacing it would require an implementation of the typed decisions, probability
results, timing, and error behavior, followed by separate validation. Merely
setting a different LLM base URL would not meet the no-hosted-inference requirement.

Therefore this project uses the explicit fallback allowed by the brief: retain
Autopilot's real instrumentation and use a transparent deterministic policy to
test the game. No local model is downloaded and no model-quality claims are made.
The driver can catch specified regressions; it does not assess arbitrary design
quality with the breadth of a human player.

Source: [OpenCode provider configuration](https://github.com/ramenvr/autopilot/blob/1818cc337b20762cd50102bc774a8e45eb7c4dc7/autopilot/agents/opencode.py)
and the runtime/CLI links above.

## How the integration works

Normal game startup has no Autopilot autoload. The editor dock remains disabled.
For native tests, `tools/autopilot_bootstrap.gd` creates the original
`addons/autopilot/playtest.gd` node and then instantiates the normal main scene.
The addon connects out to a server bound specifically to `127.0.0.1` on a random
ephemeral port. The local driver accepts one connection, checks protocol 1, and
sends explicit request/response frames.

The runner passes `--playtest-share=0` and verifies that the addon's handshake says
`share: false`. It never invokes the upstream service installer, login, agent
service, model SDKs, or paid providers. All state uses a fresh temporary
`XDG_DATA_HOME`, so automated native sessions do not reuse a real learner's data.
The export preset excludes the test tooling and addon from the browser build.

The driver uses the upstream `ui` / `ui_act` operations for real controls and
`key` for actual input events. Read-only snapshots are obtained through the
upstream `rc` reflection operation; this lets an assertion inspect observable
state without calling the game's answer or progression methods directly.
Every protocol frame and its relative timestamp is written to losslessly
compressed `trace.jsonl.gz`. It can be read with Python's standard `gzip` module
or `gzip -dc artifacts/autopilot/trace.jsonl.gz`.

## Reproduce locally

Install the exact free Python dependency once:

```sh
python3 -m pip install -r tools/autopilot-requirements.txt
```

Import the Godot project, then test the actual upstream bridge:

```sh
godot --headless --editor --path . --import --quit
python3 tools/autopilot_local.py --godot godot --scenario bridge
```

Run the playable-goal suite:

```sh
python3 tools/autopilot_local.py --godot godot --scenario goals
```

Use `--output artifacts/autopilot-repeat` for a second independent pass. The
default output is `artifacts/autopilot/`, containing `report.json`, `trace.jsonl.gz`,
and `godot.log`. Early development evidence may keep
the uncompressed `trace.jsonl`. A failing assertion exits nonzero and remains in
the report. `--seed 73` (the default) sends `--dd-seed=73` to Godot; every goal
session checks the actual seed. Reports include hashes of the executed project
source and a flag indicating whether those files changed during the run. A source
change is a failed check and a nonzero exit, so a moving build cannot count as a
final regression pass.

The bridge scenario checks the pinned original file hashes, the genuine addon
handshake, disabled sharing, engine version, real scene/UI inspection, advancing
time, pause behavior, invalid-request errors, and an honest headless-capture
failure. A bridge-only report must not be cited as a completed gameplay journey.
The goals scenario adds five six-gate sessions: Practice/addition,
Classic/subtraction, Cadence/multiplication, Practice/division, and Practice/mixed.
It exercises menu navigation, setup dropdowns, keyboard digits and Enter, manual
Space jumping, pause and resume, a wrong answer plus hint, a real seven-second
timeout and recovery, rapid repeat submission, first-attempt versus eventual
correctness, assisted evidence, save completion, and returning to the menu.
Setup dropdowns use the upstream `ui_act` selection operation (which selects and
emits the normal control signal); answer and jump input uses native key events.
Consult the report's individual checks and `scenario` field for exactly what was
executed. The additional browser suite tests actual DOM/canvas interaction and
rendered output separately.

## Limits and terminology

- No full Aura/Jev inference run was performed; no paid service was used.
- This integration does not claim to replace human playtesting or measure enjoyment.
- Headless native runs cannot produce screenshots; rendered browser runs provide
  the visual evidence.
- The release export does not need an Autopilot service, Python, WebSocket server,
  model, subscription, or API key.
- Upstream's optional editor dock can be manually enabled in a development copy.
  Its model-backed workflow has separate service requirements described upstream;
  it is not a dependency of this project's free workflow.

Licenses and attribution are in `THIRD_PARTY_NOTICES.md` and the vendored addon.
