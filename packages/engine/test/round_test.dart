// The round machine (Phase 3 round 2) — DEADLINE_CHECK, tier clear/reseed,
// win/death, forward meters, and the strict phase gates.
//
// Doc 02 §2 (the state machine + DEADLINE_CHECK), doc 02 §1 (RunState
// baselines + ForwardMeters), doc 01 §1 (tier-clear rule), §3.3 (reseed
// deltas), §5 (bars/deadlines), §7.4 (runway gauge at the max-crunch rate),
// economy-model.json tierBars / constants.{carrySeedFrac, reseedMult,
// interestMax} / tuningKnobs.crunchRateMul.
//
// Covers, one behavior per test:
//   - model additions: schemaVersion 3, DeathCause order, the two §5.1
//     whitelisted snapshots, won/death defaults + copyWith semantics
//   - tierBarCents 1e8/1e9/1e10/1e11 cents + the T5 unreachable sentinel
//   - endTurn: act -> shop, no economics, StateError elsewhere
//   - runDeadlineCheck: round advance / missed-deadline death / tier clear
//     with the doc 01 §3.3 reseed (uncapped + capped + debt-carry +
//     multi-venture + no-venture variants, exact-integer pins) / T4 win /
//     T5 endless
//   - the reseed no-conjuring property: derived NW never increases
//   - phase + plays gates on apply(): wrong_phase, no_plays_remaining,
//     decrement-on-success-only, the free three (Reroll/PlayConsumable/
//     SellPlay), Reroll's ACT-or-SHOP phase set, gate ordering
//   - runOperate: strict phase gate, netWorthLastRound snapshot (doc 02 §2
//     step 9), death = bankruptcy
//   - ForwardMeters: exact-integer bisection pins (1434 / 1756 / 2000 /
//     1017), saturation, runway boundary, the max-crunch rate
//   - telegraph (doc 02 §5.2 #6): bankruptcy and missed-deadline are
//     pre-flagged by the meters on crafted fixtures
//   - the full machine: operate -> act -> shop -> deadline check looped,
//     round/tier/phase/snapshots asserted at each step
//
// All money is integer cents; no floating point anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/init.dart';
import 'package:engine/meta.dart' show backgroundFor;
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/resolver.dart';
import 'package:engine/rng.dart';
import 'package:engine/round.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Venture venture({
  String id = 'v1',
  Sector sector = Sector.software,
  int ebitdaCents = 600000,
  int multipleMilli = 6000,
  int netDebtCents = 0,
  int ownershipBp = 10000,
  bool passive = false,
  int roundsNeglected = 0,
}) =>
    Venture(
      id: id,
      sector: sector,
      ebitdaCents: ebitdaCents,
      multipleMilli: multipleMilli,
      netDebtCents: netDebtCents,
      ownershipBp: ownershipBp,
      passive: passive,
      roundsNeglected: roundsNeglected,
    );

/// A mid-ACT state with budget to act: tier 4 (recap un-gated, 3 slots),
/// 3 plays, two equity-positive ventures — every action's success path is
/// reachable (mirrors the §7 invariant fixture).
GameState actFixture({int playsRemaining = 3, PhaseId phase = PhaseId.act}) =>
    GameState(
      ventures: [
        venture(
            id: 'v1',
            ebitdaCents: 600000,
            multipleMilli: 14000,
            netDebtCents: 100000,
            ownershipBp: 8000),
        venture(
            id: 'v2',
            sector: Sector.retail,
            ebitdaCents: 400000,
            multipleMilli: 3000),
      ],
      cashCents: 5000000,
      round: 2,
      tier: 4,
      phase: phase,
      playsRemaining: playsRemaining,
      playsHeld: const ['p'], // PlayConsumable/SellPlay membership gate
    );

/// A SHOP-phase state ready for DEADLINE_CHECK.
GameState shopState({
  List<Venture>? ventures,
  int cashCents = 5000000,
  int round = 2,
  int tier = 1,
  int rerollsUsed = 1,
  int netWorthAtTierEntry = 5600000,
}) =>
    GameState(
      ventures: ventures ?? const [],
      cashCents: cashCents,
      round: round,
      tier: tier,
      phase: PhaseId.shop,
      rerollsUsed: rerollsUsed,
      netWorthAtTierEntry: netWorthAtTierEntry,
    );

/// Every play-COSTING action's success payload against [actFixture]
/// (doc 02 §3 matrix: everything except REROLL / PLAY_CONSUMABLE /
/// sell-a-play costs 1 play).
Map<String, Action> costingActions() => {
      'StartVenture': const StartVenture(
        ventureId: 'v3',
        sector: Sector.services,
        ebitdaCents: 500000,
        multipleMilli: 6000,
        priceCents: 1000000,
        faceDebtCents: 200000,
      ),
      'RaiseEquity': const RaiseEquity(ventureId: 'v1', raiseCents: 1000000),
      'TakeDebt': const TakeDebt(
          ventureId: 'v1', proceedsCents: 1000000, faceDebtCents: 1150000),
      'AcquireAddOn': const AcquireAddOn(
        targetVentureId: 'v1',
        addonSector: Sector.software,
        addonEbitdaCents: 100000,
        addonBuyMultipleMilli: 5000,
        addonFaceDebtCents: 50000,
      ),
      'DividendRecap': const DividendRecap(ventureId: 'v1', recapPctBp: 3000),
      'ExitVenture': const ExitVenture(
          ventureId: 'v2',
          offerMultipleMilli: 3500,
          liveMarketMultipleMilli: 3200),
      'HireCEO': const HireCEO(ventureId: 'v1', costCents: 500000),
      'ReinvestBaseline':
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
    };

/// The three FREE actions (doc 02 §3 matrix: no throughput cost).
Map<String, Action> freeActions() => {
      'Reroll': const Reroll(costCents: 250000),
      'SellPlay': const SellPlay(playId: 'p', purchasePriceCents: 400000),
      'PlayConsumable':
          PlayConsumable(playId: 'p', deltas: const {'cash': -300000}),
    };

bool wasRejected(ApplyResult r, [String? reason]) => r.events.any((e) =>
    e.type == GameEventType.actionRejected &&
    (reason == null || e.reason == reason));

void main() {
  // -------------------------------------------------------------------------
  // Model additions (schemaVersion 3)
  // -------------------------------------------------------------------------
  group('model: round-machine fields (doc 02 §1 RunState)', () {
    test('engineSchemaVersion is 10 (R20b: the draw-pool keystone — the full '
        'unlocked card set into play, the frozen unlock snapshot on the '
        'state, SPIN_OFF/EARN_OUT resolvers; the widened pool moved the '
        'stream)', () {
      expect(engineSchemaVersion, 10);
      expect(GameState(ventures: const [], cashCents: 0).schemaVersion, 10);
    });

    test('DeathCause declaration order is the replay contract', () {
      expect(DeathCause.values, [
        DeathCause.bankruptcy,
        DeathCause.missedDeadline,
      ]);
      expect(DeathCause.bankruptcy.index, 0);
      expect(DeathCause.missedDeadline.index, 1);
    });

    test('snapshots/won/death default to 0/0/false/null', () {
      final s = GameState(ventures: const [], cashCents: 0);
      expect(s.netWorthAtTierEntry, 0);
      expect(s.netWorthLastRound, 0);
      expect(s.won, isFalse);
      expect(s.death, isNull);
    });

    test('copyWith round-trips each new field and breaks equality', () {
      final s = GameState(ventures: const [], cashCents: 0);
      expect(s.copyWith(netWorthAtTierEntry: 7), isNot(s));
      expect(s.copyWith(netWorthAtTierEntry: 7).netWorthAtTierEntry, 7);
      expect(s.copyWith(netWorthLastRound: 9), isNot(s));
      expect(s.copyWith(netWorthLastRound: 9).netWorthLastRound, 9);
      expect(s.copyWith(won: true), isNot(s));
      expect(s.copyWith(won: true).won, isTrue);
      expect(s.copyWith(death: DeathCause.bankruptcy), isNot(s));
      expect(s.copyWith(death: DeathCause.bankruptcy).death,
          DeathCause.bankruptcy);
    });

    test('death is terminal: copyWith never clears it', () {
      final dead = GameState(ventures: const [], cashCents: 0)
          .copyWith(death: DeathCause.missedDeadline);
      // A later unrelated copyWith (death omitted -> null) keeps the cause.
      expect(dead.copyWith(cashCents: 5).death, DeathCause.missedDeadline);
    });
  });

  // -------------------------------------------------------------------------
  // Tier bars (economy-model.json tierBars; doc 01 §5)
  // -------------------------------------------------------------------------
  group('tierBarCents (economy-model.json tierBars)', () {
    test('bars are 1e8/1e9/1e10/1e11 cents for T1..T4 (10x ladder)', () {
      expect(tierBarCents(1), 100000000); // $1M
      expect(tierBarCents(2), 1000000000); // $10M
      expect(tierBarCents(3), 10000000000); // $100M
      expect(tierBarCents(4), 100000000000); // $1B — the win bar
    });

    test('T5 endless is the unreachable sentinel (doc 02 §2)', () {
      expect(tierBarCents(5), endlessBarSentinelCents);
      expect(endlessBarSentinelCents, 0x7FFFFFFFFFFFFFFF);
    });

    test('throws on a tier outside 1..5', () {
      expect(() => tierBarCents(0), throwsArgumentError);
      expect(() => tierBarCents(6), throwsArgumentError);
    });
  });

  // -------------------------------------------------------------------------
  // endTurn (doc 02 §3.11 END_TURN)
  // -------------------------------------------------------------------------
  group('endTurn (doc 02 §3.11 + the deal-flow SHOP draw)', () {
    test('moves act -> shop, deals exactly kShopOfferCount offers, and '
        'changes NOTHING else', () {
      final before = actFixture(playsRemaining: 2);
      final rng = SplitMix64Rng(31);
      final after = endTurn(before, rng, kContent);
      expect(after.phase, PhaseId.shop);
      expect(after.shopOffers.length, kShopOfferCount,
          reason: 'entering SHOP deals the counter (doc 02 §2 SHOP)');
      expect(rng.cursor, kShopOfferCount,
          reason: 'the shop routine is the ONLY draw in endTurn');
      expect(
          after,
          before.copyWith(
              phase: PhaseId.shop,
              shopOffers: after.shopOffers,
              rngCursor: rng.cursor),
          reason: 'END_TURN has no economic delta (doc 02 §3.11) beyond '
              'the offer deal + cursor reconcile');
      expect(after.cashCents, before.cashCents);
      expect(after.playsRemaining, 2,
          reason: 'ending the turn early forfeits, never spends, plays');
    });

    test('throws StateError outside ACT', () {
      for (final phase in [
        PhaseId.operate,
        PhaseId.shop,
        PhaseId.deadlineCheck,
        PhaseId.runOver,
      ]) {
        expect(
            () => endTurn(actFixture(phase: phase), SplitMix64Rng(1), kContent),
            throwsStateError,
            reason: 'endTurn from $phase must be a caller bug');
      }
    });
  });

  // -------------------------------------------------------------------------
  // DEADLINE_CHECK: round advance + missed deadline (doc 02 §2)
  // -------------------------------------------------------------------------
  group('runDeadlineCheck: bar not cleared (doc 02 §2)', () {
    test('requires phase == shop (StateError otherwise)', () {
      for (final phase in [
        PhaseId.operate,
        PhaseId.act,
        PhaseId.deadlineCheck,
        PhaseId.runOver,
      ]) {
        final s = GameState(
            ventures: const [], cashCents: 0, round: 1, tier: 1, phase: phase);
        expect(() => runDeadlineCheck(s), throwsStateError,
            reason: 'deadline check from $phase must be a caller bug');
      }
    });

    test('round < deadline: round+1, plays/rerolls reset, phase operate, '
        'no events', () {
      final before = shopState(cashCents: 5000000, round: 2, tier: 1);
      expect(before.netWorthCents, lessThan(tierBarCents(1)));
      final result = runDeadlineCheck(before);
      expect(result.state.round, 3);
      expect(result.state.tier, 1);
      expect(result.state.phase, PhaseId.operate);
      expect(result.state.playsRemaining, playsPerRound(1));
      expect(result.state.rerollsUsed, 0);
      expect(result.state.death, isNull);
      expect(result.state.won, isFalse);
      expect(result.events, isEmpty,
          reason: 'a plain round advance is not an event');
      expect(result.state.netWorthAtTierEntry, before.netWorthAtTierEntry,
          reason: 'the tier-entry snapshot only moves on a tier ADVANCE');
      expect(result.state.cashCents, before.cashCents);
      expect(result.state.actionLog, before.actionLog);
    });

    test('the round BEFORE the deadline still advances (rounds allowed == '
        'deadline)', () {
      // T1 deadline is 9 (R12): round 8 -> 9 is legal; round 9 is the
      // last chance.
      final result =
          runDeadlineCheck(shopState(cashCents: 100, round: 8, tier: 1));
      expect(result.state.round, 9);
      expect(result.state.phase, PhaseId.operate);
    });

    test('out of rounds: RUN_OVER, death = missedDeadline, MISSED_DEADLINE '
        'event', () {
      final before = shopState(cashCents: 5000000, round: 9, tier: 1);
      final result = runDeadlineCheck(before);
      expect(result.state.phase, PhaseId.runOver);
      expect(result.state.death, DeathCause.missedDeadline);
      expect(result.state.won, isFalse);
      expect(result.state.round, 9,
          reason: 'the autopsy reads the death round from the state');
      expect(result.state.tier, 1);
      expect(result.state.playsRemaining, 0,
          reason: 'a dead run gets no plays (bankruptcy precedent)');
      final deaths = result.events
          .where((e) => e.type == GameEventType.missedDeadline);
      expect(deaths, hasLength(1));
      expect(deaths.single.amount, before.netWorthCents,
          reason: 'the event headlines the final net worth');
    });

    test('deadlines are per tier: 9/10/9/10 (economy tierBars; T1/T2 '
        'loosened in the R12 tune)', () {
      // Round == deadline and the bar missed -> death, per tier.
      const deadlines = {1: 9, 2: 10, 3: 9, 4: 10};
      for (final entry in deadlines.entries) {
        final live = runDeadlineCheck(shopState(
            cashCents: 100, round: entry.value - 1, tier: entry.key));
        expect(live.state.phase, PhaseId.operate,
            reason: 'T${entry.key} round ${entry.value - 1} must advance');
        final dead = runDeadlineCheck(
            shopState(cashCents: 100, round: entry.value, tier: entry.key));
        expect(dead.state.death, DeathCause.missedDeadline,
            reason: 'T${entry.key} dies at round ${entry.value}');
      }
    });
  });

  // -------------------------------------------------------------------------
  // DEADLINE_CHECK: tier clear + reseed (doc 01 §1, §3.3)
  // -------------------------------------------------------------------------
  group('runDeadlineCheck: tier clear + reseed (doc 01 §3.3)', () {
    /// Designed-path clear: the venture dominates net worth, so the 0.37*NW
    /// seed is far below the EV/8 cap and the doc formula applies verbatim.
    /// EV = 12e6 * 14000 / 1000 = 168,000,000; stake 168e6 + cash 32e6
    /// -> NW = 200,000,000 >= T1's 1e8 bar.
    GameState uncappedClear() => shopState(
          ventures: [
            venture(id: 'plat', ebitdaCents: 12000000, multipleMilli: 14000)
          ],
          cashCents: 32000000,
          round: 3,
          tier: 1,
        );

    test('clears: tier+1, round 1, plays/rerolls reset, phase operate, '
        'TIER_CLEARED', () {
      final result = runDeadlineCheck(uncappedClear());
      expect(result.state.tier, 2);
      expect(result.state.round, 1);
      expect(result.state.phase, PhaseId.operate);
      expect(result.state.playsRemaining, playsPerRound(2));
      expect(result.state.rerollsUsed, 0);
      expect(result.state.death, isNull);
      expect(result.state.won, isFalse);
      final cleared =
          result.events.where((e) => e.type == GameEventType.tierCleared);
      expect(cleared, hasLength(1));
      expect(cleared.single.amount, 200000000,
          reason: 'the event headlines the bar-clearing net worth');
    });

    test('netWorthAtTierEntry snapshots the PRE-reseed clearing net worth',
        () {
      // Doc 01 §6 keys its 10x-per-tier table off the cleared bar value, so
      // the entry baseline is the mark that cleared, before the haircut.
      final result = runDeadlineCheck(uncappedClear());
      expect(result.state.netWorthAtTierEntry, 200000000);
    });

    test('clearing ON the deadline round advances (doc 01 §1: evaluated "on '
        'or before the tier deadline"); one cent short on it kills', () {
      const deadlines = {1: 9, 2: 10, 3: 9, 4: 10};
      for (final entry in deadlines.entries) {
        final tier = entry.key;
        // An all-cash NW of exactly the bar, ON the deadline round:
        final cleared = runDeadlineCheck(shopState(
            cashCents: tierBarCents(tier), round: entry.value, tier: tier));
        expect(cleared.state.death, isNull,
            reason: 'T$tier: clearing on the deadline round is not a death');
        if (tier == 4) {
          expect(cleared.state.won, isTrue,
              reason: 'T4: the deadline-round clear IS the \$1B win');
          expect(cleared.state.phase, PhaseId.runOver);
        } else {
          expect(cleared.state.tier, tier + 1,
              reason: 'T$tier: the deadline-round clear advances the tier');
          expect(cleared.state.round, 1);
          expect(cleared.state.phase, PhaseId.operate);
        }
        // The same round one cent short: the growth-rate death.
        final dead = runDeadlineCheck(shopState(
            cashCents: tierBarCents(tier) - 1,
            round: entry.value,
            tier: tier));
        expect(dead.state.death, DeathCause.missedDeadline,
            reason: 'T$tier: nw == bar - 1 on the deadline round dies');
      }
    });

    test('reseed (uncapped): ebitda set to trunc(0.37*NW*1000/8000), '
        'multiple set to 8000, debt/own/cash carried (carrySeedFrac 0.37 '
        'since the R12 tune)', () {
      // seedEbitda = trunc(200,000,000 * 37 * 1000 / (100 * 8000))
      //            = 9,250,000 (one final division).
      final result = runDeadlineCheck(uncappedClear());
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 9250000);
      expect(v.multipleMilli, 8000);
      expect(v.netDebtCents, 0, reason: 'netDebt delta is 0 (doc 01 §3.3)');
      expect(v.ownershipBp, 10000, reason: 'you carry your slice');
      expect(result.state.cashCents, 32000000,
          reason: 'pocket cash carries as-is; no cash injected');
      // The reseeded venture re-derives to 9.25e6 * 8 = 74e6 of stake:
      expect(result.state.netWorthCents, 106000000);
    });

    test('reseed reconciles: dNetWorth == the reseeded venture stake delta '
        '(§7: no value conjured outside the five inputs)', () {
      final before = uncappedClear();
      final preStake = (equityValueOf(before.ventures.single) *
              before.ventures.single.ownershipBp) ~/
          bpScale;
      final result = runDeadlineCheck(before);
      final postStake = (equityValueOf(result.state.ventures.single) *
              result.state.ventures.single.ownershipBp) ~/
          bpScale;
      expect(result.state.netWorthCents - before.netWorthCents,
          postStake - preStake,
          reason: 'cash carries as-is, so the whole NW move is the stake');
      expect(result.state.netWorthCents - before.netWorthCents, -94000000,
          reason: 'stake 168e6 -> 74e6 (carrySeedFrac 0.37, R12)');
    });

    test('reseed is LOGGED like any other action (doc 01 §3.3)', () {
      final before = uncappedClear();
      final result = runDeadlineCheck(before);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.summary, contains('TierReseed'));
      expect(result.state.actionLog.last.round, before.round,
          reason: 'logged against the round the clear happened in');
    });

    test('reseed (capped): the seed never marks the venture UP — cash-heavy '
        'clears cap at pre-reseed EV', () {
      // EV = 100,000 * 3000 / 1000 = 300,000; NW = 300,000 + 199,700,000
      // = 200,000,000. Uncapped seed 6,000,000 would re-derive the venture
      // to 48e6 — conjured value. Cap = trunc(EV * 1000 / 8000) = 37,500,
      // so the venture re-derives to exactly its old EV (300,000) at 8x.
      final before = shopState(
        ventures: [
          venture(id: 'runt', sector: Sector.retail, ebitdaCents: 100000,
              multipleMilli: 3000)
        ],
        cashCents: 199700000,
        round: 3,
        tier: 1,
      );
      final result = runDeadlineCheck(before);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 37500);
      expect(v.multipleMilli, 8000);
      expect(enterpriseValueOf(v), 300000,
          reason: 'value-neutral normalization at the cap');
      expect(result.state.netWorthCents, before.netWorthCents,
          reason: 'the cap binds exactly where the doc formula would have '
              'conjured net worth');
    });

    test('reseed carries debt and partial ownership through unchanged', () {
      // EV 168e6, debt 20e6, own 80% -> stake trunc(148e6*8000/10000)
      // = 118,400,000; + cash 32e6 -> NW = 150,400,000.
      final before = shopState(
        ventures: [
          venture(
              id: 'plat',
              ebitdaCents: 12000000,
              multipleMilli: 14000,
              netDebtCents: 20000000,
              ownershipBp: 8000)
        ],
        cashCents: 32000000,
        round: 4,
        tier: 1,
      );
      expect(before.netWorthCents, 150400000);
      final result = runDeadlineCheck(before);
      final v = result.state.ventures.single;
      // seed = trunc(150,400,000 * 37000 / 800,000) = 6,956,000 (R12
      // carrySeedFrac 0.37).
      expect(v.ebitdaCents, 6956000);
      expect(v.multipleMilli, 8000);
      expect(v.netDebtCents, 20000000, reason: 'debt carries (delta 0)');
      expect(v.ownershipBp, 8000, reason: 'ownership carries');
      // NW' = trunc((6,956,000*8 - 20e6) * 8000/10000) + 32e6 = 60,518,400.
      expect(result.state.netWorthCents, 60518400);
    });

    test('a negative-equity platform reseeds value-neutrally: the 8000 SET '
        'plus the capped ebitda cannot lift NW (equity stays negative)', () {
      // EV = 300,000 but debt 10e6: equity -9.7e6; the clear rides on cash.
      final before = shopState(
        ventures: [
          venture(
              id: 'sunk',
              sector: Sector.retail,
              ebitdaCents: 100000,
              multipleMilli: 3000,
              netDebtCents: 10000000)
        ],
        cashCents: 110000000,
        round: 5,
        tier: 1,
      );
      expect(before.netWorthCents, 100300000,
          reason: 'fixture must clear via cash with equity under water');
      final result = runDeadlineCheck(before);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 37500,
          reason: 'cap = trunc(EV x 1000 / 8000) binds, not the NW formula');
      expect(v.multipleMilli, 8000);
      expect(v.netDebtCents, 10000000, reason: 'debt carries (delta 0)');
      expect(enterpriseValueOf(v), 300000,
          reason: 'EV preserved exactly: 8 x the capped seed');
      expect(result.state.netWorthCents, before.netWorthCents,
          reason: 'raising the multiple to 8000 conjures nothing');
    });

    test('multi-venture: the reseed targets ventures.first; the rest carry '
        'untouched (documented engine interpretation)', () {
      final before = shopState(
        ventures: [
          venture(id: 'first', ebitdaCents: 12000000, multipleMilli: 14000),
          venture(
              id: 'second',
              sector: Sector.retail,
              ebitdaCents: 10000000,
              multipleMilli: 3000),
        ],
        cashCents: 2000000,
        round: 3,
        tier: 1,
      );
      expect(before.netWorthCents, 200000000);
      final result = runDeadlineCheck(before);
      // seed = trunc(200e6 x 37 x 1000 / (100 x 8000)) — carrySeedFrac 0.37
      // since the R12 tune.
      expect(result.state.ventures.first.ebitdaCents, 9250000);
      expect(result.state.ventures.first.multipleMilli, 8000);
      expect(result.state.ventures.last,
          before.ventures.last.copyWith(), // value-identical carry
          reason: 'only the carried platform is reseeded');
      expect(result.state.netWorthCents, 106000000); // 74e6 + 30e6 + 2e6
    });

    test('a venture-less clear advances with NO reseed and NO log entry',
        () {
      final before =
          shopState(ventures: const [], cashCents: 100000000, tier: 1);
      final result = runDeadlineCheck(before);
      expect(result.state.tier, 2);
      expect(result.state.ventures, isEmpty);
      expect(result.state.actionLog, before.actionLog);
      expect(result.state.netWorthCents, before.netWorthCents,
          reason: 'nothing to seed: all-cash carries unchanged');
    });

    test('the reseed NEVER increases derived net worth (the no-conjuring '
        'property doc 01 §3.3 claims)', () {
      final fixtures = [
        uncappedClear(), // designed path: strict haircut
        shopState(// cap boundary: value-neutral
            ventures: [
              venture(id: 'runt', sector: Sector.retail, ebitdaCents: 100000,
                  multipleMilli: 3000)
            ],
            cashCents: 199700000,
            tier: 1),
        shopState(// debt + partial ownership
            ventures: [
              venture(
                  id: 'plat',
                  ebitdaCents: 12000000,
                  multipleMilli: 14000,
                  netDebtCents: 20000000,
                  ownershipBp: 8000)
            ],
            cashCents: 32000000,
            tier: 1),
        shopState(// T3 -> T4 scale
            ventures: [
              venture(id: 'big', ebitdaCents: 900000000,
                  multipleMilli: 14000)
            ],
            cashCents: 500000000,
            tier: 3),
        shopState(// venture-dominant RETAIL: multiple SET 3000 -> 8000 with
            // the uncapped formula binding — the ebitda cut must dominate
            // the raise on the low-multiple platform
            ventures: [
              venture(id: 'shop', sector: Sector.retail,
                  ebitdaCents: 50000000, multipleMilli: 3000)
            ],
            cashCents: 1000000,
            tier: 1),
        shopState(// negative equity: debt > EV, cash carries the clear
            ventures: [
              venture(id: 'sunk', ebitdaCents: 100000, multipleMilli: 3000,
                  netDebtCents: 10000000)
            ],
            cashCents: 110000000,
            tier: 1),
      ];
      for (final before in fixtures) {
        final result = runDeadlineCheck(before);
        expect(result.state.tier, before.tier + 1,
            reason: 'fixture must actually clear');
        expect(result.state.netWorthCents,
            lessThanOrEqualTo(before.netWorthCents),
            reason: 'reseed is a haircut/normalization, never a top-up');
      }
      // And the designed path is a STRICT reduction:
      expect(runDeadlineCheck(uncappedClear()).state.netWorthCents,
          lessThan(uncappedClear().netWorthCents));
    });
  });

  // -------------------------------------------------------------------------
  // DEADLINE_CHECK: the T4 win + T5 endless (doc 02 §2)
  // -------------------------------------------------------------------------
  group('runDeadlineCheck: win + endless (doc 02 §2)', () {
    GameState aboutToWin() => shopState(
          ventures: [
            venture(id: 'money', ebitdaCents: 8000000000,
                multipleMilli: 14000)
          ],
          cashCents: 0,
          round: 5,
          tier: 4,
          netWorthAtTierEntry: 10000000000,
        );

    test('clearing the T4 bar IS the win: won=true, runOver, WON event', () {
      final before = aboutToWin();
      expect(before.netWorthCents, 112000000000);
      final result = runDeadlineCheck(before);
      expect(result.state.won, isTrue);
      expect(result.state.phase, PhaseId.runOver);
      expect(result.state.death, isNull,
          reason: 'a win is not a death');
      expect(result.state.tier, 4, reason: 'no advance past the win');
      expect(result.state.round, 5);
      expect(result.state.playsRemaining, 0);
      final wonEvents =
          result.events.where((e) => e.type == GameEventType.won);
      expect(wonEvents, hasLength(1));
      expect(wonEvents.single.amount, 112000000000);
    });

    test('the win does NOT reseed or snapshot a new tier entry', () {
      final before = aboutToWin();
      final result = runDeadlineCheck(before);
      expect(result.state.ventures.single, before.ventures.single);
      expect(result.state.netWorthAtTierEntry, 10000000000);
      expect(result.state.actionLog, before.actionLog);
    });

    test('T5 endless never WINS even at a huge net worth (doc 02 §2): a '
        'mid-ante round just advances', () {
      // Round 3 is NOT an ante deadline (10 | round), so it advances with
      // no bar check — and the win bar is the unreachable sentinel, so even
      // a $10B net worth never trips `won`.
      final result = runDeadlineCheck(
          shopState(cashCents: 1000000000000, round: 3, tier: 5));
      expect(result.state.tier, 5);
      expect(result.state.round, 4);
      expect(result.state.phase, PhaseId.operate);
      expect(result.state.won, isFalse, reason: 'won is never set in T5');
      // Bootstrapper background (shopState default) -> no +1; the grant is
      // playsPerRound(5).
      expect(result.state.playsRemaining, playsGrantedForRound(5, 'BOOTSTRAPPER'));
    });

    test('T5 endless ESCALATES (audit L1): clearing an ante\'s rising bar '
        'advances + emits ENDLESS_ANTE_CLEARED, the bar rises next ante', () {
      // Entry NW $10M; ante 1 deadline = round 10; bar = 10M x 1.5 = 15M.
      // Net worth $20M clears it.
      final entry = 10000000;
      final s = shopState(
        ventures: [
          venture(id: 'big', ebitdaCents: 2500000, multipleMilli: 8000),
        ],
        cashCents: 0,
        round: kEndlessAnteRounds, // round 10 = the ante deadline
        tier: 5,
        netWorthAtTierEntry: entry,
      );
      expect(s.netWorthCents, 20000000, reason: 'EV 2.5M x 8 = 20M, no debt');
      expect(endlessSurvivalBarCents(entry, kEndlessAnteRounds), 15000000,
          reason: 'ante 1 bar = entry x 1.5');
      final result = runDeadlineCheck(s);
      expect(result.state.death, isNull, reason: 'cleared — still alive');
      expect(result.state.round, kEndlessAnteRounds + 1);
      expect(result.state.won, isFalse, reason: 'endless never wins');
      expect(result.events.any((e) => e.type == GameEventType.endlessAnteCleared),
          isTrue);
      // The next ante (round 20) demands the ESCALATED bar (x1.5^2 = 22.5M).
      expect(endlessSurvivalBarCents(entry, kEndlessAnteRounds * 2), 22500000,
          reason: 'ante 2 bar is higher — escalation');
    });

    test('T5 endless FAILS OUT when it can\'t keep pace with the rising bar '
        '(doc 02 §2 fails-out, never wins)', () {
      // Entry NW $10M; ante 1 bar = 15M. Net worth only $12M -> below bar.
      final entry = 10000000;
      final s = shopState(
        ventures: [
          venture(id: 'small', ebitdaCents: 1500000, multipleMilli: 8000),
        ],
        cashCents: 0,
        round: kEndlessAnteRounds,
        tier: 5,
        netWorthAtTierEntry: entry,
      );
      expect(s.netWorthCents, 12000000, reason: 'EV 1.5M x 8 = 12M < 15M bar');
      final result = runDeadlineCheck(s);
      expect(result.state.phase, PhaseId.runOver);
      expect(result.state.death, DeathCause.missedDeadline,
          reason: 'endless fails out on the escalating deadline');
      expect(result.state.won, isFalse);
      expect(result.state.playsRemaining, 0);
      final miss =
          result.events.where((e) => e.type == GameEventType.missedDeadline);
      expect(miss, hasLength(1));
      expect(miss.single.reason, 'endless_below_escalating_bar');
    });

    test('T5 endless mid-ante rounds always advance (only the ante '
        'deadline evaluates the bar)', () {
      // Round 7 is mid-ante (not a multiple of 10): advance regardless of
      // a tiny net worth.
      final result = runDeadlineCheck(shopState(
          cashCents: 100, round: 7, tier: 5, netWorthAtTierEntry: 10000000));
      expect(result.state.round, 8);
      expect(result.state.death, isNull,
          reason: 'no bar check off the ante deadline');
    });

    test('endlessAnteOf / isEndlessAnteDeadline map rounds to antes', () {
      expect(endlessAnteOf(1), 1);
      expect(endlessAnteOf(kEndlessAnteRounds), 1);
      expect(endlessAnteOf(kEndlessAnteRounds + 1), 2);
      expect(isEndlessAnteDeadline(kEndlessAnteRounds), isTrue);
      expect(isEndlessAnteDeadline(kEndlessAnteRounds * 2), isTrue);
      expect(isEndlessAnteDeadline(kEndlessAnteRounds - 1), isFalse);
      expect(isEndlessAnteDeadline(1), isFalse);
    });

    test('T5 endless TERMINATES: the geometric bar compounds monotonically '
        'so it outruns any finite net worth in a bounded number of antes '
        '(the run cannot go forever)', () {
      // The bar rises strictly each ante (x1.5 every time), so for any fixed
      // net worth there is a finite ante where bar > nw and the run fails.
      const entry = 5600000; // the $56k seed * 100 scale; any positive entry
      var prev = entry;
      for (var ante = 1; ante <= 60; ante++) {
        final round = kEndlessAnteRounds * ante;
        final bar = endlessSurvivalBarCents(entry, round);
        expect(bar, greaterThanOrEqualTo(prev),
            reason: 'the bar never decreases ante-to-ante (monotone rising)');
        prev = bar;
      }
      // Within a modest number of antes the bar has multiplied many-fold
      // over entry — no finite net worth survives indefinitely.
      final farBar = endlessSurvivalBarCents(entry, kEndlessAnteRounds * 30);
      expect(farBar, greaterThan(entry * 1000),
          reason: 'ante 30 demands >1000x entry — termination is guaranteed');
    });

    test('T5 endless CAP: the rising bar saturates (satMul) and never '
        'overflows int64, even at an absurd ante depth', () {
      // A huge entry compounded 200 antes deep would overflow a naive int64
      // multiply; satMul caps each step so the bar stays a sane sentinel
      // instead of wrapping negative (audit M3 co-design).
      const bigEntry = 1000000000000000; // $10B in cents
      final deepBar =
          endlessSurvivalBarCents(bigEntry, kEndlessAnteRounds * 200);
      expect(deepBar, greaterThan(0),
          reason: 'never wraps to a negative bar (the overflow backstop)');
      // A non-positive entry yields a 0 bar (degenerate guard).
      expect(endlessSurvivalBarCents(0, kEndlessAnteRounds), 0);
      expect(endlessSurvivalBarCents(-100, kEndlessAnteRounds), 0);
    });
  });

  // -------------------------------------------------------------------------
  // The DEALMAKER +1-play grant (schemaVersion 9; R14-deferred, audit)
  // -------------------------------------------------------------------------
  group('founder-background plays grant (the Dealmaker +1)', () {
    test('playsGrantedForRound adds the background extra to playsPerRound', () {
      // Bootstrapper: no extra -> exactly playsPerRound(tier).
      for (final t in [1, 2, 3, 4, 5]) {
        expect(playsGrantedForRound(t, 'BOOTSTRAPPER'), playsPerRound(t));
      }
      // Dealmaker: +1 every tier.
      expect(backgroundFor('DEALMAKER').extraPlaysPerRound, 1);
      for (final t in [1, 2, 3, 4, 5]) {
        expect(playsGrantedForRound(t, 'DEALMAKER'), playsPerRound(t) + 1);
      }
    });

    test('initRun carries the backgroundId onto the run state', () {
      expect(initRun(economy: kEconomyConfig).backgroundId, 'BOOTSTRAPPER');
      expect(
          initRun(economy: kEconomyConfig, backgroundId: 'DEALMAKER')
              .backgroundId,
          'DEALMAKER');
    });

    test('Dealmaker T1: the first OPERATE grants playsPerRound(1) + 1 = 3',
        () {
      final start = initRun(economy: kEconomyConfig, backgroundId: 'DEALMAKER');
      expect(start.tier, 1);
      final after = runOperate(start, SplitMix64Rng(42), kContent).state;
      expect(after.phase, PhaseId.act, reason: 'the run is alive');
      expect(after.playsRemaining, playsPerRound(1) + 1);
      expect(after.playsRemaining, 3, reason: 'T1 base 2 + Dealmaker 1');
      // The background rides through OPERATE unchanged.
      expect(after.backgroundId, 'DEALMAKER');
    });

    test('Bootstrapper T1: the first OPERATE grants the base 2 (no +1)', () {
      final start = initRun(economy: kEconomyConfig); // BOOTSTRAPPER
      final after = runOperate(start, SplitMix64Rng(42), kContent).state;
      expect(after.playsRemaining, 2, reason: 'no background extra');
    });

    test('the Dealmaker +1 re-stages on a round advance and a tier clear',
        () {
      // Round advance: a shop state that just advances re-stages the grant.
      final advancing = shopState(
        ventures: [venture(id: 'v1', ebitdaCents: 600000, multipleMilli: 8000)],
        cashCents: 1000,
        round: 2,
        tier: 1,
        netWorthAtTierEntry: 5600000,
      ).copyWith(backgroundId: 'DEALMAKER');
      final advanced = runDeadlineCheck(advancing).state;
      expect(advanced.round, 3);
      expect(advanced.playsRemaining, playsPerRound(1) + 1);

      // Tier clear: clearing T1 reseeds into T2 and re-stages the T2 grant +1.
      final clearing = shopState(
        ventures: [
          venture(id: 'v1', ebitdaCents: 20000000, multipleMilli: 8000),
        ],
        cashCents: 0,
        round: 3,
        tier: 1,
        netWorthAtTierEntry: 5600000,
      ).copyWith(backgroundId: 'DEALMAKER');
      expect(clearing.netWorthCents, greaterThanOrEqualTo(tierBarCents(1)));
      final cleared = runDeadlineCheck(clearing).state;
      expect(cleared.tier, 2);
      expect(cleared.playsRemaining, playsPerRound(2) + 1);
    });
  });

  // -------------------------------------------------------------------------
  // Phase + plays gates on apply() (doc 02 §3 PREs)
  // -------------------------------------------------------------------------
  group('apply() phase gate (doc 02 §3: every action PREs its phase)', () {
    test('non-Reroll actions are rejected outside ACT with wrong_phase', () {
      final all = {...costingActions(), ...freeActions()}..remove('Reroll');
      for (final phase in [
        PhaseId.operate,
        PhaseId.shop,
        PhaseId.deadlineCheck,
        PhaseId.runOver,
      ]) {
        for (final entry in all.entries) {
          final before = actFixture(phase: phase);
          final result = apply(before, entry.value, SplitMix64Rng(1), kContent);
          expect(wasRejected(result, 'wrong_phase'), isTrue,
              reason: '${entry.key} must reject in $phase');
          expect(result.state, before,
              reason: '${entry.key} rejection must not mutate');
        }
      }
    });

    test('Reroll is legal in ACT and SHOP, rejected elsewhere (doc 02 §3.8)',
        () {
      const reroll = Reroll(costCents: 250000);
      for (final phase in [PhaseId.act, PhaseId.shop]) {
        final result =
            apply(actFixture(phase: phase), reroll, SplitMix64Rng(1), kContent);
        expect(wasRejected(result), isFalse,
            reason: 'Reroll must succeed in $phase');
        expect(result.state.rerollsUsed, 1);
      }
      for (final phase in [
        PhaseId.operate,
        PhaseId.deadlineCheck,
        PhaseId.runOver,
      ]) {
        final before = actFixture(phase: phase);
        final result = apply(before, reroll, SplitMix64Rng(1), kContent);
        expect(wasRejected(result, 'wrong_phase'), isTrue);
        expect(result.state, before);
      }
    });

    test('the phase gate fires BEFORE action-specific PREs', () {
      // DividendRecap at tier 1 in SHOP: wrong_phase, not recap_tier_gated.
      final before = GameState(
        ventures: [venture()],
        cashCents: 5000000,
        tier: 1,
        phase: PhaseId.shop,
        playsRemaining: 3,
      );
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: 3000),
          SplitMix64Rng(1), kContent);
      expect(wasRejected(result, 'wrong_phase'), isTrue);
    });
  });

  group('apply() plays gate (doc 02 §3 matrix: costs 1 play)', () {
    test('every costing action decrements playsRemaining by 1 on success',
        () {
      for (final entry in costingActions().entries) {
        final result =
            apply(actFixture(playsRemaining: 3), entry.value, SplitMix64Rng(1), kContent);
        expect(wasRejected(result), isFalse,
            reason: '${entry.key} must reach its success path');
        expect(result.state.playsRemaining, 2,
            reason: '${entry.key} costs exactly 1 play');
      }
    });

    test('every costing action is rejected at 0 plays with '
        'no_plays_remaining and no mutation', () {
      for (final entry in costingActions().entries) {
        final before = actFixture(playsRemaining: 0);
        final result = apply(before, entry.value, SplitMix64Rng(1), kContent);
        expect(wasRejected(result, 'no_plays_remaining'), isTrue,
            reason: '${entry.key} must reject when exhausted');
        expect(result.state, before);
      }
    });

    test('the free three succeed at 0 plays and never decrement', () {
      for (final entry in freeActions().entries) {
        final result =
            apply(actFixture(playsRemaining: 0), entry.value, SplitMix64Rng(1), kContent);
        expect(wasRejected(result), isFalse,
            reason: '${entry.key} is throughput-free (doc 02 §3 matrix)');
        expect(result.state.playsRemaining, 0,
            reason: '${entry.key} must not touch the plays budget');
      }
    });

    test('a rejected costing action does NOT spend the play', () {
      // venture_not_found fires after the gates; plays stay at 3.
      final before = actFixture(playsRemaining: 3);
      final result = apply(before,
          const RaiseEquity(ventureId: 'ghost', raiseCents: 1),
          SplitMix64Rng(1), kContent);
      expect(wasRejected(result, 'venture_not_found'), isTrue);
      expect(result.state, before);
    });

    test('the plays gate fires before action-specific PREs', () {
      // DividendRecap at tier 1 with 0 plays: no_plays_remaining, not
      // recap_tier_gated.
      final before = GameState(
        ventures: [venture()],
        cashCents: 5000000,
        tier: 1,
        phase: PhaseId.act,
        playsRemaining: 0,
      );
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: 3000),
          SplitMix64Rng(1), kContent);
      expect(wasRejected(result, 'no_plays_remaining'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // runOperate: strict gate + snapshot + death (edits to operate.dart)
  // -------------------------------------------------------------------------
  group('runOperate round-2 wiring (doc 02 §2)', () {
    GameState operateState({PhaseId phase = PhaseId.operate}) => GameState(
          ventures: [venture(ebitdaCents: 600000, netDebtCents: 2000000)],
          cashCents: 5000000,
          round: 2,
          tier: 2,
          phase: phase,
        );

    test('requires phase == operate: StateError from every other phase', () {
      for (final phase in [
        PhaseId.act,
        PhaseId.shop,
        PhaseId.deadlineCheck,
        PhaseId.runOver,
      ]) {
        expect(
            () => runOperate(
                operateState(phase: phase), SplitMix64Rng(1), kContent),
            throwsStateError,
            reason: 'runOperate from $phase must be a caller bug');
      }
    });

    test('snapshots netWorthLastRound AFTER all steps (doc 02 §2 step 9)',
        () {
      final result = runOperate(operateState(), SplitMix64Rng(3), kContent);
      expect(result.state.netWorthLastRound, result.state.netWorthCents,
          reason: 'the snapshot is the post-OPERATE derived net worth');
      expect(result.state.netWorthLastRound,
          isNot(operateState().netWorthCents),
          reason: 'yield/interest moved cash, so the snapshot is fresh');
    });

    test('bankruptcy sets death = DeathCause.bankruptcy and still snapshots',
        () {
      final doomed = GameState(
        ventures: [venture(ebitdaCents: 0, netDebtCents: 50000000)],
        cashCents: 100,
        round: 3,
        tier: 2,
        phase: PhaseId.operate,
      );
      final result = runOperate(doomed, SplitMix64Rng(12), kContent);
      expect(result.state.phase, PhaseId.runOver);
      expect(result.state.death, DeathCause.bankruptcy);
      expect(result.state.won, isFalse);
      expect(result.state.netWorthLastRound, result.state.netWorthCents,
          reason: 'the autopsy can quote the end-of-OPERATE net worth');
    });
  });

  // -------------------------------------------------------------------------
  // ForwardMeters (doc 02 §1; doc 01 §7.4)
  // -------------------------------------------------------------------------
  group('ForwardMeters: runway (doc 01 §7.4 max-crunch gauge)', () {
    test('maxCrunchRateBp = interestMax x crunch rateMul = 1200 x 130/100 '
        '(both ends R12-tuned)', () {
      expect(maxCrunchRateBp, 1560);
    });

    test('projectedCash = cash + per-venture yield (passive dampened); '
        'debtService = interest at the max-crunch rate on TOTAL debt', () {
      final s = GameState(
        ventures: [
          venture(ebitdaCents: 600000, netDebtCents: 4000000),
          venture(
              id: 'v2',
              sector: Sector.retail,
              ebitdaCents: 600000,
              netDebtCents: 6000000,
              passive: true),
        ],
        cashCents: 1000000,
        round: 2,
        tier: 2,
        phase: PhaseId.act,
      );
      final m = computeMeters(s);
      // yield: 210,000 active + 105,000 passive (the 35/200 dial).
      expect(m.projectedCashNextRoundCents, 1000000 + 210000 + 105000);
      // service: trunc(1560 * 10,000,000 / 10,000) = 1,560,000.
      expect(m.debtServiceNextRoundCents, 1560000);
      expect(m.runwayOk, isFalse);
      expect(m.marketTempGauge, s.market.temp);
    });

    test('runwayOk boundary: projected == service is OK; one cent short is '
        'not', () {
      GameState withCash(int cash) => GameState(
            ventures: [venture(ebitdaCents: 0, netDebtCents: 10000000)],
            cashCents: cash,
            round: 2,
            tier: 2,
            phase: PhaseId.act,
          );
      expect(computeMeters(withCash(1560000)).runwayOk, isTrue);
      expect(computeMeters(withCash(1559999)).runwayOk, isFalse);
    });

    test('a debt-free run is always runway-OK', () {
      final m = computeMeters(GameState(
          ventures: [venture()],
          cashCents: 0,
          phase: PhaseId.act));
      expect(m.debtServiceNextRoundCents, 0);
      expect(m.runwayOk, isTrue);
    });
  });

  group('ForwardMeters: growth rates (integer bisection, doc 02 §1)', () {
    test('compoundCents applies r per round with per-step truncation', () {
      expect(compoundCents(5600000, 1434, 8), 100133912);
      expect(compoundCents(5600000, 1433, 8), 99576643);
      expect(compoundCents(1000, 1000, 5), 1000, reason: '1.0x is identity');
      expect(compoundCents(123456, 0, 3), 0);
    });

    test('compoundCents is monotone nondecreasing in r — the property both '
        'bisections rely on (per-step truncation cannot mis-bracket)', () {
      // Sweep every rate in the gauge bracket on truncation-hostile bases.
      const bases = [1, 999, 5600000, 99999999];
      const horizons = [1, 8, 10];
      for (final base in bases) {
        for (final n in horizons) {
          var prev = compoundCents(base, growthRateMinMilli, n);
          for (var r = growthRateMinMilli + 1;
              r <= growthRateMaxMilli;
              r++) {
            final cur = compoundCents(base, r, n);
            expect(cur, greaterThanOrEqualTo(prev),
                reason: 'compound($base, r, $n) decreased at r=$r — the '
                    'bisection bracket would be unsound');
            prev = cur;
          }
        }
      }
    });

    test('the bisections return EXACT boundaries: needed-1 misses the bar, '
        'realized+1 overshoots the net worth', () {
      // The 1599 pin's fixture: nw 6e6, T1 round 4 -> 6 rounds left
      // (deadline 9 since the R12 tune).
      final needed = computeMeters(GameState(
              ventures: const [],
              cashCents: 6000000,
              round: 4,
              tier: 1,
              phase: PhaseId.act))
          .growthRateNeededMilli;
      expect(compoundCents(6000000, needed, 6),
          greaterThanOrEqualTo(tierBarCents(1)));
      expect(compoundCents(6000000, needed - 1, 6),
          lessThan(tierBarCents(1)),
          reason: 'needed is the SMALLEST satisfying rate');
      // The 1017 pin's fixture: entry 5.6e6 -> nw 6e6 over 4 rounds.
      final realized = computeMeters(GameState(
              ventures: const [],
              cashCents: 6000000,
              round: 4,
              tier: 1,
              phase: PhaseId.act,
              netWorthAtTierEntry: 5600000))
          .growthRateThisTierMilli;
      expect(compoundCents(5600000, realized, 4),
          lessThanOrEqualTo(6000000));
      expect(compoundCents(5600000, realized + 1, 4), greaterThan(6000000),
          reason: 'realized is the LARGEST satisfying rate');
    });

    test('growthRateNeeded: the T1 seed needs 1378 milli over 9 rounds '
        '(doc 01 §6\'s ~1.42x line eased to ~1.38x by the R12 T1 deadline '
        '8 -> 9)', () {
      // nw = the $56k seed net worth; bar 1e8; roundsLeft = 9 - 1 + 1 = 9.
      final s = GameState(
          ventures: const [],
          cashCents: 5600000,
          round: 1,
          tier: 1,
          phase: PhaseId.act);
      expect(computeMeters(s).growthRateNeededMilli, 1378);
    });

    test('growthRateNeeded mid-tier: 6e6 at T1 round 4 needs 1599 over the '
        '6 rounds left', () {
      final s = GameState(
          ventures: const [],
          cashCents: 6000000,
          round: 4,
          tier: 1,
          phase: PhaseId.act,
          netWorthAtTierEntry: 5600000);
      expect(computeMeters(s).growthRateNeededMilli, 1599);
    });

    test('growthRateNeeded is 1000 once the bar is already cleared', () {
      final s = GameState(
          ventures: const [],
          cashCents: 100000000,
          round: 4,
          tier: 1,
          phase: PhaseId.act);
      expect(computeMeters(s).growthRateNeededMilli, 1000);
    });

    test('growthRateNeeded saturates at 3000 when even 3x/round cannot '
        'reach the bar', () {
      // 6e6 with 1 round left needs ~16.7x: off the gauge.
      final s = GameState(
          ventures: const [],
          cashCents: 6000000,
          round: 8,
          tier: 1,
          phase: PhaseId.act);
      expect(computeMeters(s).growthRateNeededMilli, 3000);
      expect(computeMeters(s).growthRateNeededMilli, growthRateMaxMilli);
    });

    test('growthRateNeeded floors at 1000 in T5 with a degenerate (<=0) '
        'entry baseline (the rising bar is 0)', () {
      final s = GameState(
          ventures: const [],
          cashCents: 100,
          round: 3,
          tier: 5,
          phase: PhaseId.act); // netWorthAtTierEntry defaults to 0
      expect(computeMeters(s).growthRateNeededMilli, 1000);
    });

    test('growthRateNeeded in T5 telegraphs the ESCALATING ante bar '
        '(audit L1): a real entry baseline yields a real needed pace', () {
      // Entry $10M; at round 1 the ante-1 bar (round-10 deadline) is 15M.
      // With net worth still ~$10M and 10 rounds to compound to 15M, the
      // needed pace is a small but NON-trivial rate above 1.0x (not the
      // old flat 1000 "no bar" sentinel).
      final s = GameState(
        ventures: [
          Venture(
            id: 'v',
            sector: Sector.software,
            ebitdaCents: 1250000,
            multipleMilli: 8000,
            netDebtCents: 0,
            ownershipBp: 10000,
          ),
        ],
        cashCents: 0,
        round: 1,
        tier: 5,
        phase: PhaseId.act,
        netWorthAtTierEntry: 10000000,
      );
      expect(s.netWorthCents, 10000000);
      final needed = computeMeters(s).growthRateNeededMilli;
      expect(needed, greaterThan(1000),
          reason: 'endless now has a rising bar — the meter shows real '
              'pressure, not a flat 1.0x');
      expect(needed, lessThan(growthRateMaxMilli),
          reason: '15M in 10 rounds from 10M is comfortably reachable');
    });

    test('growthRateThisTier: a clean 2.0x first round pins 2000', () {
      final s = GameState(
          ventures: const [],
          cashCents: 11200000,
          round: 1,
          tier: 2,
          phase: PhaseId.act,
          netWorthAtTierEntry: 5600000);
      expect(computeMeters(s).growthRateThisTierMilli, 2000);
    });

    test('growthRateThisTier: 5.6e6 -> 6e6 over 4 rounds pins 1017', () {
      final s = GameState(
          ventures: const [],
          cashCents: 6000000,
          round: 4,
          tier: 1,
          phase: PhaseId.act,
          netWorthAtTierEntry: 5600000);
      expect(computeMeters(s).growthRateThisTierMilli, 1017);
    });

    test('growthRateThisTier is 0 when the baseline is unusable', () {
      // Entry 0 (raw fixture) or a non-positive current NW: no rate.
      expect(
          computeMeters(GameState(
                  ventures: const [],
                  cashCents: 500,
                  round: 2,
                  tier: 1,
                  phase: PhaseId.act))
              .growthRateThisTierMilli,
          0,
          reason: 'netWorthAtTierEntry defaults to 0 here');
      expect(
          computeMeters(GameState(
                  ventures: const [],
                  cashCents: -500,
                  round: 2,
                  tier: 1,
                  phase: PhaseId.act,
                  netWorthAtTierEntry: 1000))
              .growthRateThisTierMilli,
          0,
          reason: 'a negative net worth has no realized growth rate');
    });
  });

  // -------------------------------------------------------------------------
  // Telegraph (doc 02 §5.2 #6): death is pre-flagged
  // -------------------------------------------------------------------------
  group('telegraph: bankruptcy is pre-flagged by runwayOk (doc 02 §5.2 #6)',
      () {
    /// End-of-round states (phase act) that MUST die next OPERATE under any
    /// rate draw: even the band minimum (800 bp) out-bills cash + yield.
    final doomedFixtures = <String, GameState>{
      'no yield, deep debt': GameState(
        ventures: [venture(ebitdaCents: 0, netDebtCents: 50000000)],
        cashCents: 100,
        round: 2,
        tier: 2,
        phase: PhaseId.act,
        playsRemaining: 3,
      ),
      'some yield, still under water': GameState(
        ventures: [venture(ebitdaCents: 1000000, netDebtCents: 20000000)],
        cashCents: 100000,
        round: 3,
        tier: 2,
        phase: PhaseId.act,
        playsRemaining: 3,
      ),
    };

    for (final entry in doomedFixtures.entries) {
      test('${entry.key}: runwayOk is false the round BEFORE the death', () {
        final s = entry.value;
        expect(computeMeters(s).runwayOk, isFalse,
            reason: 'the meter is computed vs the max-crunch rate, so a '
                'certain death is always pre-flagged');
        // And the death actually happens next OPERATE, on several seeds
        // (the slice events carry no cash delta, so the doom is
        // event-proof too):
        for (final seed in [1, 7, 99]) {
          final rng = SplitMix64Rng(seed);
          var state = endTurn(s, rng, kContent);
          state = runDeadlineCheck(state).state;
          expect(state.phase, PhaseId.operate);
          final result = runOperate(state, rng, kContent);
          expect(result.state.phase, PhaseId.runOver,
              reason: 'seed $seed: the fixture must be doomed by design');
          expect(result.state.death, DeathCause.bankruptcy);
        }
      });
    }

    test('a healthy levered run is NOT flagged and survives any draw', () {
      final s = GameState(
        ventures: [venture(ebitdaCents: 1000000, netDebtCents: 10000000)],
        cashCents: 10000000,
        round: 2,
        tier: 2,
        phase: PhaseId.act,
        playsRemaining: 3,
      );
      expect(computeMeters(s).runwayOk, isTrue);
      for (final seed in [1, 7, 99]) {
        final rng = SplitMix64Rng(seed);
        var state = endTurn(s, rng, kContent);
        state = runDeadlineCheck(state).state;
        final result = runOperate(state, rng, kContent);
        expect(result.state.phase, PhaseId.act,
            reason: 'seed $seed: max-crunch headroom means survival');
      }
    });

    test('the telegraph survives a tier clear: a reseed-gutted yield is '
        'flagged on the END-of-round state before the OPERATE it can kill '
        '(meters are derived, never stale)', () {
      // RETAIL-heavy T1 clear carrying debt: pre-check the yield covers the
      // worst bill; the §3.3 reseed then SETS ebitda to 0.37*NW at 8x — a
      // cut from 70e6 to ~6e6 — while the 90e6 debt carries into T2.
      final s = GameState(
        ventures: [
          venture(
              id: 'shop',
              sector: Sector.retail,
              ebitdaCents: 70000000,
              multipleMilli: 3000,
              netDebtCents: 90000000)
        ],
        cashCents: 10100000,
        round: 3,
        tier: 1,
        phase: PhaseId.act,
        playsRemaining: 2,
        market: const MarketState(
            temp: MarketTemp.cold,
            roundsInState: 1,
            stateDurationRounds: 3,
            liveRateBp: 1440),
      );
      expect(computeMeters(s).runwayOk, isTrue,
          reason: 'pre-clear: 34.6e6 projected covers the 14.04e6 worst '
              'bill (maxCrunchRateBp 1560 since the R12 tune)');
      final check = runDeadlineCheck(endTurn(s, SplitMix64Rng(0), kContent));
      expect(check.state.tier, 2, reason: 'the fixture must clear T1');
      expect(check.state.ventures.single.ebitdaCents, 6017125,
          reason: 'seed = trunc(0.37 x 130.1e6 x 1000 / 8000), uncapped '
              '(carrySeedFrac 0.37 since the R12 tune)');
      expect(computeMeters(check.state).runwayOk, isFalse,
          reason: 'the post-reseed end-of-round state IS pre-flagged '
              '(doc 02 §5.2 #6): projected ~12.21e6 < 14.04e6 service');
      // The flag means CAN die, not MUST: sweep seeds through the sticky
      // cold round and require both outcomes (a warning, not a verdict).
      var deaths = 0;
      var survivals = 0;
      for (var seed = 0; seed < 40; seed++) {
        final result = runOperate(check.state, SplitMix64Rng(seed), kContent);
        if (result.state.death == DeathCause.bankruptcy) {
          deaths++;
        } else {
          survivals++;
        }
      }
      expect(deaths, greaterThan(0),
          reason: 'a high cold draw out-bills the gutted yield');
      expect(survivals, greaterThan(0),
          reason: 'a low cold draw does not — the flag is a warning');
    });
  });

  group('telegraph: missed deadline is pre-flagged by the growth meters',
      () {
    test('a behind-pace final round flags growthRateThisTier < needed, then '
        'dies at the check', () {
      final s = GameState(
        ventures: const [],
        cashCents: 6000000,
        round: 9, // T1 deadline round (9 since the R12 tune)
        tier: 1,
        phase: PhaseId.act,
        netWorthAtTierEntry: 5600000,
        playsRemaining: 2,
      );
      final m = computeMeters(s);
      expect(m.growthRateThisTierMilli, 1007);
      expect(m.growthRateNeededMilli, 3000, reason: 'saturated: hopeless');
      expect(m.growthRateThisTierMilli, lessThan(m.growthRateNeededMilli),
          reason: 'the warning the autopsy quotes was raised in time');
      final result = runDeadlineCheck(endTurn(s, SplitMix64Rng(0), kContent));
      expect(result.state.death, DeathCause.missedDeadline);
    });

    test('a behind-pace mid-tier round is flagged rounds before the death',
        () {
      final s = GameState(
        ventures: const [],
        cashCents: 6000000,
        round: 4,
        tier: 1,
        phase: PhaseId.act,
        netWorthAtTierEntry: 5600000,
        playsRemaining: 2,
      );
      final m = computeMeters(s);
      expect(m.growthRateThisTierMilli, 1017);
      expect(m.growthRateNeededMilli, 1599);
      expect(m.growthRateThisTierMilli, lessThan(m.growthRateNeededMilli));
    });
  });

  // -------------------------------------------------------------------------
  // The full machine (integration)
  // -------------------------------------------------------------------------
  group('full machine: operate -> act -> shop -> deadline check, looped', () {
    GameState seedRun() => GameState(
          ventures: [venture(id: 'seed')], // $6k EBITDA at 6x, debt-free
          cashCents: 2000000,
          round: 1,
          tier: 1,
          phase: PhaseId.operate,
          netWorthAtTierEntry: 5600000, // doc 01 §3.1 seed identity
          playsHeld: const ['p'], // one held play for the sell test below
        );

    test('three full rounds keep the strict phase order and the snapshots',
        () {
      var state = seedRun();
      final rng = SplitMix64Rng(11);
      for (var round = 1; round <= 3; round++) {
        expect(state.round, round);
        expect(state.tier, 1);
        expect(state.phase, PhaseId.operate);

        final opResult = runOperate(state, rng, kContent);
        state = opResult.state;
        expect(state.phase, PhaseId.act);
        expect(state.playsRemaining, playsPerRound(1)); // T1: 2
        expect(state.hand.length, inInclusiveRange(3, 5),
            reason: 'every OPERATE deals a fresh hand (doc 03 §3.1)');
        expect(state.netWorthLastRound, state.netWorthCents,
            reason: 'doc 02 §2 step 9 snapshot');

        // ACT: two actions — one costing, one free (an ACT reroll, which
        // REDRAWS the hand and advances the stream).
        var result = apply(
            state,
            const ReinvestBaseline(ventureId: 'seed', amountCents: 100000),
            rng,
            kContent);
        expect(wasRejected(result), isFalse);
        state = result.state;
        expect(state.playsRemaining, 1);
        result =
            apply(state, const Reroll(costCents: 50000), rng, kContent);
        expect(wasRejected(result), isFalse);
        state = result.state;
        expect(state.playsRemaining, 1, reason: 'the reroll is free');
        expect(state.hand.length, inInclusiveRange(3, 5),
            reason: 'an ACT reroll re-deals the hand');

        state = endTurn(state, rng, kContent);
        expect(state.phase, PhaseId.shop);
        expect(state.shopOffers.length, kShopOfferCount);

        final check = runDeadlineCheck(state);
        expect(check.events, isEmpty, reason: 'NW is far below the T1 bar');
        state = check.state;
        expect(state.round, round + 1);
        expect(state.tier, 1);
        expect(state.rerollsUsed, 0);
        expect(state.netWorthAtTierEntry, 5600000,
            reason: 'the tier-entry baseline holds inside a tier');
      }
      expect(state.round, 4);
      expect(state.death, isNull);
      expect(state.won, isFalse);
    });

    test('plays exhaustion mid-round: the third costing action is rejected',
        () {
      var state = seedRun();
      final rng = SplitMix64Rng(13);
      state = runOperate(state, rng, kContent).state;
      expect(state.playsRemaining, 2);
      for (var i = 0; i < 2; i++) {
        final result = apply(
            state,
            const ReinvestBaseline(ventureId: 'seed', amountCents: 10000),
            rng,
            kContent);
        expect(wasRejected(result), isFalse);
        state = result.state;
      }
      expect(state.playsRemaining, 0);
      final third = apply(
          state,
          const ReinvestBaseline(ventureId: 'seed', amountCents: 10000),
          rng,
          kContent);
      expect(wasRejected(third, 'no_plays_remaining'), isTrue);
      expect(third.state, state);
      // The free sell still works (the 'p' play is held), then the turn
      // can end.
      final sale = apply(state,
          const SellPlay(playId: 'p', purchasePriceCents: 50000), rng,
          kContent);
      expect(wasRejected(sale), isFalse);
      expect(sale.state.playsHeld, isEmpty,
          reason: 'the sold play leaves the held inventory');
      state = endTurn(sale.state, rng, kContent);
      expect(state.phase, PhaseId.shop);
    });

    test('a SHOP reroll spends cash, redraws the OFFERS, then the deadline '
        'check resets the counter', () {
      var state = seedRun();
      final rng = SplitMix64Rng(17);
      state = runOperate(state, rng, kContent).state;
      state = endTurn(state, rng, kContent);
      final offersBefore = state.shopOffers;
      final rerolled =
          apply(state, const Reroll(costCents: 100000), rng, kContent);
      expect(wasRejected(rerolled), isFalse,
          reason: 'Reroll is legal in SHOP (doc 02 §3.8)');
      expect(rerolled.state.rerollsUsed, 1);
      expect(rerolled.state.shopOffers.length, kShopOfferCount,
          reason: 'a SHOP reroll re-deals the counter');
      expect(rerolled.state.hand, state.hand,
          reason: 'a SHOP reroll never touches the HAND');
      // (The redraw MAY deal the same ids — small pool — so only the
      // count and the consumed draws are asserted, not inequality.)
      expect(offersBefore.length, kShopOfferCount);
      final check = runDeadlineCheck(rerolled.state);
      expect(check.state.rerollsUsed, 0,
          reason: 'rerollsUsed resets each round (doc 02 §2)');
      expect(check.state.round, 2);
    });

    test('the machine replays deterministically end to end', () {
      GameState play(int seed) {
        var state = seedRun();
        final rng = SplitMix64Rng(seed);
        for (var round = 1; round <= 4; round++) {
          state = runOperate(state, rng, kContent).state;
          if (state.phase == PhaseId.runOver) return state;
          state = apply(
                  state,
                  const ReinvestBaseline(
                      ventureId: 'seed', amountCents: 50000),
                  rng,
                  kContent)
              .state;
          state = endTurn(state, rng, kContent);
          state = runDeadlineCheck(state).state;
          if (state.phase == PhaseId.runOver) return state;
        }
        return state;
      }

      final first = play(23);
      final second = play(23);
      expect(identical(first, second), isFalse);
      expect(first, second);
      expect(play(23), isNot(play(24)));
    });
  });
}
