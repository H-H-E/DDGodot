#!/usr/bin/env node
/** Execute the original scheduler to generate cross-language parity fixtures.
 * Usage: node tools/generate_learning_fixtures.mjs /path/to/geometrymash
 * The original is read only. No network, credentials, model or paid service.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import vm from 'node:vm';

const sourceRoot = resolve(process.argv[2] || '../original');
const source = readFileSync(resolve(sourceRoot, 'public/game/learning/scheduler.js'), 'utf8');
const patterns = readFileSync(resolve(sourceRoot, 'public/game/patterns.js'), 'utf8');
const context = vm.createContext({ window: {} });
vm.runInContext(patterns, context);
vm.runInContext(source, context);
const { buildFactPool, createScheduler } = context.GMDLearning;
const classifyFact = (...args) => context.window.GMDPatterns.classifyFact(...args);
const random = (seed) => () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);
const scenarios = [];
for (const operation of ['addition', 'subtraction', 'multiplication', 'division', 'mixed']) {
  let now = 1700000000000;
  const scheduler = createScheduler({ classifyFact, random: random(73), now: () => now });
  scheduler.init(operation, 5);
  const initialSweep = [...scheduler.sweep];
  const trace = [];
  for (let i = 0; i < 120; i++) {
    now += 1000;
    const question = scheduler.next();
    const correct = i % 4 !== 0;
    const latency = (i % 7) + 0.5;
    scheduler.record(question, correct, latency);
    const key = `${question.a}${question.symbol}${question.b}`;
    trace.push({ key, correct, latency, now, stat: JSON.parse(JSON.stringify(scheduler.bucket[key])), tier: scheduler.tier(key), requeue: JSON.parse(JSON.stringify(scheduler.requeue)) });
  }
  scenarios.push({ operation, range: 5, seed: 73, initialSweep, trace });
}
const fixture = {
  source: { repository: 'H-H-E/geometrymash', commit: 'f43bf817e8dc20c554615a9fd39cb79585fab8c2', scheduler_sha256: createHash('sha256').update(source).digest('hex'), patterns_sha256: createHash('sha256').update(patterns).digest('hex') },
  note: 'Executed original JavaScript; no assisted responses in trace. Deliberate stricter assisted streak handling has its own regression test.',
  pool_counts: Object.fromEntries(['addition', 'subtraction', 'multiplication', 'division', 'mixed'].map(op => [op, buildFactPool(op, 20).length])),
  classification: buildFactPool('mixed', 5).map(f => ({ key: f.key, ...classifyFact(f.opType, f.a, f.b) })),
  scenarios,
};
const output = resolve('tests/fixtures/learning_original.json');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, JSON.stringify(fixture, null, 2) + '\n');
console.log(`Generated ${output}: ${scenarios.length * 120} executed original question/record traces.`);
