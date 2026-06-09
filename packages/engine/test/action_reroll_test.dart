// Reroll — banker fee, recover a bad hand (doc 02 §3.8 REROLL), with the
// REAL redraw the Phase-1 note promised (live since the deal-flow layer /
// schemaVersion 4).
//
// Covers, one behavior per test:
//   - happy path: cash -= cost (odd-cent pinned; no division exists in this
//     action, so exactness is pinned instead of truncation); rerollsUsed += 1
//   - boundary: cash == cost is allowed (PRE is >=)
//   - THE REDRAW: in ACT the HAND re-runs the full hand routine (fresh
//     size draw + the no-replacement walk, twin-probed id-by-id); in SHOP
//     the OFFERS re-run the shop routine; the other deck is untouched;
//     rngCursor reconciles to the stream
//   - rejection (insufficient cash) leaves the WHOLE state value-identical
//     (including rerollsUsed and both decks), emits ACTION_REJECTED, no
//     log, NO draw (a rejected reroll must not move the stream)
//   - §7 shape: only cash + rerollsUsed + the redrawn deck + rngCursor +
//     actionLog change
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

GameState base({
  int cashCents = 2000000,
  int rerollsUsed = 0,
  PhaseId phase = PhaseId.act,
  List<String> hand = const ['STALE_HAND'],
  List<String> shopOffers = const ['STALE_OFFER'],
}) =>
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
      round: 2,
      tier: 1,
      rerollsUsed: rerollsUsed,
      phase: phase,
      hand: hand,
      shopOffers: shopOffers,
    );

/// Fresh deterministic RNG (the reroll DRAWS from it — the real redraw).
SplitMix64Rng rng() => SplitMix64Rng(1);

void main() {
  group('Reroll happy path (doc 02 §3.8)', () {
    test('charges exactly the cost from cash (odd cents preserved)', () {
      final result =
          apply(base(), const Reroll(costCents: 250001), rng(), kContent);
      expect(result.state.cashCents, 1749999);
    });

    test('increments rerollsUsed from zero', () {
      final result =
          apply(base(), const Reroll(costCents: 250000), rng(), kContent);
      expect(result.state.rerollsUsed, 1);
    });

    test('increments rerollsUsed from a non-zero count', () {
      final result = apply(base(rerollsUsed: 3),
          const Reroll(costCents: 250000), rng(), kContent);
      expect(result.state.rerollsUsed, 4);
    });

    test('cash exactly equal to the cost is allowed (PRE is >=)', () {
      final result = apply(base(cashCents: 250000),
          const Reroll(costCents: 250000), rng(), kContent);
      expect(result.state.cashCents, 0);
      expect(result.state.rerollsUsed, 1);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result =
          apply(before, const Reroll(costCents: 250000), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });
  });

  group('the REAL redraw (doc 02 §3.8: the target deck for the current '
      'phase; doc 03 §3.1 step 4)', () {
    test('in ACT the hand re-runs the FULL hand routine (twin-probed, v5: '
        'dead-draw-filtered pool + the exit-offer pair)', () {
      // The probe replays dealflow.dart's v5 contract: 1 size draw, the
      // shrinking-pool walk over the tier-1 ACT pool (slots FULL — base()
      // holds T1's one slot, so venture cards are filtered), then the two
      // exit-offer draws (ventures exist).
      final pool = handPool(kContent, 1, slotsFull: true);
      final probe = SplitMix64Rng(7);
      var size = kHandSizeMin + probe.nextInt(kHandSizeSpan);
      if (size > pool.length) size = pool.length;
      final remaining = [...pool];
      final expected = <String>[
        for (var i = 0; i < size; i++)
          remaining.removeAt(probe.nextInt(remaining.length)).id,
      ];
      probe.nextInt(1); // exit-offer venture pick (one venture)
      final u = probe.nextInt(kExitOfferBandDraws);
      final expectedOffer = (5000 * (kExitOfferBandFloorPermille + u)) ~/ 1000;

      final stream = SplitMix64Rng(7);
      final result = apply(
          base(), const Reroll(costCents: 250000), stream, kContent);
      expect(result.state.hand, expected,
          reason: 'the ACT reroll re-runs the hand routine, fresh size '
              'draw included');
      expect(result.state.hand, isNot(contains('STALE_HAND')),
          reason: 'the old hand is replaced wholesale');
      expect(result.state.exitOffer,
          ExitOffer(ventureId: 'v1', offerMultipleMilli: expectedOffer),
          reason: 'the exit offer renews with the hand (v5)');
      expect(result.state.shopOffers, ['STALE_OFFER'],
          reason: 'an ACT reroll never touches the SHOP counter');
      expect(stream.cursor, 1 + size + 2,
          reason: '1 size + size cards + the exit-offer pair');
      expect(result.state.rngCursor, stream.cursor,
          reason: 'the state mirror reconciles to the stream');
    });

    test('in SHOP the offers re-run the shop routine (twin-probed)', () {
      final pool = shopPool(kContent, 1);
      final probe = SplitMix64Rng(7);
      final remaining = [...pool];
      final expected = <String>[
        for (var i = 0; i < kShopOfferCount; i++)
          remaining.removeAt(probe.nextInt(remaining.length)).id,
      ];

      final stream = SplitMix64Rng(7);
      final result = apply(base(phase: PhaseId.shop),
          const Reroll(costCents: 250000), stream, kContent);
      expect(result.state.shopOffers, expected);
      expect(result.state.shopOffers, isNot(contains('STALE_OFFER')));
      expect(result.state.hand, ['STALE_HAND'],
          reason: 'a SHOP reroll never touches the HAND');
      expect(stream.cursor, kShopOfferCount,
          reason: 'no size draw on the shop routine');
      expect(result.state.rngCursor, stream.cursor);
    });

    test('the redrawn hand size is 3-5 and duplicate-free across seeds', () {
      for (var seed = 0; seed < 25; seed++) {
        final result = apply(base(), const Reroll(costCents: 250000),
            SplitMix64Rng(seed), kContent);
        final hand = result.state.hand;
        expect(hand.length, inInclusiveRange(3, 5), reason: 'seed $seed');
        expect(hand.toSet().length, hand.length, reason: 'seed $seed');
      }
    });
  });

  group('Reroll rejection paths (PRE failed: no mutation)', () {
    test('insufficient cash leaves the WHOLE state value-identical and '
        'does NOT move the stream', () {
      final before = base(cashCents: 249999, rerollsUsed: 2);
      final stream = rng();
      final result =
          apply(before, const Reroll(costCents: 250000), stream, kContent);
      expect(result.state, before);
      expect(result.state.rerollsUsed, 2); // explicitly not incremented
      expect(result.state.hand, ['STALE_HAND'],
          reason: 'a rejected reroll redraws NOTHING');
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'insufficient_cash');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0,
          reason: 'a rejected reroll must not move the stream — a fee '
              'failure cannot fork the replay');
    });
  });

  group('§7 shape (cash + rerollsUsed + the redrawn deck + rngCursor + '
      'actionLog only)', () {
    test('ventures and other bookkeeping are untouched; the cursor moves '
        'by exactly the redraw', () {
      final before = base();
      final stream = rng();
      final result =
          apply(before, const Reroll(costCents: 250000), stream, kContent);
      expect(result.state.ventures, before.ventures);
      expect(stream.cursor, greaterThan(0),
          reason: 'the reroll DRAWS now (deal-flow layer)');
      expect(result.state.rngCursor, stream.cursor);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.playsHeld, before.playsHeld);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('net worth falls by exactly the fee', () {
      final before = base();
      final result =
          apply(before, const Reroll(costCents: 250000), rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents, -250000);
    });
  });
}
