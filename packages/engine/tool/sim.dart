/// MULTIPLES — Phase 5 FULL-MODEL Monte-Carlo balance harness (R12).
///
/// The doc 01 §12 / economy-model.json `simCheck.fullModelMonteCarlo` P1
/// deliverable: a headless auto-player that drives the REAL engine — initRun
/// -> runOperate -> policy ACT (apply/playCard over the live card surface)
/// -> endTurn -> policy SHOP (buyShopOffer) -> runDeadlineCheck -> ... to
/// win/death — so the §11 acceptance bands stop being floor-only claims.
/// Unlike prototype/sim-check.js this models EVERYTHING the engine does:
/// the deal-flow hand, drift compounding, neglect decay, events, partner
/// engines + organic growth, the canonical recap, synergy merges, exit
/// offers, hot windows, the reseed cap.
///
/// DETERMINISM CONTRACT: run k uses SplitMix64Rng(seedBase + k - 1),
/// k = 1..N (seedBase defaults to 1). The report is a pure function of
/// (N, seedBase, policy set, engine build) — byte-for-byte reproducible
/// (test/sim_test.dart pins this). No RNG outside the engine stream; all
/// aggregation is integer/fixed-point (permille and x100 units) — no
/// `double` anywhere in this tool, matching the engine's own discipline.
///
/// ==========================================================================
/// THE THREE POLICIES (decision rules, exact — honest heuristics, cited):
///
/// THE DEBT PACE (floor + greedy, sim-check.js fidelity): the JS ancestor
/// drew debt as `min(targetDebt - netDebt, ebitda x 1.2)` PER ROUND — a
/// pace cap that kept the §11 strategies' EFFECTIVE leverage near
/// ~1.5-2x while EBITDA compounded (the steady state of r = (r+1.2)/g for
/// growth g). The doc's measured numbers (floor 40% win / 0% bankrupt,
/// greedy 73% / 9%) were calibrated on that pace, NOT on a strategy
/// pinned at its leverage line. The engine's debt instruments are chunky
/// (a recap pull is ~2.4x EBITDA at one stroke), so the pace is
/// amortized: every ACT accrues 1.2 x EBITDA of budget, each chunk
/// spends it, unused budget rolls forward.
///
/// FLOOR — doc 01 §11.3's plain strategy translated to the real action
/// space (the "is it winnable?" check):
///   ACT (in order, while plays remain):
///   1. TAKE DEBT toward targetLeverage (3.0x EBITDA) when market != COLD,
///      at the pace above: play a held PLY_DIVIDEND_RECAP (the engine's
///      only EV-scaled debt instrument — the canonical doc 01 §7.7 pull)
///      while the pull keeps debt <= 3.0x, then exercise debt-shaped
///      financing offers (type financing, dilution 0, +netDebt) under the
///      same line. Target: the platform (ventures.first).
///   2. REINVEST free cash above a 1-round interest buffer into the
///      platform. Buffer = computeMeters().debtServiceNextRoundCents (the
///      MAX-CRUNCH 1-round bill, >= every reachable draw — the doc's 0.0%
///      floor bankruptcy made structural). The reinvest fires even at
///      amount 0: touching the platform every round is the floor's
///      neglect-decay shield (the JS floor had no decay at all).
///   3. Never merges, never exits, never hires. SHOP: buys ONLY the recap
///      ticket (cost.cash 0 — its §11.3 "take debt" instrument).
///
/// GREEDY — §11.2's over-lever variant (the "is greed fatal?" check):
///   SHOP: buys PLY_DIVIDEND_RECAP (the doc's recap greed dial) and
///   PLY_BRIDGE_LOAN whenever offered and affordable (held-cap permitting).
///   ACT: 1. plays every held recap/bridge onto the platform while
///   totalNetDebt + faceDebt <= 5.8 x totalEBITDA and the pace budget
///   allows; 2. exercises debt financing offers under the same 5.8x line —
///   in ANY market temp (no crunch gate); 3. reinvests ALL cash, NO buffer
///   (its undoing: a crunch rate spike must be paid from yield alone).
///
/// SMART — floor + the skill layers (the headroom check; "plays the game
/// as designed"). ACT priority, consuming plays in order, every spend
/// gated to leave cash >= the floor's max-crunch buffer:
///   1. HOT EXIT: with the hot window armed (or arming a held
///      PLY_HOT_WINDOW first — free) and an exit offer on a non-sole
///      venture, exit it at live x135/100.
///   2. BUBBLE EXIT: market HOT + offer >= live on a non-sole venture ->
///      exit at the full (bubble-inflated) live mark.
///   3. RE-FOUND: a free slot + an affordable venture card in hand ->
///      StartVenture on the best (equity-minus-price) face — the re-entry
///      leg of the exit cycle.
///   4. PARTNER HIRE: an affordable partner card in hand -> hire onto the
///      highest-multiple venture (the permanent +EBITDA engine, and the
///      organic-growth attribution for re-founded ventures).
///   5. SAME-SECTOR MERGE: an affordable addon whose sector matches a held
///      venture with multiple > m_buy (accretive) -> merge into the
///      highest-multiple same-sector venture.
///   5b. PRUDENT RECAP: play a held PLY_DIVIDEND_RECAP onto the
///      highest-multiple venture when the pull keeps total leverage <=
///      4.0x EBITDA — inside doc 01 §7.4's "stretched" amber band, never
///      the 6.0x danger line (policy heuristic; unpaced — smart is OUR
///      design baseline, not a JS port).
///   6. LEVER to 3.0x like the floor (market != COLD; paced).
///   7. REINVEST the rest above the buffer into the highest-multiple
///      venture; leftover plays touch the most-neglected other venture
///      with a 0-amount reinvest (decay shield).
///   SHOP: buys PLY_HOT_WINDOW and PLY_DIVIDEND_RECAP when offered,
///   affordable and below the held cap.
///
/// No policy rerolls (the fee is a dial under separate review; rerolling
/// would also blur the dead-hand feel metric below).
///
/// FEEL METRICS (the R12 work order's playtest answer, measured for EVERY
/// policy at EVERY ACT start, all tiers, before the policy moves):
///   - playable tickets = hand cards whose engine PRE would pass right
///     then (venture: free slot + price; addon: a venture exists +
///     recomputed price; partner: a venture exists + price). Exit offers /
///     financing offers / the always-legal ReinvestBaseline are NOT
///     counted: the metric is about the dealt tickets themselves.
///   - DEAD-HAND rate = % of ACT phases with 0 playable tickets — the
///     "nothing to do" blotter the playtest hated, quantified.
///   - avg playable tickets per hand (x100 fixed-point).
///   - avg ACTIONS taken per round (x100) = successful policy applies
///     (incl. free consumable plays and shop buys) / rounds survived.
///   - % runs that ever merged / ever exited / ever hired.
/// ==========================================================================
///
/// Usage (cwd = packages/engine):
///   dart run tool/sim.dart [--runs N] [--policy floor|greedy|smart]
///                          [--seed S] [N]
/// Defaults: N=5000, all three policies, seedBase 1.
library;

import 'dart:io';

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/content.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/init.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/resolver.dart';
import 'package:engine/rng.dart';
import 'package:engine/round.dart';

// --- Policy knobs (mirrors of doc 01 §11.3, NOT engine dials) ---

/// Floor target leverage: 3.0x EBITDA (economy constants.targetLeverage).
const int kFloorLeverageMilli = 3000;

/// Greedy leverage line: ~5.8x (doc 01 §11 "just under dangerLeverage").
const int kGreedyLeverageMilli = 5800;

/// Smart's recap ceiling: 4.0x EBITDA — inside doc 01 §7.4's "stretched"
/// amber band (3.0..6.0), never the danger line. Policy heuristic.
const int kSmartRecapLeverageMilli = 4000;

/// The per-ACT debt-pace accrual: 1.2 x EBITDA in permille (sim-check.js
/// `ebitda * 1.2` — see the library header's DEBT PACE block).
const int kDebtPacePermille = 1200;

/// The three policies under test.
enum SimPolicy { floor, greedy, smart }

/// Per-run mutable tally the policy hooks write into (reset per run).
class RunTally {
  /// Successful policy applies this run (any accepted action/buy).
  int actions = 0;

  /// Ever merged an addon / exited a venture / hired a partner.
  bool merged = false;
  bool exited = false;
  bool hired = false;

  /// The FLOOR/GREEDY debt-pace budget in cents (library header).
  int debtBudgetCents = 0;
}

/// Accrues one ACT's debt-pace budget (see [RunTally.debtBudgetCents]).
void _accrueDebtBudget(GameState s, RunTally tally) {
  tally.debtBudgetCents += (_totalEbitda(s) * kDebtPacePermille) ~/ 1000;
}

/// One finished run's outcome.
class RunOutcome {
  RunOutcome({
    required this.won,
    required this.death,
    required this.deathTier,
    required this.clearRounds,
    required this.totalRounds,
    required this.playableCounts,
    required this.actions,
    required this.merged,
    required this.exited,
    required this.hired,
  });

  /// True when the T4 bar was cleared.
  final bool won;

  /// Why the run ended (null on a win).
  final DeathCause? death;

  /// The tier the run died in (-1 on a win).
  final int deathTier;

  /// Round-in-tier each tier was cleared at, index tier-1; -1 = not cleared.
  final List<int> clearRounds;

  /// OPERATEs survived (the run length).
  final int totalRounds;

  /// Playable-ticket count of EVERY hand at ACT start (all tiers).
  final List<int> playableCounts;

  /// Successful policy applies over the whole run.
  final int actions;

  /// Uptake flags (the "plays the game as designed" feel reads).
  final bool merged;
  final bool exited;
  final bool hired;
}

/// Whether [result] carries an ACTION_REJECTED event (no state change).
bool _rejected(ApplyResult result) =>
    result.events.any((e) => e.type == GameEventType.actionRejected);

/// Total EBITDA across ventures, cents.
int _totalEbitda(GameState s) =>
    s.ventures.fold(0, (sum, v) => sum + v.ebitdaCents);

/// Total net debt across ventures, cents.
int _totalNetDebt(GameState s) =>
    s.ventures.fold(0, (sum, v) => sum + v.netDebtCents);

/// The 1-round max-crunch interest buffer the prudent policies keep
/// (round.dart's meters definition; >= every reachable live-rate bill).
int _buffer(GameState s) {
  final service = computeMeters(s).debtServiceNextRoundCents;
  return service > 0 ? service : 0;
}

/// The venture with the highest live multiple (reinvest/hire target —
/// every reinvested dollar's EV gain scales with the multiple). Ties keep
/// list order (deterministic).
Venture _bestVenture(GameState s) {
  var best = s.ventures.first;
  for (final v in s.ventures.skip(1)) {
    if (v.multipleMilli > best.multipleMilli) best = v;
  }
  return best;
}

/// The engine's recomputed addon price (apply.dart's PRE): the card's
/// implied m_buy re-multiplied, which may land a sliver under the face.
int _addonPrice(Card card) {
  final ebitda = card.deltas['ebitda']!;
  final mBuy = (card.cost.cashCents * milliScale) ~/ ebitda;
  return enterpriseValue(ebitda, mBuy);
}

/// The canonical recap pull (doc 01 §7.7) [v]'s EV would yield right now.
int _recapPull(Venture v) =>
    (enterpriseValueOf(v) * kRecapPctBp) ~/ bpScale;

/// FEEL METRIC: how many of this hand's tickets could be played RIGHT NOW
/// (engine PREs only — see the library header for what is counted).
int playableHandCount(GameState s, ContentDb content) {
  var count = 0;
  for (final id in s.hand) {
    final card = content.byId(id);
    switch (card.type) {
      case CardType.venture:
        if (s.ventures.length < slotsMax(s.tier) &&
            s.cashCents >= card.cost.cashCents) count++;
      case CardType.addon:
        if (s.ventures.isNotEmpty && s.cashCents >= _addonPrice(card)) {
          count++;
        }
      case CardType.partner:
        if (s.ventures.isNotEmpty && s.cashCents >= card.cost.cashCents) {
          count++;
        }
      case CardType.financing:
      case CardType.consumable:
      case CardType.event:
        break; // never dealt to the hand
    }
  }
  return count;
}

// --- The shared ACT building blocks ---

/// Exercises debt-shaped financing offers (type financing, dilution 0,
/// +netDebt) while total debt stays <= [leverageMilli] x total EBITDA and
/// the pace budget allows.
GameState _leverUp(GameState s, SplitMix64Rng rng, ContentDb content,
    RunTally tally,
    {required int leverageMilli}) {
  for (final id in [...s.shopOffers]) {
    if (s.playsRemaining < 1 || s.ventures.isEmpty) break;
    final card = content.byId(id);
    if (card.type != CardType.financing ||
        card.cost.dilutionBp > 0 ||
        (card.deltas['netDebt'] ?? 0) <= 0) {
      continue;
    }
    final face = card.deltas['netDebt']!;
    if (face > tally.debtBudgetCents) continue; // the JS pace cap
    final cap = (_totalEbitda(s) * leverageMilli) ~/ milliScale;
    if (_totalNetDebt(s) + face > cap) continue;
    final result = playCard(s, id, rng, content,
        targetVentureId: s.ventures.first.id);
    if (!_rejected(result)) {
      s = result.state;
      tally.actions++;
      tally.debtBudgetCents -= face;
    }
  }
  return s;
}

/// Reinvests `cash - keepCents` (floored at 0) into [target]; fires even
/// at amount 0 to reset the venture's neglect counter (library header).
GameState _reinvest(GameState s, SplitMix64Rng rng, ContentDb content,
    RunTally tally,
    {required String target, required int keepCents}) {
  if (s.playsRemaining < 1) return s;
  var amount = s.cashCents - keepCents;
  if (amount < 0) amount = 0;
  final result = apply(
      s,
      ReinvestBaseline(ventureId: target, amountCents: amount),
      rng,
      content);
  if (_rejected(result)) return s;
  tally.actions++;
  return result.state;
}

// --- FLOOR ---

GameState _floorAct(
    GameState s, SplitMix64Rng rng, ContentDb content, RunTally tally) {
  _accrueDebtBudget(s, tally);
  if (s.market.temp != MarketTemp.cold) {
    // "Take debt up to targetLeverage x EBITDA if market != crunch"
    // (doc 01 §11.3), at the JS pace: the engine's only EV-scaled debt
    // instrument is the canonical recap (trunc(EV x recapPct) as new
    // debt, doc 01 §7.7), so the faithful floor plays a held recap while
    // the pull keeps debt <= 3.0x, then exercises the fixed-face
    // financing offers under the same line.
    if (s.ventures.isNotEmpty && s.playsHeld.contains('PLY_DIVIDEND_RECAP')) {
      final platform = s.ventures.first;
      final pull = _recapPull(platform);
      final cap = (_totalEbitda(s) * kFloorLeverageMilli) ~/ milliScale;
      if (pull > 0 &&
          pull <= tally.debtBudgetCents && // the JS pace cap
          _totalNetDebt(s) + pull <= cap) {
        final result = playCard(s, 'PLY_DIVIDEND_RECAP', rng, content,
            targetVentureId: platform.id);
        if (!_rejected(result)) {
          s = result.state;
          tally.actions++;
          tally.debtBudgetCents -= pull;
        }
      }
    }
    s = _leverUp(s, rng, content, tally, leverageMilli: kFloorLeverageMilli);
  }
  if (s.ventures.isNotEmpty) {
    s = _reinvest(s, rng, content, tally,
        target: s.ventures.first.id, keepCents: _buffer(s));
  }
  return s;
}

GameState _floorShop(GameState s, ContentDb content, RunTally tally) {
  // The floor's one SHOP exception: the recap ticket is its §11.3 "take
  // debt" instrument (cost.cash 0 — buying it spends nothing; the debt
  // only lands when ACT plays it under the 3.0x line and the pace).
  if (s.shopOffers.contains('PLY_DIVIDEND_RECAP') &&
      s.playsHeld.length < playsHeldMax(s.tier)) {
    final result = buyShopOffer(s, 'PLY_DIVIDEND_RECAP', content);
    if (!_rejected(result)) {
      s = result.state;
      tally.actions++;
    }
  }
  return s;
}

// --- GREEDY ---

GameState _greedyAct(
    GameState s, SplitMix64Rng rng, ContentDb content, RunTally tally) {
  _accrueDebtBudget(s, tally);
  // 1. Fire held debt consumables (free plays) under the 5.8x line and
  // the pace budget. PLY_DIVIDEND_RECAP's debt face is the CANONICAL
  // resolve-time pull (trunc(platform EV x recapPct), doc 01 §7.7 — the
  // R12 canon recap), so greedy prices it the way the engine will.
  for (final id in [...s.playsHeld]) {
    if (s.ventures.isEmpty) break;
    final card = content.byId(id);
    final face = id == 'PLY_DIVIDEND_RECAP'
        ? _recapPull(s.ventures.first)
        : (card.deltas['netDebt'] ?? 0);
    if (face <= 0) continue;
    if (face > tally.debtBudgetCents) continue; // the JS pace cap
    final cap = (_totalEbitda(s) * kGreedyLeverageMilli) ~/ milliScale;
    if (_totalNetDebt(s) + face > cap) continue;
    final result = playCard(s, id, rng, content,
        targetVentureId: s.ventures.first.id);
    if (!_rejected(result)) {
      s = result.state;
      tally.actions++;
      tally.debtBudgetCents -= face;
    }
  }
  // 2. Exercise financing in ANY market temp (no crunch prudence).
  s = _leverUp(s, rng, content, tally, leverageMilli: kGreedyLeverageMilli);
  // 3. Reinvest everything, no buffer.
  if (s.ventures.isNotEmpty) {
    s = _reinvest(s, rng, content, tally,
        target: s.ventures.first.id, keepCents: 0);
  }
  return s;
}

GameState _greedyShop(GameState s, ContentDb content, RunTally tally) {
  for (final id in [...s.shopOffers]) {
    if (id != 'PLY_DIVIDEND_RECAP' && id != 'PLY_BRIDGE_LOAN') continue;
    final result = buyShopOffer(s, id, content);
    if (!_rejected(result)) {
      s = result.state;
      tally.actions++;
    }
  }
  return s;
}

// --- SMART ---

/// Counter for minted venture ids (per run; reset by [simulateRun]).
int _ventureSerial = 0;

GameState _smartAct(
    GameState s, SplitMix64Rng rng, ContentDb content, RunTally tally) {
  // 1+2. Exit play: hot-window (arm a held PLY_HOT_WINDOW first — free)
  // or a bubble offer at/above live, never on the sole venture.
  if (s.ventures.length >= 2 && s.exitOffer != null) {
    final offer = s.exitOffer!;
    final idx = s.ventures.indexWhere((v) => v.id == offer.ventureId);
    if (idx >= 0) {
      final live = s.ventures[idx].multipleMilli;
      if (!s.market.hotWindowArmed && s.playsHeld.contains('PLY_HOT_WINDOW')) {
        final result = playCard(s, 'PLY_HOT_WINDOW', rng, content);
        if (!_rejected(result)) {
          s = result.state;
          tally.actions++;
        }
      }
      final hot = s.market.hotWindowArmed;
      final bubble =
          s.market.temp == MarketTemp.hot && offer.offerMultipleMilli >= live;
      if (hot || bubble) {
        final action = exitOfferAction(s);
        if (action != null && s.playsRemaining >= 1) {
          final result = apply(s, action, rng, content);
          if (!_rejected(result)) {
            s = result.state;
            tally.actions++;
            tally.exited = true;
          }
        }
      }
    }
  }
  // 3. Re-found a freed slot from the hand's best venture face.
  if (s.ventures.length < slotsMax(s.tier) && s.playsRemaining >= 1) {
    Card? best;
    var bestValue = 0;
    for (final id in s.hand) {
      final card = content.byId(id);
      if (card.type != CardType.venture) continue;
      if (s.cashCents - card.cost.cashCents < _buffer(s)) continue;
      final value =
          enterpriseValue(card.deltas['ebitda']!, card.deltas['multiple']!) -
              card.cost.cashCents;
      if (best == null || value > bestValue) {
        best = card;
        bestValue = value;
      }
    }
    if (best != null) {
      _ventureSerial++;
      final result = playCard(s, best.id, rng, content,
          targetVentureId: 'sv$_ventureSerial');
      if (!_rejected(result)) {
        s = result.state;
        tally.actions++;
      }
    }
  }
  // 4. Partner hire onto the highest-multiple venture.
  if (s.ventures.isNotEmpty && s.playsRemaining >= 1) {
    for (final id in [...s.hand]) {
      final card = content.byId(id);
      if (card.type != CardType.partner) continue;
      if (s.cashCents - card.cost.cashCents < _buffer(s)) continue;
      final result = playCard(s, id, rng, content,
          targetVentureId: _bestVenture(s).id);
      if (!_rejected(result)) {
        s = result.state;
        tally.actions++;
        tally.hired = true;
      }
      break; // one hire per round
    }
  }
  // 5. Same-sector accretive merges.
  for (final id in [...s.hand]) {
    if (s.playsRemaining < 1) break;
    final card = content.byId(id);
    if (card.type != CardType.addon) continue;
    final price = _addonPrice(card);
    if (s.cashCents - price < _buffer(s)) continue;
    final mBuy = (card.cost.cashCents * milliScale) ~/ card.deltas['ebitda']!;
    Venture? target;
    for (final v in s.ventures) {
      if (v.sector != card.sector || v.multipleMilli <= mBuy) continue;
      if (target == null || v.multipleMilli > target.multipleMilli) {
        target = v;
      }
    }
    if (target == null) continue; // cross-sector / non-accretive: skip
    final result =
        playCard(s, id, rng, content, targetVentureId: target.id);
    if (!_rejected(result)) {
      s = result.state;
      tally.actions++;
      tally.merged = true;
    }
  }
  // 5b. PRUDENT RECAP (library header): a held recap onto the
  // highest-multiple venture while the pull keeps leverage <= 4.0x.
  if (s.ventures.isNotEmpty && s.playsHeld.contains('PLY_DIVIDEND_RECAP')) {
    final target = _bestVenture(s);
    final pull = _recapPull(target);
    final cap = (_totalEbitda(s) * kSmartRecapLeverageMilli) ~/ milliScale;
    if (pull > 0 && _totalNetDebt(s) + pull <= cap) {
      final result = playCard(s, 'PLY_DIVIDEND_RECAP', rng, content,
          targetVentureId: target.id);
      if (!_rejected(result)) {
        s = result.state;
        tally.actions++;
      }
    }
  }
  // 6. Lever like the floor.
  if (s.market.temp != MarketTemp.cold) {
    s = _leverUp(s, rng, content, tally, leverageMilli: kFloorLeverageMilli);
  }
  // 7. Reinvest into the highest-multiple venture; spare plays touch the
  // most-neglected other venture (0-amount decay shield).
  if (s.ventures.isNotEmpty) {
    final best = _bestVenture(s);
    s = _reinvest(s, rng, content, tally,
        target: best.id, keepCents: _buffer(s));
    while (s.playsRemaining >= 1) {
      Venture? neglected;
      for (final v in s.ventures) {
        if (v.roundsNeglected < 1) continue;
        if (neglected == null ||
            v.roundsNeglected > neglected.roundsNeglected) {
          neglected = v;
        }
      }
      if (neglected == null) break;
      final before = s;
      s = _reinvest(s, rng, content, tally,
          target: neglected.id, keepCents: s.cashCents);
      if (identical(s, before)) break; // rejected: stop, never spin
    }
  }
  return s;
}

GameState _smartShop(GameState s, ContentDb content, RunTally tally) {
  for (final id in const ['PLY_HOT_WINDOW', 'PLY_DIVIDEND_RECAP']) {
    if (!s.shopOffers.contains(id)) continue;
    final cost = content.byId(id).cost.cashCents;
    if (s.cashCents - cost < _buffer(s)) continue;
    final result = buyShopOffer(s, id, content);
    if (!_rejected(result)) {
      s = result.state;
      tally.actions++;
    }
  }
  return s;
}

// --- The run loop ---

/// Drives one full run under [policy] with run-seed [seed] (the
/// determinism contract). Returns the outcome.
RunOutcome simulateRun(
    int seed, SimPolicy policy, ContentDb content, EconomyConfig economy) {
  // R20b: the harness re-sweep runs with the FULL pool active — the
  // keystone's whole point. Unlock EVERY card + all six sectors so the
  // draw pools are the entire content (the big-leverage FIN_LBO_LOAN, the
  // dividend recap, asset-strip, the new sectors, SPIN_OFF/EARN_OUT all in
  // play, gated only by tier). This is where "does the fuller game still
  // feel balanced" gets answered against the §11 bands.
  var state = initRun(
    economy: economy,
    unlockedCardIds: [for (final c in content.cards) c.id],
    unlockedSectors: Sector.values,
  );
  final rng = SplitMix64Rng(seed);
  _ventureSerial = 0;
  final tally = RunTally();
  final clearRounds = List<int>.filled(4, -1);
  final playable = <int>[];
  var totalRounds = 0;

  while (true) {
    final op = runOperate(state, rng, content);
    state = op.state;
    totalRounds++;
    if (state.phase == PhaseId.runOver) break; // F6 bankruptcy
    playable.add(playableHandCount(state, content));

    state = switch (policy) {
      SimPolicy.floor => _floorAct(state, rng, content, tally),
      SimPolicy.greedy => _greedyAct(state, rng, content, tally),
      SimPolicy.smart => _smartAct(state, rng, content, tally),
    };

    state = endTurn(state, rng, content);
    state = switch (policy) {
      SimPolicy.floor => _floorShop(state, content, tally),
      SimPolicy.greedy => _greedyShop(state, content, tally),
      SimPolicy.smart => _smartShop(state, content, tally),
    };

    final tierBefore = state.tier;
    final roundBefore = state.round;
    final check = runDeadlineCheck(state);
    state = check.state;
    for (final e in check.events) {
      if (e.type == GameEventType.tierCleared) {
        clearRounds[tierBefore - 1] = roundBefore;
      } else if (e.type == GameEventType.won) {
        clearRounds[3] = roundBefore;
      }
    }
    if (state.phase == PhaseId.runOver) break;
    if (totalRounds > 64) {
      throw StateError('runaway run (seed $seed, $policy)');
    }
  }

  return RunOutcome(
    won: state.won,
    death: state.death,
    deathTier: state.won ? -1 : state.tier,
    clearRounds: clearRounds,
    totalRounds: totalRounds,
    playableCounts: playable,
    actions: tally.actions,
    merged: tally.merged,
    exited: tally.exited,
    hired: tally.hired,
  );
}

// --- Aggregation (integer/fixed-point only) ---

/// Aggregated Monte-Carlo statistics for one policy over N seeded runs.
class SimStats {
  SimStats(this.policy, this.n, List<RunOutcome> outcomes)
      : wins = outcomes.where((o) => o.won).length,
        bankruptcies =
            outcomes.where((o) => o.death == DeathCause.bankruptcy).length,
        missedByTier = List<int>.generate(
            4,
            (t) => outcomes
                .where((o) =>
                    o.death == DeathCause.missedDeadline &&
                    o.deathTier == t + 1)
                .length),
        clearedByTier = List<int>.generate(4,
            (t) => outcomes.where((o) => o.clearRounds[t] >= 0).length),
        medianClearRound = List<int>.generate(4, (t) {
          final rounds = [
            for (final o in outcomes)
              if (o.clearRounds[t] >= 0) o.clearRounds[t]
          ]..sort();
          return rounds.isEmpty ? -1 : rounds[rounds.length ~/ 2];
        }),
        runLengths =
            ([for (final o in outcomes) o.totalRounds]..sort()),
        playableCounts = ([
          for (final o in outcomes) ...o.playableCounts
        ]..sort()),
        totalActions =
            outcomes.fold(0, (sum, o) => sum + o.actions),
        totalRounds =
            outcomes.fold(0, (sum, o) => sum + o.totalRounds),
        mergedRuns = outcomes.where((o) => o.merged).length,
        exitedRuns = outcomes.where((o) => o.exited).length,
        hiredRuns = outcomes.where((o) => o.hired).length;

  final SimPolicy policy;
  final int n;
  final int wins;
  final int bankruptcies;

  /// Missed-deadline deaths per tier (index tier-1).
  final List<int> missedByTier;

  /// Runs that cleared each tier (index tier-1; T4 clear == win).
  final List<int> clearedByTier;

  /// Median round-in-tier each tier was cleared at (-1 = never cleared).
  final List<int> medianClearRound;

  /// Sorted run lengths in OPERATEs.
  final List<int> runLengths;

  /// Sorted playable-ticket counts over EVERY hand (all tiers).
  final List<int> playableCounts;

  /// Successful policy applies, summed over all runs.
  final int totalActions;

  /// OPERATEs survived, summed over all runs.
  final int totalRounds;

  /// Runs that ever merged / exited / hired.
  final int mergedRuns;
  final int exitedRuns;
  final int hiredRuns;

  /// Win rate in permille (integer — the package convention; no double).
  int get winPermille => (wins * 1000) ~/ n;

  /// Bankruptcy rate in permille.
  int get bankruptcyPermille => (bankruptcies * 1000) ~/ n;

  /// Median run length in OPERATEs.
  int get medianRunLength => runLengths[runLengths.length ~/ 2];

  /// DEAD-HAND rate: hands with 0 playable tickets, permille of all hands.
  int get deadHandPermille => playableCounts.isEmpty
      ? -1
      : (playableCounts.where((c) => c == 0).length * 1000) ~/
          playableCounts.length;

  /// Mean playable tickets per hand, x100 fixed-point (e.g. 215 = 2.15).
  int get avgPlayableX100 => playableCounts.isEmpty
      ? -1
      : (playableCounts.fold(0, (a, b) => a + b) * 100) ~/
          playableCounts.length;

  /// Mean successful actions per surviving round, x100 fixed-point.
  int get avgActionsPerRoundX100 =>
      totalRounds == 0 ? 0 : (totalActions * 100) ~/ totalRounds;

  /// Uptake permilles.
  int get mergedPermille => (mergedRuns * 1000) ~/ n;
  int get exitedPermille => (exitedRuns * 1000) ~/ n;
  int get hiredPermille => (hiredRuns * 1000) ~/ n;

  int _lengthAtPercentile(int pct) =>
      runLengths[((runLengths.length - 1) * pct) ~/ 100];
}

/// Runs the batch for one policy: run k = seed (seedBase + k - 1), k in 1..n.
SimStats runBatch(SimPolicy policy, int n, ContentDb content,
    EconomyConfig economy, {int seedBase = 1}) {
  final outcomes = [
    for (var k = 0; k < n; k++)
      simulateRun(seedBase + k, policy, content, economy)
  ];
  return SimStats(policy, n, outcomes);
}

/// One in-thousand as a fixed "xx.x%" string (integer math only).
String _pct(int permille) => '${permille ~/ 10}.${permille % 10}%';

/// x100 fixed-point as "x.yz" (integer math only).
String _x100(int v) =>
    '${v ~/ 100}.${(v % 100) ~/ 10}${v % 10}';

/// Formats one policy's report block (deterministic, byte-stable).
String formatStats(SimStats s) {
  final b = StringBuffer();
  b.writeln('=== ${s.policy.name.toUpperCase()} (N=${s.n}) ===');
  b.writeln('win rate (T1->T4) : ${_pct(s.winPermille)} (${s.wins})');
  b.writeln(
      'bankruptcy rate   : ${_pct(s.bankruptcyPermille)} (${s.bankruptcies})');
  b.writeln('tier | cleared% | missed-deadline% | medianClearRound');
  for (var t = 0; t < 4; t++) {
    final cleared = _pct((s.clearedByTier[t] * 1000) ~/ s.n);
    final missed = _pct((s.missedByTier[t] * 1000) ~/ s.n);
    final median =
        s.medianClearRound[t] < 0 ? '-' : '${s.medianClearRound[t]}';
    b.writeln(' T${t + 1}  | $cleared | $missed | $median');
  }
  b.writeln('run length (OPERATEs) min/p25/median/p75/max: '
      '${s.runLengths.first}/${s._lengthAtPercentile(25)}/'
      '${s._lengthAtPercentile(50)}/${s._lengthAtPercentile(75)}/'
      '${s.runLengths.last}');
  b.writeln('FEEL: dead-hand rate ${_pct(s.deadHandPermille)} of ACT '
      'phases; avg playable tickets/hand ${_x100(s.avgPlayableX100)}; '
      'avg actions/round ${_x100(s.avgActionsPerRoundX100)}');
  b.writeln('UPTAKE: merged ${_pct(s.mergedPermille)} | exited '
      '${_pct(s.exitedPermille)} | hired ${_pct(s.hiredPermille)} of runs');
  return b.toString();
}

void main(List<String> args) {
  var n = 5000;
  var seedBase = 1;
  var policies = SimPolicy.values.toList();
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--runs':
        n = int.parse(args[++i]);
      case '--policy':
        policies = [SimPolicy.values.byName(args[++i])];
      case '--seed':
        seedBase = int.parse(args[++i]);
      default:
        n = int.parse(args[i]); // bare positional N
    }
  }
  final content = loadCards(File('assets/cards.json').readAsStringSync());
  final economy =
      loadEconomy(File('assets/economy-model.json').readAsStringSync());
  stdout.writeln('MULTIPLES full-model Monte-Carlo '
      '(engine schema v$engineSchemaVersion, N=$n, seedBase=$seedBase)');
  stdout.writeln();
  for (final policy in policies) {
    stdout.write(
        formatStats(runBatch(policy, n, content, economy, seedBase: seedBase)));
    stdout.writeln();
  }
}
