// EXIT OFFERS PLAYABLE (round-10 item 2; doc 02 §3.7 "an exit offer card
// is present"; dealflow.dart v5 hand-routine contract):
//   - the hand routine appends TWO draws when ventures exist: venture pick
//     (nextInt(#ventures), list order) + band multiple (u = nextInt(301),
//     offer = (live x (900 + u)) ~/ 1000, floored at 1000 milli)
//   - venture-less states draw NOTHING extra and clear any stale offer
//   - exitOfferAction maps the ticket onto ExitVenture with live = the
//     venture's CURRENT multiple; min(offer, live) resolves as ever
//   - an exit of the offered venture clears the ticket
//
// All money integer cents; no double anywhere.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

Venture venture(String id, {int multipleMilli = 6000}) => Venture(
      id: id,
      sector: Sector.software,
      ebitdaCents: 600000,
      multipleMilli: multipleMilli,
      netDebtCents: 0,
      ownershipBp: 10000,
    );

GameState state({List<Venture>? ventures, int tier = 1}) => GameState(
      ventures: ventures ?? [venture('v1')],
      cashCents: 3000000,
      round: 2,
      tier: tier,
      phase: PhaseId.act,
      playsRemaining: 2,
    );

void main() {
  group('the exit-offer draws (the v5 hand-routine tail)', () {
    test('one venture: the pair is twin-probed — pick over 1, then the '
        'EXACT band formula offer = (live x (900 + u)) ~/ 1000', () {
      final probe = SplitMix64Rng(17);
      final pool = handPool(kContent, 1, slotsFull: true);
      var size = kHandSizeMin + probe.nextInt(kHandSizeSpan);
      if (size > pool.length) size = pool.length;
      for (var i = 0; i < size; i++) {
        probe.nextInt(pool.length - i);
      }
      expect(probe.nextInt(1), 0); // the venture pick (one venture)
      final u = probe.nextInt(kExitOfferBandDraws);
      final expected = (6000 * (kExitOfferBandFloorPermille + u)) ~/ 1000;

      final rng = SplitMix64Rng(17);
      final after = drawHand(state(), rng, kContent);
      expect(after.exitOffer,
          ExitOffer(ventureId: 'v1', offerMultipleMilli: expected));
      expect(rng.cursor, probe.cursor,
          reason: 'hand + the exit-offer pair, nothing else');
      expect(after.rngCursor, rng.cursor);
    });

    test('multi-venture: the pick indexes ventures LIST ORDER and the band '
        'reads THAT venture\'s live multiple', () {
      final two = state(
          ventures: [venture('a', multipleMilli: 4000),
              venture('b', multipleMilli: 9000)],
          tier: 2);
      for (var seed = 0; seed < 30; seed++) {
        final probe = SplitMix64Rng(seed);
        final pool = handPool(kContent, 2, slotsFull: true);
        var size = kHandSizeMin + probe.nextInt(kHandSizeSpan);
        if (size > pool.length) size = pool.length;
        for (var i = 0; i < size; i++) {
          probe.nextInt(pool.length - i);
        }
        final pick = probe.nextInt(2);
        final u = probe.nextInt(kExitOfferBandDraws);
        final live = pick == 0 ? 4000 : 9000;
        final expected =
            (live * (kExitOfferBandFloorPermille + u)) ~/ 1000;

        final after = drawHand(two, SplitMix64Rng(seed), kContent);
        expect(
            after.exitOffer,
            ExitOffer(
                ventureId: pick == 0 ? 'a' : 'b',
                offerMultipleMilli: expected),
            reason: 'seed $seed');
      }
    });

    test('the band lands in [0.90x, 1.20x] of live across a sweep', () {
      for (var seed = 0; seed < 40; seed++) {
        final after = drawHand(state(), SplitMix64Rng(seed), kContent);
        final offer = after.exitOffer!;
        expect(offer.offerMultipleMilli,
            inInclusiveRange((6000 * 900) ~/ 1000, (6000 * 1200) ~/ 1000),
            reason: 'seed $seed');
      }
    });

    test('a floor-multiple venture\'s low-band offer clamps at 1000 milli',
        () {
      // live = 1000: raw band floor is 900 — must clamp to the
      // live-venture floor.
      var sawClamp = false;
      for (var seed = 0; seed < 200 && !sawClamp; seed++) {
        final after = drawHand(
            state(ventures: [venture('v1', multipleMilli: 1000)]),
            SplitMix64Rng(seed),
            kContent);
        final offer = after.exitOffer!.offerMultipleMilli;
        expect(offer, greaterThanOrEqualTo(1000), reason: 'seed $seed');
        if (offer == 1000) sawClamp = true;
      }
      expect(sawClamp, isTrue,
          reason: 'the sweep should witness the clamp binding at least '
              'once (u < 100 has ~1/3 probability per draw)');
    });

    test('venture-less: ZERO extra draws and any stale offer clears', () {
      final stale = GameState(
        ventures: const [],
        cashCents: 0,
        tier: 1,
        exitOffer: const ExitOffer(ventureId: 'gone', offerMultipleMilli: 1),
      );
      final probe = SplitMix64Rng(3);
      final pool = handPool(kContent, 1, slotsFull: false);
      var size = kHandSizeMin + probe.nextInt(kHandSizeSpan);
      if (size > pool.length) size = pool.length;
      for (var i = 0; i < size; i++) {
        probe.nextInt(pool.length - i);
      }

      final rng = SplitMix64Rng(3);
      final after = drawHand(stale, rng, kContent);
      expect(after.exitOffer, isNull,
          reason: 'no ventures, no offer — the stale ticket expires');
      expect(rng.cursor, probe.cursor,
          reason: 'no exit-offer draws without ventures');
    });

    test('each hand draw REPLACES the offer wholesale (one per round)', () {
      final first = drawHand(state(), SplitMix64Rng(1), kContent);
      final second = drawHand(first, SplitMix64Rng(99), kContent);
      expect(second.exitOffer, isNotNull);
      // Different stream position -> almost surely a different offer; the
      // CONTRACT point is that the field was rewritten, not appended.
      expect(second.exitOffer!.ventureId, 'v1');
    });
  });

  group('exitOfferAction (the ticket -> ExitVenture mapping)', () {
    test('maps the offer with live = the venture\'s CURRENT multiple', () {
      final s = state().copyWith(
          exitOffer:
              const ExitOffer(ventureId: 'v1', offerMultipleMilli: 5400));
      expect(
          exitOfferAction(s),
          const ExitVenture(
            ventureId: 'v1',
            offerMultipleMilli: 5400,
            liveMarketMultipleMilli: 6000,
          ));
    });

    test('null when no offer is pending', () {
      expect(exitOfferAction(state()), isNull);
    });

    test('null when the offered venture has left play (stale ticket)', () {
      final s = state(ventures: [venture('other')]).copyWith(
          exitOffer:
              const ExitOffer(ventureId: 'v1', offerMultipleMilli: 5400));
      expect(exitOfferAction(s), isNull);
    });

    test('the mapped action resolves through apply: min(offer, live) and '
        'the ticket clears with the venture', () {
      final s = state().copyWith(
          exitOffer:
              const ExitOffer(ventureId: 'v1', offerMultipleMilli: 5400));
      final action = exitOfferAction(s)!;
      final r = apply(s, action, SplitMix64Rng(1), kContent);
      expect(r.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      // exitMultiple = min(5400, 6000) = 5400; EV = 600000*5400/1000 =
      // 3,240,000; equity = 3,240,000; proceeds at 100% = 3,240,000.
      expect(
          r.events
              .singleWhere((e) => e.type == GameEventType.exitRealized)
              .amount,
          3240000);
      expect(r.state.ventures, isEmpty);
      expect(r.state.exitOffer, isNull,
          reason: 'the ticket died with the company');
    });

    test('an exit of a DIFFERENT venture leaves the ticket pending', () {
      final s = state(
              ventures: [venture('a'), venture('b')], tier: 2)
          .copyWith(
              exitOffer:
                  const ExitOffer(ventureId: 'a', offerMultipleMilli: 5400));
      final r = apply(
          s,
          const ExitVenture(
              ventureId: 'b',
              offerMultipleMilli: 5000,
              liveMarketMultipleMilli: 6000),
          SplitMix64Rng(1),
          kContent);
      expect(r.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      expect(r.state.exitOffer,
          const ExitOffer(ventureId: 'a', offerMultipleMilli: 5400));
    });
  });
}
