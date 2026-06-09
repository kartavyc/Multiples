// HireCEO — delegation: convert a venture to passive at an agency cost
// (doc 02 §3.10 HIRE_CEO).
//
// Covers, one behavior per test:
//   - happy path: cash -= cost (odd-cent pinned; the action has no division,
//     so exactness is pinned instead of truncation); venture.passive = true
//   - boundary: cash == cost is allowed (PRE is >=)
//   - rejections (missing venture, already passive, insufficient cash)
//     leave the WHOLE state value-identical, emit ACTION_REJECTED, no log,
//     no draw — in the work-order PRE order
//   - §7 shape: only cash + passive(bookkeeping) + actionLog change
//
// The passive consequences (reduced neglect decay, dampened cash yield)
// resolve in OPERATE, which lands with the round loop.
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

Venture venture({bool passive = false}) => Venture(
      id: 'v1',
      sector: Sector.services,
      ebitdaCents: 600000,
      multipleMilli: 5000,
      netDebtCents: 100000,
      ownershipBp: 9000,
      passive: passive,
    );

GameState base({Venture? v, int cashCents = 2000000}) => GameState(
      ventures: [v ?? venture()],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: 3,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (a hire draws nothing; cursor must not move).
SplitMix64Rng rng() => SplitMix64Rng(1);

void main() {
  group('HireCEO happy path (doc 02 §3.10)', () {
    test('charges exactly the cost from cash (odd cents preserved)', () {
      final result = apply(
          base(), const HireCEO(ventureId: 'v1', costCents: 500001), rng(), kContent);
      expect(result.state.cashCents, 1499999);
    });

    test('flips the venture to passive', () {
      final result = apply(
          base(), const HireCEO(ventureId: 'v1', costCents: 500000), rng(), kContent);
      expect(result.state.ventures.single.passive, isTrue);
    });

    test('cash exactly equal to the cost is allowed (PRE is >=)', () {
      final result = apply(base(cashCents: 500000),
          const HireCEO(ventureId: 'v1', costCents: 500000), rng(), kContent);
      expect(result.state.cashCents, 0);
      expect(result.state.ventures.single.passive, isTrue);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result = apply(before,
          const HireCEO(ventureId: 'v1', costCents: 500000), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });
  });

  group('HireCEO rejection paths (PRE failed: no mutation)', () {
    test('missing venture leaves the WHOLE state value-identical', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const HireCEO(ventureId: 'nope', costCents: 500000), stream, kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'venture_not_found');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });

    test('an already-passive venture is rejected with already_passive', () {
      final before = base(v: venture(passive: true));
      final stream = rng();
      final result = apply(before,
          const HireCEO(ventureId: 'v1', costCents: 500000), stream, kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'already_passive');
      expect(stream.cursor, 0);
    });

    test('the passive check precedes the cash check', () {
      // Already passive AND broke: the work-order PRE order says
      // already_passive wins.
      final before = base(v: venture(passive: true), cashCents: 0);
      final result = apply(before,
          const HireCEO(ventureId: 'v1', costCents: 500000), rng(), kContent);
      expect(result.events.single.reason, 'already_passive');
    });

    test('insufficient cash is rejected one cent short', () {
      final before = base(cashCents: 499999);
      final result = apply(before,
          const HireCEO(ventureId: 'v1', costCents: 500000), rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'insufficient_cash');
    });
  });

  group('§7 shape (cash + passive bookkeeping + actionLog only)', () {
    test('the five economic venture inputs and bookkeeping are untouched; '
        '0 draws', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const HireCEO(ventureId: 'v1', costCents: 500000), stream, kContent);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 600000);
      expect(v.multipleMilli, 5000);
      expect(v.netDebtCents, 100000);
      expect(v.ownershipBp, 9000);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('net worth falls by exactly the agency cost', () {
      final before = base();
      final result = apply(before,
          const HireCEO(ventureId: 'v1', costCents: 500000), rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents, -500000);
    });
  });
}
