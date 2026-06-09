// DividendRecap — pull cash out against EV; greed, can be fatal
// (doc 02 §3.6 DIVIDEND_RECAP; economy-model.json `dividendRecap`).
//
// Covers, one behavior per test:
//   - happy path: pull = trunc(EV * recapPctBp / 10000); cash += pull;
//     netDebt += pull (exact pinned integers + a truncation edge)
//   - the tier >= 2 gate (reason recap_tier_gated), checked BEFORE the
//     venture-exists PRE (work-order PRE order)
//   - rejections leave the WHOLE state value-identical, emit
//     ACTION_REJECTED, do not log, draw nothing
//   - §7 shape: only netDebt + cash + actionLog change; 0 RNG draws
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

Venture venture({int ebitdaCents = 600000, int ownershipBp = 10000}) =>
    Venture(
      id: 'v1',
      sector: Sector.retail,
      ebitdaCents: ebitdaCents,
      multipleMilli: 6000,
      netDebtCents: 0,
      ownershipBp: ownershipBp,
    );

GameState base({Venture? v, int tier = 2, int cashCents = 2000000}) =>
    GameState(
      ventures: [v ?? venture()],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: tier,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (a recap draws nothing; cursor must not move).
SplitMix64Rng rng() => SplitMix64Rng(1);

/// The canonical recap percentage: economy-model.json constants.recapPct
/// = 0.30 -> 3000 bp. The content layer passes it in; pinned here.
const int kRecapPctBp = 3000;

void main() {
  group('DividendRecap happy path (doc 02 §3.6; economy dividendRecap)', () {
    test('pulls trunc(EV * recapPct) into cash', () {
      // EV = trunc(600,000 * 6000 / 1000) = 3,600,000;
      // pull = trunc(3,600,000 * 3000 / 10000) = 1,080,000.
      final result = apply(base(),
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp), rng(), kContent);
      expect(result.state.cashCents, 2000000 + 1080000);
    });

    test('adds the same pull to the venture netDebt', () {
      final result = apply(base(),
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp), rng(), kContent);
      expect(result.state.ventures.single.netDebtCents, 1080000);
    });

    test('truncates the pull toward zero on odd cents', () {
      // ebitda 333: EV = trunc(333 * 6000 / 1000) = 1998;
      // pull = trunc(1998 * 3000 / 10000) = trunc(599.4) = 599.
      final before = base(v: venture(ebitdaCents: 333));
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp), rng(), kContent);
      expect(result.state.cashCents - before.cashCents, 599);
      expect(result.state.ventures.single.netDebtCents, 599);
    });

    test('cash delta always equals the netDebt delta (both sides = pull)', () {
      final before = base(v: venture(ebitdaCents: 777777));
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp), rng(), kContent);
      expect(result.state.cashCents - before.cashCents,
          result.state.ventures.single.netDebtCents);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });
  });

  group('DividendRecap rejection paths (PRE failed: no mutation)', () {
    test('tier 1 is gated with recap_tier_gated', () {
      final before = base(tier: 1);
      final stream = rng();
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp),
          stream, kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'recap_tier_gated');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });

    test('the tier gate is checked before venture existence', () {
      final before = base(tier: 1);
      final result = apply(before,
          const DividendRecap(ventureId: 'nope', recapPctBp: kRecapPctBp),
          rng(), kContent);
      expect(result.events.single.reason, 'recap_tier_gated');
    });

    test('missing venture (tier ok) leaves the WHOLE state value-identical',
        () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const DividendRecap(ventureId: 'nope', recapPctBp: kRecapPctBp),
          stream, kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'venture_not_found');
      expect(stream.cursor, 0);
    });
  });

  group('§7 shape (only netDebt + cash + actionLog change)', () {
    test('ebitda/multiple/own and bookkeeping are untouched; 0 draws', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp),
          stream, kContent);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 600000);
      expect(v.multipleMilli, 6000);
      expect(v.ownershipBp, 10000);
      expect(v.passive, isFalse);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('at partial ownership the recap is net-positive for you', () {
      // You bank 100% of the pull but only own 80% of the equity it debits:
      // dNW = pull - trunc(pull * 8000 / 10000) = 1,080,000 - 864,000.
      final before = base(v: venture(ownershipBp: 8000));
      final result = apply(before,
          const DividendRecap(ventureId: 'v1', recapPctBp: kRecapPctBp), rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents, 216000);
    });
  });
}
