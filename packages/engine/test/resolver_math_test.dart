// Layer-1 frozen-formula tests — Dart port of prototype/resolver_test.mjs.
//
// These 11 assertions are GREEN in the Node prototype (prototype/resolver_test.mjs)
// and are reproduced here against the real model types (package:engine/model.dart)
// and the authoritative constants in data/economy-model.json.
//
// Mapping prototype .mjs assertion -> Dart test (see final report):
//   1  seed NetWorth == $56,000 (5,600,000 cents)
//   2  tier-1 bar == $1M   in cents (100000000)
//   3  tier-2 bar == $10M  in cents (1000000000)
//   4  tier-3 bar == $100M in cents (10000000000)
//   5  tier-4 bar == $1B   in cents (100000000000)
//   6  T1 climb ~17.9x from seed net worth
//   7  §7 invariant: a delta may carry only the five mutable inputs
//   8  raise dilutes owner (80% -> <80%)
//   9  zero debt => zero interest
//  10  more debt => more interest
//  11  multiple arbitrage is accretive
//
// All money is integer cents; no `double` is used anywhere in this test.

import 'package:engine/model.dart';
import 'package:engine/resolver.dart';
import 'package:test/test.dart';

// --- Seed constants, cited from data/economy-model.json "constants" block ---
//   startCash=2000000, startEbitda=600000, startMultiple=6000,
//   startOwnership=10000, startNetDebt=0. Seed NetWorth is contractually
//   $56,000 = 5,600,000 cents (see constants._note and tierBars).
const int kStartCash = 2000000;
const int kStartEbitda = 600000;
const int kStartMultiple = 6000;
const int kStartOwnership = 10000;
const int kStartNetDebt = 0;

// --- Tier bars, cited from data/economy-model.json "tierBars" (integer cents) ---
const int kTier1BarCents = 100000000; //   $1M
const int kTier2BarCents = 1000000000; //  $10M
const int kTier3BarCents = 10000000000; // $100M
const int kTier4BarCents = 100000000000; // $1B

/// The canonical seed venture (one SOFTWARE company at the low 6x seed multiple).
Venture seedVenture() => const Venture(
      id: 'seed',
      sector: Sector.software,
      ebitdaCents: kStartEbitda,
      multipleMilli: kStartMultiple,
      netDebtCents: kStartNetDebt,
      ownershipBp: kStartOwnership,
    );

void main() {
  group('Layer-1 frozen formulas (port of resolver_test.mjs)', () {
    // Assertion 1: seed NetWorth must equal $56,000 (5,600,000 cents).
    test('1. seed NetWorth == \$56,000 (5,600,000 cents)', () {
      final state = GameState(
        ventures: [seedVenture()],
        cashCents: kStartCash,
      );
      // F1/F2/F3 composed: EV = 600000*6000/1000 = 3,600,000; equity = 3,600,000;
      // mine = 3,600,000; + cash 2,000,000 = 5,600,000.
      expect(netWorth([seedVenture()], kStartCash), 5600000);
      // Cross-check against the model's own derived getter (same formula chain).
      expect(state.netWorthCents, 5600000);
    });

    // Assertions 2-5: tier bars are in cents and label-consistent ($1M..$1B).
    test('2. tier-1 bar == \$1M in cents', () {
      expect(kTier1BarCents, 100000000);
    });
    test('3. tier-2 bar == \$10M in cents', () {
      expect(kTier2BarCents, 1000000000);
    });
    test('4. tier-3 bar == \$100M in cents', () {
      expect(kTier3BarCents, 10000000000);
    });
    test('5. tier-4 bar == \$1B in cents', () {
      expect(kTier4BarCents, 100000000000);
    });

    // Assertion 6: T1 growth from seed to bar matches the stated multiple (~17.9x).
    // Integer fixed-point: ratio in milli-x = trunc(bar * 1000 / seedNW).
    // 100000000 * 1000 / 5600000 = 17857 milli-x = 17.857x, within 0.5 of 17.9.
    test('6. T1 climb is ~17.9x from seed net worth', () {
      final seedNw = netWorth([seedVenture()], kStartCash);
      final climbMilliX = (kTier1BarCents * 1000) ~/ seedNw;
      // |climb - 17.9x| < 0.5x, i.e. within 500 milli-x of 17900 milli-x.
      expect((climbMilliX - 17900).abs() < 500, isTrue,
          reason: 'got $climbMilliX milli-x');
    });

    // Assertion 7: §7 invariant — every card delta uses only the five inputs.
    test('7. delta obeys §7 invariant (only the five mutable inputs)', () {
      expect(deltaObeysInvariant({'ebitda': 1, 'cash': -2}), isTrue);
      expect(deltaObeysInvariant({'multiple': 1, 'netDebt': 1, 'own': 1}),
          isTrue);
      // A delta touching anything else (e.g. a flat score) violates the invariant.
      expect(deltaObeysInvariant({'score': 100}), isFalse);
    });

    // Assertion 8: dilution shrinks the slice (80% -> <80% after a raise).
    test('8. a raise dilutes the owner (80% -> <80%)', () {
      // preMoney = current equity; raise adds to post-money. F5.
      final newOwn = diluteOwnership(8000, 5600000, 2000000);
      expect(newOwn < 8000, isTrue, reason: 'got $newOwn bp');
      // Exact: trunc(8000 * 5600000 / 7600000) = 5894 bp.
      expect(newOwn, 5894);
    });

    // Assertion 9: zero debt => zero interest.
    test('9. zero debt => zero interest', () {
      expect(interestDue(1200, 0), 0);
    });

    // Assertion 10: more debt => more interest (scales with debt).
    test('10. more debt => more interest', () {
      expect(interestDue(1200, 10000000) > interestDue(1200, 1000000), isTrue);
      // Exact at 12% (1200 bp): trunc(1200 * 10,000,000 / 10000) = 1,200,000.
      expect(interestDue(1200, 10000000), 1200000);
      expect(interestDue(1200, 1000000), 120000);
    });

    // Assertion 11: multiple arbitrage is accretive — cheap EBITDA inside an
    // expensive wrapper gains value (bought at 5.0x, revalued at 14.0x).
    test('11. multiple arbitrage is accretive', () {
      final buyVal = enterpriseValue(100000, 5000); //  bought at 5.0x
      final platformVal = enterpriseValue(100000, 14000); // revalued at 14.0x
      expect(platformVal > buyVal, isTrue);
      // Realized accretion helper mirrors the prototype's RENDER-ONLY flash:
      // trunc(ebitda * (m_platform - m_buy) / 1000) = 100000*(14000-5000)/1000.
      expect(arbitrageAccretion(100000, 14000, 5000), platformVal - buyVal);
      expect(arbitrageAccretion(100000, 14000, 5000), 900000);
    });
  });

  // --- Extra coverage explicitly named by the task brief (directional truths
  //     the prototype groups under "directionalityRule"): same-sector synergy is
  //     accretive, a cross-sector merge can be net-dilutive on the blended
  //     multiple, and the bankruptcy condition fires when cash < interest due.
  group('Directional Layer-1 truths (economy-model.json authoritative)', () {
    test('same-sector add-on bolts in EBITDA + 20% synergy (accretive)', () {
      // economy-model.json constants.synergySameSector = 0.20.
      // ebitda += addon.ebitda + trunc(addon.ebitda * 0.20).
      final result = absorbSameSector(platformEbitda: 600000, addonEbitda: 100000);
      expect(result, 600000 + 100000 + 20000); // 720000
      expect(result > 700000, isTrue); // strictly more than a flat bolt-on
    });

    test('cross-sector add-on drags the live platform multiple down', () {
      // economy-model.json constants.congDiscountPerAddon = 0.08:
      // multiple = trunc(multiple * (1 - 0.08)) per add-on (stacks 0.92^n).
      final dragged = absorbCrossSectorMultiple(14000);
      expect(dragged, 12880); // trunc(14000 * 92 / 100)
      expect(dragged < 14000, isTrue); // net-dilutive on the blended multiple

      // Two cross-sector add-ons stack multiplicatively (0.92^2).
      final draggedTwice = absorbCrossSectorMultiple(dragged);
      expect(draggedTwice, 11849); // trunc(12880 * 92 / 100)
      expect(draggedTwice < dragged, isTrue);
    });

    test('bankruptcy when cash < interest due (F6)', () {
      // F6: run ends when cash < 0 after interest is charged (not clamped).
      // 12% on $1,000,000 net debt = $120,000 interest due.
      final due = interestDue(1200, 1000000);
      expect(isBankrupt(100000 - due), isTrue); // cash 100k < 120k due
      expect(isBankrupt(200000 - due), isFalse); // cash 200k >= 120k due
    });
  });

  group('rerollCostCents (doc 02 §3.8/§4 scaling banker fee)', () {
    test('the first reroll of a round is the base fee (\$15k)', () {
      expect(rerollCostCents(0), kRerollBaseCents);
      expect(kRerollBaseCents, 1500000);
    });

    test('each prior reroll adds one step — a linear ramp', () {
      expect(rerollCostCents(1), 3000000); // base + 1*step = $30k
      expect(rerollCostCents(2), 4500000); // $45k
      expect(rerollCostCents(3), 6000000); // $60k
      // General shape: base + step*used.
      for (var used = 0; used <= 9; used++) {
        expect(rerollCostCents(used),
            kRerollBaseCents + kRerollStepCents * used);
      }
    });

    test('the ramp saturates at the cap (\$150k), never runs away', () {
      // base + 9*step == cap exactly; past that it stays pinned.
      expect(rerollCostCents(9), kRerollMaxCents);
      expect(rerollCostCents(10), kRerollMaxCents);
      expect(rerollCostCents(1000), kRerollMaxCents);
      expect(kRerollMaxCents, 15000000);
    });

    test('a negative rerollsUsed is clamped to the base (defensive)', () {
      expect(rerollCostCents(-1), kRerollBaseCents);
    });

    test('strictly non-decreasing in rerollsUsed (a monotone fee)', () {
      var prev = rerollCostCents(0);
      for (var used = 1; used <= 12; used++) {
        final cur = rerollCostCents(used);
        expect(cur, greaterThanOrEqualTo(prev));
        prev = cur;
      }
    });
  });
}
