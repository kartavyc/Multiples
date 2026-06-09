// ORGANIC GROWTH (doc 01 §3.2 organicGrowthDefault; §6.1 step 3's
// "+ partner engines, incl. organicGrowthDefault EBITDA bumps") — the R12
// balance round's engine-gap close.
//
// The economy constant (0.10/round) has been PARSED since Phase 2
// (EconomyConstants.organicGrowthDefaultBp) but was never applied anywhere:
// the full-model Monte-Carlo harness (tool/sim.dart) measured the floor at
// a 0.0% win rate against doc 01 §11's [25%, 42%] band — the §8 knob
// existed on paper only. Doc 01 §3.2 pins the semantics exactly:
//   - "applied as a system event (§2.1 path)" -> OPERATE step 3a, an
//     ebitda delta through the five-input discipline;
//   - "attributed to the seed partner every run and to any hired partner;
//     a venture with no partner gets 0" -> keyed off partners.isNotEmpty;
//     initRun attaches the FOUNDING OPERATOR (perRound +0) to the seed
//     venture so every run compounds out of the gate;
//   - "NOT free engine drift" -> a partnerless venture gets nothing;
//   - passive ventures are dampened to half (doc 01 §7.8 "organic growth
//     is dampened"; economy decay.passiveMultiplier = 0.5 — the
//     cashYieldDenPassive pattern, a TUNING DIAL until the spreadsheet
//     pins it).
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/init.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

void main() {
  GameState fixture({
    List<PartnerEngine> partners = const [],
    bool passive = false,
    int ebitdaCents = 600000,
  }) =>
      GameState(
        ventures: [
          Venture(
            id: 'v1',
            sector: Sector.software,
            ebitdaCents: ebitdaCents,
            multipleMilli: 6000,
            netDebtCents: 0,
            ownershipBp: 10000,
            passive: passive,
            partners: partners,
          ),
        ],
        cashCents: 1000000,
        round: 2,
        tier: 1,
        phase: PhaseId.operate,
      );

  const founding =
      PartnerEngine(defId: kFoundingPartnerDefId, perRoundEbitdaCents: 0);
  const salesLead =
      PartnerEngine(defId: 'PRT_SALES_LEAD', perRoundEbitdaCents: 150000);

  group('the organicGrowthCents helper (economy constants'
      '.organicGrowthDefault = 0.20, the R12 tune)', () {
    test('active: trunc(ebitda x 20/100)', () {
      expect(organicGrowthCents(600000, passive: false), 120000);
      expect(organicGrowthCents(999, passive: false), 199,
          reason: 'truncation toward zero, division LAST');
      expect(organicGrowthCents(0, passive: false), 0);
    });

    test('passive: halved to trunc(ebitda x 20/200) (doc 01 §7.8 '
        '"organic growth is dampened")', () {
      expect(organicGrowthCents(600000, passive: true), 60000);
      expect(organicGrowthCents(1999, passive: true), 199);
    });
  });

  group('OPERATE step 3a: organic growth for PARTNERED ventures', () {
    test('a venture with a 0-engine partner still grows 20% organically '
        '(the growth is the PARTNER attribution, not the engine face)', () {
      final withP = runOperate(
          fixture(partners: const [founding]), SplitMix64Rng(7), kContent);
      final without = runOperate(fixture(), SplitMix64Rng(7), kContent);
      expect(
          withP.state.ventures.single.ebitdaCents -
              without.state.ventures.single.ebitdaCents,
          120000,
          reason: 'organic = trunc(600000 x 20/100); same seed, same '
              'drift/decay/event otherwise');
    });

    test('organic growth and the per-round engine BOTH land, pre-yield', () {
      final withP = runOperate(
          fixture(partners: const [salesLead]), SplitMix64Rng(7), kContent);
      final without = runOperate(fixture(), SplitMix64Rng(7), kContent);
      expect(
          withP.state.ventures.single.ebitdaCents -
              without.state.ventures.single.ebitdaCents,
          120000 + 150000);
      // The SAME round's yield converts the whole accrual: 35% of 270k.
      expect(withP.state.cashCents - without.state.cashCents, 94500,
          reason: 'doc 01 §6.1 step 3: the bump is inside the yield step');
    });

    test('a venture with NO partner gets ZERO organic growth (doc 01 §3.2 '
        '"NOT free engine drift")', () {
      final r = runOperate(fixture(), SplitMix64Rng(7), kContent);
      // Drift touches the multiple, decay is off (attended), seed-7 fires
      // no ebitda-touching event for a SOFTWARE venture: ebitda holds.
      expect(r.state.ventures.single.ebitdaCents, 600000);
    });

    test('organic growth is computed on the PRE-accrual base (one round), '
        'and COMPOUNDS across rounds', () {
      // Round A: 600000 -> +120000 organic = 720000.
      final a = runOperate(
          fixture(partners: const [founding]), SplitMix64Rng(7), kContent);
      expect(a.state.ventures.single.ebitdaCents, 720000);
      // Round B (fresh fixture at the grown base): 720000 -> +144000.
      final b = runOperate(
          fixture(partners: const [founding], ebitdaCents: 720000),
          SplitMix64Rng(7),
          kContent);
      expect(b.state.ventures.single.ebitdaCents, 864000,
          reason: 'the organic compounder (doc 02 §3.5 prose)');
    });

    test('passive + partnered: organic halves, the engine face does not',
        () {
      final withP = runOperate(
          fixture(partners: const [salesLead], passive: true),
          SplitMix64Rng(7),
          kContent);
      final without =
          runOperate(fixture(passive: true), SplitMix64Rng(7), kContent);
      expect(
          withP.state.ventures.single.ebitdaCents -
              without.state.ventures.single.ebitdaCents,
          60000 + 150000,
          reason: 'organic dampens to 20/200 for passive; the hired '
              'engine\'s face accrues in full (R10 behavior unchanged)');
    });

    test('organic growth draws NOTHING (the stream is untouched)', () {
      final withP = runOperate(
          fixture(partners: const [founding]), SplitMix64Rng(7), kContent);
      final without = runOperate(fixture(), SplitMix64Rng(7), kContent);
      expect(withP.state.rngCursor, without.state.rngCursor);
    });
  });

  group('initRun: the founding operating partner (doc 01 §3.2 "attributed '
      'to the seed partner every run")', () {
    test('the seed venture carries the founding operator with a 0 engine '
        'face', () {
      final s = initRun(economy: kEconomyConfig);
      expect(s.ventures.single.partners,
          [const PartnerEngine(defId: kFoundingPartnerDefId,
              perRoundEbitdaCents: 0)]);
    });

    test('the founding operator does not move the \$56k seed contract', () {
      expect(initRun(economy: kEconomyConfig).netWorthCents, 5600000,
          reason: 'a 0-face engine adds no EV; organic growth only lands '
              'at the first OPERATE');
    });

    test('the first OPERATE grows the seed venture 20% organically, every '
        'seed (no slice event touches a SOFTWARE venture\'s ebitda)', () {
      for (final seed in [1, 7, 42, 1234]) {
        final r = runOperate(
            initRun(economy: kEconomyConfig), SplitMix64Rng(seed), kContent);
        expect(r.state.ventures.single.ebitdaCents, 720000,
            reason: 'seed $seed: 600000 + trunc(600000 x 20/100)');
      }
    });
  });
}
