# 07 — QA report

## Release evidence

The deliverable is an actual Godot 4.7.2 project and single-threaded WebAssembly export. Verification exercises the real main scene, the real upstream Autopilot bridge and the real exported browser game. All learner data used here is synthetic and local. The original application's guest Practice route was observed separately; no authenticated learner or teacher records were used.

**Two complete verification passes passed with unchanged game source and export.** Final results, source hashes, archive hash and browser measurements are recorded in [release-manifest.json](../evidence/verification/release-manifest.json). The two full browser reports are [release 1](../evidence/verification/browser-release-1.json) and [release 2](../evidence/verification/browser-release-2.json). Intermediate runs and rejected artifacts are excluded.

| Verification | First retained pass | Second retained pass |
| --- | ---: | ---: |
| Native learning | 8,267 assertions / 11 scenarios | 8,267 / 11 |
| Native course | 13,203 assertions / 10 scenarios | 13,203 / 10 |
| Native main scene | 138 assertions / 8 scenarios | 138 / 8 |
| **Native total** | **21,608 assertions / 29 scenarios** | **21,608 / 29** |
| Actual Autopilot bridge + local goals | 69/69 checks | 69/69 checks |
| Chromium 141.0.7390.37 | 29/29 scenarios | 29/29 scenarios |
| Firefox 142.0.1 | 7/7 scenarios | 7/7 scenarios |
| WebKit 26.0 | 7/7 scenarios | 7/7 scenarios |
| **Browser total** | **43/43 scenarios** | **43/43 scenarios** |

There were zero engine/script errors in the selected native/bridge evidence and zero browser console errors, page errors, failed resource requests or HTTP errors. Firefox emitted one nonfatal engine-WASM deprecation warning per browser pass about its older exception-handling instruction. This warning is retained in the reports rather than hidden or described as a completely silent console.

The final browser runs occurred on 2026-10-30 at 20:43:43–20:48:46 UTC and 20:51:08–20:56:09 UTC. Build ID: **`a9f5adc38198c5eb`**. The 11-file browser archive is **10,672,413 bytes**; its manifest and every listed payload hash match the tested runtime. Archive SHA-256:

```text
a27aad6af82459e0a655b547d43820e011ad162c3678d1267267f201c7bba0ee
```

Detailed native reports are [pass 1](../evidence/verification/native-release-1.json) and [pass 2](../evidence/verification/native-release-2.json). The bridge evidence is retained under [output final2](../evidence/verification/autopilot-final2/report.json) and [output final1](../evidence/verification/autopilot-final1/report.json), in chronological order. Each bridge run completed five six-gate goals using 86 key events, 31 UI mouse actions and 12 dropdown selections. Both compressed traces fully decode and have exact request/response matches; their summaries distinguish native key/pointer actions, upstream dropdown selection and read-only observations.

## Environment and reproducibility

The editor and web templates are official `4.7.2.stable.official.ed1daf0bf`. `tools/install_godot.sh` pins and verifies the downloaded archives. Rendering uses Compatibility/WebGL 2 with a single WebAssembly thread. The web loader has a guarded, documented browser-presentation adjustment; the engine WASM remains unchanged. See [WEB-COMPATIBILITY.md](WEB-COMPATIBILITY.md).

Playwright is pinned to 1.56.1 in the package lock. Tests use its bundled Chromium 141, Firefox 142 and WebKit 26 engines on Linux. Chromium uses SwiftShader in this cloud environment. Firefox uses headed rendering under Xvfb with software graphics because its headless configuration cannot supply the required WebGL 2 context here. These conditions are recorded rather than treating an unavailable graphics context as a gameplay success. Physical-device claims cannot be inferred from this setup.

The source and actual runtime file hashes are captured before and after browser runs. Unexpected console errors, page errors, missing HTTP resources and failed requests fail the suite. Expected offline transport failures are distinguished only inside the deliberate offline scenario. Changed source/export files also fail the final gate. The Autopilot harness independently verifies its source stability and all vendored upstream hashes.

## What the tests actually exercise

| Layer | Executed behavior | Evidence boundary |
| --- | --- | --- |
| Learning and storage | 600 frozen original-JavaScript steps across five operation selections; arithmetic pools, priorities, assistance, first opportunities, timeouts, checkpoints, corrupt storage and idempotent completion | Exact fixture scope and intentional policy differences are in [LEARNING-PARITY.md](LEARNING-PARITY.md) |
| Course simulation | Deterministic seeded runs, exact restore, jump arc, 120 ms buffer, single collision/recovery, manual and assisted crossings at every pace and 60/120 Hz, two-minute Practice waiting and five-minute simulation | A simulation check is not a physical GPU or enjoyment test |
| Main scene | Real input events, correct/wrong/hinted results, early finish, pause, resume, pending-run guard, malformed checkpoints, learner settings, empty finish and a real seven-second timeout | Native tests do not establish browser save durability |
| Actual Autopilot bridge | Upstream handshake, UI reading, key input, pointer controls, dropdowns, goal completion, mistakes, hints, pause and setup options | Driven by the separate deterministic local driver; no Aura/Jev model inference occurred |
| Chromium export | All 15 mode × operation combinations, full-session results and replay; wrong/repeated/hinted responses; pause/help; real timeout; immediate reload; player separation; 24 gates and JSON download; touch-only phone; short layouts; production offline play; blocked storage; performance | QA configures synthetic setup only; actual inputs complete the goals |
| Firefox and WebKit exports | Actual startup, keyboard session, visible menu/play/results changes, replay, Classic multiplication, Cadence division, help/pause and mistakes/hints, with strict runtime checks | Representative coverage; the full operation matrix, actual timeout and frame sample are Chromium cases |

The QA query `?qa=1` exposes a read-only snapshot and a constrained fixture configuration callback. It does not solve questions or advance sessions. Normal production URLs are separately checked for the absence of the QA interfaces. The public status projection is used for browser announcements. Snapshots include the answer only on the explicit test route and cannot be used as authoritative grading data.

## Defects found and repairs verified

These are development defects found in this remake. They are not claims that the original game had the same failures.

| Defect | Root cause and repair | Regression/evidence |
| --- | --- | --- |
| Web export omitted required scripts | Scene-only export filtering did not include all preloaded resources. Export now includes project resources and explicitly excludes development/evidence directories. | Real WASM startup and gameplay, rather than export-command success alone |
| JSON checkpoint continuation rejected valid numbers | JSON normalizes numeric variants. Validation now checks finite numeric values and whole-count requirements before restore. | Cross-language fixtures, JSON roundtrips and exact question/course continuation |
| Incomplete or stale outer checkpoints could replace a run | Added complete outer-state validation, learner/session agreement and a Resume/Discard guard against stale Start callbacks. | Eight main-scene journeys, malformed-state rejection and actual browser reload |
| Fresh local player inherited previous preferences | Loading a new profile now reestablishes defaults before applying that profile's settings. | Native profile switching and browser player-separation journey |
| Slow-pace obstacle was unfair | Collision width exceeded the usable airborne crossing time. Narrowed the damaging core and made assisted jump distance pace-aware. | Seed/pace/step matrix plus manual crossings; arithmetic evidence remains separate |
| Procedural scenery emitted invalid polygons | Mountain points could create self-intersection. The renderer now generates ordered horizontal points with bounded peaks and clips to its own area. | Strict native engine logs, actual bridge playthroughs and all-browser console checks |
| Completed result returned as an interrupted run after reload | Godot's in-memory write could be acknowledged before asynchronous IndexedDB persistence completed. Web storage now validates and synchronously writes/reads back localStorage with a previous-value backup. | The original failing browser report is retained; immediate reload now runs without an arbitrary save delay |
| High-density phone appeared as a miniature desktop | Layout used backing pixels. Logical canvas scaling now follows CSS viewport dimensions while retaining DPR resolution. | Actual touch-only 390 × 844 CSS viewport at DPR 2; button bounds measured in CSS pixels |
| Resizing an existing tab shrank the old layout | A Control resize signal did not fire when the backing canvas changed but logical size remained fixed. An explicit browser resize listener now updates logical dimensions and rebuilds the layout. | Exact CSS/logical viewport agreement plus 44 px minimum gameplay buttons after live 960 × 420 and 720 × 450 resizes; [previous failure](../evidence/screenshots/defect-resize-shrunken-controls.png) retained |
| Phone results text clipped or had oversized layout bounds | Label text was laid out before wrapping/width/font initialization. Labels now receive their width and inherited font before text; mobile summary uses short lines. | Read-only label bounds, summary/save separation and inspected phone results screenshot |
| Repeated runs showed overlapping old save text | A previous completion/export notice survived a new run, and both HUD and footer constructed it. New runs clear the stale notice; footer creation respects the existing HUD label. | Native scene counts exactly one warning after rebuild/update, browser replay rejects stale notices, and the [visible failure](../evidence/screenshots/defect-duplicate-save-notice.png) is retained |
| WebKit framebuffer error | The emitted explicit-swap offscreen copy attempted an invalid framebuffer blit. A guarded context-creation transform uses normal browser implicit presentation. | Real keyboard completion, actual visible repaint and zero-error checks in all three final browser engines |
| A proposed WebKit workaround hid the visible failure | Textured-quad fallback cleared logs while the canvas stayed frozen. It was rejected. | Same-region screenshot hashes must change from menu to play to results; state-only success is insufficient |
| Earlier green checks could conceal a changed build | Source stability was initially informational. Both browser and bridge runners now fail when relevant source/runtime changes during a run. | Final pair must retain matching source and export hashes |

The selected failed initial browser report is retained at [browser-initial-failures.json](../evidence/verification/browser-initial-failures.json). Some subsequent failures in that report cascade from the stale checkpoint; they are not independent defects. The original headless Firefox graphics failure is an environment finding, resolved for verification by the recorded headed/Xvfb configuration. Intermediate runs whose source changed are explicitly excluded from final release evidence even when individual assertions passed.

One intermediate bridge trace was truncated despite completed scenario checks. That artifact was rejected; its cause was not established, and no trace-writer repair is claimed. Both selected final gzip streams were independently decoded in full, and every request ID was matched to its response. Their output folder names are identifiers rather than chronological labels: the retained `autopilot-final2` run completed before the replacement `autopilot-final1` run. Both use identical current source. The per-run summary files preserve the exact stream counts and hashes.

## Visual and interaction review

Screenshots cover title, mode choice, setup, playing, wrong answer, hint, timeout, pause, saved-run selection, results, progress, settings, short viewport, mobile and production offline states. Review considered equation readability, visible focus, geometric separation, feedback, reachable actions and clipping. The important visual repairs were renderer clipping, high-density logical sizing and phone result wrapping. The final screenshots are captured from the exported game, not from a separate mockup.

The browser suite captures repeatable images and detects a frozen canvas through heading-region transitions. It does not implement a comprehensive golden-image pixel-diff service. Human image inspection is still recorded separately from machine assertions. First-pass desktop and phone WebM recordings retain actual automated gameplay where video capture is enabled.

The [final visual review](../evidence/verification/visual-review.md) records 28 directly inspected screenshots with an exact hashed inventory. Actual [desktop](../evidence/recordings/release-final-1-chromium-desktop-playthrough.webm) and [touch-only phone](../evidence/recordings/release-final-1-chromium-mobile-touch-playthrough.webm) recordings are included.

The complete desktop recording was recompressed from VP8 to VP9 to fit the publication transport limit. Its duration, dimensions, frame rate and frame count are preserved; there is no trimming or speed change. This is lossy delivery compression, not a new playthrough. [Transcode provenance](../evidence/verification/recording-transcode.json) records both hashes and metadata. Original screenshots remain separate evidence.

Interaction is intentionally forgiving: a correct answer removes its associated hazard, Practice waits indefinitely, and a timed-out gate permits a supported answer. Optional manual jumping changes the motor task without changing arithmetic accuracy. Automatic tests establish reachable goals and accounting. They cannot establish that a student finds the game delightful or that one pace is appropriate for every learner.

## Performance interpretation

The target is smooth 60 FPS desktop gameplay and a usable low-powered mobile experience. Final reports record engine loading time, wall startup time, animation-frame mean/p95, observed FPS and available JavaScript heap measurements. The frame sample uses browser animation timestamps in a software-rendered cloud environment; it is not a GPU-profiler trace or a total-process memory measurement.

There is no matching original-game performance baseline. No performance superiority is claimed. A desktop cloud result below 60 FPS does not establish the same speed on physical hardware, and a clean console does not establish acceptable thermal or memory behavior on a phone. The full unpacked export includes the Godot engine; the archive size is reported separately from cold network download size and cache behavior.

| Observed measurement | Pass 1, with recording | Pass 2, without recording |
| --- | ---: | ---: |
| Chromium localhost wall startup | 1,692 ms | 1,434 ms |
| Chromium mean frame interval | 33.11 ms | 24.51 ms |
| Chromium p95 frame interval | 50.10 ms | 33.40 ms |
| FPS derived as 1,000 / mean interval | 30.20 | 40.80 |
| Reported JavaScript heap | 86.4 MB | 86.4 MB |
| Firefox localhost wall startup | 2,201 ms | 2,212 ms |
| WebKit localhost wall startup | 4,059 ms | 5,184 ms |

Each frame sample lasts about 2.5 seconds and runs with QA observation enabled. The second sample avoids video-recording overhead, but is still software-rendered cloud data. The 60 FPS target was **not met in this environment**. Physical-device profiling remains necessary. Startup is local HTTP loading under the suite's ready criterion, not an internet download benchmark; the engine/game payload totals 40,360,818 bytes before server-side transfer compression.

## Exact verification commands

From the repository root, using a standard Godot install with its matching export templates:

```sh
npm ci
npx playwright install --with-deps chromium firefox webkit
python3 -m pip install -r tools/autopilot-requirements.txt
GODOT_BIN=/path/to/Godot_v4.7.2-stable_linux.x86_64 bash tools/run_checks.sh
```

The combined script exports once and runs all three native suites, actual bridge goals and browser journeys twice. For this managed environment, the equivalent individual commands were run with the pinned engine at `/tmp/ddgodot-tools/Godot_v4.7.2-stable_linux.x86_64`, web templates under `/tmp/ddgodot-data`, and browsers under `/tmp/ddgodot-browsers`:

```sh
godot --headless --path . --script tests/test_learning.gd
godot --headless --path . --script tests/test_game.gd
godot --headless --path . --script tests/test_session.gd

python3 tools/autopilot_local.py --godot /path/to/godot \
  --scenario goals --seed 73 --output artifacts/autopilot-final2
python3 tools/autopilot_local.py --godot /path/to/godot \
  --scenario goals --seed 73 --output artifacts/autopilot-final1
gzip -t artifacts/autopilot-final2/trace.jsonl.gz artifacts/autopilot-final1/trace.jsonl.gz

python3 tools/serve.py --port 8060
xvfb-run -a env DD_FIREFOX_HEADED=1 LIBGL_ALWAYS_SOFTWARE=1 \
  PLAYWRIGHT_BROWSERS_PATH=/tmp/ddgodot-browsers \
  node tests/browser.mjs --engines chromium,firefox,webkit \
  --run-id release-final-1 --record-video
xvfb-run -a env DD_FIREFOX_HEADED=1 LIBGL_ALWAYS_SOFTWARE=1 \
  PLAYWRIGHT_BROWSERS_PATH=/tmp/ddgodot-browsers \
  node tests/browser.mjs --engines chromium,firefox,webkit \
  --run-id release-final-2
```

The second pass uses a distinct output/run ID and the same source/export. Video is an optional capture flag, not a different gameplay assertion. See the machine reports for timestamps and exact identities.

## Remaining limits and follow-up work

- Physical iPhone/iPad Safari, low-powered Android, hardware-accelerated desktop GPUs and prolonged rendered thermal/memory testing were not executed here.
- The 720 × 450 layout test approximates the content footprint of 200% zoom on a 1440 × 900 window. Actual browser-chrome 200% zoom is not certified by that test.
- Keyboard and touch paths, visible focus, reduced motion and live announcements are implemented. Screen-reader workflows and full accessibility conformance remain unverified.
- Sound activation/preferences are exercised, but no human listening evaluation of the mix or musical quality occurred.
- No learner study or comparative enjoyment, retention, fluency or attainment study was conducted. Short-session progress is practice evidence, not a validated diagnosis.
- The standalone game has three local slots. It has no authenticated teacher dashboard, assignments, server-authoritative results or cross-device sync. Concurrent writes from two tabs using the same player are unsupported.
- Browser caches and local records can be cleared or evicted. JSON export is available; accepted local writes are not a cloud-backup guarantee.
- The real upstream Autopilot bridge was used. Aura/Jev model-driven autonomous exploration and local language-model inference were not run. The supplied free deterministic driver is the reproducible supported test path.

These limits are also reflected in the [original/remake comparison](06-ORIGINAL-VS-REMAKE.md). They are not hidden behind an aggregate pass count.
