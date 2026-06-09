// The PLY_SPIN_OFF + PLY_EARN_OUT resolvers (doc 02 §3.6; R20b). Both are
// consumables routed via actionForCard -> PlayConsumable; the engine resolves
// the structural / scheduled semantics the v1 layer left minimal.
//
// SPIN_OFF (whole-venture form — no add-on ledger in v1): split the target
// back out at its CURRENT live mark, bank the equity stake, FREE the slot.
// Structural, like a partial exit but at the live multiple (no offer
// haircut / hot window) — it LOCKS the value at the current mark. The 300k
// fee rides through deltas.cash.
//
// EARN_OUT: the card's +500k EBITDA lands NOW (no cash/debt/dilution
// upfront); a non-recurring PCT_EBITDA ScheduledCost is pushed onto the
// target, charging -trunc(target.ebitda x pct / 10000) each OPERATE for N
// rounds (the seller paid out of future earnings).
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/resolver.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

SplitMix64Rng rng() => SplitMix64Rng(1);

/// A T3 ACT state (both cards gate to tier 3) with two ventures and both
/// plays held, so each play's success path is reachable.
GameState fixture() => GameState(
      ventures: const [
        Venture(
          id: 'plat',
          sector: Sector.software,
          ebitdaCents: 2000000,
          multipleMilli: 14000,
          netDebtCents: 1000000,
          ownershipBp: 8000,
        ),
        Venture(
          id: 'unit',
          sector: Sector.retail,
          ebitdaCents: 500000,
          multipleMilli: 4000,
          netDebtCents: 200000,
          ownershipBp: 10000,
        ),
      ],
      cashCents: 5000000,
      round: 2,
      tier: 3,
      phase: PhaseId.act,
      playsRemaining: 3,
      playsHeld: const ['PLY_SPIN_OFF', 'PLY_EARN_OUT'],
    );

void main() {
  group('PLY_SPIN_OFF (doc 02 §3.6 — whole-venture form)', () {
    test('actionForCard maps PLY_SPIN_OFF to a spins-off PlayConsumable', () {
      final action = actionForCard(kContent.byId('PLY_SPIN_OFF'),
          targetVentureId: 'unit') as PlayConsumable;
      expect(action.spinsOff, isTrue);
      expect(action.earnOutPctBp, 0);
      // The card's cost.cash (300k) MIRRORS its deltas.cash (-300k), so the
      // fee was paid at the SHOP buy and the glue STRIPS it at play time —
      // exactly like PLY_HOT_WINDOW (no double-charge). At PLAY there is no
      // cash delta; the proceeds are the only cash move.
      expect(action.deltas.containsKey('cash'), isFalse);
    });

    test('banks the equity stake at the LIVE mark, frees the slot (fee paid '
        'at the shop buy, not re-charged)', () {
      final before = fixture();
      final unit = before.ventures.firstWhere((v) => v.id == 'unit');
      // proceeds = trunc((EV_live - netDebt) x own / 10000).
      final equity = equityValueOf(unit);
      final expectedProceeds = (equity * unit.ownershipBp) ~/ bpScale;

      final result = playCard(before, 'PLY_SPIN_OFF', rng(), kContent,
          targetVentureId: 'unit');
      expect(
          result.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      // Slot freed: the unit is gone, the platform remains.
      expect(result.state.ventures.map((v) => v.id), ['plat']);
      // Cash = before + proceeds (the 300k fee was the shop-buy cost).
      expect(result.state.cashCents, before.cashCents + expectedProceeds);
      // EXIT_REALIZED carries the proceeds.
      final exit = result.events
          .firstWhere((e) => e.type == GameEventType.exitRealized);
      expect(exit.amount, expectedProceeds);
      expect(exit.ventureId, 'unit');
      // The played card left the inventory (the other held play stays).
      expect(result.state.playsHeld, ['PLY_EARN_OUT']);
    });

    test('net worth reconciles: dNW == proceeds - the removed stake '
        '(no value conjured)', () {
      final before = fixture();
      final unit = before.ventures.firstWhere((v) => v.id == 'unit');
      final preStake =
          (equityValueOf(unit) * unit.ownershipBp) ~/ bpScale;
      final result = playCard(before, 'PLY_SPIN_OFF', rng(), kContent,
          targetVentureId: 'unit');
      final proceeds = result.events
          .firstWhere((e) => e.type == GameEventType.exitRealized)
          .amount;
      // The stake leaves (it was in NW); proceeds land in cash.
      expect(result.state.netWorthCents - before.netWorthCents,
          proceeds - preStake);
    });

    test('a missing target rejects with no mutation', () {
      final before = fixture();
      final result = playCard(before, 'PLY_SPIN_OFF', rng(), kContent);
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.state, before);
    });
  });

  group('PLY_EARN_OUT (doc 02 §3.6 — PCT_EBITDA scheduled drag)', () {
    test('actionForCard maps PLY_EARN_OUT to the earn-out PlayConsumable', () {
      final action = actionForCard(kContent.byId('PLY_EARN_OUT'),
          targetVentureId: 'plat') as PlayConsumable;
      expect(action.earnOutPctBp, kEarnOutPctBp);
      expect(action.earnOutRounds, kEarnOutRounds);
      expect(action.spinsOff, isFalse);
      // The acquired earnings land via deltas (no cash/debt upfront).
      expect(action.deltas['ebitda'], 500000);
      expect(action.deltas.containsKey('cash'), isFalse);
    });

    test('lands the +EBITDA now and pushes a PCT_EBITDA countdown — no cash '
        'or debt upfront', () {
      final before = fixture();
      final platBefore =
          before.ventures.firstWhere((v) => v.id == 'plat').ebitdaCents;
      final result = playCard(before, 'PLY_EARN_OUT', rng(), kContent,
          targetVentureId: 'plat');
      expect(
          result.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      final plat =
          result.state.ventures.firstWhere((v) => v.id == 'plat');
      expect(plat.ebitdaCents, platBefore + 500000,
          reason: 'the acquired earnings land immediately');
      expect(result.state.cashCents, before.cashCents,
          reason: '\$0 down — no cash moves at play time');
      expect(plat.netDebtCents, before.ventures.first.netDebtCents,
          reason: 'no debt upfront');
      // The scheduled drag: a non-fixed PCT_EBITDA entry, countdown N.
      expect(result.state.scheduled, hasLength(1));
      final sc = result.state.scheduled.single;
      expect(sc.ventureId, 'plat');
      expect(sc.pctEbitdaBp, kEarnOutPctBp);
      expect(sc.roundsLeft, kEarnOutRounds);
      expect(sc.cashDeltaCents, 0);
    });

    test('the scheduled drag fires PCT-of-EBITDA each OPERATE for exactly N '
        'rounds, then stops', () {
      // Drive OPERATEs and count the earn-out charges. Use a single-venture
      // state so the drag target is unambiguous and the run survives.
      var state = GameState(
        ventures: const [
          Venture(
            id: 'plat',
            sector: Sector.software,
            ebitdaCents: 2000000,
            multipleMilli: 14000,
            netDebtCents: 0,
            ownershipBp: 10000,
          ),
        ],
        cashCents: 50000000,
        round: 2,
        tier: 3,
        phase: PhaseId.act,
        playsRemaining: 3,
        playsHeld: const ['PLY_EARN_OUT'],
      );
      final r = playCard(state, 'PLY_EARN_OUT', rng(), kContent,
          targetVentureId: 'plat');
      state = r.state;
      expect(state.scheduled, hasLength(1));

      // Walk OPERATEs (one per "round" — drive phase manually back to
      // operate so we isolate the scheduled step). Count the earn-out fires.
      final rngRun = SplitMix64Rng(7);
      var fires = 0;
      for (var i = 0; i < kEarnOutRounds + 2; i++) {
        state = state.copyWith(phase: PhaseId.operate);
        final op = runOperate(state, rngRun, kContent);
        for (final e in op.events) {
          if (e.type == GameEventType.scheduledEffectFired &&
              e.ventureId == 'plat') {
            fires++;
            expect(e.amount, lessThan(0),
                reason: 'an earn-out drag is a negative cash charge');
          }
        }
        state = op.state;
        if (state.phase == PhaseId.runOver) break;
      }
      expect(fires, kEarnOutRounds,
          reason: 'the drag fires exactly N times then the entry is dropped');
      expect(state.scheduled, isEmpty,
          reason: 'the countdown reached zero and the entry was pruned');
    });

    test('the drag is dropped without firing if its venture leaves play '
        '(orphaned by an exit)', () {
      var state = GameState(
        ventures: const [
          Venture(
            id: 'plat',
            sector: Sector.software,
            ebitdaCents: 2000000,
            multipleMilli: 14000,
            netDebtCents: 0,
            ownershipBp: 10000,
          ),
        ],
        cashCents: 50000000,
        round: 2,
        tier: 3,
        phase: PhaseId.act,
        playsRemaining: 3,
        playsHeld: const ['PLY_EARN_OUT'],
        scheduled: const [
          ScheduledCost(
            ventureId: 'gone', // a venture not in play
            cashDeltaCents: 0,
            recurring: true,
            roundsLeft: 3,
            pctEbitdaBp: 2500,
          ),
        ],
      );
      state = state.copyWith(phase: PhaseId.operate);
      final op = runOperate(state, SplitMix64Rng(9), kContent);
      // The orphaned entry fired nothing and was pruned.
      expect(
          op.events.where((e) =>
              e.type == GameEventType.scheduledEffectFired &&
              e.ventureId == 'gone'),
          isEmpty);
      expect(op.state.scheduled.where((s) => s.ventureId == 'gone'), isEmpty);
    });
  });
}
