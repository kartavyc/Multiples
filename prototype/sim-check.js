#!/usr/bin/env node
/*
 * MULTIPLES — Economy sim-check.
 * Headless Monte-Carlo over the FROZEN Layer-1 formulas to answer ONE question:
 * is the 10x-per-tier net-worth curve winnable-but-tight with the proposed constants?
 *
 * It does NOT model cards/UI. It models the *math floor*: a player who only ever
 * reinvests cash into EBITDA at the round's reinvest efficiency, lightly levers,
 * rides sector multiples, and exits at tier end. If even a competent-but-plain
 * strategy can *just barely* clear the bars, the curve is tight-but-fair.
 */

// ---- FROZEN Layer-1 formulas -------------------------------------------------
const EV       = (ebitda, mult)            => ebitda * mult;
const equity   = (ev, netDebt)             => ev - netDebt;
const netWorth = (own, eq, cash)           => own * eq + cash;
const interest = (rate, netDebt)           => rate * netDebt;

// ---- Constants under test ----------------------------------------------------
const C = {
  startCash: 20_000,            // T1 seed cash, $
  startEbitda: 6_000,          // T1 starting annual EBITDA, $
  // tier bars (equity-value net-worth, $)
  tierBars: [1e6, 1e7, 1e8, 1e9],
  // deadline in rounds, per tier (first-pass)
  deadlineRounds: [8, 8, 9, 10],
  // sector multiple bands [base, vol(sd as frac of base)]
  sectors: {
    SOFTWARE:   { base: 14, vol: 0.30 },
    SERVICES:   { base: 5,  vol: 0.22 },
    RETAIL:     { base: 3,  vol: 0.10 },
    INDUSTRIAL: { base: 8,  vol: 0.12 },
  },
  // reinvest efficiency: $ of new annual EBITDA bought per $ cash reinvested.
  // decays high->low as the venture matures (forces lever-switching).
  reinvestStart: 0.55,
  reinvestEnd:   0.35,
  // interest band (annual, on net debt)
  interestMin: 0.08,
  interestMax: 0.14,
  // leverage: target net-debt/EBITDA the plain strategy carries
  targetLeverage: 3.0,
  dangerLeverage: 6.0,
  // operating organic EBITDA growth from operating partners, per round
  organicGrowth: 0.10,
  // fraction of EBITDA that converts to deployable cash each round
  cashYield: 0.35,
  // on clearing a tier the platform is largely cashed out / reset:
  // a fresh, *smaller* base carries so the next 10x bar is a real climb.
  carrySeedFrac: 0.24,
  // reseed uses a blended/normalized multiple so low-mult sectors aren't doomed.
  reseedMult: 8,
  // market drift: sticky bubble/crunch, 2-3 round states
  driftBubble: 1.35,   // multiple multiplier in a bubble
  driftCrunch: 0.75,   // multiple multiplier in a crunch
};

// ---- seeded RNG (mulberry32) so runs are reproducible ------------------------
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function gauss(r) {
  // Box-Muller
  let u = 0, v = 0;
  while (u === 0) u = r();
  while (v === 0) v = r();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

// market cycle: sticky states, readable a round ahead.
// returns {mult, rateMul, state}: crunch compresses multiples AND spikes interest.
function makeMarket(r) {
  let state = 'normal', left = 2 + Math.floor(r() * 2);
  return () => {
    if (left <= 0) {
      const roll = r();
      state = roll < 0.18 ? 'bubble' : roll < 0.36 ? 'crunch' : 'normal';
      left = 2 + Math.floor(r() * 2);
    }
    left--;
    if (state === 'bubble') return { mult: C.driftBubble, rateMul: 0.9, state };
    if (state === 'crunch') return { mult: C.driftCrunch, rateMul: 1.8, state };
    return { mult: 1.0, rateMul: 1.0, state };
  };
}

// reinvest efficiency by round-progress through a tier
function reinvestEff(progress) {
  return C.reinvestStart + (C.reinvestEnd - C.reinvestStart) * Math.min(1, progress);
}

// ---- one full run T1->T4 -----------------------------------------------------
// mode: 'plain' = math floor (target leverage), 'greedy' = max-lever into danger
function runOnce(seed, mode) {
  const r = rng(seed);
  const market = makeMarket(r);

  // single-platform plain strategy (the math floor)
  let ebitda = C.startEbitda;
  let netDebt = 0;
  let cash = C.startCash;
  let own = 1.0;            // bootstrapper, undiluted
  const sectorNames = Object.keys(C.sectors);
  const sector = C.sectors[sectorNames[Math.floor(r() * sectorNames.length)]];

  const tierLog = [];
  let bankrupt = false, missed = -1;

  for (let tier = 0; tier < 4; tier++) {
    const bar = C.tierBars[tier];
    const deadline = C.deadlineRounds[tier];
    let cleared = false;

    for (let round = 0; round < deadline; round++) {
      const progress = round / deadline;
      const mkt = market();   // sticky state known a round ahead

      // ---- OPERATE: organic EBITDA growth ----
      ebitda *= (1 + C.organicGrowth);

      // ---- pay interest in cash; bankrupt if cash < interest due ----
      const baseRate = C.interestMin + (C.interestMax - C.interestMin) * r();
      const rate = baseRate * mkt.rateMul;
      const intDue = interest(rate, netDebt);
      cash += ebitda * C.cashYield;
      if (cash < intDue) { bankrupt = true; break; }
      cash -= intDue;

      // ---- ACT: lever toward target, reinvest cash into EBITDA ----
      const lev = mode === 'greedy' ? C.dangerLeverage - 0.2 : C.targetLeverage;
      const targetDebt = ebitda * lev;
      if (netDebt < targetDebt && netDebt / Math.max(ebitda, 1) < C.dangerLeverage) {
        const draw = Math.min(targetDebt - netDebt, ebitda * 1.2);
        netDebt += draw; cash += draw;
      }
      // plain keeps a prudent interest buffer; greedy deploys everything (its undoing)
      const buffer = mode === 'greedy' ? 0 : interest(C.interestMax * 1.8, netDebt) * 1.5;
      const deploy = Math.max(0, cash - buffer);
      const eff = reinvestEff(progress);
      ebitda += deploy * eff;
      cash -= deploy;

      // ---- market reprices the multiple (same sticky state) ----
      const noisyMult = Math.max(1, sector.base * (1 + gauss(r) * sector.vol) * mkt.mult);

      // ---- mark-to-market net worth ----
      const nw = netWorth(own, equity(EV(ebitda, noisyMult), netDebt), cash);

      if (nw >= bar) {
        cleared = true;
        tierLog.push({ tier: tier + 1, round: round + 1, nw, ebitda, mult: noisyMult });
        // EXIT-AND-RESTART-BIGGER: cash out, reseed a smaller base for the next 10x climb.
        const seed = nw * C.carrySeedFrac;
        ebitda = seed / C.reseedMult;  // reseed at normalized multiple, not raw sector base
        netDebt = 0;
        cash = seed * 0.10;
        break;
      }
    }
    if (bankrupt) break;
    if (!cleared) { missed = tier + 1; break; }
  }

  const lastTier = tierLog.length;
  const avgGrowth = tierLog.length
    ? tierLog.reduce((s, t) => s + t.round, 0) / tierLog.length
    : 0;
  return {
    won: lastTier === 4 && !bankrupt && missed === -1,
    lastTier, bankrupt, missed, tierLog,
  };
}

// ---- Monte-Carlo -------------------------------------------------------------
const N = 5000;
let wins = 0, bankrupts = 0;
const missedAt = [0, 0, 0, 0, 0]; // index by tier (1..4)
const reachedTier = [0, 0, 0, 0, 0];
const clearRounds = [[], [], [], []];

for (let i = 1; i <= N; i++) {
  const res = runOnce(i * 2654435761 % 2147483647, 'plain');
  if (res.won) wins++;
  if (res.bankrupt) bankrupts++;
  if (res.missed > 0) missedAt[res.missed]++;
  reachedTier[res.lastTier]++;
  res.tierLog.forEach((t) => clearRounds[t.tier - 1].push(t.round));
}

// greedy over-lever pass: confirms greed is occasionally fatal (Pillar 4)
let gWins = 0, gBankrupts = 0;
for (let i = 1; i <= N; i++) {
  const res = runOnce(i * 2654435761 % 2147483647, 'greedy');
  if (res.won) gWins++;
  if (res.bankrupt) gBankrupts++;
}

const pct = (x) => (100 * x / N).toFixed(1) + '%';
const avg = (a) => a.length ? (a.reduce((s, x) => s + x, 0) / a.length).toFixed(1) : '-';
const med = (a) => { if (!a.length) return '-'; const s=[...a].sort((x,y)=>x-y); return s[Math.floor(s.length/2)]; };

console.log('=== MULTIPLES economy sim-check (N=' + N + ' seeded runs) ===');
console.log('Overall win rate (T1->T4):', pct(wins));
console.log('Bankruptcy rate          :', pct(bankrupts));
console.log('');
console.log('Tier | deadline | cleared% | avgRoundCleared | medRound');
for (let t = 0; t < 4; t++) {
  const cleared = clearRounds[t].length;
  console.log(
    ` T${t + 1}  |    ${C.deadlineRounds[t]}     |  ${pct(cleared)}  |       ${avg(clearRounds[t])}        |    ${med(clearRounds[t])}`
  );
}
console.log('');
console.log('Missed-deadline deaths by tier:',
  missedAt.slice(1).map((m, i) => `T${i + 1}=${pct(m)}`).join('  '));
console.log('');
// verdict: "winnable but tight" target band 12-35%
const wr = wins / N;
const verdict = wr < 0.08 ? 'TOO HARD (loosen bars/deadlines)'
  : wr > 0.45 ? 'TOO EASY (tighten)'
  : 'WINNABLE-BUT-TIGHT (in target band)';
console.log('VERDICT (plain math-floor):', verdict, '(' + pct(wins) + ')');
console.log('');
console.log('--- greedy over-lever pass (lever ~5.8x, into danger) ---');
console.log('Greedy win rate :', pct(gWins));
console.log('Greedy bankrupt :', pct(gBankrupts), '(greed must be occasionally fatal)');
