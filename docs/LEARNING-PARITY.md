# Learning evidence, scheduler parity and local persistence

## Provenance and scope

The reference was the original game's `main` tree at commit
[`f43bf817e8dc20c554615a9fd39cb79585fab8c2`](https://github.com/H-H-E/geometrymash/tree/f43bf817e8dc20c554615a9fd39cb79585fab8c2), particularly:

- [`public/game/learning/scheduler.js`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/public/game/learning/scheduler.js): fact pools, pattern-first sweep, priorities, replay spacing, response samples, stages and fluency.
- [`public/game/patterns.js`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/public/game/patterns.js): rules, inverse facts and commutative mirrors.
- [`docs/run-evidence.md`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/docs/run-evidence.md): one first-attempt opportunity per observed question occurrence, honest recovery, conservative imported evidence and identity boundaries.
- The standalone game's actual `recordFact`, `submitAnswer`, `failGate` and active-run restoration code, cross-checked with its tests.

`scripts/learning.gd` contains no scene, rendering, audio, storage or input dependencies. `scripts/save_store.gd` owns local storage. The game controller owns active clocks and explicitly submits measured intervals. A seed selects a reproducible course and arithmetic stream; a timestamp override is available for regression replay.

## Executed cross-language regression

`tools/generate_learning_fixtures.mjs` executes the original JavaScript in Node's VM, with its actual pattern classifier, an injected epoch clock and the original test's 32-bit LCG random source. It writes `tests/fixtures/learning_original.json`, including source hashes and commit provenance. The fixture contains 120 question/response steps for each of addition, subtraction, multiplication, division and mixed arithmetic: **600 executed reference steps**.

The native test compares every selected question, complete changed fact record, response tier and retry queue against that fixture. It also compares the initial shuffled sweep and the original pattern classification. The fixture uses unassisted submitted responses; changes to assisted and timeout handling are checked separately below. It is not a claim of exact parity for all possible upstream UI states.

The original pool definitions survive intact:

| Selection at range 20 | Facts | Meaning |
| --- | ---: | --- |
| Addition | 441 | Each operand 0–20; the sum can reach 40. |
| Subtraction | 441 | Subtrahend and difference each 0–20; the minuend can reach 40. |
| Multiplication | 169 | Factors capped at 12; answers can reach 144. |
| Division | 156 | Divisor 1–12, quotient 0–12; integer answers only. |
| Mixed | 1,207 | Union of the four pools. |

Range therefore does **not** mean a universal maximum visible number. No negative subtraction answers or division by zero are generated. Mixed operation selection and optional answer bounds remain explicit inputs. The Godot adapter defensively limits its accepted range to 100; the current game setup exposes much smaller choices.

The port preserves pattern-first sampling, directly observed facts, unmeasured mirror inference, anti-repeat windows, missed-fact requeues, parking after three misses, spacing pressure, original priority weights and the five-stage practice ladder. Adaptive selection now operates in every game mode, rather than only when the original Practice scheduler was active. Mode changes affect gameplay pressure, not definitions of evidence.

## Evidence definitions and deliberate corrections

An occurrence begins when `next_question()` presents a fact. The same fact presented later is a new occurrence. An unanswered fact left on screen when a session ends is not an observation and contributes no denominator or fabricated timeout.

| Field | Definition |
| --- | --- |
| `first_try_opportunities` | Occurrences with at least one submitted answer or one observed timeout. |
| `first_try_correct` | Correct first submissions before a hint, retry or timeout. |
| `eventual_correct` | Occurrences eventually solved, including assisted recovery. |
| `attempts` | Submitted answers **plus** timeout events, preserving the original aggregate convention. |
| `submitted_answers` | Submitted answers only; a separate count prevents ambiguous denominators. |
| `retries` | Submissions following an earlier submission or a timeout on that occurrence. |
| `assisted` | Successfully completed occurrences that used help, a retry or timeout recovery. This is not a count of all hint clicks. |
| `accuracy` | `first_try_correct / first_try_opportunities`, in 0–1 units. The displayed denominator must accompany zero-evidence states. |
| `mean_response_seconds` | Mean first submitted-response interval among occurrences with a submission. |
| `response_samples` | Explicit denominator of that response-time average. |

Each ledger item retains all submitted-response `latencies` and separate `timeout_latencies`. A nonresponse lasting nine seconds is not evidence that a learner answered in nine seconds. Timeouts reduce confidence and stage but do not enter the fact's response-latency samples. The controller must supply actual active durations, not a nominal gate limit; pauses, hidden-tab absence and transition animation are excluded upstream.

A timeout is recorded at most once per occurrence and leaves the question open for assisted recovery. A later correct answer solves that same occurrence but cannot become first-attempt correct. Repeated Enter after a solved occurrence is ignored. A hint shown before any response marks future success assisted but does not invent an observation.

The upstream scheduler leaves its existing independent streak and two-answer promotion counter unchanged on an assisted success. The remake **resets both counters**. Otherwise an assisted answer could bridge two independent-success sequences and contribute to an inflated fluency label. Three subsequent independent, fast correct answers are required again. This is an intentional conservative correction, documented and tested rather than silently described as exact parity.

Legacy aggregates without a genuine per-answer stage record retain attempts and correct totals but start with an empty recent-latency sequence and zero streak. An aggregate average cannot establish consecutive fast correct answers. Mirror familiarity remains labeled inferred; answering `3×7` never writes a measured result to `7×3`.

## Controller API

```gdscript
var learning = DashLearning.new()
var profile = store.get_profile(learner_id)
var bucket_key = "%s:%d" % [operation, number_range]
learning.configure(operation, number_range, seed_value,
    profile.evidence.get(bucket_key, {}))
var question = learning.next_question()
var response = learning.submit(typed_integer, active_attempt_interval_seconds)
var hint_text = learning.use_hint()
learning.timeout(observed_active_nonresponse_seconds)
var summary = learning.summary()
var checkpoint = learning.export_state()
```

Call `next_question()` exactly once when presenting a new gate. Pass the active interval since the prompt for a first response and since the previous submitted attempt for a retry. A timed-out gate should stop issuing timeout calls. After timeout feedback, reset the controller's attempt origin if the recovery response is being measured from that feedback. `response.accepted` distinguishes a recorded response from a stale, repeated or invalid call. `summary()` and `export_evidence()` return independent snapshots.

Checkpoint restore validates version, settings, arithmetic, queues, occurrence IDs, latencies, counters and agreement between the current occurrence and the committed ledger before mutating live state. JSON roundtrips normalize integer values to floating-point variants in Godot; numeric fields are compared by validated numeric value, not raw Dictionary type equality.

## Local learner storage

The default path is `user://diagnostic_dash.json`. A profile has this shape:

```json
{
  "evidence": { "addition:10": {} },
  "sessions": [],
  "checkpoint": {},
  "settings": {},
  "completed_ids": {}
}
```

Learner IDs are dictionary keys, never filesystem paths. Profiles and returned snapshots are independent deep copies. These are local learner slots, **not authenticated identities**; this component provides no server authorization or authoritative school record.

Writes go to a temporary file, flush, and are parsed and validated before replacing the main file. The previous valid revision is kept as `.bak`. A failed operation returns `false` and populates `last_error`; in-memory profile mutations are rolled back. This is best-effort process-level persistence, not a guarantee against power loss or browser storage eviction.

`complete_session(profile_id, result)` requires a `session_id` and consistent observed metrics. A canonical payload fingerprint makes an identical repeat idempotent, including after a JSON roundtrip. A different result under the same completed ID is rejected. The last 500 result records are retained; the completed-ID fingerprints remain to prevent older duplicate completions. Only a checkpoint belonging to the completed ID is cleared.

Corrupt, unsupported or badly typed data is left untouched and blocks automatic overwrites. `restore_backup()` and `discard_corrupt_storage()` are explicit user actions; both preserve the damaged source as `.corrupt` before replacing it. The UI must disclose `last_error` and must not call reset automatically. The file size limit is 16 MiB. Simultaneous independent tabs playing the same learner are not transactionally synchronized; use one active tab per local learner.

No authentication keys, network endpoints, model APIs or subscription services are needed by these components. They do not automatically upload student data. The web backend uses validated synchronous `localStorage` with a previous-value backup; native builds use verified temporary files and atomic replacement. This browser adapter was added after an actual reload test exposed delayed durability in Godot's in-memory filesystem/IndexedDB path. Native tests alone do not establish browser persistence; immediate completion/reload, corruption and quota handling must be exercised in the real export. Storage acceptance does not protect against browser eviction, user clearing or concurrent same-player tabs.

## Verification

```sh
godot --headless --path . --script tests/test_learning.gd
node tools/generate_learning_fixtures.mjs /path/to/geometrymash
```

Observed on Godot `4.7.2.stable.official.ed1daf0bf`: **11 scenarios, 8,267 assertions, zero failures**. The cases cover arithmetic and classification, original scheduler replay, first-attempt denominators, hints, repeated submission, wrong-answer/timeout combinations, assisted timeout recovery, separate response and timeout timing, conservative imported records, exact checkpoint continuation, malformed checkpoints, learner separation, duplicate completion, corrupted save preservation, backup recovery and failed writes. These are native component tests; gameplay feel, browser persistence, focus, visuals and web performance require the separate integration/browser suite.
