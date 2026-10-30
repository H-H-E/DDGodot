# 05 — Test plan and release acceptance

## What counts as evidence

The release has four separate obligations: correct learning records, playable simulation, a functioning real-browser export, and a readable player experience. A parser pass establishes none of the latter three. A headless test cannot establish visual quality. A screenshot cannot establish persistence. The final outcomes and platform limits are recorded in [07-QA-REPORT.md](07-QA-REPORT.md) and the selected machine-readable verification evidence.

All automated scenarios use synthetic local data. They do not sign into the original teacher application or modify real learner records. Tests require free local tools only.

## Test layers

| Layer | Executable | What it establishes | What it does not establish |
| --- | --- | --- | --- |
| Engine import | Godot headless editor import | GDScript/resources import under the pinned engine | Gameplay, visual quality or browser compatibility |
| Learning and storage | `tests/test_learning.gd` | Exact arithmetic pools, original scheduler traces, occurrence accounting, assistance boundaries, state restoration and save validation | Main-scene integration or browser filesystem durability |
| Course simulation | `tests/test_game.gd` | Seeded reproducibility, jump envelope/buffering, collision/recovery, assisted and manual crossings, waiting and stability | UI usability or physical-device performance |
| Main-scene integration | `tests/test_session.gd` | Real scene input/actions, pause clocks, result construction, recovery, local profiles and timed retry | Browser export behavior or screenshot composition |
| Native instrumentation | `tools/autopilot_local.py` | Real vendored Autopilot bridge, UI inspection, input injection and deterministic gameplay goals | Aura/Jev model-driven testing or human judgment |
| Browser journeys | `tests/browser.mjs` | Exported WASM execution, actual keyboard/pointer/touch input, responsive UI, reload saves and offline behavior in executable engines | Unavailable engines, real hardware or native browser-UI zoom |
| Visual review | Captured screenshots under `evidence/screenshots/` | Readability, clipping, overlap and consistency in the captured states | Automatic pixel-golden regression unless a separate comparison is implemented |

## Reproducible commands

Use **Godot 4.7.2 stable** with matching export templates. `GODOT_BIN` may point to an installed executable; the examples assume it is `godot`. Run from the repository root.

### Import and native checks

```sh
godot --version
godot --headless --editor --path . --import
godot --headless --path . --script tests/test_learning.gd
godot --headless --path . --script tests/test_game.gd
godot --headless --path . --script tests/test_session.gd
```

For an isolated native run in a restricted environment, set a disposable data directory for each command. This uses the supported XDG path rather than changing a real user's data location permanently:

```sh
XDG_DATA_HOME=/tmp/ddgodot-native-qa godot --headless --path . --script tests/test_session.gd
```

The Main-scene test additionally substitutes a unique `DashSaveStore` path **before** adding the scene to the tree, so `_ready()` never reads a normal learner save. It supplies real `InputEventKey` events for answers, hints and pause, and invokes actual Control signals or scene actions for navigation. It does not increment the game's progress/evidence counters to manufacture completion.

Native output markers are `LEARNING_TEST_RESULT`, `DDGODOT_COURSE_REPORT=` and `DDGODOT_SESSION_REPORT=`. Check the process exit code as well as the reported failures. A later scenario failing does not erase earlier failures.

### Actual Autopilot instrumentation

```sh
python3 -m pip install -r tools/autopilot-requirements.txt
python3 tools/autopilot_local.py --godot godot --scenario bridge
python3 tools/autopilot_local.py --godot godot --scenario goals
```

Read [AUTOPILOT-AUDIT.md](AUTOPILOT-AUDIT.md) for the pinned source, protocol and outputs. A bridge pass and a completed gameplay-goal pass are distinct. The driver uses the real upstream addon and a deterministic local policy; it does not run the hosted Aura/Jev decision model.

### Export and browser checks

```sh
GODOT_BIN=godot bash tools/export_web.sh
npm ci
npx playwright install chromium firefox webkit
python3 tools/serve.py --directory build/web --port 8060
```

Leave the server running, then in another terminal:

```sh
node tests/browser.mjs \
  --base-url http://127.0.0.1:8060/ \
  --engines chromium,firefox,webkit \
  --run-id release-pass-1
```

`--smoke` is useful while diagnosing a change, but is not the complete release suite. The full Chromium run includes the mode/operation matrix plus mobile and production-offline scenarios. Other available engines receive representative journeys and runtime checks. The reports must state the exact engine/scenario coverage; “three browsers attempted” is not equivalent to “three browsers passed.”

`tools/run_checks.sh` is the repository's convenience entry point when present; read its output and README for its precise orchestration. The individual commands above define the component boundaries and remain the authoritative way to isolate a failure.

## Native coverage

### Learning and evidence

The learning fixture executes the pinned original JavaScript scheduler and compares selected questions and evidence with GDScript. It covers a 600-question deterministic upstream trace, as well as arithmetic pool counts and validity. An intentionally changed assisted-streak policy has its own regression rather than a claim of universal byte-for-byte parity. See [LEARNING-PARITY.md](LEARNING-PARITY.md).

Mandatory assertions include:

- Zero-inclusive pools, nonnegative subtraction, nonzero divisors and exact integer answers.
- A question shown but never answered contributes no observed opportunity.
- First wrong answer, repeated wrong answers, timeout and eventual correct retry remain one opportunity.
- Hint use is assistance; requesting it alone is not a submitted answer.
- Timeout age is separate from response latency, with an explicit response denominator.
- Assisted responses cannot create independent fluent streaks.
- Direct and inferred facts remain distinguishable.
- Checkpoints restore scheduler and occurrence identity without fabricating recent evidence.
- Corrupt/unsupported saves, invalid counters and conflicting completion payloads are refused.
- Identical repeated completion payloads remain idempotent and learner stores remain isolated.

### Course behavior

`tests/test_game.gd` contains ten behavioral scenarios. It checks 32 seeded course sequences, an airborne JSON roundtrip and continuation, a readable jump apex/landing, rejected airborne double jumps, the 120 ms landing buffer and single-hit recovery. Assisted obstacle crossings run across 24 seeds at each of 14/10/7-second paces and both 60/120 Hz. Manual crossings are checked separately.

Two-minute Practice simulations confirm that the gate remains ahead until solved. A five-minute simulation checks finite and bounded state over repeated course changes. The suite permits only negligible JSON float-rounding differences; RNG/counter identity remains exact. The 60/120 Hz comparison permits the small expected Euler trajectory difference while requiring the same fair crossing outcome.

These checks found and protect against the original remake's slow-pace hazard defect: its collision span took longer to traverse than the jump could remain above it. The narrowed collision core and pace-aware assistance must remain inside the tested envelope.

### Main scene and persistence integration

`tests/test_session.gd` contains eight integration journeys:

1. A real correct first response, wrong response plus correct retry, hint-assisted response, early finish and replay; verifies the saved result and immutable identity.
2. Pause with partially typed input; checks unchanged active clocks, course and learning ledger, then resume without catch-up.
3. Interrupted session, new Main instance and explicit restore; typed input stays unsubmitted and time away stays excluded.
4. Existing checkpoint guards the menu and rejects a stale start callback without overwriting the run.
5. Partial outer checkpoint, missing course data, incorrect types, wrong learner, inconsistent result counts, fractional counts and a broken attempt clock are rejected without silent deletion.
6. Profile preference switching restores defaults for a fresh learner and restores the first learner's saved preferences on return.
7. Finishing before any response saves honest zero evidence.
8. A real seven-second timed deadline, waiting, correct assisted retry and saved final result; verifies one timeout and no manufactured response latency.

The Main suite deliberately does not use accelerated fake clocks to pass the timeout journey. Its brief timer waits allow the actual application loop to run. Audio playback is stopped before each test scene is destroyed; audible quality remains a separate review.

## Browser scenario matrix

| Scenario group | Required observations | Implemented automation boundary |
| --- | --- | --- |
| Startup and navigation | Real WASM canvas starts; menus, setup, results and replay work | Keyboard-only first journey, startup timing and screenshots |
| Operations and modes | +, −, ×, ÷ and mixed complete under Practice/Classic/Cadence | Full 3 × 5 Chromium matrix; representative other-engine journeys |
| Answer integrity | Wrong, retry, hint and rapid submit preserve denominators | Read-only QA snapshot assertions after actual inputs |
| Pause | Time, physics and typed answer remain stable | Actual pause/resume input and elapsed checks |
| Timed recovery | Timeout occurs once and permits an assisted solution | Real timed journey; native Main suite duplicates the evidence contract |
| Recovery | Reload restores a saved active run and final results persist | Browser reload and explicit Resume |
| Learners | Settings and records do not cross local slots | Real profile selection and reload |
| Short viewport / zoom footprint | Actions remain reachable without overlap | 960 × 420 and 720 × 450 viewport checks; latter approximates the layout footprint of 200% zoom on 1440 × 900 |
| Touch / reduced motion | A phone-sized session can finish without keyboard input | 390 × 844, touch enabled, device scale 2, reduced-motion preference |
| Offline | Previously cached production build reloads and accepts a real answer offline | Service worker ready/control, network disabled, reload, answer, reconnect |
| Production instrumentation | Development control surface absent on ordinary URL | No `ddCommand` or QA `ddState` without `?qa=1` |
| Runtime/resource failures | No unexpected fatal errors or missing build assets | Console, page, request and HTTP error capture |
| Performance | Startup and frame distribution are recorded | Cloud-browser sample under stated rendering conditions |

The QA bridge may configure a synthetic fixture and read observations. It may not call solve, finish or advance methods instead of real player input. The production public state can announce the visible question without exposing the QA control interface.

The browser suite's `source_start`/`source_end` and build manifests detect source or export changes during a run. A run with changed code/build cannot satisfy the unchanged-release requirement even when its scenarios individually passed.

## Visual review checklist

Inspect the captured title, mode choice, setup, active run, wrong answer/hint, pause, saved-run choice, results, progress, settings, mobile and offline states. Review the actual images at their intended size.

- Can the equation, typed answer and next action be read immediately?
- Do the player, gate and hazard contrast with scenery?
- Are all labels inside their surfaces, including long feedback and result lists?
- Are touch controls large enough and reachable without a precision gesture?
- Does keyboard focus remain visible and belong to a usable action?
- Does a short viewport scroll naturally rather than crop the footer/actions?
- Do reduced-motion and muted states retain all essential feedback?
- Does a timed-out gate clearly become a retry opportunity?
- Is help presented without falsely describing supported success as independent?

Screenshot capture establishes a repeatable visual baseline. The current suite is not an automatic per-pixel golden-image comparison. Record reviewed images and specific fixes in the QA report; do not label a folder of screenshots “visual regression passed” without explaining what was inspected.

## Required manual or additional platform checks

These items remain separate from automated passes unless the QA report records direct execution:

- Physical low-powered phone/tablet frame timing, memory pressure, thermal behavior and touch ergonomics.
- Native browser-UI 200% zoom. Viewport emulation verifies its layout footprint, not every browser zoom behavior.
- Screen-reader navigation and announcements across operating systems. A DOM live region and keyboard support alone are not proof of full accessibility.
- Audible mix, perceived loudness, unpleasant repetition and Cadence quality on actual speakers/headphones.
- Human playtesting of frustration, readability under attention load, jump satisfaction, pace choice and willingness to replay.
- Exhaustive simultaneous input exactly on the timeout boundary and multi-tab concurrent writes. Existing rapid-input/timeout/identity tests cover representative cases, not every possible interleaving.
- Authenticated original staff functionality, cross-device records and server upload. These are outside the standalone local-game release.
- A long rendered session on physical hardware. The native five-minute simulation is a stability check, not a prolonged GPU/device test.

No speed or learning-efficacy advantage over the original should be claimed without a meaningful baseline and comparison. Design improvements may be described as deliberate decisions while user benefit remains a hypothesis.

## Severity and repair policy

**Release blockers:** launch/export failure; incorrect arithmetic; false first-attempt/assistance records; unreachable session completion; lost or crossed learner evidence; impossible mandatory motor challenge; essential controls inaccessible in a claimed supported layout; unexpected browser fatal errors.

**High priority:** confusing timeout recovery, repeatable input loss, unreadable feedback, incorrect save-status wording, save corruption without a safe recovery path, frequent frame stalls under representative conditions.

**Polish:** cosmetic alignment, excessive decorative movement, uneven sound balance and small transition issues that do not block comprehension or progress.

For a significant bug, retain a reproducible failing case, repair the underlying cause, add a focused regression and rerun affected layers. Do not remove a valid assertion because the implementation fails it.

## Final two-pass release gate

1. Finish code, settings, assets, tests and export changes; record the source and build identity.
2. Run import, all three native suites, actual Autopilot bridge/goals, export and the complete available-browser suite.
3. Inspect the resulting errors, metrics and screenshots. Repair any release blocker.
4. Run the complete suite twice consecutively with no intervening code/build changes. A later fix restarts the pair.
5. Record exact commands, exit codes, engine/browser versions, run IDs, source hashes, build ID, scenario counts, screenshot paths and unavailable platforms.
6. Publish only the source/export and evidence actually produced. Keep generated caches, credentials and synthetic transient save directories out of the repository.

A release may explicitly support one verified browser while reporting others unavailable. It may not turn unavailable coverage into a success, imply a paid autonomous-model run happened, or declare the game objectively more enjoyable because its automated checks passed.
