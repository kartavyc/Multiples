/// Layer-1 FROZEN formulas (F1..F6) — the deterministic, integer fixed-point
/// rules core the rest of the engine sits on top of.
///
/// Ported faithfully from the vetted prototype (`prototype/resolver.dart` and
/// the GREEN `prototype/resolver_test.mjs`), re-expressed against the real model
/// types in `package:engine/model.dart`. The formula text is mirrored from
/// `data/economy-model.json` ("formulas" / "constants" blocks), which is the
/// authoritative source.
///
/// LOCKED fixed-point conventions (no `double` anywhere in this package):
/// - money     : integer **cents**            ($1.00 = 100)
/// - multiple  : milli-units x1000            (14.0x  = 14000)  -> `multipleMilli`
/// - ownership : basis points x10000          (80%    = 8000)   -> `ownershipBp`
/// Rounding: truncate toward zero (`~/`) on every fixed-point multiply/divide;
/// do the bp/milli divisions LAST.
///
/// Fractions in `economy-model.json` (e.g. `0.20`, `0.08`) are applied here as
/// integer numerator/denominator pairs (see the named constants below) so the
/// math is exact and deterministic across iOS/Android.
///
/// Pure and dependency-free except for the model types + the sibling money
/// helpers (only `dart:core` transitively).
library;

import 'model.dart';
import 'money.dart' show satMul;

// --- Fixed-point scales (mirror model.dart / economy-model.json fixedPoint) ---

/// Milli-unit scale for multiples (14x = 14000). Divide by this LAST.
const int milliScale = 1000;

/// Basis-point scale for ownership (100% = 10000). Divide by this LAST.
const int bpScale = 10000;

// --- Synergy / conglomerate constants, as integer num/den from the JSON ---

/// Same-sector EBITDA synergy = +20%.
/// Source: economy-model.json constants.synergySameSector = 0.20
/// (also synergyAndConglomerate.sameSector.ebitdaBonus = 0.20).
/// Applied as `addon.ebitda * synergyNum ~/ synergyDen`.
const int synergyNum = 20;
const int synergyDen = 100;

/// Conglomerate (cross-sector) multiple drag = -8% per add-on, applied as a
/// positive magnitude: `multiple = multiple * (1 - 0.08)` = `* 92 / 100`.
/// Source: economy-model.json constants.congDiscountPerAddon = 0.08
/// (synergyAndConglomerate.crossSector.multipleDragPerAddon = 0.08, stacks
/// multiplicatively as 0.92^n).
const int congKeepNum = 92; // 100 - 8
const int congKeepDen = 100;

/// Live-venture multiple floor in milli-units (1.0x). A stored multiple never
/// goes below this: market drift floors here explicitly
/// (economy-model.json formulas.driftDelta `max(1000, ...)`) and the same
/// state clamp applies to every other multiple write
/// (economy-model.json resolverInputs.clamps: "multiple >= 1000 (1.0x) for a
/// live venture"). The Layer-1 congDrag helper below stays a faithful formula
/// mirror (no floor in its formula text); the clamp is applied at the apply
/// site, where venture state is actually written.
const int multipleFloorMilli = 1000;

// --- Reinvest decay curve (economy-model.json curves.reinvestDecay) ---

/// Reinvest efficiency at tier entry.
/// Source: economy-model.json constants.reinvestStart = 0.55 -> 5500 bp.
const int reinvestStartBp = 5500;

/// Reinvest efficiency floor (fully decayed at/after the tier deadline).
/// Source: economy-model.json constants.reinvestEnd = 0.35 -> 3500 bp.
const int reinvestFloorBp = 3500;

/// Total decay span: (0.55 - 0.35) = 0.20 -> 2000 bp.
const int reinvestSpanBp = reinvestStartBp - reinvestFloorBp;

/// Deadline rounds per tier, T1..T4.
/// Source: economy-model.json tierBars.deadlineRounds = [9, 10, 9, 10]
/// (also tuningKnobs.deadlineRounds). Tier 5 (endless) has no deadline;
/// [reinvestEfficiencyBp] treats it as fully decayed and never calls this.
/// *** R12 TUNE: T1 8 -> 9, T2 8 -> 10 *** — doc 01 §8's own trigger
/// ("T2 is the squeeze; loosen here first if floor death-rate >40%")
/// fired: the full-model harness measured the §11.3 floor's T2
/// missed-deadline rate at 42.4% (and doc 01 §12 names the T2 deadline
/// the first candidate to loosen). T1 8 -> 9 came later in the pass, for
/// FEEL: even after the growth-side knobs the 8-round T1 killed ~26% of
/// floor runs and ~45% of designed-play (smart-policy) runs in the
/// TUTORIAL tier — the playtest's "rubbish runs" complaint, measured.
/// At 9 the §3.1 on-ramp demand eases 1.43x -> 1.38x/round and T1
/// missed-deadline drops to ~18% floor / ~31% smart.
int tierDeadlineRounds(int tier) {
  switch (tier) {
    case 1:
      return 9;
    case 2:
    case 4:
      return 10;
    case 3:
      return 9;
    default:
      throw ArgumentError.value(tier, 'tier', 'must be 1..4 (T5 is endless)');
  }
}

/// Reinvest efficiency in basis points for the 1-based [round] within [tier].
///
/// Integer form of economy-model.json curves.reinvestDecay
/// `eff = start + (end - start) * min(1, roundInTier / deadline)` with
/// roundInTier zero-indexed (= round - 1):
/// ```
/// effBp = 5500 - (2000 * min(round - 1, deadline)) ~/ deadline
/// ```
/// — the division happens LAST, truncating toward zero. Clamps to the 3500
/// floor at/past the deadline; tier 5 (endless) is pinned at the floor.
///
/// NOTE (doc deviation, documented): doc 02 §3.9 sketches a per-venture
/// `reinvestCount`-based curve; economy-model.json is authoritative
/// (CLAUDE.md) and keys the decay off round-in-tier progress instead. This
/// follows the JSON.
int reinvestEfficiencyBp({required int round, required int tier}) {
  if (tier == 5) return reinvestFloorBp; // endless: curve fully decayed
  final deadline = tierDeadlineRounds(tier);
  var progress = round - 1; // zero-indexed roundInTier
  if (progress < 0) progress = 0;
  if (progress > deadline) progress = deadline; // min(1, progress/deadline)
  return reinvestStartBp - (reinvestSpanBp * progress) ~/ deadline;
}

// --- Reroll banker fee (doc 02 §3.8 / §4 rerollCost(rerollsUsed)) ---

/// Base banker fee in cents for the FIRST reroll of a round (rerollsUsed 0).
/// = $15,000 — the value the app printed as a flat placeholder, kept as the
/// first-reroll cost so the escalation rides on top of the familiar face.
///
/// *** TUNING DIAL — NOT CANON. *** Doc 02 §4 declares
/// `function rerollCost(used: number): number` but routes its exact integers
/// to the spreadsheet (§6 "exact tuning integers for all §4 constants"); no
/// canon number exists, so the SHAPE is this engine's decision (logged in
/// .claude/STATE.md). Change HERE — it is a SHOP/ACT cash dial, NOT a draw,
/// so it is golden-irrelevant and bump-free (rerolls draw via the named
/// functions; the FEE is plain cash arithmetic).
const int kRerollBaseCents = 1500000;

/// Per-reroll escalation step in cents: each reroll already taken this round
/// adds $15,000 to the next one. Doc 02 §3.8 calls the fee "scaling"; a
/// linear ramp is the simplest doc-faithful shape (first $15k, then $30k,
/// $45k, ...), so the banker punishes repeated hand-fishing within a round
/// while one corrective reroll stays cheap. DEADLINE_CHECK resets
/// `rerollsUsed` to 0 every round/tier advance, so the ramp restarts each
/// round — it does not compound across the run.
const int kRerollStepCents = 1500000;

/// Cap on the banker fee in cents ($150,000 = base + 9 steps). Bounds the
/// linear ramp so a T5-endless marathon (no deadline to reset the counter
/// for many antes — though the round advance still does) cannot let the fee
/// run away; past 9 rerolls in one round the price simply stays at the cap.
/// Also keeps the fee a deterministic small integer (no overflow concern).
const int kRerollMaxCents = 15000000;

/// The doc 02 §3.8 / §4 scaling banker fee in cents for a reroll when
/// [rerollsUsed] rerolls have already been taken this round (0-based):
/// `min(kRerollMaxCents, kRerollBaseCents + kRerollStepCents * rerollsUsed)`.
///
/// Integer-only, deterministic, draw-free. The first reroll of a round costs
/// [kRerollBaseCents] ($15k); each subsequent one costs $15k more, capped at
/// [kRerollMaxCents]. The app reads THIS (controller.rerollCostCents) instead
/// of a flat constant; apply's Reroll still gates `cash >= cost` at execute.
/// A negative [rerollsUsed] is clamped to 0 (defensive; the field is never
/// negative in practice).
int rerollCostCents(int rerollsUsed) {
  final used = rerollsUsed < 0 ? 0 : rerollsUsed;
  final cost = kRerollBaseCents + kRerollStepCents * used;
  return cost > kRerollMaxCents ? kRerollMaxCents : cost;
}

/// The five — and only — mutable resolver inputs a delta may carry.
/// Source: economy-model.json resolverInputs.fields / invariant (§7).
const Set<String> kMutableInputs = {
  'ebitda',
  'multiple',
  'netDebt',
  'own',
  'cash',
};

/// Integer division truncating toward zero (Dart `~/` already does this;
/// kept as an intention-revealing helper to match the prototype).
int _trunc(int a, int b) => a ~/ b;

// --- F1: Enterprise Value = trunc(EBITDA * Multiple / 1000) ---

/// EV in cents from raw EBITDA cents and a milli-unit multiple.
/// Source: economy-model.json formulas.F1_enterpriseValue.
int enterpriseValue(int ebitdaCents, int multipleMilli) =>
    _trunc(ebitdaCents * multipleMilli, milliScale);

/// EV in cents for a [Venture] (model-typed convenience overload).
int enterpriseValueOf(Venture v) =>
    enterpriseValue(v.ebitdaCents, v.multipleMilli);

// --- F2: Equity = EV - NetDebt (may go negative) ---

/// Equity in cents from raw inputs.
/// Source: economy-model.json formulas.F2_equityValue.
int equityValue(int ebitdaCents, int multipleMilli, int netDebtCents) =>
    enterpriseValue(ebitdaCents, multipleMilli) - netDebtCents;

/// Equity in cents for a [Venture] (model-typed convenience overload).
int equityValueOf(Venture v) =>
    enterpriseValueOf(v) - v.netDebtCents;

// --- F3: NetWorth = SUM(trunc(Ownership_bp * Equity / 10000)) + Cash ---

/// Net worth in cents across [ventures] plus the global [cashCents].
/// Per-venture the bp division happens LAST. Mirrors GameState.netWorthCents
/// EXACTLY — including the [satMul] saturation on the EV and equity products
/// (audit 2026-06-09 M3): a marathon endless run could otherwise wrap the
/// raw `ebitda * multiple` / `equity * ownership` int64 products. The two
/// helpers must stay byte-identical, so this computes the products the same
/// saturating way the getter does (NOT via [enterpriseValue], whose other
/// callers are bounded and keep plain `*`). The cap is far above every
/// in-range value, so no golden moves.
/// Source: economy-model.json formulas.F3_netWorth.
int netWorth(List<Venture> ventures, int cashCents) {
  var sum = cashCents;
  for (final v in ventures) {
    final ev = satMul(v.ebitdaCents, v.multipleMilli) ~/ milliScale;
    final eq = ev - v.netDebtCents;
    sum += satMul(v.ownershipBp, eq) ~/ bpScale;
  }
  return sum;
}

// --- F4: Interest = trunc(Rate_bp * totalNetDebt / 10000) ---

/// Interest due in cents, charged in cash each OPERATE step.
///
/// ZERO when [netDebtCents] is 0; scales linearly with debt. [rateBp] is the
/// per-round interest rate in basis points (12% = 1200).
///
/// NOTE: economy-model.json expresses interest as a *band* rather than a single
/// fixed rate — `constants.interestMin = 0.08`, `constants.interestMax = 0.12`
/// (800..1200 bp; R12 tuned interestMax 0.14 -> 0.12), with the actual rate
/// drawn per round inside that band
/// (`curves.interestBand.formula`). There is no single canonical `rateBp`; the
/// caller supplies the live rate. The constants below expose the band endpoints
/// (and its midpoint) in basis points for callers/tests. See report for the
/// prototype-vs-model note (the prototype hard-coded 1200 bp).
/// Source: economy-model.json formulas.F4_interest.
int interestDue(int rateBp, int netDebtCents) =>
    _trunc(rateBp * netDebtCents, bpScale);

/// Interest band endpoints in basis points, from economy-model.json constants.
/// interestMin = 0.08 -> 800 bp; interestMax = 0.12 -> 1200 bp.
/// *** R12 TUNE: interestMax 0.14 -> 0.12 *** — doc 01 §8 knob #5
/// ("raises/lowers the bankruptcy floor for levered play"), turned after
/// carrySeedFrac/deadlines/organicGrowth/recapPct: the full-model §11.2
/// greedy still bankrupted 22% (band [8,12]%) because a top-of-band
/// neutral draw out-bills the 0.35 cash yield from ~2.5x leverage up
/// (0.35/0.14); at 0.12 the same breakeven sits at ~2.9x, so mid-lever
/// runs stop dying to plain neutral rate noise while the crunch
/// (x rateMulColdNum) keeps killing the truly over-levered.
const int interestMinBp = 800; // 0.08 * 10000
const int interestMaxBp = 1200; // 0.12 * 10000

/// Band midpoint in basis points (1000 bp = 10%), integer math:
/// (800 + 1200) ~/ 2. Provided for callers wanting a single representative rate.
const int interestMidBp = (interestMinBp + interestMaxBp) ~/ 2;

// --- F5: Dilution. preMoney = current Equity. ---

/// New ownership in bp after a raise; the slice shrinks.
/// `newOwn = trunc(oldOwn * preMoney / (preMoney + raise))`.
/// [preMoneyCents] is the current equity; [raiseCents] is the new money in.
/// Source: economy-model.json formulas.F5_dilution.
int diluteOwnership(int oldOwnBp, int preMoneyCents, int raiseCents) =>
    _trunc(oldOwnBp * preMoneyCents, preMoneyCents + raiseCents);

// --- F6: bankruptcy when cash < 0 after interest is charged (NOT clamped). ---

/// True when the run has ended: cash went negative after the interest charge.
/// Source: economy-model.json formulas.F6_bankruptcy.
bool isBankrupt(int cashAfterInterest) => cashAfterInterest < 0;

// --- Arbitrage / accretion helpers (mirror the prototype) ---

/// RENDER-ONLY arbitrage flash: realized accretion in cents when [addonEbitda]
/// is bought at [buyMultiple] (milli) and revalued at the live [platformMultiple]
/// (milli). Written to NO field — display only.
/// `accretion = trunc(addonEbitda * (m_platform - m_buy) / 1000)`.
/// Source: economy-model.json formulas.arbitrageFlash.
int arbitrageAccretion(int addonEbitda, int platformMultiple, int buyMultiple) =>
    _trunc(addonEbitda * (platformMultiple - buyMultiple), milliScale);

/// Same-sector add-on: the platform absorbs the add-on's EBITDA in cents PLUS a
/// +20% synergy bonus on the absorbed EBITDA. Returns the new platform EBITDA
/// in cents; the platform multiple is unchanged.
/// `ebitda += addon.ebitda + trunc(addon.ebitda * synergySameSector)`.
/// Source: economy-model.json formulas.synergySameSector.
int absorbSameSector({
  required int platformEbitda,
  required int addonEbitda,
}) =>
    platformEbitda + addonEbitda + _trunc(addonEbitda * synergyNum, synergyDen);

/// Cross-sector add-on: absorbs at the platform multiple with ZERO synergy and
/// drags the live platform multiple down by the conglomerate discount.
/// Returns the new platform [multipleMilli] after one add-on; stacks
/// multiplicatively (0.92^n) when applied repeatedly.
/// `multiple = trunc(multiple * (1 - congDiscountPerAddon))`.
/// Source: economy-model.json formulas.congDrag.
int absorbCrossSectorMultiple(int multipleMilli) =>
    _trunc(multipleMilli * congKeepNum, congKeepDen);

// --- §7 invariant guard ---

/// True iff every key in [delta] is one of the five mutable resolver inputs.
/// Source: economy-model.json resolverInputs.invariant (§7).
bool deltaObeysInvariant(Map<String, num> delta) =>
    delta.keys.every(kMutableInputs.contains);
