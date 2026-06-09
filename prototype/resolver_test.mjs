// Runnable Node mirror of prototype/resolver.dart — proves the Layer-1 math and
// the §7 invariant against the real data files. Run: node prototype/resolver_test.mjs
import fs from 'node:fs';

const trunc = (a, b) => Math.trunc(a / b);
const EV = (ebitda, mult) => trunc(ebitda * mult, 1000);
const equity = (ebitda, mult, netDebt) => EV(ebitda, mult) - netDebt;
const netWorth = (ventures, cash) =>
  ventures.reduce((s, v) => s + trunc(v.own * equity(v.ebitda, v.mult, v.netDebt), 10000), cash);
const interest = (rateBp, debt) => trunc(rateBp * debt, 10000);
const dilute = (oldOwn, preMoney, raise) => trunc(oldOwn * preMoney, preMoney + raise);

const ALLOWED = new Set(['ebitda', 'multiple', 'netDebt', 'own', 'cash']);
let pass = 0, fail = 0;
const ok = (name, cond) => { (cond ? pass++ : fail++); console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}`); };

const econ = JSON.parse(fs.readFileSync(new URL('../data/economy-model.json', import.meta.url)));
const cards = JSON.parse(fs.readFileSync(new URL('../data/cards.json', import.meta.url)));
const C = econ.constants;

// --- 1. Seed net worth must equal $56,000 (5,600,000 cents) per economy-model note ---
const seed = [{ ebitda: C.startEbitda, mult: C.startMultiple, netDebt: C.startNetDebt, own: C.startOwnership }];
const seedNW = netWorth(seed, C.startCash);
ok(`seed NetWorth == $56,000  (got $${(seedNW / 100).toLocaleString('en-US')})`, seedNW === 5_600_000);

// --- 2. Tier bars are in cents and label-consistent ($1M..$1B) ---
const labels = { 1: 1_00000000, 2: 10_00000000, 3: 100_00000000, 4: 1000_00000000 };
for (const tb of econ.tierBars)
  ok(`tier ${tb.tier} bar == ${tb.barDisplay} in cents`, tb.bar === labels[tb.tier]);

// --- 3. T1 growth from seed to bar matches the stated multiple (~17.9x) ---
const t1x = labels[1] / seedNW;
ok(`T1 climb ~17.9x  (got ${t1x.toFixed(1)}x)`, Math.abs(t1x - 17.9) < 0.5);

// --- 4. §7 invariant: every card delta uses only the five inputs ---
let bad = [];
for (const c of cards) for (const k of Object.keys(c.deltas || {})) if (!ALLOWED.has(k)) bad.push(`${c.id}:${k}`);
ok(`all ${cards.length} cards obey §7 invariant`, bad.length === 0);
if (bad.length) console.log('   offenders:', bad.join(', '));

// --- 5. Dilution shrinks the slice; interest scales with debt; both directional ---
ok('raise dilutes owner (80% -> <80%)', dilute(8000, 5_600_000, 2_000_000) < 8000);
ok('zero debt => zero interest', interest(1200, 0) === 0);
ok('more debt => more interest', interest(1200, 10_000_000) > interest(1200, 1_000_000));

// --- 6. Arbitrage is accretive: cheap EBITDA inside an expensive wrapper gains value ---
const buyVal = EV(100000, 5000);          // bought at 5.0x
const platformVal = EV(100000, 14000);    // revalued at 14.0x
ok('multiple arbitrage is accretive', platformVal > buyVal);

console.log(`\n${fail === 0 ? 'ALL GREEN' : 'FAILURES'}: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
