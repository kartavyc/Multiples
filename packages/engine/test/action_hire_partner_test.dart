// HIRE_PARTNER + the PartnerEngine OPERATE layer (doc 02 §3.5, §1
// PartnerEngine/ScheduledEffect; the round-10 work order):
//   - the action: attach an engine, charge the price, optional one-time
//     multiple bump, optional recurring fixed cost via ScheduledCost
//   - OPERATE step 3a: per-round +EBITDA accrues PRE-yield
//   - OPERATE step 3c: scheduled costs fire alongside yield; recurring
//     persist, one-shots are removed, orphans die with their venture
//   - the card glue: actionForCard(PRT_SALES_LEAD) and playCard from hand
//
// All money integer cents; no double anywhere.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

GameState actFixture({int cashCents = 5000000, int plays = 2}) => GameState(
      ventures: const [
        Venture(
          id: 'v1',
          sector: Sector.software,
          ebitdaCents: 600000,
          multipleMilli: 6000,
          netDebtCents: 0,
          ownershipBp: 10000,
          roundsNeglected: 1,
        ),
      ],
      cashCents: cashCents,
      round: 2,
      tier: 1,
      phase: PhaseId.act,
      playsRemaining: plays,
    );

const HirePartner hire = HirePartner(
  ventureId: 'v1',
  defId: 'PRT_SALES_LEAD',
  costCents: 600000,
  perRoundEbitdaCents: 150000,
);

void main() {
  group('HIRE_PARTNER action (doc 02 §3.5)', () {
    test('success: charges the price, attaches the engine, resets neglect, '
        'costs a play, logs', () {
      final before = actFixture();
      final r = apply(before, hire, SplitMix64Rng(1), kContent);
      expect(r.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      expect(r.state.cashCents, before.cashCents - 600000);
      final v = r.state.ventures.single;
      expect(v.partners, [
        const PartnerEngine(
            defId: 'PRT_SALES_LEAD', perRoundEbitdaCents: 150000),
      ]);
      expect(v.ebitdaCents, 600000,
          reason: 'the +EBITDA is PER-ROUND (OPERATE step 3a), never an '
              'at-hire delta');
      expect(v.roundsNeglected, 0, reason: 'targeting resets neglect');
      expect(r.state.playsRemaining, before.playsRemaining - 1,
          reason: 'HIRE_PARTNER costs a PLAY (doc 02 §3.5/§3 matrix)');
      expect(r.state.scheduled, isEmpty,
          reason: 'no fixed cost on the base variant');
      expect(r.state.actionLog.length, before.actionLog.length + 1);
    });

    test('a second hire stacks a second engine in list order', () {
      final first = apply(actFixture(), hire, SplitMix64Rng(1), kContent);
      final r = apply(
          first.state,
          const HirePartner(
            ventureId: 'v1',
            defId: 'PRT_X',
            costCents: 100000,
            perRoundEbitdaCents: 10000,
          ),
          SplitMix64Rng(1),
          kContent);
      expect(r.state.ventures.single.partners.map((p) => p.defId).toList(),
          ['PRT_SALES_LEAD', 'PRT_X']);
    });

    test('one-time multiple bump applies at hire and floors at 1000 milli',
        () {
      final up = apply(
          actFixture(),
          const HirePartner(
            ventureId: 'v1',
            defId: 'PRT_GROWTH_HACKER',
            costCents: 750000,
            perRoundEbitdaCents: 120000,
            multipleDeltaMilli: 500,
          ),
          SplitMix64Rng(1),
          kContent);
      expect(up.state.ventures.single.multipleMilli, 6500);
      final down = apply(
          actFixture(),
          const HirePartner(
            ventureId: 'v1',
            defId: 'PRT_DOOM',
            costCents: 0,
            perRoundEbitdaCents: 0,
            multipleDeltaMilli: -99000,
          ),
          SplitMix64Rng(1),
          kContent);
      expect(down.state.ventures.single.multipleMilli, 1000,
          reason: 'the live-venture multiple floor clamps the bump');
    });

    test('fixed-cost variant registers ONE recurring ScheduledCost tied to '
        'the venture', () {
      final r = apply(
          actFixture(),
          const HirePartner(
            ventureId: 'v1',
            defId: 'PRT_COO_FIXED',
            costCents: 900000,
            perRoundEbitdaCents: 450000,
            fixedCostCents: 200000,
          ),
          SplitMix64Rng(1),
          kContent);
      expect(r.state.scheduled, [
        const ScheduledCost(
            ventureId: 'v1', cashDeltaCents: -200000, recurring: true),
      ]);
      expect(r.state.cashCents, actFixture().cashCents - 900000,
          reason: 'the fixed cost lands in OPERATE step 3c, never at hire');
    });

    for (final (label, action, expectReason, mutate) in [
      (
        'venture_not_found',
        const HirePartner(
            ventureId: 'nope',
            defId: 'PRT_SALES_LEAD',
            costCents: 1,
            perRoundEbitdaCents: 1),
        'venture_not_found',
        (GameState s) => s,
      ),
      (
        'insufficient_cash',
        hire,
        'insufficient_cash',
        (GameState s) => s.copyWith(cashCents: 599999),
      ),
      (
        'wrong_phase',
        hire,
        'wrong_phase',
        (GameState s) => s.copyWith(phase: PhaseId.shop),
      ),
      (
        'no_plays_remaining',
        hire,
        'no_plays_remaining',
        (GameState s) => s.copyWith(playsRemaining: 0),
      ),
    ]) {
      test('rejects $label with NO state change and an unmoved stream', () {
        final before = mutate(actFixture());
        final rng = SplitMix64Rng(1);
        final r = apply(before, action, rng, kContent);
        expect(r.state, before, reason: 'rejection must not mutate');
        expect(r.events.single.type, GameEventType.actionRejected);
        expect(r.events.single.reason, expectReason);
        expect(rng.cursor, 0);
      });
    }
  });

  group('OPERATE step 3a: the per-round accrual (pre-yield)', () {
    GameState operateFixture(List<PartnerEngine> partners) => GameState(
          ventures: [
            Venture(
              id: 'v1',
              sector: Sector.software,
              ebitdaCents: 600000,
              multipleMilli: 6000,
              netDebtCents: 0,
              ownershipBp: 10000,
              partners: partners,
            ),
          ],
          cashCents: 1000000,
          round: 2,
          tier: 1,
          phase: PhaseId.operate,
        );

    test('+EBITDA lands on the venture and the SAME round\'s yield converts '
        'it (the accrual is pre-yield)', () {
      const engine =
          PartnerEngine(defId: 'PRT_SALES_LEAD', perRoundEbitdaCents: 150000);
      final withP =
          runOperate(operateFixture(const [engine]), SplitMix64Rng(7),
              kContent);
      final without =
          runOperate(operateFixture(const []), SplitMix64Rng(7), kContent);
      final vP = withP.state.ventures.single;
      final v0 = without.state.ventures.single;
      expect(vP.ebitdaCents - v0.ebitdaCents, 120000 + 150000,
          reason: 'the engine accrued its per-round +EBITDA AND the '
              'organic growth a partnered venture earns (trunc(600000 x '
              '20/100), doc 01 §3.2 at the R12-tuned 0.20; same seed, '
              'same drift/decay otherwise)');
      // Yield difference = 35% of the accrued 120k organic + 150k face.
      expect(withP.state.cashCents - without.state.cashCents, 94500,
          reason: 'the yield converted the partner earnings THIS round');
      expect(withP.state.rngCursor, without.state.rngCursor,
          reason: 'partners draw NOTHING — the stream is untouched');
    });

    test('two engines both accrue', () {
      const a =
          PartnerEngine(defId: 'A', perRoundEbitdaCents: 100000);
      const b = PartnerEngine(defId: 'B', perRoundEbitdaCents: 50000);
      final withTwo = runOperate(
          operateFixture(const [a, b]), SplitMix64Rng(7), kContent);
      final without =
          runOperate(operateFixture(const []), SplitMix64Rng(7), kContent);
      expect(
          withTwo.state.ventures.single.ebitdaCents -
              without.state.ventures.single.ebitdaCents,
          120000 + 100000 + 50000,
          reason: 'organic growth (once, on the pre-accrual base) + both '
              'engine faces');
    });
  });

  group('OPERATE step 3c: scheduled costs', () {
    GameState scheduledFixture(List<ScheduledCost> scheduled,
            {int cashCents = 1000000}) =>
        GameState(
          ventures: const [
            Venture(
              id: 'v1',
              sector: Sector.software,
              ebitdaCents: 100000,
              multipleMilli: 6000,
              netDebtCents: 0,
              ownershipBp: 10000,
            ),
          ],
          cashCents: cashCents,
          round: 2,
          tier: 1,
          phase: PhaseId.operate,
          scheduled: scheduled,
        );

    test('a recurring fixed cost charges cash, emits '
        'SCHEDULED_EFFECT_FIRED, and PERSISTS', () {
      const cost = ScheduledCost(
          ventureId: 'v1', cashDeltaCents: -40000, recurring: true);
      final withC =
          runOperate(scheduledFixture(const [cost]), SplitMix64Rng(7),
              kContent);
      final without =
          runOperate(scheduledFixture(const []), SplitMix64Rng(7), kContent);
      expect(withC.state.cashCents - without.state.cashCents, -40000);
      expect(withC.state.scheduled, [cost],
          reason: 'recurring entries persist while the venture lives');
      final fired = withC.events
          .where((e) => e.type == GameEventType.scheduledEffectFired);
      expect(fired.single.amount, -40000);
      expect(fired.single.ventureId, 'v1');
    });

    test('a non-recurring entry fires ONCE and is removed', () {
      const oneShot = ScheduledCost(
          ventureId: null, cashDeltaCents: -25000, recurring: false);
      final r = runOperate(
          scheduledFixture(const [oneShot]), SplitMix64Rng(7), kContent);
      final without =
          runOperate(scheduledFixture(const []), SplitMix64Rng(7), kContent);
      expect(r.state.cashCents - without.state.cashCents, -25000);
      expect(r.state.scheduled, isEmpty);
    });

    test('an entry tied to a venture that left play is DROPPED without '
        'firing', () {
      const orphan = ScheduledCost(
          ventureId: 'gone', cashDeltaCents: -999999, recurring: true);
      final r = runOperate(
          scheduledFixture(const [orphan]), SplitMix64Rng(7), kContent);
      final without =
          runOperate(scheduledFixture(const []), SplitMix64Rng(7), kContent);
      expect(r.state.cashCents, without.state.cashCents,
          reason: 'the orphan never charged');
      expect(r.state.scheduled, isEmpty,
          reason: 'the orphan is pruned (doc 02 §2 step 5: persists while '
              'the partner exists)');
      expect(
          r.events.where(
              (e) => e.type == GameEventType.scheduledEffectFired),
          isEmpty);
    });

    test('a fixed cost can push cash negative mid-OPERATE; F6 still only '
        'verdicts at step 6 (telegraphed operating-leverage death)', () {
      const knife = ScheduledCost(
          ventureId: 'v1', cashDeltaCents: -5000000, recurring: true);
      final r = runOperate(
          scheduledFixture(const [knife], cashCents: 10000),
          SplitMix64Rng(7),
          kContent);
      expect(r.state.phase, PhaseId.runOver);
      expect(r.state.death, DeathCause.bankruptcy);
      expect(r.state.cashCents, lessThan(0));
    });
  });

  group('the card glue (PRT_SALES_LEAD, the slice partner)', () {
    test('actionForCard maps the partner card onto HirePartner — cost from '
        'the cost block, +150k/rd from the ebitda delta, the purchase '
        'mirror ignored, no fixed cost in the v1 schema', () {
      final card = kContent.byId('PRT_SALES_LEAD');
      final action = actionForCard(card, targetVentureId: 'v1');
      expect(
          action,
          const HirePartner(
            ventureId: 'v1',
            defId: 'PRT_SALES_LEAD',
            costCents: 600000,
            perRoundEbitdaCents: 150000,
            multipleDeltaMilli: 0,
            fixedCostCents: 0,
          ));
    });

    test('PRT_COO_FIXED maps a RECURRING fixed salary (R17 operating '
        'leverage): fixedCostCents = 60% of the +EBITDA it brings', () {
      final card = kContent.byId('PRT_COO_FIXED');
      final action = actionForCard(card, targetVentureId: 'v1') as HirePartner;
      // ebitda +450k -> salary 450k * 6000bp / 10000 = 270k/round.
      expect(action.perRoundEbitdaCents, 450000);
      expect(action.fixedCostCents, 270000,
          reason: 'the COO bills a fixed salary the slice partner never does');
      expect(action.costCents, 900000);
    });

    test('the COO salary is a recurring ScheduledCost that fires every '
        'OPERATE (operating leverage is REAL)', () {
      final before = actFixture(cashCents: 5000000)
          .copyWith(hand: const ['PRT_COO_FIXED']);
      final r = playCard(before, 'PRT_COO_FIXED', SplitMix64Rng(1), kContent,
          targetVentureId: 'v1');
      expect(r.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      // The hire scheduled a recurring -$270k salary tied to v1.
      final sched = r.state.scheduled
          .where((c) => c.ventureId == 'v1' && c.recurring);
      expect(sched, hasLength(1));
      expect(sched.single.cashDeltaCents, -270000);
    });

    test('actionForCard without a target throws (partners are targeted)',
        () {
      expect(() => actionForCard(kContent.byId('PRT_SALES_LEAD')),
          throwsArgumentError);
    });

    test('playCard hires from the HAND and consumes the card', () {
      final before =
          actFixture().copyWith(hand: const ['PRT_SALES_LEAD']);
      final r = playCard(before, 'PRT_SALES_LEAD', SplitMix64Rng(1),
          kContent,
          targetVentureId: 'v1');
      expect(r.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      expect(r.state.hand, isEmpty, reason: 'the played card left the hand');
      expect(r.state.ventures.single.partners.single.defId,
          'PRT_SALES_LEAD');
    });

    test('playCard rejects a partner card that is not in the hand', () {
      final r = playCard(actFixture(), 'PRT_SALES_LEAD', SplitMix64Rng(1),
          kContent,
          targetVentureId: 'v1');
      expect(r.events.single.reason, 'card_not_in_hand');
      expect(r.state, actFixture());
    });
  });
}
