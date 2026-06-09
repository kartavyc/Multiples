// SellPlay — sell a held consumable for ~50% of purchase price; the
// liquidity lesson (doc 02 §3.6 sell-a-play).
//
// Covers, one behavior per test:
//   - happy path: cash += trunc(purchasePrice / 2), incl. the odd-cent
//     truncation edge and the degenerate 1-cent play
//   - the playsHeld inventory (live since the deal-flow layer): the
//     play_not_held membership gate; success removes exactly one copy
//   - no OTHER PRE: works at zero cash and with no ventures
//   - §7 shape: only cash + playsHeld + actionLog change; 0 RNG draws
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

GameState base({
  int cashCents = 2000000,
  List<Venture>? ventures,
  List<String> playsHeld = const ['play-1'],
}) =>
    GameState(
      ventures: ventures ??
          [
            const Venture(
              id: 'v1',
              sector: Sector.retail,
              ebitdaCents: 400000,
              multipleMilli: 3000,
              netDebtCents: 0,
              ownershipBp: 10000,
            ),
          ],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: 1,
      playsHeld: playsHeld,
    );

/// Fresh deterministic RNG (selling a play draws nothing).
SplitMix64Rng rng() => SplitMix64Rng(1);

void main() {
  group('SellPlay happy path (doc 02 §3.6 sell-a-play)', () {
    test('pays out exactly half an even purchase price', () {
      final result = apply(base(),
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000), rng(), kContent);
      expect(result.state.cashCents, 2200000);
    });

    test('truncates the half toward zero on an odd purchase price', () {
      // trunc(400,001 / 2) = 200,000 — the odd cent is lost, not rounded up.
      final result = apply(base(),
          const SellPlay(playId: 'play-1', purchasePriceCents: 400001), rng(), kContent);
      expect(result.state.cashCents, 2200000);
    });

    test('a 1-cent play sells for zero', () {
      final before = base();
      final result = apply(before,
          const SellPlay(playId: 'play-1', purchasePriceCents: 1), rng(), kContent);
      expect(result.state.cashCents, before.cashCents);
    });

    test('has no cash PRE: selling at zero cash works', () {
      final result = apply(base(cashCents: 0),
          const SellPlay(playId: 'play-1', purchasePriceCents: 300000), rng(), kContent);
      expect(result.state.cashCents, 150000);
    });

    test('has no venture PRE: selling with zero ventures works', () {
      final result = apply(base(ventures: const []),
          const SellPlay(playId: 'play-1', purchasePriceCents: 300000), rng(), kContent);
      expect(result.state.cashCents, 2150000);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result = apply(before,
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });
  });

  group('the playsHeld inventory (deal-flow layer)', () {
    test('selling REMOVES the play from playsHeld', () {
      final result = apply(base(),
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000),
          rng(), kContent);
      expect(result.state.playsHeld, isEmpty);
    });

    test('a duplicate-held id loses exactly ONE copy', () {
      final before = base(playsHeld: const ['play-1', 'play-1']);
      final result = apply(before,
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000),
          rng(), kContent);
      expect(result.state.playsHeld, ['play-1']);
    });

    test('an UNHELD play is rejected with play_not_held, no mutation', () {
      final before = base(playsHeld: const []);
      final stream = rng();
      final result = apply(before,
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000),
          stream, kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'play_not_held');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });

    test('holding a DIFFERENT id does not satisfy the gate', () {
      final before = base(playsHeld: const ['other']);
      final result = apply(before,
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000),
          rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'play_not_held');
    });
  });

  group('§7 shape (cash + playsHeld consumption + actionLog only)', () {
    test('ventures and bookkeeping are untouched; 0 draws', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000),
          stream, kContent);
      expect(result.state.ventures, before.ventures);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('net worth rises by exactly the half-price proceeds', () {
      final before = base();
      final result = apply(before,
          const SellPlay(playId: 'play-1', purchasePriceCents: 400000), rng(), kContent);
      expect(result.state.netWorthCents - before.netWorthCents, 200000);
    });
  });
}
