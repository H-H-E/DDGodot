# Working on Diagnostic Dash

- Read the design, learning-parity, Autopilot audit and QA report before changing gameplay or evidence.
- Keep arithmetic evidence in `scripts/learning.gd`, simulation in `course.gd`, and drawing in `runner_view.gd`. Drawing must never mutate learning, collision, or timing state.
- Measure active response intervals with a monotonic clock. Pauses, hidden windows, and gate-opening animation must not inflate fluency samples. Timeout duration is not response latency.
- Preserve first-attempt opportunities, assistance, inferred versus measured records, local player separation and immutable session IDs.
- Preserve the upstream Autopilot addon and its licenses. Tests must use the provided free local driver; do not add a paid model, hosted decision API, trial or secret requirement.
- Never enable the test bridge in production exports. `?qa=1` is an explicit synthetic testing surface; do not give it host authentication or teacher records.
- Run all three native suites and actual browser journeys after meaningful changes. Check screenshots and engine/console errors; an export command alone is not a browser pass.
- Record a defect before repairing it and add a behavioral regression for substantial failures. Final release evidence requires two full passes with unchanged game source/export.
- Retain published Git history. Do not force-push or rewrite existing remote commits.
