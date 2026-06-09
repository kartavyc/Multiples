// ExitVenture — acquisition / IPO: convert paper to real, frees a SLOT
// (doc 02 §3.7 EXIT; economy-model.json formulas.exit / exitMultiple).
//
// Covers, one behavior per test:
//   - exitMultiple = min(offer, liveMarket) — both orderings, exact cents
//   - proceeds = trunc((trunc(ebitda*exitMultiple/1000) - netDebt) * own
//     / 10000), incl. a truncation edge and trunc-toward-zero on negative
//     equity (a fire-sale is legal as long as cash survives)
//   - the venture is REMOVED (frees its SLOT); EXIT_REALIZED is emitted
//   - structural-removal reconciliation: dNetWorth == proceeds - the
//     removed venture's pre-exit stake (no value conjured, doc 02 §3 note)
//   - rejections (missing venture, exit_would_bankrupt) leave the WHOLE
//     state value-identical, emit ACTION_REJECTED, no log, no draw
//   - §7 shape: venture removal + cash + actionLog only; 0 RNG draws
//
// The hotWindowArmed high-multiple override is DEFERRED to the market layer;
// liveMarketMultipleMilli is a TEMPORARY payload carrier until then (see
// actions.dart).
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

/// The venture under test: EBITDA $6,000, stored (live venture) multiple 6x,
/// netDebt $1,000, you own 80%.
Venture venture({
  int ebitdaCents = 600000,
  int netDebtCents = 100000,
  int ownershipBp = 8000,
}) =>
    Venture(
      id: 'v1',
      sector: Sector.software,
      ebitdaCents: ebitdaCents,
      multipleMilli: 6000,
      netDebtCents: netDebtCents,
      ownershipBp: ownershipBp,
    );

/// A second held venture that must survive any exit untouched.
const Venture bystander = Venture(
  id: 'v2',
  sector: Sector.retail,
  ebitdaCents: 400000,
  multipleMilli: 3000,
  netDebtCents: 50000,
  ownershipBp: 10000,
);

GameState base({Venture? v, int cashCents = 2000000}) => GameState(
      ventures: [v ?? venture(), bystander],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: 2,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (an exit draws nothing; cursor must not move).
SplitMix64Rng rng() => SplitMix64Rng(1);

ExitVenture exitAction({
  String ventureId = 'v1',
  int offerMultipleMilli = 7000,
  int liveMarketMultipleMilli = 6500,
}) =>
    ExitVenture(
      ventureId: ventureId,
      offerMultipleMilli: offerMultipleMilli,
      liveMarketMultipleMilli: liveMarketMultipleMilli,
    );

void main() {
  group('ExitVenture happy path (doc 02 §3.7; economy exit/exitMultiple)', () {
    test('caps the offer at the live market multiple (offer > live)', () {
      // exitMultiple = min(7000, 6500) = 6500.
      // evAtExit = trunc(600,000 * 6500 / 1000) = 3,900,000;
      // equityAtExit = 3,800,000; proceeds = trunc(* 8000 / 10000) = 3,040,000.
      final result = apply(base(), exitAction(), rng(), kContent);
      expect(result.state.cashCents, 2000000 + 3040000);
    });

    test('takes the offer when it is below the live multiple', () {
      // exitMultiple = min(5500, 6500) = 5500.
      // evAtExit = 3,300,000; equity = 3,200,000; proceeds = 2,560,000.
      final result =
          apply(base(), exitAction(offerMultipleMilli: 5500), rng(), kContent);
      expect(result.state.cashCents, 2000000 + 2560000);
    });

    test('removes the venture, freeing its SLOT; the bystander survives', () {
      final result = apply(base(), exitAction(), rng(), kContent);
      expect(result.state.ventures, hasLength(1));
      expect(result.state.ventures.single, bystander);
    });

    test('emits EXIT_REALIZED with the proceeds and venture id', () {
      final result = apply(base(), exitAction(), rng(), kContent);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.exitRealized);
      expect(result.events.single.amount, 3040000);
      expect(result.events.single.ventureId, 'v1');
    });

    test('truncates both divisions toward zero (odd cents)', () {
      // ebitda 333, netDebt 0, own 3333; exitMultiple = 6500:
      // evAtExit = trunc(333 * 6500 / 1000) = trunc(2164.5) = 2164;
      // proceeds = trunc(2164 * 3333 / 10000) = trunc(721.26) = 721.
      final before = base(
          v: venture(ebitdaCents: 333, netDebtCents: 0, ownershipBp: 3333));
      final result = apply(before, exitAction(), rng(), kContent);
      expect(result.state.cashCents - before.cashCents, 721);
    });

    test('a negative-equity fire-sale is legal and truncates toward zero', () {
      // ebitda 0 -> evAtExit 0; netDebt 1001; own 5000:
      // proceeds = trunc(-1001 * 5000 / 10000) = trunc(-500.5) = -500
      // (toward zero, NOT floor's -501). Cash absorbs the hit; venture gone.
      final before = base(
          v: venture(ebitdaCents: 0, netDebtCents: 1001, ownershipBp: 5000));
      final result = apply(before, exitAction(), rng(), kContent);
      expect(result.state.cashCents - before.cashCents, -500);
      expect(result.state.ventures, hasLength(1));
      expect(result.events.single.amount, -500);
    });

    test('logs a LoggedAction at the current round', () {
      final before = base();
      final result = apply(before, exitAction(), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
    });
  });

  group('structural-removal reconciliation (doc 02 §3 venture add/remove)',
      () {
    test('dNetWorth == proceeds - the removed venture pre-exit stake', () {
      // Pre-exit stake at the STORED 6000 multiple:
      // (3,600,000 - 100,000) * 8000 / 10000 = 2,800,000.
      // Proceeds at min(7000, 6500) = 3,040,000 -> dNW = +240,000: the exit
      // realizes the spread between the live mark and the exit multiple —
      // no value is conjured by the removal itself.
      final before = base();
      final result = apply(before, exitAction(), rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents,
          3040000 - 2800000);
    });

    test('an at-the-mark exit leaves net worth unchanged', () {
      // exitMultiple == the stored multiple (6000): proceeds == the stake,
      // so paper converts to real 1:1 and dNW == 0.
      final before = base();
      final result = apply(
          before,
          exitAction(offerMultipleMilli: 6000, liveMarketMultipleMilli: 6000),
          rng(), kContent);
      expect(result.state.netWorthCents, before.netWorthCents);
    });
  });

  group('ExitVenture rejection paths (PRE failed: no mutation)', () {
    test('missing venture leaves the WHOLE state value-identical', () {
      final before = base();
      final stream = rng();
      final result = apply(before, exitAction(ventureId: 'nope'), stream, kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'venture_not_found');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });

    test('an exit that would push cash below zero is rejected '
        '(no mid-Act bankruptcy, doc 02 §2)', () {
      // Deep negative equity: evAtExit = 3,900,000; netDebt 6,000,000 ->
      // equity -2,100,000; proceeds = trunc(-2,100,000 * 8000/10000)
      // = -1,680,000. Cash 1,000,000 + proceeds < 0 -> rejected.
      final before =
          base(v: venture(netDebtCents: 6000000), cashCents: 1000000);
      final stream = rng();
      final result = apply(before, exitAction(), stream, kContent);
      expect(result.state, before);
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'exit_would_bankrupt');
      expect(stream.cursor, 0);
    });

    test('cash + proceeds == 0 exactly is allowed (PRE is >= 0)', () {
      // proceeds = -1,680,000 as above; cash exactly covers it.
      final before =
          base(v: venture(netDebtCents: 6000000), cashCents: 1680000);
      final result = apply(before, exitAction(), rng(), kContent);
      expect(result.state.cashCents, 0);
      expect(result.state.ventures, hasLength(1));
    });
  });

  group('§7 shape (venture removal + cash + actionLog only)', () {
    test('bystander venture and bookkeeping are untouched; 0 draws', () {
      final before = base();
      final stream = rng();
      final result = apply(before, exitAction(), stream, kContent);
      expect(result.state.ventures.single, bystander);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });
  });
}
