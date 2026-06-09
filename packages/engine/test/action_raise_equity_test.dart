// RaiseEquity — grow the pie, cut your slice (doc 02 §3.2 RAISE; F5).
//
// Covers, one behavior per test:
//   - happy path: cash += raise; ownership dilutes per F5 with
//     preMoney = current equity (exact pinned integers + truncation edge)
//   - DILUTION event with the signed ownership delta in bp
//   - rejections (missing venture, non-positive equity) leave the WHOLE
//     state value-identical, emit ACTION_REJECTED, do not log, draw nothing
//   - §7 shape: only own + cash + actionLog change; 0 RNG draws
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

/// The venture under test: EBITDA $6,000 @6x, so EV = 3,600,000 cents and
/// equity = EV - netDebt reads off directly.
Venture venture({int netDebtCents = 0, int ownershipBp = 10000}) => Venture(
      id: 'v1',
      sector: Sector.software,
      ebitdaCents: 600000,
      multipleMilli: 6000,
      netDebtCents: netDebtCents,
      ownershipBp: ownershipBp,
    );

GameState base({Venture? v, int cashCents = 2000000}) => GameState(
      ventures: [v ?? venture()],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: 2,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (a raise draws nothing; cursor must not move).
SplitMix64Rng rng() => SplitMix64Rng(1);

void main() {
  group('RaiseEquity happy path (doc 02 §3.2; F5)', () {
    test('adds the raise to cash (facePrice is NEW MONEY for a RAISE)', () {
      final result = apply(
          base(),
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000),
          rng(), kContent);
      expect(result.state.cashCents, 3200000);
    });

    test('dilutes ownership per F5: preMoney = current equity', () {
      // equity = 3,600,000; raise 1,200,000:
      // newOwn = trunc(10000 * 3,600,000 / 4,800,000) = 7500.
      final result = apply(
          base(),
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000),
          rng(), kContent);
      expect(result.state.ventures.single.ownershipBp, 7500);
    });

    test('truncates the diluted ownership toward zero', () {
      // netDebt 100,000 -> equity 3,500,000; raise 1,000,000:
      // newOwn = trunc(10000 * 3,500,000 / 4,500,000) = trunc(7777.78) = 7777.
      final result = apply(
          base(v: venture(netDebtCents: 100000)),
          const RaiseEquity(ventureId: 'v1', raiseCents: 1000000),
          rng(), kContent);
      expect(result.state.ventures.single.ownershipBp, 7777);
    });

    test('GROWTH RIDERS land AFTER the dilution math (doc 02 §3.2 POST; '
        'round 10): preMoney is the PRE-rider equity', () {
      // FIN_SEED_RAISE shape: raise 3,000,000 + riders (+200k ebitda,
      // +1000 milli). preMoney = 3,600,000 (pre-rider!):
      // newOwn = trunc(10000 * 3,600,000 / 6,600,000) = 5454.
      final result = apply(
          base(),
          const RaiseEquity(
            ventureId: 'v1',
            raiseCents: 3000000,
            ebitdaDeltaCents: 200000,
            multipleDeltaMilli: 1000,
          ),
          rng(), kContent);
      final v = result.state.ventures.single;
      expect(v.ownershipBp, 5454,
          reason: 'the round prices the company AS-IS; pricing post-rider '
              'would mark up the founder\'s own raise');
      expect(v.ebitdaCents, 800000, reason: '600k + the 200k rider');
      expect(v.multipleMilli, 7000, reason: '6000 + the 1000-milli rider');
      expect(result.state.cashCents, base().cashCents + 3000000);
    });

    test('a negative multiple rider floors at the 1000-milli live floor', () {
      final result = apply(
          base(),
          const RaiseEquity(
            ventureId: 'v1',
            raiseCents: 100000,
            multipleDeltaMilli: -99000,
          ),
          rng(), kContent);
      expect(result.state.ventures.single.multipleMilli, 1000);
    });

    test('riderless raises are byte-identical to the v4 behavior (defaults '
        '0)', () {
      final withDefaults = apply(
          base(),
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000),
          rng(), kContent);
      final v = withDefaults.state.ventures.single;
      expect(v.ebitdaCents, 600000);
      expect(v.multipleMilli, 6000);
    });

    test('dilutes a partial stake proportionally', () {
      // own 8000, equity 3,600,000, raise 1,200,000:
      // newOwn = trunc(8000 * 3,600,000 / 4,800,000) = 6000.
      final result = apply(
          base(v: venture(ownershipBp: 8000)),
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000),
          rng(), kContent);
      expect(result.state.ventures.single.ownershipBp, 6000);
    });

    test('emits DILUTION with the signed bp delta and venture id', () {
      final result = apply(
          base(),
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000),
          rng(), kContent);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.dilution);
      expect(result.events.single.amount, -2500); // 7500 - 10000
      expect(result.events.single.ventureId, 'v1');
    });

    test('logs a LoggedAction at the current round', () {
      final before = base();
      final result = apply(before,
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
    });
  });

  group('RaiseEquity rejection paths (PRE failed: no mutation)', () {
    test('missing venture leaves the WHOLE state value-identical', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const RaiseEquity(ventureId: 'nope', raiseCents: 1200000), stream, kContent);
      expect(result.state, before);
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'venture_not_found');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });

    test('negative equity is rejected with raise_blocked_negative_equity', () {
      // netDebt 4,000,000 > EV 3,600,000 -> equity -400,000.
      final before = base(v: venture(netDebtCents: 4000000));
      final stream = rng();
      final result = apply(before,
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000), stream, kContent);
      expect(result.state, before);
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'raise_blocked_negative_equity');
      expect(stream.cursor, 0);
    });

    test('exactly zero equity is rejected too (PRE is strict > 0)', () {
      final before = base(v: venture(netDebtCents: 3600000));
      final result = apply(before,
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000), rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'raise_blocked_negative_equity');
    });
  });

  group('§7 shape (only own + cash + actionLog change)', () {
    test('ebitda/multiple/netDebt and bookkeeping are untouched; 0 draws', () {
      final before = base(v: venture(netDebtCents: 100000));
      final stream = rng();
      final result = apply(before,
          const RaiseEquity(ventureId: 'v1', raiseCents: 1000000), stream, kContent);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 600000);
      expect(v.multipleMilli, 6000);
      expect(v.netDebtCents, 100000);
      expect(v.passive, isFalse);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('net worth moves by raise minus the stake value lost to dilution',
        () {
      // Stake before: 3,600,000 at 10000 bp. After: at 7500 bp = 2,700,000.
      // dNW = +1,200,000 cash - 900,000 stake = +300,000.
      final before = base();
      final result = apply(before,
          const RaiseEquity(ventureId: 'v1', raiseCents: 1200000), rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents, 300000);
    });
  });
}
