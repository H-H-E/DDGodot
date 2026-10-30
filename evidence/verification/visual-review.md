# Final exported-game visual review

## Reviewed build and method

This review inspected **28 actual screenshots** from browser run `release-final-1`, build **`a9f5adc38198c5eb`**, after its report completed with all 43 scenarios passed and unchanged source/export hashes. Images were opened and examined directly. They were not inferred from internal state, recreated as mockups, or accepted solely because the automated scenario passed.

[visual-review.json](visual-review.json) records every reviewed project-relative filename, image dimensions, SHA-256 hash and the source/runtime identities from the browser report. [browser-release-1.json](browser-release-1.json) contains the executed input, state, runtime-error and layout assertions. This note documents visual observations; the machine report supplies separate behavioral evidence.

## Findings

No blocking text clipping, overlapping notices, or unreadable primary actions were found in the reviewed final frames. The equation, typed answer, feedback and keypad are visually separate. The cube, hazard and gate remain distinct from the background. Wrong-answer and hint text is readable without obscuring the next action. The pause panel and browser help dialog have clear return actions and readable explanations.

The earlier repeated-run footer defect is absent: the final wrong-answer, hint and timeout screenshots do not retain the previous completion/export notice, and no two save messages are drawn over one another. The previous failure remains available as [defect-duplicate-save-notice.png](../screenshots/defect-duplicate-save-notice.png).

The live-resize repair is visible. At 960 × 420 and 720 × 450, content uses the available width with normally sized text and controls. It no longer shows a uniformly shrunken, letterboxed desktop layout. Short windows intentionally scroll vertically, so some actions lie below the captured viewport. The automated journey separately exercised scrolling and asserted exact CSS/logical viewport agreement and gameplay button sizes of at least 44 CSS pixels. A single screenshot alone would not establish that those lower actions are reachable. The earlier shrinking failures remain in [defect-resize-letterbox.png](../screenshots/defect-resize-letterbox.png) and [defect-resize-shrunken-controls.png](../screenshots/defect-resize-shrunken-controls.png).

At the 390 × 844 CSS-pixel phone viewport with DPR 2, the menu, equation, keypad and Hint/Jump/Pause controls fit clearly. Results use short summary lines; the first-try explanation, support/timeouts, active time and save acknowledgement are separated and remain inside the width. The fact ledger continues below the fold as scrollable content. A full touch-only session is recorded by the browser suite; these images establish the appearance of its captured states.

Completed-session results identify first-try success as occurring without help. The storage-unavailable result displays an explicit warning to export before closing and keeps the export action visible. The offline capture visibly shows a correct answer, gate release and progress. The underlying save/offline guarantees are verified by the behavioral scenarios, not inferred from those pictures.

Firefox and WebKit playing/results frames visibly show the actual game and completed result. This supports the repaired frame-presentation path together with the suite's changing heading-region hashes and zero-error checks. It does not establish Safari behavior on physical Apple hardware.

## Exact screenshots inspected

All links below identify final-run captures. Additional operation/result screenshots exist in the browser report; this review does not claim to have individually opened every redundant variant.

| Engine and captured state | File |
| --- | --- |
| Chromium title | [release-final-1-chromium-01-menu.png](../screenshots/release-final-1-chromium-01-menu.png) |
| Chromium modes | [release-final-1-chromium-02-modes.png](../screenshots/release-final-1-chromium-02-modes.png) |
| Chromium arithmetic setup | [release-final-1-chromium-03-setup.png](../screenshots/release-final-1-chromium-03-setup.png) |
| Chromium active game | [release-final-1-chromium-04-playing.png](../screenshots/release-final-1-chromium-04-playing.png) |
| Chromium results | [release-final-1-chromium-05-results.png](../screenshots/release-final-1-chromium-05-results.png) |
| Chromium wrong response | [release-final-1-chromium-06-wrong-answer.png](../screenshots/release-final-1-chromium-06-wrong-answer.png) |
| Chromium hint | [release-final-1-chromium-07-hint.png](../screenshots/release-final-1-chromium-07-hint.png) |
| Chromium paused game | [release-final-1-chromium-08-paused.png](../screenshots/release-final-1-chromium-08-paused.png) |
| Chromium browser help | [release-final-1-chromium-08-browser-help-paused.png](../screenshots/release-final-1-chromium-08-browser-help-paused.png) |
| Chromium timeout/recovery | [release-final-1-chromium-09-timeout.png](../screenshots/release-final-1-chromium-09-timeout.png) |
| Chromium saved-run choice | [release-final-1-chromium-10-resume-menu.png](../screenshots/release-final-1-chromium-10-resume-menu.png) |
| Chromium progress | [release-final-1-chromium-11-progress.png](../screenshots/release-final-1-chromium-11-progress.png) |
| Chromium settings | [release-final-1-chromium-12-settings.png](../screenshots/release-final-1-chromium-12-settings.png) |
| Chromium 960 × 420 menu | [release-final-1-chromium-13-short-menu.png](../screenshots/release-final-1-chromium-13-short-menu.png) |
| Chromium 720 × 450 game | [release-final-1-chromium-14-zoom-equivalent-game.png](../screenshots/release-final-1-chromium-14-zoom-equivalent-game.png) |
| Chromium 720 × 450 pause | [release-final-1-chromium-15-short-paused.png](../screenshots/release-final-1-chromium-15-short-paused.png) |
| Chromium phone menu | [release-final-1-chromium-16-mobile-menu.png](../screenshots/release-final-1-chromium-16-mobile-menu.png) |
| Chromium phone game | [release-final-1-chromium-17-mobile-playing.png](../screenshots/release-final-1-chromium-17-mobile-playing.png) |
| Chromium phone results | [release-final-1-chromium-18-mobile-results.png](../screenshots/release-final-1-chromium-18-mobile-results.png) |
| Chromium offline play | [release-final-1-chromium-19-offline-play.png](../screenshots/release-final-1-chromium-19-offline-play.png) |
| Chromium storage unavailable | [release-final-1-chromium-20-storage-unavailable-results.png](../screenshots/release-final-1-chromium-20-storage-unavailable-results.png) |
| Chromium 24-gate result/export | [release-final-1-chromium-results-long-session-export.png](../screenshots/release-final-1-chromium-results-long-session-export.png) |
| Chromium Cadence division result | [release-final-1-chromium-results-cadence-division.png](../screenshots/release-final-1-chromium-results-cadence-division.png) |
| Chromium Practice division result | [release-final-1-chromium-results-practice-division.png](../screenshots/release-final-1-chromium-results-practice-division.png) |
| Firefox active game | [release-final-1-firefox-04-playing.png](../screenshots/release-final-1-firefox-04-playing.png) |
| Firefox results | [release-final-1-firefox-05-results.png](../screenshots/release-final-1-firefox-05-results.png) |
| WebKit active game | [release-final-1-webkit-04-playing.png](../screenshots/release-final-1-webkit-04-playing.png) |
| WebKit results | [release-final-1-webkit-05-results.png](../screenshots/release-final-1-webkit-05-results.png) |

## Limits

This is inspection of particular exported-game frames, not a comprehensive pixel-golden regression system. The resized 720 × 450 test represents a 200%-zoom layout footprint; it does not establish actual browser-chrome zoom behavior. No physical-phone ergonomics, screen-reader workflow, audible sound mix, sustained hardware performance or learner-preference study was performed. Images alone do not establish collision fairness, learning accuracy, storage durability or animation smoothness; those require the separate behavioral evidence and stated test conditions.
