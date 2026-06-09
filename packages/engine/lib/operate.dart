/// The OPERATE step — `runOperate(state, rng, content)`. Executes doc 01
/// §6.1's exact order (mirrored by doc 02 §2 OPERATE and economy-model.json
/// `roundOrder`), with the deal-flow hand draw PREPENDED per doc 03 §3.1
/// step 1:
///
///   0a. expire stale consumable flags (doc 02 §2 OPERATE step 1, FIRST:
///       hotWindowArmed / marketReadHint past their flat-round expiry —
///       draw-free, so it sits before the hand draw without moving the
///       stream)
///   0b. deal-flow hand draw (doc 03 §3.1 step 1 — the round's 3-5 cards)
///   1. market roll (state machine + the round's live interest rate)
///   2. per-venture multiple drift (additive delta, floored at 1000 milli)
///   3. (a) partner engines accrue (+EBITDA onto each venture, pre-yield);
///      (b) cash yield in (EBITDA -> pocket cash; passive dampened);
///      (c) scheduled costs fire (the ScheduledCost list — partner fixed
///      costs etc.; doc 02 §2's scheduled-effects step, positioned at the
///      step-3c comment below)
///   4. neglect decay, then increment roundsNeglected for ALL ventures
///   5. event roll — one event card MAY fire and auto-resolve as deltas
///   6. charge interest; cash < 0 after the charge = BANKRUPTCY (F6)
///   then: phase -> ACT (or RUN_OVER), playsRemaining = playsPerRound(tier).
///
/// =========================================================================
/// THE DRAW-ORDER CONTRACT (doc 03 §3.1 — golden-tested; reordering, adding,
/// or removing ANY draw is STREAM-BREAKING and requires a new golden replay
/// file + a schemaVersion bump per docs/03 §6). The deal-flow routines'
/// own internals live in dealflow.dart's header; this header is how one
/// OPERATE composes them:
///
///   Per OPERATE, the run stream is consumed in EXACTLY this order:
///     0. THE HAND ROUTINE (dealflow.dart `drawHand` — the v5 contract) —
///        FIRST, before the market roll (doc 03 §3.1 lists "Deal Flow
///        draw" as step 1):
///          draw: nextInt(3)      — hand size = 3 + draw (3..5, clamped
///                                  to the pool)
///          draws x size: nextInt(remaining pool) — the no-replacement
///                                  walk over the tier's ACT pool (v5:
///                                  + partners; ventures filtered at full
///                                  slots — dealflow.dart header)
///          IF ventures exist (v5 exit-offer pair, dealflow.dart):
///          draw: nextInt(#ventures)   — the offered venture
///          draw: nextInt(301)         — the offer-band multiple
///        (Doc 02 §2 words the fresh hand as drawn on the DEADLINE_CHECK
///        advance; the draw lives HERE per doc 03's per-round order —
///        same effective timing, and DEADLINE_CHECK stays draw-free.)
///     a. IF the market state is at its boundary
///        (roundsInState >= stateDurationRounds):
///          draw 1: nextInt(100)  — next-state bucket
///                  (0..17 hot/bubble, 18..35 cold/crunch, 36..99 neutral;
///                   economy curves.driftModel.transitionAtBoundary
///                   {bubble: 0.18, crunch: 0.18, normal: 0.64})
///          draw 2: nextInt(2)    — new duration = 2 + draw (2..3 rounds;
///                   economy curves.driftModel.stateDurationRounds [2, 3])
///        (mid-state: ZERO draws here; roundsInState just ticks)
///     b. draw: nextInt(10000)    — the live-rate position u in the interest
///                  band (economy curves.interestBand.formula), AFTER any
///                  transition so the rate uses the NEW state's rateMul
///     c. per venture, IN `ventures` LIST ORDER (the deterministic order of
///        the per-venture jitter, part of this contract):
///          draw: nextInt(1000)   — u1 (permille uniform)
///          draw: nextInt(1000)   — u2 (permille uniform)
///        tri = u1 + u2 - 1000    (triangular in [-1000, 998] permille;
///                   economy curves.driftModel.perVentureJitter)
///     d. steps 3..4 (yield, decay) draw NOTHING.
///     e. THE EVENT ROLL (doc 01 §6.1 step 5 — after decay, before
///        interest. RECONCILIATION, documented: doc 03 §3.1 lists "Event
///        roll" as its step 3, right after market drift; doc 01 §6.1 and
///        economy-model.json roundOrder — the AUTHORITATIVE order per
///        CLAUDE.md — resolve event cards at step 5. The engine follows
///        doc 01: the roll sits at the long-documented step-5 hook):
///          draw: nextInt(100)    — fires when < kEventChancePct
///                                  (dealflow.dart; 25 = a TUNING DIAL)
///          IF fired and the tier's event pool is non-empty:
///          draw: nextInt(pool)   — picks the event card by pool index;
///                                  its deltas auto-resolve (dealflow.dart
///                                  `applyEventCard`) + EVENT_RESOLVED
///     f. step 6 (interest) draws NOTHING.
///
///   Total draws per OPERATE = (1 + handSize + (2 if ventures exist))
///     + (2 if boundary else 0) + 1 + 2 * #ventures + 1
///     + (1 if the event fired else 0).
/// =========================================================================
///
/// §7 note: drift, decay, EVENT CARDS, and interest are SYSTEM EVENTS that
/// mutate only the five inputs {ebitda, multiple, netDebt, own, cash}
/// (economy-model.json resolverInputs.systemEventsThroughResolver); market
/// state / phase / playsRemaining / roundsNeglected / hand are whitelisted
/// bookkeeping — never money — but ARE replay-relevant and golden-pinned.
///
/// Phase gate (doc 02 §2, strict since the round layer): `runOperate`
/// requires `phase == PhaseId.operate` and throws [StateError] from any
/// other phase — a step from the wrong phase is a caller bug, not a
/// rejection. The rest of the machine lives in round.dart (`endTurn`,
/// `runDeadlineCheck`). OPERATE never touches `round`/`tier` — advancing
/// those is DEADLINE_CHECK's job — and it snapshots `netWorthLastRound`
/// as its last act (doc 02 §2 step 9), on the bankrupt branch too.
///
/// All integer fixed-point math; fractions from economy-model.json are
/// integer num/den constants cited at their declarations. No `double`.
library;

import 'apply.dart' show GameEvent, GameEventType;
import 'content.dart';
import 'dealflow.dart';
import 'meta.dart' show backgroundFor;
import 'model.dart';
import 'resolver.dart';
import 'rng.dart';

// --- Market transition (economy curves.driftModel.transitionAtBoundary) ---

/// P(bubble) at a state boundary = 0.18 -> 18 of 100.
/// Source: economy-model.json curves.driftModel.transitionAtBoundary.bubble.
const int transitionHotPct = 18;

/// P(crunch) at a state boundary = 0.12 -> 12 of 100 (normal is the
/// remaining 70). Source: curves.driftModel.transitionAtBoundary.crunch.
/// *** R12 TUNE: 0.18 -> 0.12 *** — doc 01 §12 routes "exact crunch
/// durations and transition probabilities" to tuning ("tune so
/// death-by-market never reads as RNG"): with crunch entry at 0.18 a
/// 2-3-round crunch landed on most levered runs at least once and the
/// full-model §11.2 greedy pass bankrupted 22-25% (band [8,12]%). 0.12
/// keeps the crunch a real threat (greedy still dies ~1 run in 9) while
/// a prudent floor stays near 0. The hot bucket (0..17) is UNTOUCHED so
/// the golden's boundary draw maps identically; only the cold/neutral
/// split moved (cold 18..29, neutral 30..99).
const int transitionColdPct = 12;

/// Minimum sticky-state duration in rounds.
/// Source: economy-model.json curves.driftModel.stateDurationRounds = [2, 3].
const int stateDurationMinRounds = 2;

/// Maximum sticky-state duration in rounds (same source).
const int stateDurationMaxRounds = 3;

/// Maps a boundary-transition draw (`nextInt(100)`) to the next market
/// state. Bucket layout follows the JSON object's key order
/// {bubble, crunch, normal}: 0..17 hot, 18..35 cold, 36..99 neutral.
MarketTemp nextTempFromDraw(int bucket) {
  if (bucket < transitionHotPct) return MarketTemp.hot;
  if (bucket < transitionHotPct + transitionColdPct) return MarketTemp.cold;
  return MarketTemp.neutral;
}

// --- Live interest rate (economy curves.interestBand) ---

/// Scale of the one uniform rate draw: u = nextInt(10000) reads the band
/// position in basis-point granularity, the package's standard fraction
/// precision (u/10000 is the spec's U[0,1); 9999/10000 keeps the top
/// exclusive). Precision choice documented per the work order.
const int rateDrawScale = 10000;

/// Width of the normal interest band in bp: 1400 - 800 = 600.
/// Source: economy-model.json constants.interestMin 0.08 / interestMax 0.14
/// (the endpoints live in resolver.dart as interestMinBp/interestMaxBp).
const int interestSpanBp = interestMaxBp - interestMinBp;

/// The CRUNCH rate multiplier numerator over [rateMulDen]: 1.3 -> 130.
/// Source: economy-model.json curves.interestBand.crunch.rateMul (also
/// tuningKnobs.crunchRateMul).
/// *** R12 TUNE: 1.8 -> 1.3 *** — doc 01 §8's own dial ("driftCrunch /
/// crunch rateMul: tune so bankruptcy ≈ 8-12% for greedy play"): the
/// full-model harness measured §11.2 greedy bankruptcy at 22-25% under
/// the 1.8 crunch (a 2-3 round cold stretch billed up to 25.2% on
/// pace-levered debt — no 0.35-of-EBITDA yield survives that). At 1.3
/// the cold bill tops out at 15.6% (interestMax x 1.3), so the crunch
/// kills from ~2.2x leverage up instead of from ~1.4x — greed still dies
/// (11% measured, in band), prudence near-never does (0.2%).
/// round.dart's maxCrunchRateBp meter derives from this const.
const int rateMulColdNum = 130;

/// State rate multiplier numerator over [rateMulDen]: normal 1.0 -> 100,
/// bubble 0.9 -> 90, crunch 1.3 -> [rateMulColdNum].
/// Source: economy-model.json curves.interestBand.{normal,bubble,crunch}
/// .rateMul (crunch also via tuningKnobs.crunchRateMul).
int rateMulNum(MarketTemp temp) {
  switch (temp) {
    case MarketTemp.hot:
      return 90;
    case MarketTemp.neutral:
      return 100;
    case MarketTemp.cold:
      return rateMulColdNum;
  }
}

/// Denominator for [rateMulNum].
const int rateMulDen = 100;

/// The round's live interest rate in bp from one uniform draw [u] in
/// `[0, rateDrawScale)` under market state [temp].
///
/// Integer form of economy curves.interestBand.formula
/// `rate = (interestMin + (interestMax - interestMin) * U[0,1]) * rateMul`:
/// ```
/// baseBp = 800 + (600 * u) ~/ 10000        // in [800, 1399]
/// liveBp = (baseBp * rateMulNum) ~/ 100    // band stretched per state
/// ```
/// Divisions truncate toward zero and happen last in each factor.
int liveRateBpFromDraw(int u, MarketTemp temp) {
  final baseBp = interestMinBp + (interestSpanBp * u) ~/ rateDrawScale;
  return (baseBp * rateMulNum(temp)) ~/ rateMulDen;
}

// --- Multiple drift (economy curves.driftModel + formulas.driftDelta) ---

/// State drift factor in milli-units: normal 1.0 -> 1000, bubble 1.35 ->
/// 1350, crunch 0.75 -> 750.
/// Source: economy-model.json curves.driftModel.driftBubble = 1.35 /
/// driftCrunch = 0.75 (normal is the implicit 1.0 baseline).
int stateFactorMilli(MarketTemp temp) {
  switch (temp) {
    case MarketTemp.hot:
      return 1350;
    case MarketTemp.neutral:
      return 1000;
    case MarketTemp.cold:
      return 750;
  }
}

/// Per-sector drift volatility in permille: SOFTWARE 0.30 -> 300, SERVICES
/// 0.22 -> 220, RETAIL 0.10 -> 100, INDUSTRIAL 0.12 -> 120.
/// Source: economy-model.json sectors[].volatility.
int sectorVolMilli(Sector sector) {
  switch (sector) {
    case Sector.software:
      return 300;
    case Sector.services:
      return 220;
    case Sector.retail:
      return 100;
    case Sector.industrial:
      return 120;
    // Post-launch sectors (GDD §8 Q6): CONSUMER 0.15 -> 150 (steady, brand-y
    // mid-multiple); MEDIA 0.35 -> 350 (SOFTWARE++ — the highest vol, whips
    // hardest). Source: economy-model.json sectors[].volatility.
    case Sector.consumer:
      return 150;
    case Sector.media:
      return 350;
  }
}

/// Scale of each drift uniform: u1, u2 = nextInt(1000) read in permille, so
/// tri = u1 + u2 - 1000 is the spec's triangular [-1, 1] in permille
/// (discrete: [-1000, 998]). Permille per the work order; vol is permille
/// too, so vol*tri lands in micro-units exactly.
const int triDrawScale = 1000;

/// The additive drift delta in milli-units for one venture
/// (economy formulas.driftDelta:
/// `driftFactor = stateFactor * (1 + sectorVol * tri)`;
/// `delta = trunc(multiple * (driftFactor - 1))`).
///
/// Integer realization — ONE final division so no precision is lost to
/// intermediate truncation (documented precision choice):
/// ```
/// micro = 1_000_000 + volMilli * triMilli      // (1 + vol*tri) in micro
/// nano  = stateFactorMilli * micro - 1e9       // (driftFactor - 1) in nano
/// delta = (multipleMilli * nano) ~/ 1e9        // trunc toward zero, LAST
/// ```
/// 64-bit headroom: |multiple| < 1e6 milli and |nano| < 2e9 keep the product
/// under 2e15, far inside the int range. The caller applies the
/// `max(multipleFloorMilli, multiple + delta)` floor (economy
/// formulas.driftDelta / multipleStored).
int driftDeltaMilli({
  required int multipleMilli,
  required int stateFactorMilli,
  required int volMilli,
  required int triMilli,
}) {
  final micro = 1000000 + volMilli * triMilli;
  final nano = stateFactorMilli * micro - 1000000000;
  return (multipleMilli * nano) ~/ 1000000000;
}

// --- Cash yield (economy constants.cashYield; doc 01 §6.1 step 3) ---

/// EBITDA -> pocket-cash conversion = 0.35 -> 35/100.
/// Source: economy-model.json constants.cashYield = 0.35.
const int cashYieldNum = 35;

/// Denominator for the ACTIVE yield.
const int cashYieldDen = 100;

/// Denominator for the PASSIVE (Hire-CEO) yield: 35/200 = half the active
/// rate.
///
/// *** TUNING DIAL — NOT CANON. *** Doc 02 §4 names
/// `CASH_YIELD_BP_PASSIVE` as a spreadsheet-owned constant that
/// economy-model.json does NOT yet set. Until the model pins it, the engine
/// uses cashYield x 1/2, citing economy-model.json decay.passiveMultiplier
/// = 0.5 ("passive ventures decay at half rate and grow slower") as the
/// closest canon for the passive damp. When the spreadsheet lands a real
/// number, change THIS constant (and the goldens: that is economy-affecting
/// and stream-irrelevant but golden-pinned — version a new golden).
/// Logged in .claude/STATE.md.
const int cashYieldDenPassive = 200;

/// The cash this venture's EBITDA throws off this OPERATE, in cents:
/// `trunc(ebitda * 35/100)` active, `trunc(ebitda * 35/200)` passive
/// (doc 02 §2 ventureCashYield; passive dampening per §Q4 agency cost).
/// Partner engines accrue their +EBITDA at step 3a BEFORE this is called
/// (so the yield converts partner earnings too); this helper itself reads
/// whatever ebitda it is handed.
int cashYieldCents(int ebitdaCents, {required bool passive}) =>
    (ebitdaCents * cashYieldNum) ~/
    (passive ? cashYieldDenPassive : cashYieldDen);

// --- Organic growth (economy constants.organicGrowthDefault; doc 01 §3.2) ---

/// Default organic EBITDA growth = 0.20/round -> 20/100.
/// Source: economy-model.json constants.organicGrowthDefault = 0.20 (also
/// tuningKnobs.organicGrowthDefault: "raises floor without touching skill
/// ceiling"; parsed as EconomyConstants.organicGrowthDefaultBp = 2000).
/// Doc 01 §3.2: "EBITDA growth from the default starting operating
/// partner, applied as a system event (§2.1 path). NOT free engine drift:
/// it is attributed to the seed partner every run and to any hired
/// partner; a venture with no partner gets 0." The R12 balance harness
/// (tool/sim.dart) measured the floor at a 0.0% win rate without this —
/// the engine parsed the knob since Phase 2 but never applied it.
/// *** R12 TUNE: 0.10 -> 0.20 *** — knob #3 in the doc 01 §8 order,
/// turned AFTER carrySeedFrac and deadlineRounds: at 0.10 the §11.3
/// floor's reachable compounding (~1.27x/round: yield x reinvest eff +
/// organic + neutral drift) sits under EVERY tier's needed rate, so the
/// full-model floor won 4-7% (vs the JS calibration's ~1.45x/round and
/// 40%) — and the SAME shortfall put §11.2 greedy's steady-state
/// leverage (debt pace / growth surplus) at ~4.4x EBITDA, past the
/// yield-vs-interest breakeven, bankrupting 25% (band [8,12]%). One
/// growth dial closes both gaps; the skill ceiling (exits/merges/hires)
/// is untouched by construction. STREAM-BREAKING: golden v7 +
/// schemaVersion 7 (the VALUES move; draw order unchanged).
const int organicGrowthNum = 20;

/// Denominator for the ACTIVE organic growth rate.
const int organicGrowthDen = 100;

/// Denominator for the PASSIVE organic growth rate: 10/200 = half.
///
/// *** TUNING DIAL — NOT CANON. *** Doc 01 §7.8 only says passive organic
/// growth "is dampened" without a number; the engine halves it, citing
/// economy-model.json decay.passiveMultiplier = 0.5 ("passive ventures
/// decay at half rate and grow slower") — the cashYieldDenPassive
/// pattern. Logged in .claude/STATE.md.
const int organicGrowthDenPassive = 200;

/// Organic EBITDA growth this OPERATE for a PARTNERED venture, in cents:
/// `trunc(ebitda * 10/100)` active, `trunc(ebitda * 10/200)` passive.
/// The caller (step 3a) gates on `partners.isNotEmpty` — a venture with
/// no partner gets 0 (doc 01 §3.2 "NOT free engine drift").
int organicGrowthCents(int ebitdaCents, {required bool passive}) =>
    (ebitdaCents * organicGrowthNum) ~/
    (passive ? organicGrowthDenPassive : organicGrowthDen);

// --- Neglect decay (economy decay; doc 01 §7.8) ---

/// EBITDA decay numerators by min(roundsNeglected, 3), index rounds-1:
/// 4% / 8% / 15%. Source: economy-model.json decay.byNeglect[].ebitdaRate
/// = [0.04, 0.08, 0.15] (also tuningKnobs.decayRate).
const List<int> neglectEbitdaNum = [4, 8, 15];

/// Multiple decay numerators by min(roundsNeglected, 3): 0% / 3% / 6%.
/// Source: economy-model.json decay.byNeglect[].multRate = [0.0, 0.03, 0.06].
const List<int> neglectMultipleNum = [0, 3, 6];

/// Denominator for ACTIVE decay rates.
const int neglectDen = 100;

/// Denominator for PASSIVE decay rates: the rates are HALVED
/// (x/200 == (x/100) * 0.5). Source: economy-model.json
/// decay.passiveMultiplier = 0.5.
const int neglectDenPassive = 200;

int _neglectIndex(int roundsNeglected) =>
    (roundsNeglected > 3 ? 3 : roundsNeglected) - 1;

/// EBITDA lost to neglect this OPERATE, in cents:
/// `trunc(ebitda * rate[min(n, 3)])`, halved for passive; 0 when the
/// venture was attended (n < 1). Source: economy-model.json formulas.decay.
int neglectEbitdaLossCents(int ebitdaCents, int roundsNeglected,
    {required bool passive}) {
  if (roundsNeglected < 1) return 0;
  return (ebitdaCents * neglectEbitdaNum[_neglectIndex(roundsNeglected)]) ~/
      (passive ? neglectDenPassive : neglectDen);
}

/// Multiple lost to neglect this OPERATE, in milli-units:
/// `trunc(multiple * multRate[min(n, 3)])`, halved for passive; 0 when
/// attended. The caller clamps the result at the 1000-milli live-venture
/// floor (economy resolverInputs.clamps).
int neglectMultipleLossMilli(int multipleMilli, int roundsNeglected,
    {required bool passive}) {
  if (roundsNeglected < 1) return 0;
  return (multipleMilli * neglectMultipleNum[_neglectIndex(roundsNeglected)]) ~/
      (passive ? neglectDenPassive : neglectDen);
}

// --- Plays grant (doc 02 §3 PLAYS/SLOTS table) ---

/// Throughput granted per round: T1 2, T2 3, T3 3 (v1 ships 3; the 3-vs-4
/// question is doc 02 §6 OPEN), T4 4, T5/endless 4.
/// Source: doc 02 §3 `playsPerRound` {1:2, 2:3, 3:3, 4:4, 5:4}.
int playsPerRound(int tier) {
  switch (tier) {
    case 1:
      return 2;
    case 2:
    case 3:
      return 3;
    case 4:
    case 5:
      return 4;
    default:
      throw ArgumentError.value(tier, 'tier', 'must be 1..5');
  }
}

/// The plays granted at the start of a round for [tier], HONORING the founder
/// background's per-round perk (schemaVersion 9): `playsPerRound(tier)` plus
/// the background's [FounderBackground.extraPlaysPerRound] — the DEALMAKER's
/// +1 (meta.dart §Q7). The dial has always lived on the background; the grant
/// was the R14-deferred piece because the round layer couldn't see the
/// background until GameState carried [GameState.backgroundId] (this round).
/// runOperate stages the per-round grant; runDeadlineCheck / _clearTier
/// re-stage it on every round/tier advance — all three call THIS so the +1
/// is honored uniformly. A dead/won run still gets 0 (the callers gate that).
int playsGrantedForRound(int tier, String backgroundId) =>
    playsPerRound(tier) + backgroundFor(backgroundId).extraPlaysPerRound;

/// The result of [runOperate]: the next immutable state plus the events the
/// step produced (unmodifiable). Event order is deterministic:
/// [market change?] then [neglect decay, ventures order] then
/// [EVENT_RESOLVED?] then [interest charged?] then [bankruptcy?].
class OperateResult {
  /// Builds an [OperateResult]; [events] is copied unmodifiable.
  OperateResult({required this.state, required List<GameEvent> events})
      : events = List.unmodifiable(events);

  /// The state after the OPERATE step.
  final GameState state;

  /// What happened, for the UI to animate. Never persisted.
  final List<GameEvent> events;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OperateResult || other.state != state) return false;
    if (other.events.length != events.length) return false;
    for (var i = 0; i < events.length; i++) {
      if (other.events[i] != events[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(state, Object.hashAll(events));

  @override
  String toString() => 'OperateResult(state: $state, events: $events)';
}

/// Runs one OPERATE step (doc 01 §6.1; header of this file = the draw-order
/// contract). Throws [StateError] unless `phase == PhaseId.operate` (the
/// doc 02 §2 strict machine) — a step from the wrong phase, including a
/// dead run, is a caller bug, not a rejection.
OperateResult runOperate(
    GameState state, SplitMix64Rng rng, ContentDb content) {
  if (state.phase != PhaseId.operate) {
    throw StateError('runOperate requires phase == PhaseId.operate '
        '(doc 02 §2 strict machine); was ${state.phase}');
  }
  final events = <GameEvent>[];

  // --- Doc 02 §2 OPERATE step 1: expire stale consumable flags FIRST ---
  // (before anything else — "no flag persists silently"; doc 02 §5.2 #7's
  // flag-lifetime guarantee). DRAW-FREE, so its position relative to the
  // hand draw cannot move the stream. An armed flag expires once the
  // current flat round is PAST its expiry (arm in round r -> usable for
  // the rest of r and all of r+1 -> swept here in r+2 if never consumed).
  var market = state.market;
  final flat = flatRoundOf(state);
  if (market.hotWindowExpiresRound >= 0 &&
      flat > market.hotWindowExpiresRound) {
    market =
        market.copyWith(hotWindowArmed: false, hotWindowExpiresRound: -1);
    events.add(const GameEvent(type: GameEventType.hotWindowExpired));
  }
  if (market.marketReadExpiresRound >= 0 &&
      flat > market.marketReadExpiresRound) {
    // Doc 02 §2 step 1 names no event for the read expiry; it clears
    // silently (the hint simply stops being shown).
    market = market.copyWith(
        clearMarketReadHint: true, marketReadExpiresRound: -1);
  }

  // --- Step 0: the deal-flow hand draw, FIRST (doc 03 §3.1 step 1) ---
  // Drawn unconditionally — even a run that goes bankrupt at step 6 drew
  // its hand at step 0 (the draw order is fixed; F6 is decided later).
  state = drawHand(state, rng, content);

  // --- Step 1a: market state machine (draws only at a boundary) ---
  if (market.roundsInState >= market.stateDurationRounds) {
    final bucket = rng.nextInt(100); // contract draw a.1
    final newTemp = nextTempFromDraw(bucket);
    final duration = stateDurationMinRounds +
        rng.nextInt(stateDurationMaxRounds - stateDurationMinRounds + 1);
    if (newTemp != market.temp) {
      // A same-temp redraw restarts the clock but is not a CHANGE; the UI
      // banner only cares when the weather actually turns.
      events.add(GameEvent(
        type: GameEventType.marketStateChanged,
        amount: duration,
        reason: 'market_now_${newTemp.name}',
      ));
    }
    market = market.copyWith(
      temp: newTemp,
      roundsInState: 1, // this OPERATE is the new state's first round
      stateDurationRounds: duration,
    );
  } else {
    market = market.copyWith(roundsInState: market.roundsInState + 1);
  }

  // --- Step 1b: the round's live interest rate (always one draw) ---
  final rateU = rng.nextInt(rateDrawScale); // contract draw b
  market = market.copyWith(liveRateBp: liveRateBpFromDraw(rateU, market.temp));

  // --- Step 2: per-venture drift delta, ventures list order ---
  final factorMilli = stateFactorMilli(market.temp);
  var ventures = <Venture>[];
  for (final v in state.ventures) {
    final u1 = rng.nextInt(triDrawScale); // contract draw c (u1)
    final u2 = rng.nextInt(triDrawScale); // contract draw c (u2)
    final delta = driftDeltaMilli(
      multipleMilli: v.multipleMilli,
      stateFactorMilli: factorMilli,
      volMilli: sectorVolMilli(v.sector),
      triMilli: u1 + u2 - triDrawScale,
    );
    var multiple = v.multipleMilli + delta;
    if (multiple < multipleFloorMilli) multiple = multipleFloorMilli;
    ventures.add(v.copyWith(multipleMilli: multiple));
  }

  // --- Step 3a: partner engines accrue (+EBITDA lands PRE-yield) ---
  // Doc 02 §2 step 4 resolves partner perRound deltas "via ventureCashYield";
  // its §3.5 prose calls the partner an ORGANIC COMPOUNDER ("a permanent
  // +EBITDA engine every round"). Engine decision (model.dart PartnerEngine
  // documents it): the +EBITDA ACCRUES onto the venture's stored ebitda each
  // OPERATE — landing BEFORE the yield so this round's yield converts the
  // partner earnings too (which also satisfies the pseudocode's grossEbitda
  // = ebitda + partnerEbitda for the yield read). Draw-free.
  //
  // ORGANIC GROWTH (doc 01 §3.2 / §6.1 step 3 "+ partner engines, incl.
  // organicGrowthDefault EBITDA bumps"; landed in the R12 balance round):
  // a PARTNERED venture also grows trunc(ebitda x 10/100) of its PRE-accrual
  // EBITDA each OPERATE (halved passive — organicGrowthCents). Attribution,
  // not free drift: partnerless ventures get nothing; initRun attaches the
  // FOUNDING OPERATOR (a 0-face engine, init.dart) to the seed venture so
  // every run compounds out of the gate, per §3.2's "attributed to the seed
  // partner every run". Draw-free.
  ventures = [
    for (final v in ventures)
      v.partners.isEmpty
          ? v
          : v.copyWith(
              ebitdaCents: v.ebitdaCents +
                  organicGrowthCents(v.ebitdaCents, passive: v.passive) +
                  v.partners.fold(0, (s, p) => s + p.perRoundEbitdaCents)),
  ];

  // --- Step 3b: cash yield in (on PRE-decay EBITDA; step 3 before step 4) ---
  var cash = state.cashCents;
  for (final v in ventures) {
    cash += cashYieldCents(v.ebitdaCents, passive: v.passive);
  }

  // --- Step 3c: scheduled costs fire (the minimal ScheduledCost list) ---
  // POSITION DECISION (documented per the work order): doc 01 §6.1 /
  // economy-model roundOrder have no scheduled-effects step; doc 02 §2's
  // expanded machine resolves them at ITS step 5 — immediately after the
  // yield step and before decay. The engine resolves the minimal list HERE,
  // alongside yield (after the inflow, before decay/events/interest), which
  // is doc 02's relative position expressed inside doc 01 §6.1's step 3.
  // A negative entry can push cash below zero mid-OPERATE; F6 still only
  // fires at step 6 (doc 02 §2 ACT note: deferred negatives land in OPERATE,
  // where bankruptcy is a legal telegraphed outcome). Lifetime: an entry
  // tied to a venture that has left play is DROPPED without firing (doc 02
  // §2 step 5: recurring entries persist while the partner exists);
  // non-recurring entries fire once and are removed. Draw-free.
  var scheduled = state.scheduled;
  if (scheduled.isNotEmpty) {
    final kept = <ScheduledCost>[];
    for (final e in scheduled) {
      if (e.ventureId != null && !ventures.any((v) => v.id == e.ventureId)) {
        continue; // orphaned by an exit — dies with its venture, no charge
      }
      // TWO BASES (schemaVersion 10): a FIXED entry charges its flat
      // cashDeltaCents; a PCT_EBITDA entry (EARN_OUT) charges
      // -trunc(target.ebitda x pctEbitdaBp / 10000) against the target's
      // POST-accrual/PRE-decay EBITDA (the live earnings this round threw
      // off — the same base the yield read). A run-level (null target)
      // entry is always FIXED (a PCT entry needs a target; the constructor
      // contract). Divisions last.
      final int charge;
      if (e.pctEbitdaBp > 0) {
        final v = ventures.firstWhere((v) => v.id == e.ventureId);
        charge = -((v.ebitdaCents * e.pctEbitdaBp) ~/ bpScale);
      } else {
        charge = e.cashDeltaCents;
      }
      cash += charge;
      events.add(GameEvent(
        type: GameEventType.scheduledEffectFired,
        amount: charge,
        ventureId: e.ventureId,
      ));
      // LIFETIME: a countdown (roundsLeft > 0) decrements and is kept only
      // while it has fires left; the sentinel (roundsLeft < 0) lives until
      // its venture leaves play (a recurring partner fixed cost). A
      // non-recurring, non-countdown entry fires once and is dropped.
      if (e.roundsLeft > 0) {
        final left = e.roundsLeft - 1;
        if (left > 0) kept.add(e.copyWith(roundsLeft: left));
      } else if (e.recurring) {
        kept.add(e);
      }
    }
    scheduled = kept;
  }

  // --- Step 4: neglect decay, then increment roundsNeglected for ALL ---
  ventures = [
    for (final v in ventures) _decayed(v, events),
  ];

  // --- Step 5: the event roll (doc 01 §6.1 step 5; header step e) ---
  // The long-documented hook, now live: one chance roll every OPERATE;
  // when it fires, one event card auto-resolves as five-input deltas
  // (dealflow.applyEventCard) against the ventures-as-of-after-decay and
  // the cash-as-of-after-yield. A (post-slice) negative-cash event lands
  // BEFORE the F6 check at step 6, consistent with doc 01 §6.1's order.
  final eventRoll = rng.nextInt(100); // contract draw e.1
  if (eventRoll < kEventChancePct) {
    final pool = eventPool(content, state.tier,
        unlockedCardIds: state.unlockedCardIds.toSet(),
        unlockedSectors: state.unlockedSectors.toSet());
    if (pool.isNotEmpty) {
      final card = pool[rng.nextInt(pool.length)]; // contract draw e.2
      final resolved =
          applyEventCard(ventures: ventures, cashCents: cash, card: card);
      ventures = resolved.ventures;
      cash = resolved.cashCents;
      events.add(GameEvent(
        type: GameEventType.eventResolved,
        reason: card.id, // the UI looks the face up by id
      ));
    }
  }

  // --- Step 6: charge interest; F6 bankruptcy strictly below zero ---
  var totalNetDebt = 0;
  for (final v in ventures) {
    totalNetDebt += v.netDebtCents;
  }
  // F4 sums net debt FIRST, one trunc on the total (resolver.interestDue).
  final interest = interestDue(market.liveRateBp, totalNetDebt);
  cash -= interest;
  if (interest > 0) {
    events.add(GameEvent(
      type: GameEventType.interestCharged,
      amount: interest,
    ));
  }

  final bankrupt = cash < 0; // F6: cash is NOT clamped; negative IS the death
  if (bankrupt) {
    events.add(GameEvent(
      type: GameEventType.bankruptcy,
      amount: cash, // the (negative) post-charge deficit
      reason: 'cash_below_zero_after_interest',
    ));
  }

  // --- Doc 02 §2 step 9: snapshot netWorthLastRound AFTER all the above ---
  // Engine decision (documented): the snapshot is taken on the bankrupt
  // branch too — `netWorthLastRound` always means "net worth at the end of
  // the most recent OPERATE", which the autopsy can quote.
  final next = state.copyWith(
    ventures: ventures,
    cashCents: cash,
    scheduled: scheduled,
    market: market,
    phase: bankrupt ? PhaseId.runOver : PhaseId.act,
    // Honor the founder background's per-round perk (the Dealmaker +1;
    // schemaVersion 9). A bankrupt run gets 0.
    playsRemaining:
        bankrupt ? 0 : playsGrantedForRound(state.tier, state.backgroundId),
    netWorthLastRound: netWorth(ventures, cash),
    death: bankrupt ? DeathCause.bankruptcy : null, // null = keep (alive)
    rngCursor: rng.cursor, // reconcile the bookkeeping mirror to the stream
  );
  return OperateResult(state: next, events: events);
}

/// Applies step 4 to one venture: decay if neglected (emitting
/// NEGLECT_DECAY when anything was actually lost), then increment the
/// counter. The multiple write clamps at the 1000-milli live-venture floor
/// (economy resolverInputs.clamps).
Venture _decayed(Venture v, List<GameEvent> events) {
  if (v.roundsNeglected < 1) {
    return v.copyWith(roundsNeglected: v.roundsNeglected + 1);
  }
  final ebitdaLoss =
      neglectEbitdaLossCents(v.ebitdaCents, v.roundsNeglected,
          passive: v.passive);
  final multipleLoss =
      neglectMultipleLossMilli(v.multipleMilli, v.roundsNeglected,
          passive: v.passive);
  var multiple = v.multipleMilli - multipleLoss;
  if (multiple < multipleFloorMilli) multiple = multipleFloorMilli;
  if (ebitdaLoss > 0 || multipleLoss > 0) {
    events.add(GameEvent(
      type: GameEventType.neglectDecay,
      amount: -ebitdaLoss, // headline = the signed ebitda delta
      ventureId: v.id,
    ));
  }
  return v.copyWith(
    ebitdaCents: v.ebitdaCents - ebitdaLoss,
    multipleMilli: multiple,
    roundsNeglected: v.roundsNeglected + 1,
  );
}
