# 02 — Diagnostic Dash: Godot game design

## Purpose and scope

Create a short, satisfying arithmetic runner in which answering opens the route. A student should be able to choose a comfortable setup, play a complete session, understand what was actually recorded, and replay. A teacher should be able to configure that experience locally without introducing account management into the game.

The shipped scope is an independent Godot project and browser export. It does not replace the original application's authenticated learner database, staff roster or server-side validation. Source-based decisions are traced in [01-GAME-DNA.md](01-GAME-DNA.md). Verification and remaining gaps are reported in [07-QA-REPORT.md](07-QA-REPORT.md); this specification is not a substitute for executed evidence.

## Design pillars

1. **Thinking makes progress.** Each question owns a gate. A correct answer opens it and advances the session.
2. **Mistakes remain useful.** The player receives readable feedback, can retry, and sees honest evidence afterward.
3. **Pace is a choice.** Practice never imposes a deadline. Timed play adds tension without making a slower learner lose access to the session.
4. **Movement has readable consequences.** Jumping, collision and recovery are visible. Motor performance never changes arithmetic accuracy.
5. **The game explains what it knows.** First attempts, assisted successes, timeouts and recent measured responses remain distinct.
6. **A complete local loop is enough.** No subscription, login, hosted model, remote artwork or proprietary game service is required.

## Player journey

The main flow is title → mode and arithmetic setup → run → results → replay or title. Sound can be toggled during play. Other preferences are on the Settings screen; a player can pause, save and return home to change them, then resume. Local learner selection is explicit. If a valid interrupted run exists for that local profile, the title offers Resume or Discard before starting another run.

First launch should favor an untimed, low-friction experience. Clear choices come before advanced customization. The selected operation, fact range, mode and session length remain visible when starting, so the learner can check what they chose without opening another screen.

### Presets and deliberate changes from the source

| Preset | Question clock | Course and feedback | Intended use |
| --- | --- | --- | --- |
| Practice | Untimed; gate waits | Calm, readable route; assisted retries allowed | New facts, slower processing, learning strategies |
| Classic | Visible countdown selected by pace | Conventional geometric route | A chosen recall challenge |
| Cadence | Same countdown contract as Classic | Rhythmic presentation and course variation | A different feel without a different assessment rule |

This consolidates the original's Practice/Speed Racer/Blitz mode axis and Classic/Cadence course axis. Cadence is a presentation preset; sound does not own the clock. The original Cadence score grammar is not implicitly claimed as a complete port.

Sessions target **6, 12 or 24 solved gates**, with 12 as the standard short run. Practice remains untimed per question while gaining an explicit endpoint. A learner may finish early. A displayed but unanswered question at early finish contributes no opportunity or error.

Timed pace choices begin at **Relaxed 14 seconds, Steady 10 seconds or Swift 7 seconds**. These are game-design parameters, not age norms or claims about expected mathematical development. Any future timing adjustment must preserve a visible, predictable budget, must not treat assisted retries as independent speed evidence, and must be covered by a regression test.

## Arithmetic setup

The supported choices are addition, subtraction, multiplication, division and mixed arithmetic. Fact ranges are 5, 10 or 12. Pool construction preserves the source's zero-inclusive arithmetic and exact integer division. In subtraction, the displayed minuend may reach twice the selected base range. The setup description must make that interpretation clear.

The entire eligible pool must be representable through keyboard and onscreen keypad input. There is no 1–10 slider restriction and no silent switch from a chosen multiplication problem to division. Generated problems have a stable identity and explicit operation, operands, answer and display symbol.

### Question lifecycle

1. Select a fact with the learner's configured scheduler and seeded random stream.
2. Present the question and gate together; start its active thinking clock.
3. Accept digits and corrections during movement, except while paused or in a state that does not accept answers.
4. On explicit submit, record one actual response event and evaluate it.
5. On a correct response, resolve the gate exactly once, update evidence and increment solved progress.
6. On an incorrect response, record the error, show useful feedback, clear the typed answer and allow a retry.
7. On a timed expiration, record one timeout for the occurrence and enter a waiting/recovery state. Further time passing must not manufacture more timeouts.
8. A later correct retry permits continued play but remains assisted when the answer or solution was revealed.
9. At the solved target, show results. At early finish, leave an unobserved question uncounted.

The process must reject a second submission that belongs to the already resolved question. Double clicks, repeated Enter and frame-order races cannot create duplicate gates or opportunities.

## Learning evidence

### What each metric means

| Metric | Definition | Exclusions |
| --- | --- | --- |
| First-attempt opportunities | Question occurrences with a first submitted answer or a timeout | Merely showing a question; leaving it unanswered at finish |
| First-attempt correct | An unassisted correct first submitted answer | Correct retries, revealed answers, prior timeout |
| Solved questions | Question occurrences eventually answered correctly | Collisions and purely decorative actions |
| Submitted answers (`submitted_answers`) | Actual submissions | Timeout events, jump inputs, animation completions |
| Attempt events (`attempts`) | Submitted answers plus timeout events, preserving the source aggregate contract | Jump inputs and animation completions |
| Assisted successes | Correct submissions after assistance | Independent first answers |
| Timeouts | Occurrences that reach their timed deadline without resolution | Repeated frames in the same expired occurrence; Practice waiting |
| Mean first response (`mean_response_seconds`) | Mean active interval to the first submitted response for occurrences that have a submission; `response_samples` gives its denominator | Paused/hidden time, decorative animation delays, unanswered timeouts |
| Combo / route score | A game progression signal | Any claim of diagnostic validity |

The implementation's schema is authoritative; any aggregate field name inherited from the original must be explained rather than silently redefined. A zero-opportunity session displays no recorded responses, not a 0% ability score.

### Adaptation

Selection uses recorded history, not age or decorative scores. Difficult or slow facts can return after intervening questions. The scheduler avoids immediate repetition where the eligible pool permits it, limits repeated frustration, and keeps untested facts eligible. The same arithmetic learning core can serve all three presets; the user-selected mode changes the pressure, not the definition of independent success.

The original scheduler's exact arithmetic pools and evidence boundaries are regression targets. Any changed selection policy, missing pattern classifier or conservative simplification is named in [LEARNING-PARITY.md](LEARNING-PARITY.md). “Adaptive” must not imply that the whole source algorithm was ported if only a smaller weighted selector was implemented.

Only directly observed question events create direct evidence. A timeout is evidence of nonresponse within the selected deadline, not a measured response time. Its active duration is stored separately from submitted-response samples. A reverse or related fact may be described as inferred only if the implementation explicitly supports that distinction. Imported aggregate history cannot fabricate recent latencies, a consecutive streak or proof of fluent recall.

## Runner and obstacle design

The course is a side-scrolling geometric track with a clearly drawn ground line, a strong player silhouette and hazards that contrast with scenery. The player moves forward through world scrolling. The route remains reproducible from a seed.

The default motor-assist setting automatically jumps in response to successful arithmetic. Manual jumping uses Space or a large onscreen Jump button. Turning assistance off adds a motor challenge; it does not change the math pool or the definition of success.

A **120 ms jump input buffer** preserves a press made just before landing. The initial flat-track design does not need coyote time because it has no platform edges to step off. If ledges are later introduced, coyote time must be designed and tested then; it should not appear as an unimplemented feature in marketing copy.

### Collision and recovery invariants

- Drawn hazard geometry and collision geometry have a predictable relationship.
- A collision causes readable feedback and a brief recovery, without corrupting the current question.
- A motor collision never increments an arithmetic error or timeout counter.
- A correct answer resolves its own gate once; an old gate cannot time out the next question.
- Decorative rotation, trails, particles and camera offsets never move logical collision shapes.
- Reduced motion changes presentation, not speed, timing or available answers.
- A hazard cannot become unavoidable because a presentation effect changed the camera.

Fairness is measured against visible lead time and the actual jump envelope, not against an impression that a screenshot “looks possible.” Automated journeys should exercise successful jumps and intentional collisions separately.

## Feedback and audiovisual identity

The visual language is crisp geometric construction: a legible cube, simple terrain, restrained layered scenery and a small palette with distinct player, hazard and focus roles. The result should feel age-inclusive. Avoid babyish classroom decoration and continuous neon overload.

The equation and answer entry are the visual anchor during thinking. Progress, pause and sound controls are secondary. Decorative backgrounds sit below the contrast of playable objects. No particle burst should hide the next equation or answer field.

Correct answers receive an immediate positive cue and gate release. Incorrect responses identify the mistake and allow another attempt; a hint can reveal a strategy or answer, with assistance explicitly recorded. Timeout feedback describes what happened and permits recovery. No tone implies that slow processing is a personal failure.

Sound is synthesized locally or provided as appropriately licensed local assets. It activates only after a user gesture in browsers. A mute control and adjustable level must work throughout play. Cadence follows the gameplay clock; muted audio must leave all gameplay possible. Reduced motion suppresses unnecessary visual pulses, trails or impacts while retaining state feedback.

## Accessibility and input

| Need | Design response | Verification requirement |
| --- | --- | --- |
| Keyboard-only use | Digits, Backspace, Enter; Space to jump; Escape/P to pause; visible button focus | Full menu → session → results → replay journey without mouse |
| Touch-only use | Large onscreen digits, explicit submit, correction and Jump controls | Complete a session using taps; no keyboard injection |
| Slow processing | Untimed Practice; readable retries; no forced abandonment | Wait longer than timed budgets without a timeout |
| Motor difficulty | Default jump assistance; explicit submit; no drag-only requirement | Finish without precision jumping |
| Motion sensitivity | Reduced-motion setting | Same logical state with fewer effects |
| Low contrast / color perception | High-contrast option; labels and shapes supplement color | Inspect gameplay, selection and focus states |
| Small or short viewport | Responsive arrangement and reachable controls | Desktop, portrait, tablet and short-window screenshots |
| Browser zoom | Reflow/resize without hidden critical controls | Test browser zoom or equivalent viewport/device scale and disclose method |
| Interruption | Pause and hidden-page suspension | Active clocks do not advance during suspension |

Godot's canvas alone is not proof of screen-reader accessibility. The browser shell and Godot accessibility support must be tested before claiming screen-reader parity with the original DOM. Keyboard and touch passes do not establish WCAG conformance.

## Progression and replay

Results lead with trustworthy evidence: first-attempt correct over observed opportunities, solved gates, assisted retries and a concise next step. A personal run can also show its time and combo, explicitly as game metrics. The learner can replay, change settings or take a break.

Cosmetic cube color offers agency without changing physics. No cosmetic requires a daily streak or an arbitrary grind. There are no fabricated rankings or social comparisons. Future accomplishments should reflect transparent gameplay goals, such as a complete manual-jump route, and remain separate from educational conclusions.

Replay value comes from route variation, a cleaner personally chosen challenge, and practicing specific facts. Automated tests can demonstrate functional replay; only learner observation can establish whether replay is attractive.

## Saves and identity

The standalone version provides three explicit local learner slots. These are device-local profiles, not authenticated accounts. They should use neutral labels by default and store no credentials. Selecting another slot cannot reuse the previous profile's pending run, typed input, completed sessions or adaptive history.

Checkpoint after meaningful actions and at least once per second during active play. An interrupted session resumes only after an explicit choice. Resuming restores the question, typed answer, progress, question/opportunity flags, active ages, scheduler state and seed as supported by the implemented schema. Time spent away is excluded.

A finished session receives one stable identifier and an immutable result. Repeating completion or reopening results must not record a second session. Invalid storage and write failures must be visible. An unsupported or corrupted record must not be silently converted into valid evidence.

## Release decisions and boundaries

The release is acceptable when a real player can complete the full loop in a supported browser, the local automation can reproduce it, and evidence remains honest under errors, pauses and retries. Passing tests does not establish that the remake is superior in every category.

Authenticated host integration, cross-device synchronization, original teacher assignment links, a complete original Cadence score port, full source pattern scaffolding, screen-reader validation and low-powered physical-device performance must each be marked implemented, unverified or deferred in the final comparison. These distinctions are part of the product's integrity.
