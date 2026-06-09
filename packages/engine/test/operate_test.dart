// OPERATE — the engine's first REAL RNG consumers (doc 01 §6.1 order;
// doc 02 §2 OPERATE; economy-model.json roundOrder / curves.driftModel /
// curves.interestBand / decay / constants.cashYield), composed with the
// deal-flow draws since schemaVersion 4 (operate.dart header).
//
// Covers, one behavior per test:
//   - pure-formula pins, hand-computed integers: drift delta, live rate,
//     cash yield, neglect-decay losses, playsPerRound
//   - the DRAW-ORDER CONTRACT via a twin probe: [hand: size + cards]
//     [transition? duration?] rate, then u1,u2 per venture in
//     ventures-list order, then the event roll — if the engine reorders
//     or adds a draw, the probe disagrees and these tests fail. Tests
//     that pin exact post-OPERATE numbers use seeds whose event roll
//     does NOT fire (asserted via the probe each time); the event path
//     has its own group
//   - the step-0 hand draw: 3-5 pool ids, replaced wholesale, dealt on
//     the bankrupt branch too
//   - the step-5 event roll: fires under kEventChancePct, applies the
//     probed card's deltas, emits EVENT_RESOLVED, +1 pick draw
//   - market state machine: sticky tick, boundary transition buckets
//     (18/18/64), 2-3 round durations, stickiness across many rounds
//   - cash yield active vs passive (the 35/200 passive dampening is a
//     TUNING DIAL, see operate.dart), computed on PRE-decay EBITDA
//   - neglect decay table [4,8,15]% / [0,3,6]%, passive halving, the
//     1000-milli multiple floor, reset-on-target wired into apply()
//   - interest: zero-debt no-op, sum-then-trunc on TOTAL debt (F4),
//     bankruptcy strictly below zero (cash == interest survives at 0),
//     cash NEVER clamped, runOver phase, StateError on a dead run
//   - playsRemaining reset 2/3/3/4/4 per tier; phase -> act
//   - determinism: same seed + same mixed script twice -> identical states
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/content.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/resolver.dart';
import 'package:engine/rng.dart';
import 'package:engine/round.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

// ---------------------------------------------------------------------------
// Twin probes for the deal-flow draws (re-implement the dealflow.dart
// contract with raw nextInt calls so the tests FAIL if the engine's own
// routine drifts from the written contract)
// ---------------------------------------------------------------------------

/// Consumes the HAND routine's draws for [tier] under the v5 contract:
/// 1 size + size cards over the dead-draw-filtered pool, then the
/// exit-offer pair when [ventures] > 0. Returns the dealt size.
int probeHand(SplitMix64Rng probe, int tier, {int ventures = 1}) {
  final pool =
      handPool(kContent, tier, slotsFull: ventures >= slotsMax(tier));
  var size = kHandSizeMin + probe.nextInt(kHandSizeSpan);
  if (size > pool.length) size = pool.length;
  for (var i = 0; i < size; i++) {
    probe.nextInt(pool.length - i);
  }
  if (ventures > 0) {
    probe.nextInt(ventures); // exit-offer venture pick
    probe.nextInt(kExitOfferBandDraws); // exit-offer band multiple
  }
  return size;
}

/// Consumes the EVENT roll's draw(s) for [tier]; returns the fired card,
/// or null when the roll missed.
Card? probeEvent(SplitMix64Rng probe, int tier) {
  if (probe.nextInt(100) >= kEventChancePct) return null;
  final pool = eventPool(kContent, tier);
  if (pool.isEmpty) return null;
  return pool[probe.nextInt(pool.length)];
}

/// Probes the event a STICKY-market tier-4 OPERATE over [ventures]
/// ventures would fire at [seed] (hand + rate + drift pairs consumed
/// first). Lets seed-sensitive tests HUNT their seed instead of
/// hardcoding one — the pins survive future draw-contract changes by
/// re-hunting, never by weakening.
Card? eventForSeed(int seed, {required int ventures}) {
  final probe = SplitMix64Rng(seed);
  probeHand(probe, 4, ventures: ventures);
  probe.nextInt(10000); // rate
  for (var i = 0; i < ventures; i++) {
    probe.nextInt(1000);
    probe.nextInt(1000);
  }
  return probeEvent(probe, 4);
}

/// The first seed in [0, 400) whose sticky tier-4 OPERATE (over
/// [ventures] ventures) MISSES the event roll.
int seedMissingEvent({required int ventures, int from = 0}) {
  for (var s = from; s < 400; s++) {
    if (eventForSeed(s, ventures: ventures) == null) return s;
  }
  throw StateError('no event-free seed under 400 — widen the hunt');
}

/// The first seed in [0, 400) whose sticky tier-4 OPERATE (one venture)
/// fires exactly [cardId].
int seedFiring(String cardId) {
  for (var s = 0; s < 400; s++) {
    if (eventForSeed(s, ventures: 1)?.id == cardId) return s;
  }
  throw StateError('no seed under 400 fires $cardId — widen the hunt');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Venture venture({
  String id = 'v1',
  Sector sector = Sector.software,
  int ebitdaCents = 600000,
  int multipleMilli = 8000,
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

/// A market mid-state (round 1 of 3) so OPERATE step 1 draws NO transition;
/// the operate's first draw is the rate draw.
MarketState stickyMarket({MarketTemp temp = MarketTemp.neutral}) => MarketState(
      temp: temp,
      roundsInState: 1,
      stateDurationRounds: 3,
      liveRateBp: 0,
    );

/// A market at its boundary (roundsInState == stateDurationRounds) so OPERATE
/// step 1 draws the transition bucket + the new duration before the rate.
MarketState boundaryMarket({MarketTemp temp = MarketTemp.neutral}) =>
    MarketState(
      temp: temp,
      roundsInState: 2,
      stateDurationRounds: 2,
      liveRateBp: 0,
    );

GameState base({
  List<Venture>? ventures,
  int cashCents = 5000000,
  MarketState? market,
  int tier = 4,
  PhaseId phase = PhaseId.operate,
}) =>
    GameState(
      ventures: ventures ?? [venture()],
      cashCents: cashCents,
      market: market ?? stickyMarket(),
      phase: phase,
      round: 2,
      tier: tier,
    );

Venture ventureOf(GameState s, String id) =>
    s.ventures.firstWhere((v) => v.id == id);

void main() {
  // -------------------------------------------------------------------------
  // Pure-formula pins (hand-computed integers)
  // -------------------------------------------------------------------------
  group('driftDeltaMilli (economy driftDelta; integer realization)', () {
    test('bubble + max-ish positive tri on a 14x SOFTWARE platform', () {
      // micro = 1_000_000 + 300*998 = 1_299_400; nano = 1350*1_299_400
      //       - 1e9 = 754_190_000; delta = 14000*754_190_000 ~/ 1e9 = 10558.
      expect(
          driftDeltaMilli(
              multipleMilli: 14000,
              stateFactorMilli: 1350,
              volMilli: 300,
              triMilli: 998),
          10558);
    });

    test('crunch + min tri on a 14x SOFTWARE platform', () {
      // micro = 1_000_000 - 300_000 = 700_000; nano = 750*700_000 - 1e9
      //       = -475_000_000; delta = 14000*(-475_000_000) ~/ 1e9 = -6650.
      expect(
          driftDeltaMilli(
              multipleMilli: 14000,
              stateFactorMilli: 750,
              volMilli: 300,
              triMilli: -1000),
          -6650);
    });

    test('neutral state with tri == 0 is a perfect no-op', () {
      expect(
          driftDeltaMilli(
              multipleMilli: 14000,
              stateFactorMilli: 1000,
              volMilli: 300,
              triMilli: 0),
          0);
    });

    test('neutral + positive tri: vol scales the swing (SERVICES)', () {
      // micro = 1_000_000 + 220*500 = 1_110_000; nano = 110_000_000;
      // delta = 10000*110_000_000 ~/ 1e9 = 1100.
      expect(
          driftDeltaMilli(
              multipleMilli: 10000,
              stateFactorMilli: 1000,
              volMilli: 220,
              triMilli: 500),
          1100);
    });

    test('truncates toward zero on a tiny negative product', () {
      // micro = 999_500; nano = -500_000; 1001*(-500_000) ~/ 1e9
      //  = -500_500_000 ~/ 1e9 = 0 (toward zero, NOT floor's -1).
      expect(
          driftDeltaMilli(
              multipleMilli: 1001,
              stateFactorMilli: 1000,
              volMilli: 100,
              triMilli: -5),
          0);
    });
  });

  group('liveRateBpFromDraw (economy curves.interestBand; interestMax '
      '0.12 / crunch rateMul 1.3 since the R12 tune)', () {
    test('u=0 pins the band minimum per state', () {
      expect(liveRateBpFromDraw(0, MarketTemp.neutral), 800); // 8%
      expect(liveRateBpFromDraw(0, MarketTemp.hot), 720); // 7.2%
      expect(liveRateBpFromDraw(0, MarketTemp.cold), 1040); // 10.4%
    });

    test('u=9999 pins the band top per state (U is [0,1), top excluded)', () {
      // base = 800 + (400*9999) ~/ 10000 = 800 + 399 = 1199.
      expect(liveRateBpFromDraw(9999, MarketTemp.neutral), 1199);
      expect(liveRateBpFromDraw(9999, MarketTemp.hot), 1079); // *90 ~/ 100
      expect(liveRateBpFromDraw(9999, MarketTemp.cold), 1558); // *130 ~/ 100
    });

    test('u=5000 pins the band middle per state', () {
      expect(liveRateBpFromDraw(5000, MarketTemp.neutral), 1000); // 10%
      expect(liveRateBpFromDraw(5000, MarketTemp.hot), 900); // 9%
      expect(liveRateBpFromDraw(5000, MarketTemp.cold), 1300); // 13%
    });
  });

  group('cashYieldCents (economy constants.cashYield 0.35)', () {
    test('active converts at 35/100', () {
      expect(cashYieldCents(600000, passive: false), 210000);
    });

    test('passive converts at 35/200 (the dampening TUNING DIAL)', () {
      expect(cashYieldCents(600000, passive: true), 105000);
    });

    test('truncates toward zero (odd cents)', () {
      expect(cashYieldCents(99, passive: false), 34); // 3465 ~/ 100
      expect(cashYieldCents(99, passive: true), 17); // 3465 ~/ 200
    });
  });

  group('neglect decay losses (economy decay.byNeglect + passiveMultiplier)',
      () {
    test('ebitda loss steps 4/8/15 percent by rounds neglected', () {
      expect(neglectEbitdaLossCents(1000000, 1, passive: false), 40000);
      expect(neglectEbitdaLossCents(1000000, 2, passive: false), 80000);
      expect(neglectEbitdaLossCents(1000000, 3, passive: false), 150000);
    });

    test('the table caps at index 3 for deeper neglect', () {
      expect(neglectEbitdaLossCents(1000000, 9, passive: false), 150000);
      expect(neglectMultipleLossMilli(14000, 9, passive: false), 840);
    });

    test('zero rounds neglected loses nothing', () {
      expect(neglectEbitdaLossCents(1000000, 0, passive: false), 0);
      expect(neglectMultipleLossMilli(14000, 0, passive: false), 0);
    });

    test('multiple loss steps 0/3/6 percent by rounds neglected', () {
      expect(neglectMultipleLossMilli(14000, 1, passive: false), 0);
      expect(neglectMultipleLossMilli(14000, 2, passive: false), 420);
      expect(neglectMultipleLossMilli(14000, 3, passive: false), 840);
    });

    test('passive ventures decay at HALF rate (both axes)', () {
      expect(neglectEbitdaLossCents(1000000, 1, passive: true), 20000);
      expect(neglectEbitdaLossCents(1000000, 3, passive: true), 75000);
      expect(neglectMultipleLossMilli(14000, 2, passive: true), 210);
      expect(neglectMultipleLossMilli(14000, 3, passive: true), 420);
    });

    test('losses truncate toward zero (odd cents)', () {
      expect(neglectEbitdaLossCents(99, 1, passive: false), 3); // 396 ~/ 100
    });
  });

  group('playsPerRound (doc 02 §3 PLAYS table)', () {
    test('grants 2/3/3/4/4 across tiers 1..5', () {
      expect(playsPerRound(1), 2);
      expect(playsPerRound(2), 3);
      expect(playsPerRound(3), 3);
      expect(playsPerRound(4), 4);
      expect(playsPerRound(5), 4);
    });

    test('throws on a tier outside 1..5', () {
      expect(() => playsPerRound(0), throwsArgumentError);
      expect(() => playsPerRound(6), throwsArgumentError);
    });
  });

  group('nextTempFromDraw (economy transitionAtBoundary 18/12/70 — crunch '
      'entry 0.18 -> 0.12 in the R12 tune)', () {
    test('bucket boundaries are exact: 0-17 hot, 18-29 cold, 30-99 neutral '
        '(the hot bucket NEVER moves — golden draws map identically)', () {
      expect(nextTempFromDraw(0), MarketTemp.hot);
      expect(nextTempFromDraw(17), MarketTemp.hot);
      expect(nextTempFromDraw(18), MarketTemp.cold);
      expect(nextTempFromDraw(29), MarketTemp.cold);
      expect(nextTempFromDraw(30), MarketTemp.neutral);
      expect(nextTempFromDraw(99), MarketTemp.neutral);
    });
  });

  // -------------------------------------------------------------------------
  // The draw-order contract (twin probe — mirrors operate.dart's header)
  // -------------------------------------------------------------------------
  group('draw-order contract (doc 03 §3.1; operate.dart header)', () {
    test('sticky round: [hand, rate, then u1,u2 per venture in list order, '
        'event roll]', () {
      final state = base(ventures: [
        venture(id: 'a', sector: Sector.software, multipleMilli: 8000),
        venture(
            id: 'b',
            sector: Sector.retail,
            multipleMilli: 3000,
            ebitdaCents: 400000),
      ]);
      // Hunt the seed (no event this round) instead of hardcoding one —
      // the exact multiple pins below must stay event-free.
      final seed = seedMissingEvent(ventures: 2);
      final probe = SplitMix64Rng(seed);
      final handSize = probeHand(probe, 4, ventures: 2); // step 0, FIRST
      final uRate = probe.nextInt(10000);
      final a1 = probe.nextInt(1000);
      final a2 = probe.nextInt(1000);
      final b1 = probe.nextInt(1000);
      final b2 = probe.nextInt(1000);
      final evt = probeEvent(probe, 4); // step 5, LAST
      expect(evt, isNull,
          reason: 'the hunted seed MISSES the event roll — the exact '
              'multiple pins below stay event-free (the firing path has '
              'its own group)');
      final expectedRate = liveRateBpFromDraw(uRate, MarketTemp.neutral);
      final expectedA = 8000 +
          driftDeltaMilli(
              multipleMilli: 8000,
              stateFactorMilli: 1000,
              volMilli: 300,
              triMilli: a1 + a2 - 1000);
      final expectedB = 3000 +
          driftDeltaMilli(
              multipleMilli: 3000,
              stateFactorMilli: 1000,
              volMilli: 100,
              triMilli: b1 + b2 - 1000);

      final rng = SplitMix64Rng(seed);
      final result = runOperate(state, rng, kContent);
      expect(result.state.market.liveRateBp, expectedRate);
      // Neutral drift on 8000/3000 with vol <= 300 cannot reach the 1000
      // floor, so the expectation needs no clamp.
      expect(ventureOf(result.state, 'a').multipleMilli, expectedA);
      expect(ventureOf(result.state, 'b').multipleMilli, expectedB);
      expect(result.state.hand.length, handSize,
          reason: 'the hand the probe sized is the hand dealt');
      expect(rng.cursor, (1 + handSize + 2) + 1 + 4 + 1,
          reason: 'hand (1 size + cards + the exit-offer pair) + 1 rate '
              '+ 2 per venture + the event roll');
      expect(rng.cursor, probe.cursor,
          reason: 'the probe and the engine read the same contract');
      expect(result.state.rngCursor, rng.cursor,
          reason: 'state.rngCursor must reconcile to the stream cursor');
    });

    test('boundary round: [hand, transition, duration, rate, then '
        'per-venture, event]; rate uses the NEW temp', () {
      // Determinism makes this exhaustive-ish: 30 fixed seeds; every one
      // must follow the probe exactly, and across the set both the
      // changed-temp and same-temp boundary branches occur.
      var sawChange = false;
      var sawStay = false;
      for (var seed = 0; seed < 30; seed++) {
        final probe = SplitMix64Rng(seed);
        probeHand(probe, 4, ventures: 0); // step 0 precedes the boundary draws
        final bucket = probe.nextInt(100);
        final expTemp = nextTempFromDraw(bucket);
        final expDuration = stateDurationMinRounds + probe.nextInt(2);
        final uRate = probe.nextInt(10000);
        final expRate = liveRateBpFromDraw(uRate, expTemp);
        probeEvent(probe, 4); // 0 ventures: no drift pairs; event roll last

        final state =
            base(ventures: const [], market: boundaryMarket());
        final rng = SplitMix64Rng(seed);
        final result = runOperate(state, rng, kContent);
        final m = result.state.market;
        expect(m.temp, expTemp, reason: 'seed $seed bucket $bucket');
        expect(m.stateDurationRounds, expDuration);
        expect(m.stateDurationRounds,
            inInclusiveRange(stateDurationMinRounds, stateDurationMaxRounds));
        expect(m.roundsInState, 1,
            reason: 'a fresh state begins at roundsInState 1');
        expect(m.liveRateBp, expRate,
            reason: 'the rate draw must come AFTER the transition and use '
                'the new temp\'s rateMul');
        expect(rng.cursor, probe.cursor,
            reason: 'seed $seed: hand + transition + duration + rate + '
                'event roll, nothing else');

        final changeEvents = result.events
            .where((e) => e.type == GameEventType.marketStateChanged);
        if (expTemp != MarketTemp.neutral) {
          sawChange = true;
          expect(changeEvents, hasLength(1));
          expect(changeEvents.single.reason, 'market_now_${expTemp.name}');
          expect(changeEvents.single.amount, expDuration);
        } else {
          sawStay = true;
          expect(changeEvents, isEmpty,
              reason: 'a same-temp redraw is not a state CHANGE');
        }
      }
      expect(sawChange, isTrue,
          reason: 'the 30-seed sweep should hit at least one transition');
      expect(sawStay, isTrue,
          reason: 'the 30-seed sweep should hit at least one stay');
    });

    test('a venture-less sticky round draws the hand + the rate + the '
        'event roll, nothing else', () {
      final probe = SplitMix64Rng(9);
      final handSize = probeHand(probe, 4, ventures: 0);
      probe.nextInt(10000); // rate
      final evt = probeEvent(probe, 4);
      final rng = SplitMix64Rng(9);
      final result = runOperate(base(ventures: const []), rng, kContent);
      expect(rng.cursor, (1 + handSize) + 1 + 1 + (evt == null ? 0 : 1));
      expect(rng.cursor, probe.cursor);
      expect(result.state.rngCursor, rng.cursor);
    });
  });

  // -------------------------------------------------------------------------
  // The step-0 hand draw inside OPERATE
  // -------------------------------------------------------------------------
  group('OPERATE step 0: the deal-flow hand draw (doc 03 §3.1 step 1)', () {
    test('every OPERATE deals a fresh 3-5 card hand from the tier pool, '
        'replacing the old wholesale', () {
      final stale = base().copyWith(hand: const ['GHOST']);
      final result = runOperate(stale, SplitMix64Rng(21), kContent);
      expect(result.state.hand.length, inInclusiveRange(3, 5));
      expect(result.state.hand, isNot(contains('GHOST')));
      final poolIds = [
        for (final c in handPool(kContent, 4, slotsFull: false)) c.id
      ].toSet();
      for (final id in result.state.hand) {
        expect(poolIds, contains(id));
      }
    });

    test('the hand is dealt on the BANKRUPT branch too (step 0 precedes '
        'the F6 verdict)', () {
      final doomed = base(
          ventures: [venture(ebitdaCents: 0, netDebtCents: 50000000)],
          cashCents: 0);
      final result = runOperate(doomed, SplitMix64Rng(12), kContent);
      expect(result.state.phase, PhaseId.runOver);
      expect(result.state.hand.length, inInclusiveRange(3, 5),
          reason: 'the draw order is fixed; death is decided at step 6');
    });
  });

  // -------------------------------------------------------------------------
  // The step-5 event roll
  // -------------------------------------------------------------------------
  group('OPERATE step 5: the event roll (doc 01 §6.1 step 5)', () {
    // Seed-hunt deterministically at test time: the sweep must contain
    // both firing and missing rolls (kEventChancePct = 25 of 100).
    test('a fired roll applies the probed card via applyEventCard and '
        'emits EVENT_RESOLVED; a missed roll leaves no trace', () {
      var sawFire = false;
      var sawMiss = false;
      for (var seed = 0; seed < 40; seed++) {
        final probe = SplitMix64Rng(seed);
        probeHand(probe, 4);
        probe.nextInt(10000); // rate
        final u1 = probe.nextInt(1000), u2 = probe.nextInt(1000);
        final card = probeEvent(probe, 4);

        final before = base(); // one attended SOFTWARE venture, no debt
        final result = runOperate(before, SplitMix64Rng(seed), kContent);
        final fired = result.events
            .where((e) => e.type == GameEventType.eventResolved);

        // Expected venture after drift (+ the event, when it fired).
        final postDrift = 8000 +
            driftDeltaMilli(
                multipleMilli: 8000,
                stateFactorMilli: 1000,
                volMilli: 300,
                triMilli: u1 + u2 - 1000);
        var expected = [
          venture(multipleMilli: postDrift, roundsNeglected: 1)
        ];
        var expectedCash = 5000000 + 210000; // yield; slice events: no cash
        if (card != null) {
          sawFire = true;
          expect(fired, hasLength(1), reason: 'seed $seed');
          expect(fired.single.reason, card.id);
          final out = applyEventCard(
              ventures: expected, cashCents: expectedCash, card: card);
          expected = out.ventures;
          expectedCash = out.cashCents;
        } else {
          sawMiss = true;
          expect(fired, isEmpty, reason: 'seed $seed');
        }
        expect(result.state.ventures, expected, reason: 'seed $seed');
        expect(result.state.cashCents, expectedCash, reason: 'seed $seed');
      }
      expect(sawFire, isTrue,
          reason: 'the 40-seed sweep should fire at least one event');
      expect(sawMiss, isTrue,
          reason: 'the 40-seed sweep should miss at least once');
    });

    test('the event lands AFTER decay (step 4 before step 5): the decayed '
        'ebitda is what the event delta hits', () {
      // Hunt a seed whose event is EVT_KEY_CLIENT_LOSS against a SERVICES
      // venture: decay first (-8% of 1,000,000 at 2 rounds neglected),
      // then the flat -250,000.
      for (var seed = 0; seed < 200; seed++) {
        final probe = SplitMix64Rng(seed);
        probeHand(probe, 4);
        probe.nextInt(10000);
        probe.nextInt(1000);
        probe.nextInt(1000);
        final card = probeEvent(probe, 4);
        if (card?.id != 'EVT_KEY_CLIENT_LOSS') continue;

        final before = base(ventures: [
          venture(
              sector: Sector.services,
              ebitdaCents: 1000000,
              multipleMilli: 5000,
              roundsNeglected: 2),
        ]);
        final result = runOperate(before, SplitMix64Rng(seed), kContent);
        // decay: 1,000,000 - 80,000 = 920,000; event: -250,000 = 670,000.
        expect(ventureOf(result.state, 'v1').ebitdaCents, 670000,
            reason: 'seed $seed: decay (step 4) then the event (step 5)');
        return; // one witnessed ordering is the pin
      }
      fail('no seed under 200 fired EVT_KEY_CLIENT_LOSS — widen the hunt');
    });
  });

  // -------------------------------------------------------------------------
  // Market state machine
  // -------------------------------------------------------------------------
  group('market state machine (economy curves.driftModel)', () {
    test('a sticky round ticks roundsInState and keeps temp + duration', () {
      final result = runOperate(base(ventures: const [], market: stickyMarket()),
          SplitMix64Rng(2), kContent);
      final m = result.state.market;
      expect(m.temp, MarketTemp.neutral);
      expect(m.roundsInState, 2);
      expect(m.stateDurationRounds, 3);
    });

    test('states are sticky for their whole 2-3 round duration (12-round '
        'soak)', () {
      var state = base(
          ventures: const [],
          market: const MarketState(
              temp: MarketTemp.neutral,
              roundsInState: 1,
              stateDurationRounds: 2,
              liveRateBp: 0));
      final rng = SplitMix64Rng(7);
      var prev = state.market;
      for (var i = 0; i < 12; i++) {
        final result = runOperate(state, rng, kContent);
        final m = result.state.market;
        expect(m.stateDurationRounds,
            inInclusiveRange(stateDurationMinRounds, stateDurationMaxRounds),
            reason: 'durations are one bounded 2-3 draw (round $i)');
        if (prev.roundsInState >= prev.stateDurationRounds) {
          expect(m.roundsInState, 1,
              reason: 'boundary -> a fresh state begins (round $i)');
        } else {
          expect(m.roundsInState, prev.roundsInState + 1,
              reason: 'mid-state -> tick only (round $i)');
          expect(m.temp, prev.temp,
              reason: 'temp NEVER changes mid-state (round $i)');
          expect(m.stateDurationRounds, prev.stateDurationRounds,
              reason: 'duration never redrawn mid-state (round $i)');
        }
        prev = m;
        // Fixture jump back to the OPERATE gate: this soak isolates the
        // MARKET machine across many operates; the legal full-round loop
        // (endTurn -> deadline check) is exercised in round_test and the
        // golden, and would entangle deadline deaths into a market test.
        state = result.state.copyWith(phase: PhaseId.operate);
      }
    });
  });

  // -------------------------------------------------------------------------
  // Cash yield (step 3)
  // -------------------------------------------------------------------------
  group('cash yield (doc 01 §6.1 step 3; economy roundOrder 3)', () {
    // The cash and ebitda pins in this group hold under ANY event draw:
    // the slice events carry no cash delta, and the only ebitda event
    // (EVT_KEY_CLIENT_LOSS) is SERVICES-sectored while these fixtures hold
    // SOFTWARE/RETAIL ventures.
    test('an active debt-free venture pays trunc(ebitda * 35/100) into cash',
        () {
      final result = runOperate(base(), SplitMix64Rng(3), kContent);
      expect(result.state.cashCents, 5000000 + 210000);
    });

    test('a passive venture pays the dampened trunc(ebitda * 35/200)', () {
      final result = runOperate(base(ventures: [venture(passive: true)]),
          SplitMix64Rng(3), kContent);
      expect(result.state.cashCents, 5000000 + 105000);
    });

    test('yield sums per venture with per-venture truncation', () {
      // Two 99-cent-EBITDA ventures: 34 + 34 (per-venture trunc), not
      // trunc(198*35/100) = 69.
      final result = runOperate(
          base(ventures: [
            venture(id: 'a', ebitdaCents: 99),
            venture(id: 'b', ebitdaCents: 99, sector: Sector.retail),
          ]),
          SplitMix64Rng(3),
          kContent);
      expect(result.state.cashCents, 5000000 + 68);
    });

    test('yield is computed on PRE-decay EBITDA (step 3 before step 4)', () {
      // roundsNeglected 1: ebitda decays 4% this operate, but the yield
      // still pays on the full 1,000,000.
      final result = runOperate(
          base(ventures: [venture(ebitdaCents: 1000000, roundsNeglected: 1)]),
          SplitMix64Rng(3),
          kContent);
      expect(result.state.cashCents, 5000000 + 350000);
      expect(ventureOf(result.state, 'v1').ebitdaCents, 960000);
    });
  });

  // -------------------------------------------------------------------------
  // Neglect decay (step 4)
  // -------------------------------------------------------------------------
  group('neglect decay in OPERATE (doc 01 §7.8; economy decay)', () {
    /// A HUNTED seed whose event roll FIRES EVT_CREDIT_CRUNCH (multiple
    /// -2800) on the one-venture tier-4 shape. The two floor tests below
    /// rely on the 1000-milli clamp ABSORBING it (a crunch cannot push a
    /// floored multiple below the floor; ebitda decay pins are %-fixed
    /// and crunch-untouched), so the exact pins hold WITH the event —
    /// hunted via the probe so a contract move re-hunts instead of
    /// silently breaking.
    final crunchSeed = seedFiring('EVT_CREDIT_CRUNCH');

    test('an attended venture (0 rounds) does not decay; counter increments',
        () {
      final result = runOperate(base(), SplitMix64Rng(4), kContent);
      final v = ventureOf(result.state, 'v1');
      expect(v.ebitdaCents, 600000);
      expect(v.roundsNeglected, 1);
      expect(
          result.events.where((e) => e.type == GameEventType.neglectDecay),
          isEmpty);
    });

    test('1 round neglected: ebitda -4%, multiple untouched by decay', () {
      // Twin-probe the drift so the multiple expectation is exact.
      final probe = SplitMix64Rng(5);
      probeHand(probe, 4);
      probe.nextInt(10000); // rate
      final u1 = probe.nextInt(1000);
      final u2 = probe.nextInt(1000);
      expect(probeEvent(probe, 4), isNull,
          reason: 'seed 5 picked so the multiple pin stays event-free');
      final postDrift = 8000 +
          driftDeltaMilli(
              multipleMilli: 8000,
              stateFactorMilli: 1000,
              volMilli: 300,
              triMilli: u1 + u2 - 1000);

      final result = runOperate(
          base(ventures: [venture(ebitdaCents: 1000000, roundsNeglected: 1)]),
          SplitMix64Rng(5),
          kContent);
      final v = ventureOf(result.state, 'v1');
      expect(v.ebitdaCents, 960000);
      expect(v.multipleMilli, postDrift,
          reason: 'multRate is 0 at 1 round neglected');
      expect(v.roundsNeglected, 2);
      final decayEvents =
          result.events.where((e) => e.type == GameEventType.neglectDecay);
      expect(decayEvents, hasLength(1));
      expect(decayEvents.single.ventureId, 'v1');
      expect(decayEvents.single.amount, -40000,
          reason: 'headline = signed ebitda delta');
    });

    test('2 rounds neglected: ebitda -8% and multiple -3% (post-drift)', () {
      final seed = seedMissingEvent(ventures: 1);
      final probe = SplitMix64Rng(seed);
      probeHand(probe, 4);
      probe.nextInt(10000); // rate
      final u1 = probe.nextInt(1000);
      final u2 = probe.nextInt(1000);
      expect(probeEvent(probe, 4), isNull,
          reason: 'the hunted seed keeps the multiple pin event-free');
      final postDrift = 14000 +
          driftDeltaMilli(
              multipleMilli: 14000,
              stateFactorMilli: 1000,
              volMilli: 300,
              triMilli: u1 + u2 - 1000);
      final expectedMultiple = postDrift - (postDrift * 3) ~/ 100;

      final result = runOperate(
          base(ventures: [
            venture(
                ebitdaCents: 1000000,
                multipleMilli: 14000,
                roundsNeglected: 2)
          ]),
          SplitMix64Rng(seed),
          kContent);
      final v = ventureOf(result.state, 'v1');
      expect(v.ebitdaCents, 920000);
      expect(v.multipleMilli, expectedMultiple);
      expect(v.roundsNeglected, 3);
    });

    test('passive halves the decay (3+ rounds: -7.5% / -3%)', () {
      // COLD market on a floor multiple: drift can only push DOWN onto the
      // 1000 clamp, so the multiple entering decay is exactly 1000 — and
      // the hunted seed's crunch event is absorbed by the same clamp.
      final result = runOperate(
          base(
              ventures: [
                venture(
                    ebitdaCents: 1000000,
                    multipleMilli: 1000,
                    passive: true,
                    roundsNeglected: 3)
              ],
              market: stickyMarket(temp: MarketTemp.cold)),
          SplitMix64Rng(crunchSeed),
          kContent);
      final v = ventureOf(result.state, 'v1');
      expect(v.ebitdaCents, 925000); // -trunc(1e6 * 15/200)
      expect(v.multipleMilli, 1000,
          reason: 'decay (-trunc(1000*6/200) = -30) clamps back to the '
              '1000-milli live-venture floor');
      expect(v.roundsNeglected, 4);
    });

    test('the multiple floor clamps active deep-neglect decay too (and '
        'absorbs the hunted seed\'s crunch event)', () {
      final result = runOperate(
          base(
              ventures: [
                venture(
                    ebitdaCents: 1000000,
                    multipleMilli: 1000,
                    roundsNeglected: 5)
              ],
              market: stickyMarket(temp: MarketTemp.cold)),
          SplitMix64Rng(crunchSeed),
          kContent);
      final v = ventureOf(result.state, 'v1');
      expect(v.ebitdaCents, 850000); // -trunc(1e6 * 15/100), capped table
      expect(v.multipleMilli, multipleFloorMilli);
      expect(v.roundsNeglected, 6);
    });
  });

  group('neglect reset-on-target (wired into apply, doc 02 §2 ACT)', () {
    GameState neglected() => GameState(
          ventures: [
            venture(roundsNeglected: 3),
            venture(
                id: 'v2',
                sector: Sector.retail,
                multipleMilli: 3000,
                ebitdaCents: 400000,
                roundsNeglected: 3),
          ],
          cashCents: 5000000,
          round: 2,
          tier: 4,
          playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
          playsHeld: const ['p'], // PlayConsumable/SellPlay membership gate
        );

    final targeted = <String, Action>{
      'RaiseEquity': const RaiseEquity(ventureId: 'v1', raiseCents: 100000),
      'TakeDebt': const TakeDebt(
          ventureId: 'v1', proceedsCents: 100000, faceDebtCents: 120000),
      'AcquireAddOn': const AcquireAddOn(
        targetVentureId: 'v1',
        addonSector: Sector.software,
        addonEbitdaCents: 100000,
        addonBuyMultipleMilli: 5000,
        addonFaceDebtCents: 0,
      ),
      'DividendRecap': const DividendRecap(ventureId: 'v1', recapPctBp: 3000),
      'HireCEO': const HireCEO(ventureId: 'v1', costCents: 300000),
      'ReinvestBaseline':
          const ReinvestBaseline(ventureId: 'v1', amountCents: 100000),
      'PlayConsumable (targeted)': PlayConsumable(
          playId: 'p', targetVentureId: 'v1', deltas: const {'ebitda': 1}),
    };

    for (final entry in targeted.entries) {
      test('${entry.key} resets the TARGET to 0 and leaves the bystander',
          () {
        final result =
            apply(neglected(), entry.value, SplitMix64Rng(1), kContent);
        expect(
            result.events
                .where((e) => e.type == GameEventType.actionRejected),
            isEmpty,
            reason: '${entry.key} must reach its success path');
        expect(ventureOf(result.state, 'v1').roundsNeglected, 0);
        expect(ventureOf(result.state, 'v2').roundsNeglected, 3);
      });
    }

    test('non-targeting actions reset nothing', () {
      final untargeted = <String, Action>{
        'SellPlay': const SellPlay(playId: 'p', purchasePriceCents: 100000),
        'Reroll': const Reroll(costCents: 100000),
        'PlayConsumable (context-free)':
            PlayConsumable(playId: 'p', deltas: const {'cash': -100000}),
      };
      for (final entry in untargeted.entries) {
        final result =
            apply(neglected(), entry.value, SplitMix64Rng(1), kContent);
        expect(ventureOf(result.state, 'v1').roundsNeglected, 3,
            reason: '${entry.key} targets no venture');
        expect(ventureOf(result.state, 'v2').roundsNeglected, 3);
      }
    });

    test('StartVenture seeds the NEW venture at 0 and resets no one else',
        () {
      final result = apply(
          neglected(),
          const StartVenture(
            ventureId: 'v3',
            sector: Sector.services,
            ebitdaCents: 100000,
            multipleMilli: 5000,
            priceCents: 500000,
            faceDebtCents: 0,
          ),
          SplitMix64Rng(1),
          kContent);
      expect(ventureOf(result.state, 'v3').roundsNeglected, 0);
      expect(ventureOf(result.state, 'v1').roundsNeglected, 3);
      expect(ventureOf(result.state, 'v2').roundsNeglected, 3);
    });

    test('a rejected targeted action resets nothing (no mutation)', () {
      final before = neglected();
      final result = apply(before,
          const RaiseEquity(ventureId: 'ghost', raiseCents: 1),
          SplitMix64Rng(1), kContent);
      expect(result.state, before);
      expect(ventureOf(result.state, 'v1').roundsNeglected, 3);
    });
  });

  // -------------------------------------------------------------------------
  // Interest + bankruptcy (step 6, F4 + F6)
  // -------------------------------------------------------------------------
  group('interest charge (doc 01 §6.1 step 6; F4)', () {
    test('zero total debt charges nothing and emits no INTEREST_CHARGED', () {
      final result = runOperate(base(), SplitMix64Rng(10), kContent);
      expect(result.state.cashCents, 5000000 + 210000,
          reason: 'yield in, nothing out');
      expect(
          result.events
              .where((e) => e.type == GameEventType.interestCharged),
          isEmpty);
    });

    test('charges interestDue(liveRateBp, TOTAL netDebt) and emits the bill',
        () {
      final probe = SplitMix64Rng(11);
      probeHand(probe, 4); // step 0 precedes the rate draw
      final rate = liveRateBpFromDraw(probe.nextInt(10000), MarketTemp.neutral);
      final interest = interestDue(rate, 30000000);

      final result = runOperate(
          base(ventures: [venture(ebitdaCents: 0, netDebtCents: 30000000)]),
          SplitMix64Rng(11),
          kContent);
      expect(result.state.cashCents, 5000000 - interest);
      final billed = result.events
          .where((e) => e.type == GameEventType.interestCharged);
      expect(billed, hasLength(1));
      expect(billed.single.amount, interest);
      expect(result.state.market.liveRateBp, rate);
    });

    test('F4 truncates on the TOTAL, not per venture', () {
      // Pure-formula pin: 99 + 99 cents of debt at 800 bp.
      expect(interestDue(800, 198), 15);
      expect(2 * interestDue(800, 99), 14,
          reason: 'per-venture trunc would lose a cent — the engine sums '
              'netDebt FIRST (F4: trunc(rate * SUM(netDebt) / 10000))');
    });
  });

  group('bankruptcy (F6: cash < 0 after interest; doc 01 §2.2)', () {
    // An EBITDA-0 venture isolates the cash flow: no yield, no decay loss.
    GameState debtState(int cashCents) => base(
        ventures: [venture(ebitdaCents: 0, netDebtCents: 50000000)],
        cashCents: cashCents);

    int probedInterest(int seed) {
      final probe = SplitMix64Rng(seed);
      probeHand(probe, 4); // step 0 precedes the rate draw
      final rate = liveRateBpFromDraw(probe.nextInt(10000), MarketTemp.neutral);
      return interestDue(rate, 50000000);
    }

    test('cash == interest survives at exactly 0 (the boundary)', () {
      final interest = probedInterest(12);
      expect(interest, greaterThan(0));
      final result =
          runOperate(debtState(interest), SplitMix64Rng(12), kContent);
      expect(result.state.cashCents, 0);
      expect(result.state.phase, PhaseId.act);
      expect(
          result.events.where((e) => e.type == GameEventType.bankruptcy),
          isEmpty);
    });

    test('cash one cent short dies: runOver, cash stays NEGATIVE', () {
      final interest = probedInterest(12);
      final result =
          runOperate(debtState(interest - 1), SplitMix64Rng(12), kContent);
      expect(result.state.cashCents, -1,
          reason: 'cash is NEVER clamped — going negative IS the death '
              'signal (economy F6_bankruptcy)');
      expect(result.state.phase, PhaseId.runOver);
      final deaths =
          result.events.where((e) => e.type == GameEventType.bankruptcy);
      expect(deaths, hasLength(1));
      expect(deaths.single.amount, -1);
      expect(
          result.events
              .where((e) => e.type == GameEventType.interestCharged),
          hasLength(1),
          reason: 'the fatal bill is still itemized');
      expect(result.state.playsRemaining, 0,
          reason: 'a dead run gets no plays');
    });

    test('runOperate on a dead run throws StateError', () {
      final dead = base(phase: PhaseId.runOver);
      expect(() => runOperate(dead, SplitMix64Rng(1), kContent),
          throwsStateError);
    });
  });

  // -------------------------------------------------------------------------
  // Phase + plays grant
  // -------------------------------------------------------------------------
  group('phase transition + playsRemaining grant (doc 02 §2)', () {
    test('a surviving OPERATE always lands in ACT', () {
      final result = runOperate(base(), SplitMix64Rng(13), kContent);
      expect(result.state.phase, PhaseId.act);
    });

    test('playsRemaining resets to playsPerRound(tier): 2/3/3/4/4', () {
      const expected = {1: 2, 2: 3, 3: 3, 4: 4, 5: 4};
      for (final entry in expected.entries) {
        final result = runOperate(base(ventures: const [], tier: entry.key),
            SplitMix64Rng(14), kContent);
        expect(result.state.playsRemaining, entry.value,
            reason: 'tier ${entry.key}');
        expect(result.state.phase, PhaseId.act);
      }
    });

    test('OPERATE enforces the strict gate: any non-operate phase throws '
        '(the Round-2 flip of the documented Round-1 deferral)', () {
      for (final phase in [
        PhaseId.act,
        PhaseId.shop,
        PhaseId.deadlineCheck,
      ]) {
        expect(
            () => runOperate(base(phase: phase), SplitMix64Rng(15), kContent),
            throwsStateError,
            reason: 'runOperate from $phase is a caller bug (doc 02 §2)');
      }
    });

    test('round and tier are untouched (DEADLINE_CHECK owns round advance)',
        () {
      final before = base();
      final result = runOperate(before, SplitMix64Rng(16), kContent);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
    });
  });

  // -------------------------------------------------------------------------
  // Determinism
  // -------------------------------------------------------------------------
  group('determinism (doc 03 §3: replay is the save format)', () {
    // The strict machine (round layer) means operates are joined by the
    // legal endTurn -> runDeadlineCheck steps (NW here is far below the T4
    // bar, so each check just advances the round; both steps draw nothing).
    GameState mixedScript(int seed) {
      var state = base(ventures: [venture(roundsNeglected: 1)]);
      final rng = SplitMix64Rng(seed);
      state = runOperate(state, rng, kContent).state;
      state = apply(
              state,
              const TakeDebt(
                  ventureId: 'v1',
                  proceedsCents: 500000,
                  faceDebtCents: 600000),
              rng,
              kContent)
          .state;
      state = runDeadlineCheck(endTurn(state, rng, kContent)).state;
      state = runOperate(state, rng, kContent).state;
      state = runDeadlineCheck(endTurn(state, rng, kContent)).state;
      state = runOperate(state, rng, kContent).state;
      return state;
    }

    test('the same seed + the same mixed script reproduces the exact state',
        () {
      final first = mixedScript(99);
      final second = mixedScript(99);
      expect(identical(first, second), isFalse);
      expect(first, second);
    });

    test('a different seed diverges (the draws are real)', () {
      expect(mixedScript(99), isNot(mixedScript(100)));
    });
  });
}
