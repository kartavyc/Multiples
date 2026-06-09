// RUN INIT (the deal-flow round's opening move) + the three deal-flow model
// fields (doc 02 §1 RunState: hand / shopOffers / plays).
//
// Covers, one behavior per test:
//   - initRun maps economy-model.json constants onto the canonical T1
//     opening state: $20k pocket cash + one 100%-owned SOFTWARE venture
//     ($6k EBITDA at the 6x seed multiple, debt-free) = the $56k seed
//     net-worth CONTRACT (economy constants._note; doc 01 §6 "from $56k
//     seed NW"), phase OPERATE at round 1 / tier 1 with the documented
//     opening market and EMPTY hand/shopOffers/playsHeld (the first
//     OPERATE draws the first hand)
//   - the two doc 02 §5.1 snapshots seed at the derived opening net worth
//     (netWorthAtTierEntry per STATE.md's run-init hook; netWorthLastRound
//     so round-1 meters read a sane baseline)
//   - initRun is generic over the EconomyConfig (a non-canon fixture flows
//     through), deterministic, and draws NOTHING (no RNG in its signature)
//   - model: hand/shopOffers/playsHeld default empty, copyWith round-trips,
//     value equality is order-sensitive, lists are unmodifiable
//
// All money is integer cents; no `double` anywhere in this test.

import 'dart:io';

import 'package:engine/content.dart';
import 'package:engine/init.dart';
import 'package:engine/model.dart';
import 'package:test/test.dart';

/// The real economy model (assets/ is the byte-identical build copy of
/// /data, pinned by content_test.dart). Parsed once.
final EconomyConfig kEconomy =
    loadEconomy(File('assets/economy-model.json').readAsStringSync());

void main() {
  group('initRun: the canonical T1 opening state (economy constants)', () {
    test('the \$56k contract: derived opening net worth is 5,600,000 cents',
        () {
      final s = initRun(economy: kEconomy);
      // EV = 600000 * 6000 ~/ 1000 = 3,600,000; equity = EV (debt-free);
      // stake = 100%; + 2,000,000 pocket cash = 5,600,000 ($56k).
      expect(s.netWorthCents, 5600000);
    });

    test('seeds cash and ONE SOFTWARE venture from the constants block', () {
      final s = initRun(economy: kEconomy);
      expect(s.cashCents, 2000000); // constants.startCash
      expect(s.ventures, hasLength(1));
      final v = s.ventures.single;
      expect(v.id, kSeedVentureId);
      expect(v.sector, Sector.software); // constants.startSector
      expect(v.ebitdaCents, 600000); // constants.startEbitda
      expect(v.multipleMilli, 6000); // constants.startMultiple (low seed)
      expect(v.netDebtCents, 0); // constants.startNetDebt
      expect(v.ownershipBp, 10000); // constants.startOwnership (100%)
      expect(v.passive, isFalse);
      expect(v.roundsNeglected, 0, reason: 'the seed venture is born attended');
    });

    test('opens at round 1 / tier 1 / phase OPERATE with zero plays staged',
        () {
      final s = initRun(economy: kEconomy);
      expect(s.round, 1);
      expect(s.tier, 1);
      expect(s.phase, PhaseId.operate,
          reason: 'the first OPERATE is the run\'s first step; it grants '
              'the round\'s plays');
      expect(s.playsRemaining, 0);
      expect(s.rerollsUsed, 0);
    });

    test('carries the documented opening market and a zero RNG cursor', () {
      final s = initRun(economy: kEconomy);
      expect(s.market, kOpeningMarket);
      expect(s.rngCursor, 0,
          reason: 'initRun draws NOTHING — its signature takes no RNG; '
              'the first OPERATE consumes the first draw');
    });

    test('hand, shopOffers, and playsHeld open EMPTY', () {
      final s = initRun(economy: kEconomy);
      expect(s.hand, isEmpty,
          reason: 'the first hand is drawn by the first OPERATE '
              '(doc 03 §3.1 step 1), never by init');
      expect(s.shopOffers, isEmpty,
          reason: 'shop offers are drawn at the first endTurn');
      expect(s.playsHeld, isEmpty);
    });

    test('the §5.1 snapshots seed at the derived opening net worth', () {
      final s = initRun(economy: kEconomy);
      expect(s.netWorthAtTierEntry, 5600000,
          reason: 'T1 entry baseline = the seed NW (STATE.md run-init '
              'hook; doc 01 §6 keys T1 growth off the \$56k seed)');
      expect(s.netWorthLastRound, 5600000,
          reason: 'pre-first-OPERATE baseline so round-1 meters read sane');
    });

    test('opens alive, unwon, with an empty action log and current schema',
        () {
      final s = initRun(economy: kEconomy);
      expect(s.won, isFalse);
      expect(s.death, isNull);
      expect(s.actionLog, isEmpty);
      expect(s.schemaVersion, engineSchemaVersion);
    });

    test('is deterministic: two inits are value-identical', () {
      expect(initRun(economy: kEconomy), initRun(economy: kEconomy));
    });

    test('is generic over the economy (a non-canon fixture flows through)',
        () {
      final custom = loadEconomy('''
{
  "constants": {
    "startCash": 1000, "startEbitda": 2000, "startSector": "RETAIL",
    "startMultiple": 3000, "startOwnership": 8000, "startNetDebt": 500,
    "cashYield": 0.35, "organicGrowthDefault": 0.10,
    "carrySeedFrac": 0.24, "reseedMult": 8000,
    "interestMin": 0.08, "interestMax": 0.14,
    "targetLeverage": 3.0, "dangerLeverage": 6.0,
    "reinvestStart": 0.55, "reinvestEnd": 0.35,
    "synergySameSector": 0.20, "congDiscountPerAddon": 0.08,
    "recapPct": 0.30, "bridgeLoanRepayMul": 1.15
  },
  "sectors": [], "tierBars": []
}
''');
      final s = initRun(economy: custom);
      final v = s.ventures.single;
      expect(s.cashCents, 1000);
      expect(v.sector, Sector.retail);
      expect(v.ebitdaCents, 2000);
      expect(v.multipleMilli, 3000);
      expect(v.ownershipBp, 8000);
      expect(v.netDebtCents, 500);
      // EV = 2000*3000~/1000 = 6000; equity = 5500; stake at 8000 bp =
      // 4400; + 1000 cash = 5400. Snapshots follow the derived value.
      expect(s.netWorthCents, 5400);
      expect(s.netWorthAtTierEntry, 5400);
      expect(s.netWorthLastRound, 5400);
    });
  });

  group('model: the three deal-flow lists (doc 02 §1 RunState)', () {
    GameState empty() => GameState(ventures: const [], cashCents: 0);

    test('default to empty', () {
      final s = empty();
      expect(s.hand, isEmpty);
      expect(s.shopOffers, isEmpty);
      expect(s.playsHeld, isEmpty);
    });

    test('copyWith round-trips each list and breaks equality', () {
      final s = empty();
      expect(s.copyWith(hand: const ['A']).hand, ['A']);
      expect(s.copyWith(hand: const ['A']), isNot(s));
      expect(s.copyWith(shopOffers: const ['B']).shopOffers, ['B']);
      expect(s.copyWith(shopOffers: const ['B']), isNot(s));
      expect(s.copyWith(playsHeld: const ['C']).playsHeld, ['C']);
      expect(s.copyWith(playsHeld: const ['C']), isNot(s));
    });

    test('value equality is element- and ORDER-sensitive (list positions '
        'are replay-relevant flatten paths)', () {
      final ab = empty().copyWith(hand: const ['A', 'B']);
      final ba = empty().copyWith(hand: const ['B', 'A']);
      expect(ab, empty().copyWith(hand: const ['A', 'B']));
      expect(ab, isNot(ba));
    });

    test('the lists are unmodifiable after construction', () {
      final s = empty().copyWith(
        hand: const ['A'],
        shopOffers: const ['B'],
        playsHeld: const ['C'],
      );
      expect(() => s.hand.add('X'), throwsUnsupportedError);
      expect(() => s.shopOffers.add('X'), throwsUnsupportedError);
      expect(() => s.playsHeld.add('X'), throwsUnsupportedError);
    });

    test('copyWith leaves unnamed lists untouched', () {
      final s = empty().copyWith(
        hand: const ['A'],
        shopOffers: const ['B'],
        playsHeld: const ['C'],
      );
      final t = s.copyWith(cashCents: 5);
      expect(t.hand, ['A']);
      expect(t.shopOffers, ['B']);
      expect(t.playsHeld, ['C']);
    });
  });
}
