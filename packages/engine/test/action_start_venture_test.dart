// StartVenture — begin a new company, consumes a SLOT (doc 02 §3.1).
//
// Covers, one behavior per test:
//   - happy path: new venture at 100% ownership, face debt as netDebt,
//     cash -= price, LoggedAction appended
//   - the slotsMax(tier) table (doc 02 §3 PLAYS/SLOTS: 1/2/2/3/4 for T1..T5)
//   - rejections (full slots, insufficient cash) leave the state IDENTICAL
//     (value equality) and emit ACTION_REJECTED
//   - §7 shape: only cash + the structural venture add + actionLog change
//
// (The round-2 dispatcher-completeness group — "the 9 remaining actions throw
// UnimplementedError" — was retired in round 3 when those actions landed;
// test/invariant_test.dart now applies EVERY union variant behaviorally.)
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

/// An already-held venture, to fill SLOTS for rejection tests.
Venture heldVenture(String id) => Venture(
      id: id,
      sector: Sector.services,
      ebitdaCents: 600000,
      multipleMilli: 5000,
      netDebtCents: 0,
      ownershipBp: 10000,
    );

/// A base state at [tier] holding [held] ventures and [cashCents] of cash.
GameState base({int tier = 1, int held = 0, int cashCents = 2000000}) =>
    GameState(
      ventures: [for (var i = 0; i < held; i++) heldVenture('held-$i')],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: tier,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (StartVenture draws nothing).
SplitMix64Rng rng() => SplitMix64Rng(1);

/// A venture card's face values, already mapped to raw engine inputs
/// (the seed-venture shape: \$6,000 EBITDA at 6x for \$10,000).
StartVenture startAction({int priceCents = 1000000, int faceDebtCents = 0}) =>
    StartVenture(
      ventureId: 'v-new',
      sector: Sector.software,
      ebitdaCents: 600000,
      multipleMilli: 6000,
      priceCents: priceCents,
      faceDebtCents: faceDebtCents,
    );

void main() {
  group('StartVenture happy path (doc 02 §3.1)', () {
    test('creates the venture at 100% ownership with face debt as netDebt',
        () {
      final result = apply(base(), startAction(faceDebtCents: 250000), rng(), kContent);
      final v = result.state.ventures.single;
      expect(v.id, 'v-new');
      expect(v.sector, Sector.software);
      expect(v.ebitdaCents, 600000);
      expect(v.multipleMilli, 6000);
      expect(v.netDebtCents, 250000);
      expect(v.ownershipBp, 10000); // founding = 100% ownership
    });

    test('charges exactly the price from cash', () {
      final result = apply(base(cashCents: 2000000), startAction(), rng(), kContent);
      expect(result.state.cashCents, 1000000);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result = apply(before, startAction(), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });

    test('fills a free slot at tier 2 alongside a held venture', () {
      final result = apply(base(tier: 2, held: 1), startAction(), rng(), kContent);
      expect(result.state.ventures.length, 2);
      expect(result.state.ventures.last.id, 'v-new');
    });
  });

  group('slotsMax(tier) (doc 02 §3 PLAYS/SLOTS table)', () {
    test('is 1/2/2/3/4 for tiers 1..5', () {
      expect(slotsMax(1), 1);
      expect(slotsMax(2), 2);
      expect(slotsMax(3), 2); // stays at 2 so the exit fork bites
      expect(slotsMax(4), 3);
      expect(slotsMax(5), 4); // endless cap
    });

    test('rejects an out-of-range tier loudly', () {
      expect(() => slotsMax(0), throwsArgumentError);
      expect(() => slotsMax(6), throwsArgumentError);
    });
  });

  group('StartVenture rejection paths (PRE failed: no mutation)', () {
    test('full slots leaves the state IDENTICAL and emits ACTION_REJECTED',
        () {
      final before = base(tier: 1, held: 1); // T1 slotsMax == 1
      final result = apply(before, startAction(), rng(), kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'slots_full');
    });

    test('insufficient cash leaves the state IDENTICAL and emits '
        'ACTION_REJECTED', () {
      final before = base(cashCents: 999999); // one cent short
      final result = apply(before, startAction(), rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'insufficient_cash');
    });

    test('rejection does not log a LoggedAction', () {
      final before = base(tier: 1, held: 1);
      final result = apply(before, startAction(), rng(), kContent);
      expect(result.state.actionLog, before.actionLog);
    });
  });

  group('§7 shape (structural venture add + cash + bookkeeping only)', () {
    test('held venture fields and bookkeeping are untouched', () {
      final before = base(tier: 2, held: 1, cashCents: 2000000);
      final stream = rng();
      final result = apply(before, startAction(), stream, kContent);
      // The pre-existing venture is value-identical.
      expect(result.state.ventures.first, before.ventures.first);
      // Bookkeeping other than the log did not move; the RNG stream itself
      // did not advance (doc 03 §3.1: StartVenture is deterministic, 0 draws).
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('net-worth change equals the new venture equity minus the price',
        () {
      // Doc 02 §3: a structural add must reconcile to the five inputs — the
      // net-worth change equals the new venture's stake value minus the cash
      // spent; no value is conjured elsewhere.
      final before = base();
      final result = apply(before, startAction(faceDebtCents: 100000), rng(), kContent);
      // EV = trunc(600000 * 6000 / 1000) = 3,600,000; equity = 3,500,000 at
      // 100% ownership; price 1,000,000 -> dNW = +2,500,000.
      final nwDelta = result.state.netWorthCents - before.netWorthCents;
      expect(nwDelta, 2500000);
    });
  });

}
