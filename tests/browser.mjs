/** Real-browser verification of the Godot WebAssembly export.
 * Only QA fixture configuration uses ddCommand. Every gameplay interaction is a
 * real pointer, keyboard, or touch event; assertions read the opt-in snapshot.
 * No model, hosted test service or subscription is used.
 *
 * npm ci && npx playwright install chromium firefox webkit
 * python3 tools/serve.py --port 8060
 * node tests/browser.mjs --engines chromium,firefox,webkit --run-id local
 */
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { chromium, firefox, webkit } from 'playwright';

const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const origin = option('--base-url', process.env.DD_BASE_URL || 'http://127.0.0.1:8060/');
const runId = option('--run-id', new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-'));
const engines = option('--engines', 'chromium,firefox,webkit').split(',');
const smokeOnly = args.includes('--smoke');
const recordVideo = args.includes('--record-video');
const onlyPattern = option('--only', '');
const selectedCases = onlyPattern ? new RegExp(onlyPattern) : null;
const screenshotRoot = path.resolve('evidence/screenshots');
const reportRoot = path.resolve('evidence/runs');
const recordingRoot = path.resolve('evidence/recordings');
await fs.mkdir(screenshotRoot, { recursive: true });
await fs.mkdir(reportRoot, { recursive: true });
if (recordVideo) await fs.mkdir(recordingRoot, { recursive: true });
const report = { run_id: runId, started_at: new Date().toISOString(), base_url: origin,
  policy: 'Real exported Godot game. Read-only observation and explicit configuration fixture; real user input for navigation and gameplay.',
  engines: [], limitations: ['Software-rendered cloud browser performance is not representative of a physical low-powered phone.', 'Sound preference and browser activation are exercised; audible sound quality is not automatically judged.', 'Corrupt-save injection and malformed checkpoint validation are covered by the native component suite, not fabricated as browser passes.'] };
async function sourceManifest() {
  const files = ['project.godot', 'export_presets.cfg', 'tools/export_web.sh', 'tools/finalize_web.py', 'tests/browser.mjs'];
  for (const directory of ['scripts', 'scenes', 'web']) {
    for (const name of await fs.readdir(directory)) if (/\.(gd|tscn|html|js|css)$/.test(name)) files.push(`${directory}/${name}`);
  }
  async function assets(directory) {
    for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
      const file = `${directory}/${entry.name}`;
      if (entry.isDirectory()) await assets(file);
      else if (/\.(ttf|otf|png|svg|wav|ogg)$/.test(file)) files.push(file);
    }
  }
  await assets('assets');
  const hashes = {};
  for (const file of files.sort()) hashes[file] = createHash('sha256').update(await fs.readFile(file)).digest('hex');
  return { sha256: createHash('sha256').update(JSON.stringify(hashes)).digest('hex'), files: hashes };
}
report.source_start = await sourceManifest();
report.build_manifest_start = JSON.parse(await fs.readFile('build/web/build-manifest.json', 'utf8'));
async function runtimeManifest() {
  const files = {};
  for (const name of (await fs.readdir('build/web')).sort()) {
    if (!/\.(html|js|wasm|pck|png)$/.test(name)) continue;
    files[name] = createHash('sha256').update(await fs.readFile(`build/web/${name}`)).digest('hex');
  }
  return { sha256: createHash('sha256').update(JSON.stringify(files)).digest('hex'), files };
}
report.runtime_start = await runtimeManifest();
report.selected_case_filter = onlyPattern || null;
report.smoke_only = smokeOnly;
report.video_recording = recordVideo;
let failed = false;
let engineName = '';
let activeCase = '';
let engineReport;

const state = page => page.evaluate(() => window.ddState);
const waitState = async (page, predicate, timeout = 12000) => {
  await page.waitForFunction(predicate, undefined, { timeout });
  return state(page);
};
const screen = (page, value, timeout) => page.waitForFunction(s => window.ddState?.screen === s, value, { timeout: timeout || 12000 });
const shortWait = (page, ms = 180) => page.waitForTimeout(ms);

function attachLogs(page, logs) {
  page.on('console', message => {
    if (['error', 'warning'].includes(message.type())) logs.console.push({ scenario: activeCase, type: message.type(), message: message.text() });
  });
  page.on('pageerror', error => logs.page_errors.push({ scenario: activeCase, message: error.message }));
  page.on('requestfailed', request => logs.failed_requests.push({ scenario: activeCase, url: request.url(), error: request.failure()?.errorText }));
  page.on('response', response => { if (response.status() >= 400) logs.http_errors.push({ scenario: activeCase, status: response.status(), url: response.url() }); });
}

function unexpectedRuntimeErrors(logs, allowOfflineTransportFailures = false) {
  return {
    console: logs.console.filter(e => e.type === 'error' && !/AudioContext.*(allowed|start)|autoplay/i.test(e.message)),
    page_errors: logs.page_errors,
    http_errors: logs.http_errors,
    failed_requests: allowOfflineTransportFailures ? [] : logs.failed_requests,
  };
}

function assertNoRuntimeErrors(logs, allowOfflineTransportFailures = false) {
  const unexpected = unexpectedRuntimeErrors(logs, allowOfflineTransportFailures);
  for (const [kind, errors] of Object.entries(unexpected)) assert.equal(errors.length, 0, `Unexpected browser ${kind}: ${JSON.stringify(errors)}`);
}

async function screenshot(page, label) {
  const filename = `${runId}-${engineName}-${label}.png`;
  await page.screenshot({ path: path.join(screenshotRoot, filename), fullPage: true });
  engineReport.screenshots.push(`evidence/screenshots/${filename}`);
}

async function preserveRecording(video, label) {
  if (!video) return;
  const filename = `${runId}-${engineName}-${label}.webm`;
  await fs.rename(await video.path(), path.join(recordingRoot, filename));
  engineReport.recordings.push(`evidence/recordings/${filename}`);
}

async function load(page, qa = true) {
  const url = new URL(origin);
  if (qa) url.searchParams.set('qa', '1');
  const start = Date.now();
  await page.goto(url.toString(), { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(({ qa }) => (qa ? !!window.ddState : !!window.ddPublicState) || document.getElementById('failure')?.textContent, { qa }, { timeout: 90000 });
  const failure = await page.evaluate(() => document.getElementById('failure')?.textContent || '');
  if (failure) throw new Error(`Godot startup failure: ${failure}`);
  await page.locator('#loading').waitFor({ state: 'detached', timeout: 90000 });
  await shortWait(page, 250);
  return { wall_startup_ms: Date.now() - start, engine_loaded_ms: await page.evaluate(() => window.ddLoadedAt || null) };
}

async function controlPoint(page, id, touch = false) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const s = await state(page);
    const c = s?.controls?.[id];
    assert(c, `Missing control ${id} on ${s?.screen}`);
    assert(c.visible && !c.disabled, `Control ${id} must be visible and enabled`);
    const box = await page.locator('#canvas').boundingBox();
    const x = box.x + (c.x + c.w / 2) * box.width / s.viewport.w;
    const y = box.y + (c.y + c.h / 2) * box.height / s.viewport.h;
    if (x >= 0 && x < box.x + box.width && y >= box.y + 4 && y < box.y + box.height - 4) return { x, y, c };
    assert(!touch, `Touch control ${id} is outside the visible viewport; touch-only path cannot reach it`);
    await page.mouse.move(box.x + box.width * 0.48, box.y + box.height * 0.5);
    await page.mouse.wheel(0, y < 0 ? -Math.abs(y) - 120 : y - box.height + 120);
    await shortWait(page, 250);
  }
  throw new Error(`Control ${id} remained outside the viewport after scrolling`);
}

async function click(page, id, touch = false) {
  const { x, y } = await controlPoint(page, id, touch);
  if (touch) await page.touchscreen.tap(x, y); else await page.mouse.click(x, y);
  await shortWait(page);
}

async function home(page) {
  let s = await state(page);
  if (s.screen === 'playing') { await page.keyboard.press('Escape'); await screen(page, 'paused'); }
  s = await state(page);
  if (s.screen === 'paused') { await click(page, 'FinishRun'); await screen(page, 'results'); }
  s = await state(page);
  if (s.screen !== 'menu') {
    if (s.controls.Home) await click(page, 'Home'); else await page.keyboard.press('Escape');
    if ((await state(page)).screen === 'modes') await click(page, 'Home');
  }
  await screen(page, 'menu');
}

async function configure(page, values) {
  await page.evaluate(v => window.ddCommand(JSON.stringify({ action: 'configure', seed: 73, ...v })), values);
  await shortWait(page);
}

async function startRun(page, { mode = 'practice', operation = 'addition', range = 5, target = 6, pace = 0, touch = false } = {}) {
  await home(page);
  // New independent fixtures explicitly discard any interrupted test run. The
  // persistence scenario checks its own recovery assertions before reaching here.
  if ((await state(page)).controls.DiscardSaved) await click(page, 'DiscardSaved', touch);
  await click(page, 'Play', touch);
  await screen(page, 'modes');
  await click(page, { practice: 'Practice', classic: 'Classic', cadence: 'Cadence' }[mode], touch);
  await screen(page, 'setup');
  await configure(page, { mode, operation, range, target, pace });
  const setup = await state(page);
  assert.equal(setup.operation, operation);
  assert.equal(setup.target, target);
  await click(page, 'StartRun', touch);
  await screen(page, 'playing');
  const s = await state(page);
  assert.equal(s.mode, mode);
  assert.equal(s.completed, 0);
  assert.equal(s.stats.first_try_opportunities, 0);
  return s;
}

async function enterAnswer(page, answer, touch = false, expectCorrect = true) {
  const before = await state(page);
  if (touch) {
    for (const digit of String(answer)) await click(page, `Digit${digit}`, true);
    await click(page, 'SubmitAnswer', true);
  } else {
    await page.keyboard.type(String(answer), { delay: 18 });
    await page.keyboard.press('Enter');
  }
  await page.waitForFunction(({ attempts }) => window.ddState?.stats.attempts > attempts, { attempts: before.stats.attempts }, { timeout: 12000 });
  const after = await state(page);
  if (expectCorrect) assert.equal(after.completed, before.completed + 1, 'Correct answer must clear the gate');
  else assert.equal(after.completed, before.completed, 'Wrong answer cannot clear the gate');
  return after;
}

async function completeRun(page, touch = false) {
  for (let guard = 0; guard < 100; guard++) {
    let s = await state(page);
    if (s.screen === 'results') return s;
    assert.equal(s.screen, 'playing', 'Run must remain active until results');
    if (s.gate_solved) {
      await page.waitForFunction(() => window.ddState?.screen === 'results' || !window.ddState?.gate_solved, undefined, { timeout: 12000 });
      continue;
    }
    await enterAnswer(page, s.question.answer, touch);
  }
  throw new Error('Run did not reach results within the expected number of gates');
}

async function finishEarly(page, touch = false) {
  await click(page, 'Pause', touch);
  await screen(page, 'paused');
  await click(page, 'FinishRun', touch);
  await screen(page, 'results');
}

async function selectOption(page, id, index) {
  await click(page, id);
  // Godot PopupMenu initially has no keyboard-highlighted item: the first Down
  // highlights item zero. Home is not a supported popup selection shortcut.
  for (let i = 0; i <= index; i++) await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await shortWait(page, 250);
}

async function checkCase(page, name, fn) {
  if (selectedCases && !selectedCases.test(name)) return true;
  activeCase = name;
  const started = Date.now();
  try {
    const observations = await fn();
    engineReport.scenarios.push({ name, status: 'passed', duration_ms: Date.now() - started, observations: observations || {} });
    console.log(`PASS ${engineName}: ${name}`);
    return true;
  } catch (error) {
    failed = true;
    const current = await state(page).catch(() => null);
    const record = { name, status: 'failed', duration_ms: Date.now() - started, error: error.message, snapshot: current };
    engineReport.scenarios.push(record);
    await screenshot(page, `FAIL-${name.replace(/[^a-z0-9-]/gi, '-')}`).catch(() => {});
    console.error(`FAIL ${engineName}: ${name}: ${error.message}`);
    return false;
  }
}

async function desktopScenarios(browser, page) {
  await checkCase(page, 'first-launch-menu-and-keyboard-navigation', async () => {
    assert.equal((await state(page)).screen, 'menu');
    await screenshot(page, '01-menu');
    const headingClip = { x: 32, y: 110, width: 500, height: 270 };
    const menuPixels = createHash('sha256').update(await page.screenshot({ clip: headingClip })).digest('hex');
    await page.keyboard.press('Enter');
    await screen(page, 'modes');
    await screenshot(page, '02-modes');
    await page.keyboard.press('Enter');
    await screen(page, 'setup');
    await screenshot(page, '03-setup');
    await configure(page, { target: 6, range: 5 });
    await page.keyboard.press('Enter');
    await screen(page, 'playing');
    await screenshot(page, '04-playing');
    const playingPixels = createHash('sha256').update(await page.screenshot({ clip: headingClip })).digest('hex');
    assert.notEqual(playingPixels, menuPixels, 'The displayed game must repaint after leaving the menu, not merely advance internal state');
    const result = await completeRun(page);
    assert.equal(result.result.first_try_correct, 6);
    assert.equal(result.result.first_try_opportunities, 6);
    assert.equal(result.result.eventual_correct, 6);
    assert.equal(result.save_error, '');
    await screenshot(page, '05-results');
    const resultPixels = createHash('sha256').update(await page.screenshot({ clip: headingClip })).digest('hex');
    assert.notEqual(resultPixels, playingPixels, 'The results must actually repaint the visible canvas');
    const previous = result.session_id;
    await page.keyboard.press('Enter');
    await screen(page, 'playing');
    assert.notEqual((await state(page)).session_id, previous, 'Replay creates a fresh run identity');
    assert.equal((await state(page)).stats.attempts, 0);
    assert(!(await state(page)).labels.SaveNotice, 'A fresh replay must not retain the previous run completion notice');
    return { completed_gates: 6, keyboard_only: true, replay_started: true, seed: result.seed };
  });

  const matrix = engineName === 'chromium' && !smokeOnly
    ? ['practice', 'classic', 'cadence'].flatMap((mode, pace) => ['addition', 'subtraction', 'multiplication', 'division', 'mixed'].map((operation, i) => ({ mode, operation, range: [5, 10, 12, 12, 10][i], pace })))
    : [{ mode: 'classic', operation: 'multiplication', range: 12, pace: 1 }, { mode: 'cadence', operation: 'division', range: 12, pace: 2 }];
  for (const fixture of matrix) {
    await checkCase(page, `complete-${fixture.mode}-${fixture.operation}`, async () => {
      const initial = await startRun(page, fixture);
      const result = await completeRun(page);
      assert.equal(result.result.completed, 6);
      assert.equal(result.result.first_try_correct, 6);
      assert.equal(result.result.first_try_opportunities, 6);
      assert.equal(result.result.accuracy, 1);
      assert.equal(result.save_error, '');
      assert(result.result.facts.every(f => f.correct && f.first_correct && !f.assisted));
      if (fixture.operation === 'division' || fixture.mode === 'cadence') await screenshot(page, `results-${fixture.mode}-${fixture.operation}`);
      return { gates: result.completed, attempts: result.result.attempts, seed: initial.seed, session_id: result.session_id };
    });
  }

  await checkCase(page, 'wrong-retry-hint-and-rapid-submission-evidence', async () => {
    await startRun(page, { mode: 'practice', operation: 'addition' });
    const question = (await state(page)).question;
    await enterAnswer(page, question.answer + 1, false, false);
    await screenshot(page, '06-wrong-answer');
    await enterAnswer(page, question.answer + 2, false, false);
    let s = await state(page);
    assert.equal(s.stats.first_try_opportunities, 1);
    assert.equal(s.stats.retries, 1);
    await page.keyboard.press('h');
    await shortWait(page);
    await screenshot(page, '07-hint');
    await enterAnswer(page, question.answer);
    await page.keyboard.press('Enter');
    await page.keyboard.press('Enter');
    await shortWait(page);
    s = await state(page);
    assert.equal(s.completed, 1);
    assert.equal(s.stats.first_try_opportunities, 1);
    assert.equal(s.stats.first_try_correct, 0);
    assert.equal(s.stats.attempts, 3);
    assert.equal(s.stats.retries, 2);
    assert.equal(s.stats.assisted, 1);
    const result = await completeRun(page);
    assert.equal(result.result.first_try_opportunities, 6);
    assert.equal(result.result.first_try_correct, 5);
    assert.equal(result.result.eventual_correct, 6);
    return { result: result.result };
  });

  await checkCase(page, 'pause-freezes-clock-course-and-answer-input', async () => {
    await startRun(page, { mode: 'classic', operation: 'subtraction', pace: 2 });
    await shortWait(page, 350);
    await page.keyboard.press('Escape');
    await screen(page, 'paused');
    await shortWait(page);
    const paused = await state(page);
    await screenshot(page, '08-paused');
    await page.keyboard.type('999');
    await shortWait(page);
    const frozen = await state(page);
    await shortWait(page, 1100);
    const later = await state(page);
    assert(Math.abs(later.elapsed - frozen.elapsed) < 0.03, 'Paused active session clock must stay still');
    assert(Math.abs(later.question_elapsed - frozen.question_elapsed) < 0.03, 'Paused response clock must stay still');
    assert.equal(later.course.scroll, frozen.course.scroll, 'Pause must freeze simulation');
    assert.equal(later.input, paused.input, 'Digits while paused must not enter an answer');
    assert.equal(later.stats.attempts, 0);
    await click(page, 'Resume');
    await screen(page, 'playing');
    await enterAnswer(page, (await state(page)).question.answer);
    assert.equal((await state(page)).stats.first_try_correct, 1);
    return { pause_interval_ms: 1100, active_time_drift_seconds: later.elapsed - frozen.elapsed, frozen_course: true };
  });

  await checkCase(page, 'browser-help-dialog-pauses-active-game', async () => {
    await startRun(page, { mode: 'classic', operation: 'addition', pace: 2 });
    // Focus the HTML help control explicitly; this verifies modal behavior,
    // not an untested browser-Tab traversal or screen-reader interaction.
    await page.locator('#help-button').focus();
    await page.keyboard.press('Enter');
    await page.locator('#help-dialog').waitFor({ state: 'visible' });
    await screen(page, 'paused');
    const paused = await state(page);
    await shortWait(page, 1200);
    const later = await state(page);
    assert(Math.abs(later.elapsed - paused.elapsed) < 0.03, 'Reading browser help must not consume active session time');
    assert(Math.abs(later.question_elapsed - paused.question_elapsed) < 0.03, 'Reading browser help must not consume the response deadline');
    assert.equal(later.course.scroll, paused.course.scroll);
    assert.equal(later.stats.timeouts, 0);
    await screenshot(page, '08-browser-help-paused');
    await page.locator('#close-help').click();
    await page.locator('#help-dialog').waitFor({ state: 'hidden' });
    assert.equal((await state(page)).screen, 'paused', 'Closing help keeps resume explicit');
    await click(page, 'Resume');
    await screen(page, 'playing');
    await enterAnswer(page, (await state(page)).question.answer);
    return { focus_setup: 'Explicit focus of the HTML help button', activation: 'Real Enter key', help_interval_ms: 1200, active_time_drift_seconds: later.elapsed - paused.elapsed, explicit_resume: true };
  });

  if (!smokeOnly && engineName === 'chromium') {
    await checkCase(page, 'long-session-and-result-json-download', async () => {
      await startRun(page, { mode: 'practice', operation: 'mixed', range: 12, target: 24 });
      const result = await completeRun(page);
      assert.equal(result.result.first_try_opportunities, 24);
      assert.equal(result.result.first_try_correct, 24);
      const downloadPromise = page.waitForEvent('download', { timeout: 15000 });
      await click(page, 'ExportResult');
      const download = await downloadPromise;
      const local = await download.path();
      assert(local, 'Browser must produce a real download');
      const exported = JSON.parse(await fs.readFile(local, 'utf8'));
      assert.equal(exported.session_id, result.session_id);
      assert.equal(exported.first_try_opportunities, 24);
      assert.equal(exported.eventual_correct, 24);
      await screenshot(page, 'results-long-session-export');
      return { gates: 24, downloaded_filename: download.suggestedFilename(), exported_session_id: exported.session_id, actual_download: true };
    });
    await checkCase(page, 'timed-out-gate-recovery-and-honest-response-time', async () => {
      await startRun(page, { mode: 'classic', operation: 'division', pace: 2 });
      await page.waitForFunction(() => window.ddState?.timed_out, undefined, { timeout: 15000 });
      let s = await state(page);
      assert.equal(s.stats.timeouts, 1);
      assert.equal(s.stats.first_try_opportunities, 1);
      assert.equal(s.stats.submitted_answers, 0);
      assert.equal(s.stats.response_samples, 0);
      await screenshot(page, '09-timeout');
      await shortWait(page, 1000);
      assert.equal((await state(page)).stats.timeouts, 1, 'Waiting cannot invent repeated timeout events');
      await enterAnswer(page, s.question.answer);
      s = await state(page);
      assert.equal(s.stats.first_try_correct, 0);
      assert.equal(s.stats.assisted, 1);
      assert.equal(s.stats.first_try_opportunities, 1);
      assert.equal(s.stats.submitted_answers, 1);
      assert(s.stats.mean_response_seconds < 4, 'Recovery latency must exclude elapsed timeout duration');
      const result = await completeRun(page);
      assert.equal(result.result.first_try_opportunities, 6);
      assert.equal(result.result.first_try_correct, 5);
      return { timeout_duration: result.result.facts[0].timeout_latencies, recovery_interval: result.result.facts[0].first_latency };
    });

    await checkCase(page, 'interrupted-save-reload-resume-and-completed-record', async () => {
      await startRun(page, { mode: 'practice', operation: 'multiplication' });
      await enterAnswer(page, (await state(page)).question.answer);
      await waitState(page, () => !window.ddState.gate_solved);
      await page.keyboard.type('12');
      await shortWait(page, 350);
      await page.keyboard.press('Escape');
      await screen(page, 'paused');
      await shortWait(page, 350);
      const before = await state(page);
      assert.equal(before.input, '12');
      await page.reload({ waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => !!window.ddState, undefined, { timeout: 90000 });
      await screen(page, 'menu');
      assert((await state(page)).controls.ResumeSaved, 'Interrupted run must offer explicit resume');
      await screenshot(page, '10-resume-menu');
      await click(page, 'ResumeSaved');
      await screen(page, 'paused');
      const restored = await state(page);
      assert.equal(restored.session_id, before.session_id);
      assert.equal(restored.input, '12');
      assert.equal(restored.completed, 1);
      assert.deepEqual(restored.stats, before.stats);
      assert(Math.abs(restored.question_elapsed - before.question_elapsed) < 0.25);
      await click(page, 'Resume');
      await page.keyboard.press('Backspace');
      await page.keyboard.press('Backspace');
      await shortWait(page);
      assert.equal((await state(page)).input, '');
      const result = await completeRun(page);
      assert.equal(result.result.first_try_opportunities, 6);
      assert.equal(result.save_error, '');
      await page.reload({ waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => window.ddState?.screen === 'menu', undefined, { timeout: 90000 });
      assert(!(await state(page)).controls.ResumeSaved, 'Durably completed run must not reappear as interrupted');
      await click(page, 'Progress');
      await screen(page, 'progress');
      await screenshot(page, '11-progress');
      return { resumed_session_id: before.session_id, typed_answer_restored_without_submission: true, completion_survives_reload: true };
    });

    await checkCase(page, 'learner-separation-and-settings-persistence', async () => {
      await startRun(page, { mode: 'practice', operation: 'addition' });
      await page.keyboard.type('7');
      await click(page, 'Pause');
      await click(page, 'SaveAndHome');
      await screen(page, 'menu');
      const firstSession = (await state(page)).session_id;
      await click(page, 'Settings');
      await screen(page, 'settings');
      await click(page, 'ReducedMotion');
      await click(page, 'Sound');
      await shortWait(page);
      assert.equal((await state(page)).reduced_motion, true);
      assert.equal((await state(page)).audio_enabled, false);
      await screenshot(page, '12-settings');
      await selectOption(page, 'LearnerProfile', 1);
      assert.equal((await state(page)).learner_id, 'player-2');
      await click(page, 'Home');
      assert(!(await state(page)).controls.ResumeSaved, 'Player 2 cannot resume Player 1');
      await startRun(page, { operation: 'division' });
      assert.equal((await state(page)).stats.attempts, 0);
      const secondSession = (await state(page)).session_id;
      assert.notEqual(secondSession, firstSession);
      await finishEarly(page);
      await home(page);
      await click(page, 'Settings');
      await selectOption(page, 'LearnerProfile', 0);
      assert.equal((await state(page)).learner_id, 'player-1');
      assert.equal((await state(page)).reduced_motion, true);
      assert.equal((await state(page)).audio_enabled, false);
      await click(page, 'Home');
      assert((await state(page)).controls.ResumeSaved);
      await click(page, 'ResumeSaved');
      assert.equal((await state(page)).session_id, firstSession);
      assert.equal((await state(page)).input, '7');
      return { separated_players: ['player-1', 'player-2'], saved_input_restored: true, reduced_motion_and_mute_retained: true };
    });

    await checkCase(page, 'short-viewport-scroll-and-zoom-equivalent-layout', async () => {
      await home(page);
      await page.setViewportSize({ width: 960, height: 420 });
      await shortWait(page, 350);
      assert.deepEqual((await state(page)).viewport, { w: 960, h: 420 }, 'Dynamic resize must reflow to the CSS viewport, not scale an old desktop layout');
      await screenshot(page, '13-short-menu');
      await click(page, 'Settings');
      await click(page, 'Home');
      await page.setViewportSize({ width: 720, height: 450 });
      await shortWait(page, 350);
      assert.deepEqual((await state(page)).viewport, { w: 720, h: 450 }, 'Zoom-equivalent footprint must use the new logical viewport');
      await startRun(page, { operation: 'subtraction' });
      await screenshot(page, '14-zoom-equivalent-game');
      const layout = await state(page);
      const canvas = await page.locator('#canvas').boundingBox();
      for (const id of ['SubmitAnswer', 'Pause', 'Jump']) {
        assert(layout.controls[id].w * canvas.width / layout.viewport.w >= 44, `${id} retains its minimum CSS width after resize`);
        assert(layout.controls[id].h * canvas.height / layout.viewport.h >= 44, `${id} retains its minimum CSS height after resize`);
      }
      await enterAnswer(page, (await state(page)).question.answer);
      await page.keyboard.press('Escape');
      await screen(page, 'paused');
      await screenshot(page, '15-short-paused');
      await click(page, 'FinishRun');
      assert.equal((await state(page)).screen, 'results');
      await page.setViewportSize({ width: 1440, height: 900 });
      await shortWait(page, 300);
      assert.deepEqual((await state(page)).viewport, { w: 1440, h: 900 }, 'Returning to desktop must restore desktop logical dimensions');
      return { short_viewport: [960, 420], css_viewport_equivalent_to_200_percent_zoom_on_1440x900: [720, 450], note: 'Viewport emulation verifies the layout footprint; it is not native browser-UI zoom.' };
    });

    await checkCase(page, 'performance-sample-and-practice-remains-untimed', async () => {
      await startRun(page, { mode: 'practice', operation: 'mixed' });
      const frames = await page.evaluate(() => new Promise(resolve => {
        const intervals = []; let previous = performance.now(); const start = previous;
        function sample(now) { intervals.push(now - previous); previous = now; if (now - start < 2500) requestAnimationFrame(sample); else resolve({ intervals, elapsed: now - start, heap_bytes: performance.memory?.usedJSHeapSize || null }); }
        requestAnimationFrame(sample);
      }));
      const sorted = frames.intervals.slice(2).sort((a, b) => a - b);
      const s = await state(page);
      assert.equal(s.timed_out, false);
      assert.equal(s.stats.first_try_opportunities, 0);
      await page.keyboard.press('Space');
      await shortWait(page, 250);
      assert((await state(page)).course.jumps > s.course.jumps, 'Manual jump input reaches the simulation');
      return { sample_duration_ms: frames.elapsed, rendered_frame_intervals: sorted.length, mean_frame_ms: sorted.reduce((a, b) => a + b, 0) / sorted.length, p95_frame_ms: sorted[Math.floor(sorted.length * .95)], heap_bytes: frames.heap_bytes, environment: 'headless Chromium, software WebGL on managed Linux' };
    });
  }
}

async function mobileScenario(browser) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, reducedMotion: 'reduce',
    ...(recordVideo ? { recordVideo: { dir: recordingRoot, size: { width: 390, height: 844 } } } : {}) });
  const page = await context.newPage();
  attachLogs(page, engineReport.logs);
  try {
    await load(page);
    await checkCase(page, 'mobile-touch-only-complete-session', async () => {
      assert.equal((await state(page)).reduced_motion, true, 'System reduced-motion preference honored');
      await screenshot(page, '16-mobile-menu');
      await startRun(page, { mode: 'practice', operation: 'addition', touch: true });
      await screenshot(page, '17-mobile-playing');
      const s = await state(page);
      const canvas = await page.locator('#canvas').boundingBox();
      for (const id of ['Digit0', 'Digit5', 'SubmitAnswer', 'Pause', 'Jump']) {
        const cssWidth = s.controls[id].w * canvas.width / s.viewport.w;
        const cssHeight = s.controls[id].h * canvas.height / s.viewport.h;
        assert(cssWidth >= 44 && cssHeight >= 44, `${id} must have a 44px CSS touch target; actual ${cssWidth.toFixed(1)}×${cssHeight.toFixed(1)}`);
      }
      await completeRun(page, true);
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const result = await state(page);
      assert.equal(result.result.completed, 6);
      assert.equal(result.result.first_try_correct, 6);
      assert.equal(result.save_error, '');
      for (const id of ['ResultDetails', 'ResultExplanation', 'ResultSave']) {
        const label = result.labels?.[id];
        assert(label?.visible, `${id} must be present in the visible results`);
        assert(label.x >= 0 && label.x + label.w <= result.viewport.w, `${id} must fit within the phone width`);
      }
      assert(result.labels.ResultDetails.y + result.labels.ResultDetails.h <= result.labels.ResultSave.y, 'Mobile summary must not overlap the save message');
      await screenshot(page, '18-mobile-results');
      await click(page, 'PlayAgain', true);
      assert.equal((await state(page)).screen, 'playing');
      return { viewport: [390, 844], godot_viewport: s.viewport, canvas_css_bounds: canvas, device_scale_factor: 2, touch_only_navigation_and_answers: true, completed_gates: 6 };
    });
  } finally {
    const video = page.video();
    await context.close();
    await preserveRecording(video, 'mobile-touch-playthrough');
  }
}

async function productionOffline(browser) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  const logs = { console: [], page_errors: [], failed_requests: [], http_errors: [] };
  attachLogs(page, logs);
  try {
    await load(page, false);
    assertNoRuntimeErrors(logs);
    await checkCase(page, 'production-qa-absence-and-offline-reload', async () => {
      assert.equal(await page.evaluate(() => typeof window.ddCommand), 'undefined');
      assert.equal(await page.evaluate(() => typeof window.ddState), 'undefined');
      await page.evaluate(() => navigator.serviceWorker.ready);
      await page.waitForFunction(() => !!navigator.serviceWorker.controller, undefined, { timeout: 20000 });
      await context.setOffline(true);
      await page.reload({ waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => window.ddPublicState?.screen === 'menu', undefined, { timeout: 90000 });
      await page.locator('#loading').waitFor({ state: 'detached', timeout: 90000 });
      await page.keyboard.press('Enter');
      await page.waitForFunction(() => window.ddPublicState?.screen === 'modes');
      await page.keyboard.press('Enter');
      await page.waitForFunction(() => window.ddPublicState?.screen === 'setup');
      await page.keyboard.press('Enter');
      await page.waitForFunction(() => window.ddPublicState?.screen === 'playing');
      const prompt = await page.evaluate(() => window.ddPublicState.question);
      const operands = prompt.match(/(\d+)\s*\+\s*(\d+)/);
      assert(operands, `Public readable math prompt: ${prompt}`);
      await page.keyboard.type(String(Number(operands[1]) + Number(operands[2])));
      await page.keyboard.press('Enter');
      await page.waitForFunction(() => window.ddPublicState?.completed === 1);
      await screenshot(page, '19-offline-play');
      await context.setOffline(false);
      // Network-first cache fallback is expected to encounter offline requests.
      // Engine, JavaScript and HTTP response errors remain release failures.
      assertNoRuntimeErrors(logs, true);
      return { qa_interface_absent: true, service_worker_controlled: true, offline_reload_and_answer: true, reconnect: true, expected_offline_network_failures: logs.failed_requests.length, logs };
    });
  } finally { await context.close(); }
}

async function blockedStorage(browser) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  // Explicit browser-storage fault fixture; no gameplay or evidence is injected.
  await context.addInitScript(() => {
    Storage.prototype.setItem = function () { throw new DOMException('Synthetic browser quota exhaustion', 'QuotaExceededError'); };
  });
  const page = await context.newPage();
  attachLogs(page, engineReport.logs);
  try {
    await load(page);
    await checkCase(page, 'blocked-browser-storage-is-visible-and-game-remains-playable', async () => {
      await startRun(page, { mode: 'practice', operation: 'addition' });
      assert.notEqual((await state(page)).save_error, '', 'Failed checkpoint must disclose storage failure');
      const result = await completeRun(page);
      assert.equal(result.result.eventual_correct, 6, 'Storage failure must not prevent gameplay completion');
      assert.notEqual(result.save_error, '', 'Failed completion must never report successful persistence');
      await screenshot(page, '20-storage-unavailable-results');
      const downloadPromise = page.waitForEvent('download', { timeout: 15000 });
      await click(page, 'ExportResult');
      const download = await downloadPromise;
      const exported = JSON.parse(await fs.readFile(await download.path(), 'utf8'));
      assert.equal(exported.eventual_correct, 6, 'Player can export valid unsaved results');
      return { fault: 'QuotaExceededError on Storage.setItem', gameplay_completed: true, visible_save_error: result.save_error, exported_unsaved_result: true };
    });
  } finally { await context.close(); }
}

for (const name of engines) {
  engineName = name;
  engineReport = { engine: name, status: 'running', scenarios: [], screenshots: [], recordings: [], logs: { console: [], page_errors: [], failed_requests: [], http_errors: [] } };
  report.engines.push(engineReport);
  const type = { chromium, firefox, webkit }[name];
  assert(type, `Unknown browser ${name}`);
  let browser;
  try {
    const headedFirefox = name === 'firefox' && process.env.DD_FIREFOX_HEADED === '1';
    engineReport.launch_configuration = { headless: !headedFirefox, virtual_display: headedFirefox, software_rendering: process.env.LIBGL_ALWAYS_SOFTWARE === '1' || name === 'chromium' };
    browser = await type.launch({ headless: !headedFirefox,
      ...(name === 'chromium' ? { args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] } : {}),
      ...(name === 'firefox' && headedFirefox ? { firefoxUserPrefs: { 'webgl.force-enabled': true, 'webgl.disabled': false, 'gfx.webrender.all': true, 'gfx.webrender.software': true } } : {}) });
  } catch (error) {
    engineReport.status = name === 'chromium' ? 'failed' : 'unavailable';
    engineReport.reason = error.message;
    if (name === 'chromium') failed = true;
    console.error(`${engineReport.status.toUpperCase()} ${name}: ${error.message.split('\n')[0]}`);
    continue;
  }
  try {
    engineReport.browser_version = browser.version();
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion: 'no-preference',
      ...(recordVideo && name === 'chromium' ? { recordVideo: { dir: recordingRoot, size: { width: 960, height: 600 } } } : {}) });
    const page = await context.newPage();
    attachLogs(page, engineReport.logs);
    activeCase = 'startup';
    engineReport.startup = await load(page);
    await desktopScenarios(browser, page);
    const video = page.video();
    await context.close();
    await preserveRecording(video, 'desktop-playthrough');
    if (!smokeOnly && name === 'chromium') {
      await mobileScenario(browser);
      await productionOffline(browser);
      await blockedStorage(browser);
    }
    const runtimeErrors = unexpectedRuntimeErrors(engineReport.logs);
    if (Object.values(runtimeErrors).some(errors => errors.length)) {
      engineReport.scenarios.push({ name: 'browser-runtime-and-resource-errors', status: 'failed', ...runtimeErrors });
      failed = true;
    } else engineReport.scenarios.push({ name: 'browser-runtime-and-resource-errors', status: 'passed' });
    engineReport.status = engineReport.scenarios.some(s => s.status === 'failed') ? 'failed' : 'passed';
  } catch (error) {
    const unsupported = name !== 'chromium' && /WebGL|graphics|Missing libraries|Host system is missing/i.test(error.message);
    engineReport.status = unsupported ? 'unavailable' : 'failed';
    engineReport.reason = error.message;
    if (!unsupported) failed = true;
    console.error(`${engineReport.status.toUpperCase()} ${name}: ${error.message}`);
  } finally { await browser.close(); }
}

report.finished_at = new Date().toISOString();
report.source_end = await sourceManifest();
report.build_manifest_end = JSON.parse(await fs.readFile('build/web/build-manifest.json', 'utf8'));
report.runtime_end = await runtimeManifest();
report.source_changed_during_run = report.source_start.sha256 !== report.source_end.sha256 || report.runtime_start.sha256 !== report.runtime_end.sha256;
if (report.source_changed_during_run) {
  failed = true;
  report.verification_error = 'Source or exported runtime changed during this run; it cannot verify an unchanged release.';
}
report.status = failed ? 'failed' : 'passed-with-explicit-platform-limitations';
if (!failed && report.engines.every(e => e.status === 'passed')) report.status = 'passed';
const output = path.join(reportRoot, `browser-${runId}.json`);
await fs.writeFile(output, JSON.stringify(report, null, 2) + '\n');
console.log(`BROWSER_REPORT ${output}`);
console.log(JSON.stringify({ status: report.status, engines: report.engines.map(e => ({ engine: e.engine, status: e.status, passed: e.scenarios.filter(s => s.status === 'passed').length, failed: e.scenarios.filter(s => s.status === 'failed').length, reason: e.reason })) }));
process.exitCode = failed ? 1 : 0;
