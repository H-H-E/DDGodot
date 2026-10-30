# 01 — Diagnostic Dash: game DNA

## What was inspected

The source baseline is [`H-H-E/geometrymash` at `f43bf817e8dc20c554615a9fd39cb79585fab8c2`](https://github.com/H-H-E/geometrymash/tree/f43bf817e8dc20c554615a9fd39cb79585fab8c2), inspected on 2026-10-30. The intended live baseline is [dd.vlc.tools](https://dd.vlc.tools/). A live deployment can differ from that commit; this document does not silently treat the two as identical.

Primary source references:

| Reference | What it establishes |
| --- | --- |
| [`PRODUCT.md`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/PRODUCT.md) | Student independence, age-inclusive game identity, progressive disclosure, attention and accessibility aims |
| [`DESIGN.md`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/DESIGN.md) | Original procedural geometric artwork, visual roles, reserved host status, separation of visual effects from physics |
| [`public/game/geo-math-dash.html`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/public/game/geo-math-dash.html) | Actual mode presets, answer handlers, gate clock, movement, results, pause, setup, recovery and host protocol |
| [`public/game/learning/scheduler.js`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/public/game/learning/scheduler.js) | Pools, selection priority, anti-repeat guards, measured versus inferred evidence, fluency policy |
| [`public/game/runtime/fixed-step.js`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/public/game/runtime/fixed-step.js) | Fixed simulation updates, stall bounds, clock reset contract |
| [`public/game/engine/cadence.js`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/public/game/engine/cadence.js) | Cadence course/music adapter and geometric bounds |
| [`docs/runtime-architecture.md`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/docs/runtime-architecture.md) | Current subsystem ownership and documented modernization limits |
| [`docs/run-evidence.md`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/docs/run-evidence.md) | First-attempt denominator, aggregate hydration, learner separation and result idempotency |
| [`tests/learning-core.test.mjs`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/tests/learning-core.test.mjs), [`tests/first-try-metrics.test.mjs`](https://github.com/H-H-E/geometrymash/blob/f43bf817e8dc20c554615a9fd39cb79585fab8c2/tests/first-try-metrics.test.mjs) | Existing executable assertions, including pool cardinality and assisted-answer boundaries |

**Evidence terminology:** “Source-verified” means the implementation was read. It does not mean that route was played in the deployed application. “Design inference” means a reasoned interpretation of the mechanics. Executed journeys, screenshots, browser coverage and measurements belong in [07-QA-REPORT.md](07-QA-REPORT.md); improvement claims belong in [06-ORIGINAL-VS-REMAKE.md](06-ORIGINAL-VS-REMAKE.md).

### Directly observed live baseline

The live guest journey was opened in the connected browser: **Play → Practice (recommended, no timer) → Start Practice**. The displayed question `12 − 5` was answered by tapping the onscreen `7`; the original automatically submitted it, showed correct feedback and advanced to `1 − 1`. The blue geometric interface and active Practice state were captured at 1279 × 609 in [original-practice.png](../evidence/screenshots/original-practice.png). This observation confirms the basic answer-to-progress connection, untimed Practice labeling and default auto-submit behavior in the deployed guest experience.

This was a basic Practice interaction, not a complete session or a test of every original mode. Original Speed Racer, Blitz, Cadence, authenticated staff views and cross-device records were not established by this journey. No teacher records were accessed. Statements elsewhere about those systems remain source-based unless the QA report identifies separate execution evidence.

## 1. The player fantasy

The player is a quick-thinking geometric runner whose arithmetic changes the route ahead. A correct answer is an action in the world: a gate resolves, a platform becomes traversable, the cube jumps, and the course carries on. The fantasy is competence made visible. Thinking creates motion.

This interpretation follows the actual `submitAnswer`, `clearGate`, `playerSpeedBoost` and `updatePhysics` chain. The original is principally an **answer-controlled runner**, rather than a conventional platformer with a worksheet floating above it. Keeping this causal link matters more than reproducing a particular animation or menu.

## 2. What is enjoyable without the educational purpose?

The repeating anticipation-and-release rhythm is the game's strongest action design. An approaching geometric obstacle makes a pending decision visible. A successful action releases that tension through a jump, particles, increased scrolling speed and a musical response. Increasing laps rearrange seeded spikes and blocks, while the cube performs different tricks over cleared platforms. The player can feel a chain of successful actions even before reading a results panel.

These are source-verified mechanisms, not proof that every player enjoys them. The hypothesis to test with learners is that the visible consequence makes repeated recall feel purposeful, and that controlling the pace provides enough agency to sustain a short session.

The original also contains background rivals. Their relative positions come from presentation-side speed and random jumps; they are not evidence of another learner's performance. The remake should avoid implying an authentic competition where none exists.

## 3. How arithmetic belongs to the game

Each question owns one timed gate. Correct input clears that gate and advances progress. An incorrect answer reveals the correct pairing, resets the combo and draws the gate closer in timed play. A timeout records a missed opportunity and provides a recovery interval. In Practice, the gate eases toward the player and waits indefinitely.

This gives arithmetic a structural role: it determines whether a route opens. The remake must preserve that role. Manual jumps may add an optional motor challenge, but clearing an arithmetic gate cannot become optional, and a missed jump must never be recorded as an arithmetic mistake.

### Source modes are not named exactly like the brief

| Source concept | Actual behavior |
| --- | --- |
| Practice | Untimed, forgiving, no automatic lap endpoint; a learner ends when ready; adaptive fact scheduler active |
| Speed Racer (`racer`) | Closing answer windows, standard pace, finite laps |
| Blitz Overdrive (`blitz`) | Shorter answer windows and faster course movement |
| Classic course | Seeded geometric gate plan |
| Cadence course | A separate course-style choice; phrase-derived music and gate geometry share a seed and timing relationship |

The original defaults to eight successful questions per lap and three laps in the timed modes. A question that times out does not count as a successful gate toward those laps. **Classic and Cadence are course styles in the original, not replacements for Practice/Speed Racer/Blitz.** The remake's simpler mode menu is a deliberate product decision, documented in [02-GAME-DESIGN-DOCUMENT.md](02-GAME-DESIGN-DOCUMENT.md).

## 4. Sources of anticipation, satisfaction and mastery

| Interaction | Source behavior | Value to preserve |
| --- | --- | --- |
| Gate approaches | Its position derives from remaining answer frames | A legible, world-based representation of pending time |
| Correct answer | Gate clears, cube jumps, scroll receives a boost, feedback sounds | Immediate cause and effect |
| Successful sequence | Combo and audiovisual energy increase | A readable feeling of flow, separate from learning evidence |
| Mistake | Correct fact and strategy appear; input remains available | A chance to repair understanding immediately |
| Practice gate waits | Approach eases asymptotically; latency remains active wall time | Time to think without failure pressure |
| Fact returns later | Missed facts are requeued after intervening questions | Retrieval after spacing, without immediate endless drilling |
| Results suggest facts | Suggestions derive from observed misses, retries, timeouts and latency | A concrete reason for another useful round |
| Personal choice | Mode, arithmetic, range, appearance and audio can be selected | Ownership without social comparison |

“Mastery” in the source is an internal practice model, not a validated assessment. Its outward labels already qualify “quick & correct” as three consecutive unassisted answers within a game-defined target. That caution is a feature worth preserving.

## 5. Educational contracts that must survive

### Arithmetic pools

The original Practice pool is deterministic for a given operation and range:

| Operation | Pool construction |
| --- | --- |
| Addition | `a + b`, with both operands from `0..range` |
| Subtraction | `(b + d) − b = d`, with `b` and `d` from `0..range`; the minuend can reach `2 × range` |
| Multiplication | Both operands from `0..min(range, 12)` |
| Division | `(b × q) ÷ b = q`, with divisor `1..min(range, 12)` and quotient `0..min(range, 12)` |
| Mixed | Union of the chosen operation pools |

Subtraction therefore does **not** mean “both displayed numbers are at most the range.” Division never uses a zero divisor and never introduces fractional answers. Any slider adapter must filter eligible answers rather than invent a different operation. The original timed-mode generator has a fallback that can change a multiplication choice into division to satisfy a 1–10 slider; the remake uses an expressive keypad and explicit submit instead.

### First attempt versus eventual success

One question occurrence contributes at most one first-attempt opportunity. The opportunity begins with the first submitted answer or a timeout. A wrong answer, more retries and a later timeout are still one opportunity. A later occurrence of the same fact is a new opportunity. Leaving a question unanswered at session end is neither an error nor a timeout.

The first-attempt numerator requires an unassisted correct first response. A correct answer after a revealed solution is recorded as assisted eventual success. The interface may celebrate the recovery, but it must not convert that response into independent fluency.

### Timing

The source separates the 60 Hz simulation clock from response-time measurement. Manual pause, audio settings, covered menus and page hiding must stop active clocks. Decorative delays, animation time scales and a visually slowing Practice gate must not improve measured fluency.

There is a distinction to tighten in the remake: `failGate` passes the nominal answer-window duration into the source fact ledger. A timeout is not a measured human response. The remake must retain timeout counts without presenting a manufactured response time as though a learner answered.

### Selection and inferred knowledge

The original scheduler prioritizes a chosen focus queue, due missed facts, an initial sweep and then priority scoring. Priority considers accuracy, actual latency, spacing, elapsed days and recent repetition. It parks a fact after repeated misses and avoids immediate repetition. Pattern metadata reduces the initial sweep and may infer a commutative reverse. Inferred knowledge remains distinct from direct testing; it does not create a fake measured answer.

Saved aggregate attempts and averages cannot reconstruct a recent streak. Any migration that fabricates recent latencies would inflate fluency. Exact ported portions and intentional policy differences are specified in [LEARNING-PARITY.md](LEARNING-PARITY.md).

## 6. Friction and redesign candidates

These are implementation-grounded concerns and design hypotheses. They are not results of a user study.

1. **Many controls compete with the central loop.** Course style, mode, music mode, mood, input style, range, operations, laps, themes, immersive behavior and reports all coexist. Preserve useful choices, but let a learner reach a safe default with few decisions.
2. **Animation sometimes owns too much of the action.** Original jumps are automatic; spectacular movement is rewarding but offers limited direct motor agency. Add a small optional jump challenge while retaining assistance for learners concentrating on arithmetic.
3. **The default timed mode may be a poor first experience.** Practice is the appropriate low-pressure entry point for an unknown learner. Do not infer ability from age alone.
4. **Wrong-answer consequences mix motor pressure and learning.** Pulling a gate closer can punish the time spent reading the newly revealed answer. The remake should provide a readable recovery phase and ensure assisted retries remain possible.
5. **A speed rank can be misread as ability.** Keep combo, best run and clear count visibly separate from evidence. Avoid rank names that suggest a two-minute sample determines mathematical competence.
6. **The large HTML host makes boundaries easy to violate.** Learning and timing modules are already extracted, but question presentation, persistence and game state still meet in a single large file. Godot is an opportunity to make these responsibilities inspectable without creating a generic framework.
7. **A smaller implementation can still lose useful original features.** Teacher assignment links, authenticated records, report exports, slider input and full pattern scaffolding are not automatically preserved by a native rewrite. Any omitted feature must be listed, not hidden behind “better in every way.”

## 7. Preserve / improve / replace / remove / invent

### Essential — preserve the value

- Arithmetic opens the next gate and visibly advances the runner.
- The geometric runner, readable obstacles and satisfying clear feedback remain the recognizable identity.
- Practice provides unlimited thinking time on each question.
- Facts, opportunities, attempts, assistance and timeouts remain distinct.
- Saves are learner-scoped, and completed sessions have stable identifiers.
- Presentation cannot change collision boundaries or educational clocks.
- Every loop can be played using free local software, without inference services.

### Improve — keep the idea, revise execution

- Simplify first-run setup and make the selected arithmetic range precise.
- Make pauses, hint use and recovery states visible and predictable.
- Use readable contrast, large controls, touch input and visible keyboard focus.
- Keep a short, finite session option that ends in useful feedback and easy replay.
- Keep feedback immediate while reducing continuous shake, glow and competing motion.
- Give misses a later return with anti-repeat safeguards.

### Replace — change the limiting mechanism

- Replace the monolithic HTML gameplay host with separated Godot learning, simulation, presentation and save ownership.
- Replace answer-prefix auto-submission with deliberate submit as the default.
- Replace invented opponent positions with personal route progress.
- Replace score-led results with first-attempt evidence, completed questions and specific next-practice facts.
- Replace service-dependent test agents with actual vendored instrumentation plus a local deterministic driver where required.

### Remove — avoid low-value complexity

- No simulated social ranking, streak-loss pressure, login requirement or paid backend in the standalone game.
- No need for a second renderer or runtime asset service.
- No automatic conversion of an operation to fit a restricted input adapter.
- No generalized plugin system, scene factory or event bus without a concrete need.

### Invent — add only what serves the loop

- Optional player-controlled jump with a visible obstacle window and a motor-assist setting.
- Seeded route variation that can be replayed exactly during debugging.
- Explicit, finite practice goals that respect slower processing without a timer.
- A test snapshot contract that exposes actual game state and observable UI controls.
- A reproducible local quality gate covering native behavior and the exported WASM game.

## 8. Why return voluntarily?

A useful return invitation is specific: “These two facts took another try. Try a short route with them again.” Another is a personally chosen challenge: a different arithmetic family, a more comfortable pace, or a route played with manual jumping. A third is the satisfaction of a cleaner sequence on a familiar seeded course.

The design does not need daily attendance pressure, a currency grind, fabricated leaderboards or a penalty for choosing Practice. Returning should mean either a better-feeling run or a useful opportunity to remember something. Whether learners actually choose another round remains a playtesting question. Automated completion demonstrates playability and integrity; it cannot establish delight or learning efficacy.
