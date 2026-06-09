// TakeDebt — leverage: cash now, a recurring interest bill forever
// (doc 02 §3.3 TAKE_DEBT).
//
// Covers, one behavior per test:
//   - happy path: cash += proceeds; venture netDebt += faceDebt (odd-cent
//     pinned integers; the action has no division, so no truncation exists —
//     exactness is pinned instead)
//   - proceeds and face debt move independently (OID/fee spreads are legal)
//   - rejection (missing venture) leaves the WHOLE state value-identical,
//     emits ACTION_REJECTED, does not log, draws nothing
//   - §7 shape: only netDebt + cash + actionLog change; 0 RNG draws
//
// The doc 02 §3.3 COLD-market gate is DEFERRED to the market layer (the
// engine has no MarketState yet); see the resolver doc comment.
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

Venture venture({int netDebtCents = 0}) => Venture(
      id: 'v1',
      sector: Sector.industrial,
      ebitdaCents: 600000,
      multipleMilli: 8000,
      netDebtCents: netDebtCents,
      ownershipBp: 10000,
    );

GameState base({Venture? v, int cashCents = 2000000}) => GameState(
      ventures: [v ?? venture()],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: 1,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (TakeDebt draws nothing; cursor must not move).
SplitMix64Rng rng() => SplitMix64Rng(1);

void main() {
  group('TakeDebt happy path (doc 02 §3.3)', () {
    test('adds the proceeds to cash exactly (odd cents preserved)', () {
      final result = apply(
          base(),
          const TakeDebt(
              ventureId: 'v1', proceedsCents: 1000001, faceDebtCents: 1150001),
          rng(), kContent);
      expect(result.state.cashCents, 3000001);
    });

    test('adds the face debt to the venture netDebt exactly', () {
      final result = apply(
          base(v: venture(netDebtCents: 250000)),
          const TakeDebt(
              ventureId: 'v1', proceedsCents: 1000001, faceDebtCents: 1150001),
          rng(), kContent);
      expect(result.state.ventures.single.netDebtCents, 1400001);
    });

    test('proceeds and face debt are independent (the OID/fee spread)', () {
      // Face 1,150,000 owed for 1,000,000 in pocket: the spread is the cost.
      final before = base();
      final result = apply(
          before,
          const TakeDebt(
              ventureId: 'v1', proceedsCents: 1000000, faceDebtCents: 1150000),
          rng(), kContent);
      expect(result.state.cashCents - before.cashCents, 1000000);
      expect(
          result.state.ventures.single.netDebtCents -
              before.ventures.single.netDebtCents,
          1150000);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result = apply(
          before,
          const TakeDebt(
              ventureId: 'v1', proceedsCents: 1000000, faceDebtCents: 1150000),
          rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });
  });

  group('TakeDebt rejection paths (PRE failed: no mutation)', () {
    test('missing venture leaves the WHOLE state value-identical', () {
      final before = base();
      final stream = rng();
      final result = apply(
          before,
          const TakeDebt(
              ventureId: 'nope', proceedsCents: 1000000, faceDebtCents: 1150000),
          stream, kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'venture_not_found');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });
  });

  group('§7 shape (only netDebt + cash + actionLog change)', () {
    test('ebitda/multiple/own and bookkeeping are untouched; 0 draws', () {
      final before = base();
      final stream = rng();
      final result = apply(
          before,
          const TakeDebt(
              ventureId: 'v1', proceedsCents: 1000000, faceDebtCents: 1150000),
          stream, kContent);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 600000);
      expect(v.multipleMilli, 8000);
      expect(v.ownershipBp, 10000);
      expect(v.passive, isFalse);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('net worth moves by proceeds minus the new debt (at 100% own)', () {
      // dNW = +1,000,000 cash - 1,150,000 equity = -150,000: leverage is not
      // free money; the spread plus future interest is the price.
      final before = base();
      final result = apply(
          before,
          const TakeDebt(
              ventureId: 'v1', proceedsCents: 1000000, faceDebtCents: 1150000),
          rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents, -150000);
    });
  });
}
