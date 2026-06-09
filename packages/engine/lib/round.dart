/// The round machine — `endTurn`, `runDeadlineCheck`, and the derived
/// `ForwardMeters` — closing doc 02 §2's strict loop:
///
///   OPERATE -> ACT -> SHOP -> DEADLINE_CHECK -> (next OPERATE | RUN_OVER)
///
/// `runOperate` (operate.dart) owns the round-start step; this library owns
/// everything after the player acts. Since the deal-flow layer
/// (schemaVersion 4), `endTurn` DRAWS: entering SHOP deals the round's
/// offers (dealflow.dart's SHOP routine — exactly kShopOfferCount draws,
/// doc 02 §2 SHOP / §3.8). `runDeadlineCheck` still draws NOTHING — its
/// signature takes no stream at all, so the no-draw property stays
/// structural (the fresh HAND on a round/tier advance is drawn by the next
/// OPERATE, doc 03 §3.1 step 1 — dealflow.dart documents the
/// reconciliation with doc 02 §2's wording).
///
/// DEADLINE_CHECK (doc 02 §2, doc 01 §1 tier-clear rule), exactly:
///   nw = derived net worth (F3) — note this runs AFTER ACT, so a
///   bar-clearing final-round EXIT is already reflected.
///   - nw >= bar[tier]:
///       tier 4  -> WIN (clearing TIER_BAR[4] IS the $1B win; won = true,
///                  RUN_OVER, no reseed, no new tier-entry snapshot).
///       tier <4 -> TIER_CLEARED: snapshot netWorthAtTierEntry = nw
///                  (PRE-reseed — doc 01 §6 keys its growth table off the
///                  cleared bar), apply the §3.3 reseed (below), advance
///                  tier += 1, round = 1, re-stage plays, rerollsUsed = 0,
///                  phase -> OPERATE.
///   - else, round < deadline[tier] (T5: no deadline — always advances):
///       round += 1, re-stage plays, rerollsUsed = 0, phase -> OPERATE.
///   - else: RUN_OVER, death = missedDeadline (growth-rate death,
///       telegraphed by growthRateThisTier < growthRateNeeded).
///
/// THE RESEED (doc 01 §3.3; economy constants.carrySeedFrac/.reseedMult) is
/// a SYSTEM EVENT through the same five-input delta discipline, logged to
/// the action log like any other action:
///   seedEbitda = trunc(carrySeedFrac x NW x 1000 / reseedMult)  [ONE
///   division]; the carried venture's ebitda is SET to seedEbitda and its
///   multiple SET to 8000 (deltas computed against current values); netDebt
///   delta 0 (carries), ownership unchanged, cash carries as-is.
/// Engine decisions, documented:
///   - CAP: doc 01 §3.3 claims the reseed "re-derives to a net worth <= the
///     net worth you actually had", but the raw formula violates that for
///     cash-heavy clears (venture EV < 0.24 x NW would be marked UP — value
///     conjured from nothing, against the §7 no-conjuring rule). The engine
///     honors the doc's stated property over its formula in that corner:
///     `seedEbitda = min(formula, trunc(EV x 1000 / 8000))`, so the
///     reseeded EV never exceeds the pre-reseed EV. In designed play
///     (venture-dominant clears) the cap never binds and the formula
///     applies verbatim. The proven prototype (sim-check.js) replaced cash
///     AND debt too, making its reseed unconditionally reducing; doc 01
///     §3.3 carries cash/debt, which is what opened this corner.
///   - MULTI-VENTURE: §3.3 is written for the single-platform case ("the
///     carried venture"). The engine reseeds `ventures.first` — the
///     longest-held platform, deterministic because list order is
///     replay-locked — and carries every other venture untouched. The cap
///     keeps the no-conjuring property for any portfolio shape.
///   - NO VENTURE: an all-cash clear (player exited everything) has nothing
///     to seed; the tier advances with no reseed and no log entry.
///   - T5 ENDLESS (audit 2026-06-09 L1 — no longer a stub): the WIN bar is
///     the unreachable sentinel (endless never wins; doc 02 §2), but endless
///     now ESCALATES per doc 01 §5 ("score-chase, escalating modifiers").
///     It runs in fixed-length ANTES ([kEndlessAnteRounds]) against a RISING
///     survival bar ([endlessSurvivalBarCents], geometric off the entry net
///     worth at [kEndlessBarStepMilli]/ante). A mid-ante DEADLINE_CHECK
///     advances; on the ante deadline ([isEndlessAnteDeadline]) it evaluates
///     the bar — clear it and the next ante's bar is higher (ENDLESS_ANTE_
///     CLEARED, advance), miss it and the run FAILS OUT MISSED_DEADLINE (doc
///     02 §2's "fails-out on the deadline only"). `won` is never set in T5.
///     The geometric bar also bounds run length (you fail out long before
///     net worth could reach the satMul cap — that M3 guard is the backstop).
///
/// FORWARD METERS (doc 02 §1; doc 01 §7.4) are PURE DERIVED reads —
/// recompute on demand, never stored. The runway gauge is computed against
/// the MAX-CRUNCH rate (interestMax x crunch rateMul = 1560 bp), which is
/// >= every reachable live-rate draw, so an OPERATE that CAN bankrupt is
/// always pre-flagged (`runwayOk == false` the round before — doc 02 §5.2
/// telegraph test #6; the flag is a warning, not a verdict).
/// Growth rates are integer per-round compounding with per-step truncation
/// (the engine's own arithmetic shape):
///   growthRateNeeded = the smallest r in [1000, 3000] milli with
///     compound(nw, r, roundsLeft) >= bar, found by bisection
///     (roundsLeft = deadline - round + 1, including the current round);
///     1000 once the bar is cleared (and in T5: no bar), saturates at 3000
///     ("off the gauge") when even 3.0x/round cannot reach the bar.
///   growthRateThisTier = the largest r in [0, 3000] milli with
///     compound(netWorthAtTierEntry, r, round) <= nw; 0 when the baseline
///     or the current net worth is non-positive (no meaningful rate).
///
/// All integer fixed-point; fractions cited from economy-model.json as
/// num/den constants. Pure dart:core.
library;

import 'apply.dart' show GameEvent, GameEventType;
import 'content.dart';
import 'dealflow.dart';
import 'model.dart';
import 'money.dart' show satMul;
import 'operate.dart'
    show cashYieldCents, playsGrantedForRound, rateMulColdNum, rateMulDen;
import 'platform_limits.dart' show kIntWidthMaxCents;
import 'resolver.dart';
import 'rng.dart';

// --- Tier bars (economy-model.json tierBars; doc 01 §5) ---

/// T5 endless "bar": an unreachable sentinel (doc 02 §2 "Infinity sentinel
/// in the bar map's intent") — the largest platform int, so `nw >= bar` never
/// fires and endless has no win path. Native: 2^63-1; web: 2^53-1 (still far
/// above any reachable net worth, so the never-fires property holds).
const int endlessBarSentinelCents = kIntWidthMaxCents;

/// The net-worth bar in cents to clear [tier] (the 10x ladder).
/// Source: economy-model.json tierBars[].bar = [1e8, 1e9, 1e10, 1e11]
/// cents ($1M/$10M/$100M/$1B); TIER_BAR[4] IS the win bar (doc 02 §2).
int tierBarCents(int tier) {
  switch (tier) {
    case 1:
      return 100000000; // $1M
    case 2:
      return 1000000000; // $10M
    case 3:
      return 10000000000; // $100M
    case 4:
      return 100000000000; // $1B — the win bar
    case 5:
      return endlessBarSentinelCents;
    default:
      throw ArgumentError.value(tier, 'tier', 'must be 1..5');
  }
}

// --- Reseed constants (economy-model.json constants; doc 01 §3.3) ---

/// Fraction of net worth that reseeds the next tier's base: 0.37 -> 37/100.
/// Source: economy-model.json constants.carrySeedFrac = 0.37 (also
/// tuningKnobs: "biggest difficulty lever; Up=easier").
/// *** R12 TUNE: 0.24 -> 0.37 *** — the §8 knob table's first row, turned
/// per the full-model harness: the 0.24 haircut made every post-T1 tier
/// demand ~1.59x/round from the reseeded base (vs the doc 01 §6 design
/// line of 1.33x from the cleared bar), which no §11.3 floor can compound;
/// floor T2 clear measured 2.5% at 0.24. 0.37 puts the post-reseed demand
/// at ~1.39x/round and the measured floor at 39-41% (§11.3 band [25,42]).
/// It still haircuts (no value conjured — the reseed cap in _clearTier
/// holds), it just carries real momentum between tiers.
const int carrySeedNum = 37;

/// Denominator for [carrySeedNum].
const int carrySeedDen = 100;

/// The normalized reseed multiple in milli-units (8x, sector-neutral).
/// Source: economy-model.json constants.reseedMult = 8000.
const int reseedMultMilli = 8000;

/// The doc 01 §3.3 seed formula, ONE final division (the locked precision
/// rule): `seedEbitda = trunc(carrySeedFrac x NW x 1000 / reseedMult)`.
/// 64-bit headroom: NW x 24 x 1000 stays far inside the int range for any
/// reachable net worth.
int reseedEbitdaCents(int netWorthCents) =>
    (netWorthCents * carrySeedNum * milliScale) ~/
    (carrySeedDen * reseedMultMilli);

/// The no-conjuring cap on the seed (see the library header): the largest
/// ebitda whose re-derived EV at 8x does not exceed [evCents], i.e.
/// `trunc(EV x 1000 / 8000)` — so `cap x 8 <= EV` always.
int reseedEbitdaCapCents(int evCents) =>
    (evCents * milliScale) ~/ reseedMultMilli;

// --- Endless escalation (doc 01 §5 "Score-chase, escalating modifiers";
// doc 02 §2 "endless only ever fails-out on the deadline, won is never set";
// audit 2026-06-09 L1, coordinated with M3's magnitude guard) ---
//
// Before this round T5 was a stub: DEADLINE_CHECK always advanced and the run
// could never end (or escalate). Doc 01 §5 calls endless a "score-chase with
// escalating modifiers" and doc 02 §2 says endless "only ever fails-out on
// the deadline" with no win — there is no canonical T5 deadline value, so the
// engine OWNS one. The minimal doc-faithful realization: endless runs in
// fixed-length ANTES, and each ante you must keep pace with a RISING survival
// bar derived from the net worth you entered endless with. Clear the ante's
// bar -> the next ante's bar is higher (escalation); miss it at the ante
// deadline -> the run ends MISSED_DEADLINE (fails-out, never wins). The rising
// bar also BOUNDS the run length (you die long before net worth could reach
// the satMul cap — M3's guard is the backstop, the escalation is the design),
// so endless can't run forever and can't silently overflow.

/// Rounds per endless ante (the survival window). Reuses the T4 cadence (10)
/// so endless feels like "another tier that never ends" rather than a new
/// rhythm. *** TUNING DIAL — no canon pins an endless ante length. ***
const int kEndlessAnteRounds = 10;

/// Per-ante escalation of the survival bar, in milli (1.50x -> 1500): each
/// endless ante demands 1.5x the previous ante's bar. Above the design
/// growth line (~1.45x/round ceiling, doc 01 §6) compounded over an ante is
/// easy early but the bar compounds geometrically, so a finite number of
/// antes are survivable — the run ENDS. *** TUNING DIAL — no canon. ***
const int kEndlessBarStepMilli = 1500;

/// 1-based endless ante index for [round] within T5 (round 1..ante = ante 1,
/// next block = ante 2, ...). T5 `round` starts at 1 on entry (the tier-clear
/// advance), so `ante = ((round - 1) ~/ kEndlessAnteRounds) + 1`.
int endlessAnteOf(int round) =>
    ((round < 1 ? 1 : round) - 1) ~/ kEndlessAnteRounds + 1;

/// True on the LAST round of an endless ante (the round DEADLINE_CHECK
/// evaluates the rising bar): `round % kEndlessAnteRounds == 0`.
bool isEndlessAnteDeadline(int round) =>
    round >= 1 && round % kEndlessAnteRounds == 0;

/// The rising endless SURVIVAL bar in cents for the ante that ends at
/// [round], escalating geometrically off [entryNetWorthCents] (the net worth
/// when endless began, snapshotted in [GameState.netWorthAtTierEntry] on the
/// T4->T5 clear): `entry x kEndlessBarStepMilli^ante`, each multiply
/// saturating ([satMul]) so the bar itself can never overflow. Ante 1's bar
/// is `entry x 1.5`, ante 2's `entry x 2.25`, etc. — the player must have
/// GROWN past it by the ante deadline or fail out. A non-positive entry
/// (degenerate) yields a 0 bar that any positive net worth clears.
int endlessSurvivalBarCents(int entryNetWorthCents, int round) {
  if (entryNetWorthCents <= 0) return 0;
  final ante = endlessAnteOf(round);
  var bar = entryNetWorthCents;
  for (var i = 0; i < ante; i++) {
    bar = satMul(bar, kEndlessBarStepMilli) ~/ milliScale;
  }
  return bar;
}

// --- END_TURN (doc 02 §3.11; doc 02 §2 SHOP since the deal-flow layer) ---

/// Leaves ACT for SHOP and deals the round's offers: `shopOffers` is
/// REPLACED via dealflow.dart's SHOP routine (exactly kShopOfferCount
/// draws — the signature change documented at the schemaVersion-4 bump).
/// No other economic delta; remaining plays are forfeited, never spent.
/// Throws [StateError] outside ACT (a step from the wrong phase is a
/// caller bug; player ACTIONS reject instead — apply.dart).
GameState endTurn(GameState state, SplitMix64Rng rng, ContentDb content) {
  if (state.phase != PhaseId.act) {
    throw StateError('endTurn requires phase == PhaseId.act '
        '(doc 02 §3.11); was ${state.phase}');
  }
  return drawShop(state, rng, content).copyWith(phase: PhaseId.shop);
}

// --- DEADLINE_CHECK (doc 02 §2; doc 01 §1 tier-clear rule) ---

/// The result of [runDeadlineCheck]: the next immutable state plus the
/// events the check produced (unmodifiable). Possible events: TIER_CLEARED,
/// WON, MISSED_DEADLINE; a plain round advance emits nothing.
class DeadlineResult {
  /// Builds a [DeadlineResult]; [events] is copied unmodifiable.
  DeadlineResult({required this.state, required List<GameEvent> events})
      : events = List.unmodifiable(events);

  /// The state after the deadline check.
  final GameState state;

  /// What happened, for the UI to animate. Never persisted.
  final List<GameEvent> events;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DeadlineResult || other.state != state) return false;
    if (other.events.length != events.length) return false;
    for (var i = 0; i < events.length; i++) {
      if (other.events[i] != events[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(state, Object.hashAll(events));

  @override
  String toString() => 'DeadlineResult(state: $state, events: $events)';
}

/// Evaluates the tier bar (doc 02 §2 DEADLINE_CHECK; library header = the
/// exact branch map). Draws NOTHING — the signature takes no RNG. Throws
/// [StateError] unless `phase == PhaseId.shop`.
DeadlineResult runDeadlineCheck(GameState state) {
  if (state.phase != PhaseId.shop) {
    throw StateError('runDeadlineCheck requires phase == PhaseId.shop '
        '(doc 02 §2 strict machine); was ${state.phase}');
  }
  final nw = state.netWorthCents;

  if (nw >= tierBarCents(state.tier)) {
    if (state.tier == 4) {
      // Clearing TIER_BAR[4] IS the $1B win (doc 02 §2): no separate
      // billion check, no reseed, no advance — the run ends victorious.
      final next = state.copyWith(
        won: true,
        phase: PhaseId.runOver,
        playsRemaining: 0, // the run is over: no plays (F6 precedent)
      );
      return DeadlineResult(state: next, events: [
        GameEvent(type: GameEventType.won, amount: nw),
      ]);
    }
    return _clearTier(state, nw);
  }

  // T5 ENDLESS (doc 01 §5 escalating modifiers; doc 02 §2 fails-out only,
  // never wins; audit L1). Endless runs in fixed-length antes against a
  // RISING survival bar derived from the entry net worth. On a NON-deadline
  // round it just advances (keep playing the ante); on the ante DEADLINE it
  // evaluates the rising bar — clear it and the next ante's bar is higher
  // (escalation), miss it and the run fails out MISSED_DEADLINE. `won` is
  // never set in T5.
  if (state.tier == 5) {
    if (!isEndlessAnteDeadline(state.round)) {
      // Mid-ante: advance (the score-chase continues this ante).
      final next = state.copyWith(
        round: state.round + 1,
        playsRemaining: playsGrantedForRound(state.tier, state.backgroundId),
        rerollsUsed: 0,
        phase: PhaseId.operate,
      );
      return DeadlineResult(state: next, events: const []);
    }
    // Ante deadline: did the player grow past this ante's RISING bar?
    final bar = endlessSurvivalBarCents(state.netWorthAtTierEntry, state.round);
    if (nw >= bar) {
      // Cleared the ante — escalate into the next (the bar rises with the
      // ante index). Endless never WINS (no won flag), it only continues.
      final next = state.copyWith(
        round: state.round + 1,
        playsRemaining: playsGrantedForRound(state.tier, state.backgroundId),
        rerollsUsed: 0,
        phase: PhaseId.operate,
      );
      return DeadlineResult(state: next, events: [
        GameEvent(type: GameEventType.endlessAnteCleared, amount: nw),
      ]);
    }
    // Failed to keep pace with the escalating bar — endless fails out.
    final dead = state.copyWith(
      phase: PhaseId.runOver,
      death: DeathCause.missedDeadline,
      playsRemaining: 0,
    );
    return DeadlineResult(state: dead, events: [
      GameEvent(
        type: GameEventType.missedDeadline,
        amount: nw,
        reason: 'endless_below_escalating_bar',
      ),
    ]);
  }

  // T1..T4: advance while rounds remain (library header).
  if (state.round < tierDeadlineRounds(state.tier)) {
    final next = state.copyWith(
      round: state.round + 1,
      // The per-round plays grant honors the Dealmaker +1 (schemaVersion 9).
      playsRemaining: playsGrantedForRound(state.tier, state.backgroundId),
      rerollsUsed: 0,
      phase: PhaseId.operate,
    );
    return DeadlineResult(state: next, events: const []);
  }

  // Out of rounds: the growth-rate death (doc 02 §2; doc 01 §9).
  final next = state.copyWith(
    phase: PhaseId.runOver,
    death: DeathCause.missedDeadline,
    playsRemaining: 0, // a dead run gets no plays
  );
  return DeadlineResult(state: next, events: [
    GameEvent(
      type: GameEventType.missedDeadline,
      amount: nw,
      reason: 'net_worth_below_bar_at_deadline',
    ),
  ]);
}

/// The tier-clear branch: TIER_CLEARED + the doc 01 §3.3 reseed + advance.
/// [nw] is the bar-clearing PRE-reseed net worth (snapshotted as the new
/// tier-entry baseline; see the library header for why pre-reseed).
DeadlineResult _clearTier(GameState state, int nw) {
  var ventures = state.ventures;
  var actionLog = state.actionLog;

  if (ventures.isNotEmpty) {
    // The reseed (doc 01 §3.3 + the engine cap; library header). Two
    // five-input deltas on the carried venture: ebitda set to the seed,
    // multiple set to the normalized 8x.
    final carried = ventures.first;
    final uncapped = reseedEbitdaCents(nw);
    final cap = reseedEbitdaCapCents(enterpriseValueOf(carried));
    final seed = uncapped < cap ? uncapped : cap;
    ventures = [
      carried.copyWith(ebitdaCents: seed, multipleMilli: reseedMultMilli),
      ...ventures.skip(1),
    ];
    actionLog = [
      ...actionLog,
      LoggedAction(
        round: state.round,
        summary: 'TierReseed ${carried.id}: T${state.tier} cleared at '
            'NW $nw; ebitda ${carried.ebitdaCents} -> $seed, multiple '
            '${carried.multipleMilli} -> $reseedMultMilli '
            '(carrySeedFrac $carrySeedNum/$carrySeedDen'
            '${seed == cap && uncapped > cap ? ', capped at pre-reseed EV' : ''})',
      ),
    ];
  }

  final newTier = state.tier + 1;
  final next = state.copyWith(
    ventures: ventures,
    actionLog: actionLog,
    tier: newTier,
    round: 1,
    // The new tier's per-round grant honors the Dealmaker +1 (schemaVersion 9).
    playsRemaining: playsGrantedForRound(newTier, state.backgroundId),
    rerollsUsed: 0,
    netWorthAtTierEntry: nw,
    phase: PhaseId.operate,
  );
  return DeadlineResult(state: next, events: [
    GameEvent(type: GameEventType.tierCleared, amount: nw),
  ]);
}

// --- Forward meters (doc 02 §1 ForwardMeters; doc 01 §7.4) ---

/// The max-crunch runway rate in bp: interestMax x crunch rateMul
/// = 1200 x 130/100 = 1560 bp (rateMulColdNum — the R12-tuned crunch
/// dial; operate.dart documents the turn). Source: economy-model.json
/// curves.interestBand.crunch.max (equivalently constants.interestMax
/// 0.14 x tuningKnobs.crunchRateMul). Deriving from the SAME const keeps
/// this strictly >= every reachable live-rate draw (the band top at
/// u=9999), which is what makes the bankruptcy telegraph sound.
const int maxCrunchRateBp = (interestMaxBp * rateMulColdNum) ~/ rateMulDen;

/// Lower bracket of the realized-growth gauge (declines allowed).
const int growthRateMinMilli = 0;

/// Lower bracket of the needed-growth gauge (never below 1.0x: a cleared
/// bar needs no growth).
const int growthRateNeededMinMilli = 1000;

/// Saturation top of BOTH growth gauges: 3.0x/round, comfortably above the
/// design line's ~1.45x ceiling (doc 01 §6). Values past it read "off the
/// gauge"; the bisection bracket per the work order.
const int growthRateMaxMilli = 3000;

/// Overflow guard for [compoundCents]: values are clamped here so the next
/// `x * rateMilli` cannot exceed the 64-bit range. The cap (~3e15 cents,
/// $30T) is orders of magnitude above every bar, so clamped comparisons
/// against bars/net-worths are exact within the model's domain.
const int _compoundCapCents = kIntWidthMaxCents ~/ growthRateMaxMilli;

/// Applies [rateMilli] per round for [rounds] rounds to [baseCents] with
/// per-step truncation — `x = trunc(x * r / 1000)` repeated — the engine's
/// own compounding shape. Monotone nondecreasing in [rateMilli] for
/// non-negative bases, which is what the bisections rely on.
int compoundCents(int baseCents, int rateMilli, int rounds) {
  var x = baseCents > _compoundCapCents ? _compoundCapCents : baseCents;
  for (var i = 0; i < rounds; i++) {
    x = (x * rateMilli) ~/ milliScale;
    if (x > _compoundCapCents) x = _compoundCapCents;
  }
  return x;
}

/// Smallest r in [lo, hi] with `ok(r)` true, for a monotone-in-r predicate;
/// [hi] when even `ok(hi)` fails (the gauge saturates).
int _minRateSatisfying(bool Function(int) ok, int lo, int hi) {
  if (!ok(hi)) return hi;
  var low = lo, high = hi;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (ok(mid)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}

/// Largest r in [lo, hi] with `ok(r)` true, for a monotone-in-r predicate
/// that holds at [lo]; [hi] when `ok(hi)` still holds (saturated).
int _maxRateSatisfying(bool Function(int) ok, int lo, int hi) {
  if (ok(hi)) return hi;
  var low = lo, high = hi;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (ok(mid)) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

/// The doc 02 §1 forward meters — telegraph death a round ahead. PURE
/// DERIVED value type: computed on demand by [computeMeters], never stored
/// on the state (the snapshots it reads ARE state; the meters are not).
class ForwardMeters {
  /// Builds a [ForwardMeters] (all fields final; value equality).
  const ForwardMeters({
    required this.projectedCashNextRoundCents,
    required this.debtServiceNextRoundCents,
    required this.runwayOk,
    required this.growthRateThisTierMilli,
    required this.growthRateNeededMilli,
    required this.marketTempGauge,
  });

  /// Cash after next OPERATE's expected EBITDA inflow, in cents:
  /// `cash + sum(per-venture yield)` (passive dampened; yield is computed
  /// on pre-decay EBITDA, so this is exact, not an estimate). Scheduled
  /// effects join when that layer lands.
  final int projectedCashNextRoundCents;

  /// Next OPERATE's interest bill at the MAX-CRUNCH rate, in cents:
  /// `interestDue(maxCrunchRateBp, total netDebt)` (doc 01 §7.4). Negative
  /// when the run holds net cash (F4 is unclamped, matching OPERATE).
  final int debtServiceNextRoundCents;

  /// `projectedCash >= debtService` — false means next OPERATE CAN
  /// bankrupt (under the worst rate), the doc 02 §5.2 #6 pre-flag.
  final bool runwayOk;

  /// Realized per-round growth this tier, milli (1.31x == 1310): the
  /// largest r with compound(netWorthAtTierEntry, r, round) <= nw. 0 when
  /// the baseline or current net worth is non-positive.
  final int growthRateThisTierMilli;

  /// Per-round growth needed to clear the bar in the rounds left, milli:
  /// the smallest r in [1000, 3000] with compound(nw, r, roundsLeft) >=
  /// bar; saturates at 3000 (and is 1000 once cleared / in T5).
  final int growthRateNeededMilli;

  /// Mirrors `market.temp` for the HOT/COLD gauge (doc 02 §1).
  final MarketTemp marketTempGauge;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ForwardMeters &&
        other.projectedCashNextRoundCents == projectedCashNextRoundCents &&
        other.debtServiceNextRoundCents == debtServiceNextRoundCents &&
        other.runwayOk == runwayOk &&
        other.growthRateThisTierMilli == growthRateThisTierMilli &&
        other.growthRateNeededMilli == growthRateNeededMilli &&
        other.marketTempGauge == marketTempGauge;
  }

  @override
  int get hashCode => Object.hash(
        projectedCashNextRoundCents,
        debtServiceNextRoundCents,
        runwayOk,
        growthRateThisTierMilli,
        growthRateNeededMilli,
        marketTempGauge,
      );

  @override
  String toString() => 'ForwardMeters('
      'projectedCash: $projectedCashNextRoundCents, '
      'debtService: $debtServiceNextRoundCents, runwayOk: $runwayOk, '
      'growthRateThisTier: $growthRateThisTierMilli, '
      'growthRateNeeded: $growthRateNeededMilli, '
      'marketTempGauge: $marketTempGauge)';
}

/// Computes the forward meters for [state] (library header = the exact
/// definitions). Pure, draw-free, O(ventures + ~12 bisection probes).
ForwardMeters computeMeters(GameState state) {
  var yieldCents = 0;
  var totalNetDebt = 0;
  for (final v in state.ventures) {
    yieldCents += cashYieldCents(v.ebitdaCents, passive: v.passive);
    totalNetDebt += v.netDebtCents;
  }
  final projected = state.cashCents + yieldCents;
  final service = interestDue(maxCrunchRateBp, totalNetDebt);

  final nw = state.netWorthCents;
  final round = state.round < 1 ? 1 : state.round;

  // Realized rate vs the tier-entry baseline (0 = no meaningful rate).
  final entry = state.netWorthAtTierEntry;
  final realized = (entry <= 0 || nw <= 0)
      ? 0
      : _maxRateSatisfying((r) => compoundCents(entry, r, round) <= nw,
          growthRateMinMilli, growthRateMaxMilli);

  // Needed rate vs the bar over the rounds left (including this one).
  final int needed;
  if (nw <= 0) {
    needed = growthRateMaxMilli; // nothing positive compounds from <= 0
  } else if (state.tier == 5) {
    // Endless now HAS a rising survival bar (audit L1): the meter telegraphs
    // the pace needed to clear THIS ante's escalating bar by its deadline.
    final anteDeadlineRound =
        endlessAnteOf(round) * kEndlessAnteRounds; // last round of the ante
    final bar = endlessSurvivalBarCents(state.netWorthAtTierEntry,
        anteDeadlineRound);
    var roundsLeft = anteDeadlineRound - round + 1;
    if (roundsLeft < 1) roundsLeft = 1;
    needed = bar <= 0
        ? growthRateNeededMinMilli
        : _minRateSatisfying(
            (r) => compoundCents(nw, r, roundsLeft) >= bar,
            growthRateNeededMinMilli,
            growthRateMaxMilli);
  } else {
    final bar = tierBarCents(state.tier);
    var roundsLeft = tierDeadlineRounds(state.tier) - round + 1;
    if (roundsLeft < 1) roundsLeft = 1;
    needed = _minRateSatisfying(
        (r) => compoundCents(nw, r, roundsLeft) >= bar,
        growthRateNeededMinMilli,
        growthRateMaxMilli);
  }

  return ForwardMeters(
    projectedCashNextRoundCents: projected,
    debtServiceNextRoundCents: service,
    runwayOk: projected >= service,
    growthRateThisTierMilli: realized,
    growthRateNeededMilli: needed,
    marketTempGauge: state.market.temp,
  );
}
