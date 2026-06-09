// ReinvestBaseline — the always-available baseline: brute-force EBITDA
// growth at decaying efficiency (doc 02 §3.9 REINVEST; economy-model.json
// curves.reinvestDecay).
//
// DOC DEVIATION, documented: doc 02 §3.9 sketches a per-venture
// reinvestCount-based decay; data/economy-model.json (authoritative per
// CLAUDE.md) decays by round-in-tier progress instead:
//   eff = start + (end - start) * min(1, roundInTier/deadline)
// in integer form (round 1-based, divisions LAST):
//   effBp = 5500 - (2000 * min(round - 1, deadline)) ~/ deadline
// with deadline from tierBars.deadlineRounds = [8, 8, 9, 10] and tier 5
// (endless) pinned at the 3500 floor.
//
// Covers, one behavior per test:
//   - the efficiency curve pinned at entry / midway / deadline / past it,
//     per tier, incl. the ~/ truncation inside the curve
//   - ebitda += trunc(amount * effBp / 10000), incl. a truncation edge
//   - boundary: cash == amount allowed
//   - rejections (missing venture, insufficient cash) leave the WHOLE state
//     value-identical, emit ACTION_REJECTED, no log, no draw
//   - §7 shape: only ebitda + cash + actionLog change; 0 RNG draws
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/resolver.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

GameState base({int round = 1, int tier = 1, int cashCents = 2000000}) =>
    GameState(
      ventures: [
        const Venture(
          id: 'v1',
          sector: Sector.services,
          ebitdaCents: 600000,
          multipleMilli: 5000,
          netDebtCents: 0,
          ownershipBp: 10000,
        ),
      ],
      cashCents: cashCents,
      rngCursor: 7,
      round: round,
      tier: tier,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (reinvest draws nothing; cursor must not move).
SplitMix64Rng rng() => SplitMix64Rng(1);

void main() {
  group('reinvestEfficiencyBp (economy-model.json curves.reinvestDecay)', () {
    test('tier entry (round 1) starts at 5500 bp (0.55)', () {
      expect(reinvestEfficiencyBp(round: 1, tier: 1), 5500);
    });

    test('decays linearly with round-in-tier progress (T1 deadline 9, '
        'the R12 tune)', () {
      // round 5: 5500 - (2000 * 4) ~/ 9 = 5500 - 888 = 4612.
      expect(reinvestEfficiencyBp(round: 5, tier: 1), 4612);
    });

    test('truncates the decay step toward zero (T3 deadline 9)', () {
      // round 4: 5500 - (2000 * 3) ~/ 9 = 5500 - trunc(666.67) = 4834.
      expect(reinvestEfficiencyBp(round: 4, tier: 3), 4834);
    });

    test('reaches the 3500 floor exactly at the deadline', () {
      // T1 round 10: roundInTier 9 == deadline 9 -> 5500 - 2000 = 3500.
      expect(reinvestEfficiencyBp(round: 10, tier: 1), 3500);
    });

    test('clamps to the floor past the deadline', () {
      expect(reinvestEfficiencyBp(round: 20, tier: 1), 3500);
    });

    test('uses the per-tier deadline table [9, 10, 9, 10] (R12 tune)', () {
      // Same round 10, different deadlines:
      // T1 (9): floor 3500. T4 (10): 5500 - (2000 * 9) ~/ 10 = 3700.
      expect(reinvestEfficiencyBp(round: 10, tier: 1), 3500);
      expect(reinvestEfficiencyBp(round: 10, tier: 4), 3700);
    });

    test('tier 5 (endless) is pinned at the 3500 floor', () {
      expect(reinvestEfficiencyBp(round: 1, tier: 5), 3500);
      expect(reinvestEfficiencyBp(round: 12, tier: 5), 3500);
    });
  });

  group('ReinvestBaseline happy path (doc 02 §3.9)', () {
    test('round 1 tier 1: \$1M in at 5500 bp -> +550,000 EBITDA', () {
      final result = apply(base(),
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
          rng(), kContent);
      expect(result.state.ventures.single.ebitdaCents, 600000 + 550000);
      expect(result.state.cashCents, 1000000);
    });

    test('truncates the EBITDA gain toward zero (odd cents)', () {
      // T1 round 2: effBp = 5500 - (2000 * 1) ~/ 9 = 5500 - 222 = 5278.
      // gain = trunc(333 * 5278 / 10000) = trunc(175.75) = 175.
      final before = base(round: 2);
      final result = apply(before,
          const ReinvestBaseline(ventureId: 'v1', amountCents: 333), rng(), kContent);
      expect(result.state.ventures.single.ebitdaCents, 600000 + 175);
      expect(result.state.cashCents, before.cashCents - 333);
    });

    test('at the deadline the floor efficiency applies', () {
      // T1 round 10 (deadline 9, R12): 3500 bp -> $1M in gains 350,000.
      final result = apply(base(round: 10),
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
          rng(), kContent);
      expect(result.state.ventures.single.ebitdaCents, 600000 + 350000);
    });

    test('cash exactly equal to the amount is allowed (PRE is >=)', () {
      final result = apply(base(cashCents: 1000000),
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
          rng(), kContent);
      expect(result.state.cashCents, 0);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result = apply(before,
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
          rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });
  });

  group('ReinvestBaseline rejection paths (PRE failed: no mutation)', () {
    test('missing venture leaves the WHOLE state value-identical', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const ReinvestBaseline(ventureId: 'nope', amountCents: 1000000),
          stream, kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'venture_not_found');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });

    test('insufficient cash is rejected one cent short', () {
      final before = base(cashCents: 999999);
      final stream = rng();
      final result = apply(before,
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
          stream, kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'insufficient_cash');
      expect(stream.cursor, 0);
    });
  });

  group('§7 shape (ebitda + cash + actionLog only)', () {
    test('multiple/netDebt/own and bookkeeping are untouched; 0 draws', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
          stream, kContent);
      final v = result.state.ventures.single;
      expect(v.multipleMilli, 5000);
      expect(v.netDebtCents, 0);
      expect(v.ownershipBp, 10000);
      expect(v.passive, isFalse);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('reinvest is net-dilutive in cash terms but accretive at 5x', () {
      // dNW = gain * multiple/1000 - amount
      //     = 550,000 * 5 - 1,000,000 = +1,750,000.
      final before = base();
      final result = apply(before,
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
          rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents, 1750000);
    });
  });
}
