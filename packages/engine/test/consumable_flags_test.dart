// Consumable market flags (doc 02 §1 hotWindowArmed/marketReadHint, §3.6
// HOT_WINDOW / MARKET_READ, §2 OPERATE step-1 expiry; doc 01 §7.6 hot exit
// multiple) — the round-10 layer that closes the v1 "pure cost" gap.
//
//   - PLY_HOT_WINDOW arms; the next EXIT uses live x135/100 (the doc 01
//     §7.3 driftBubble factor as the engine's hot read), clears on use
//   - PLY_MARKET_READ reveals direction only, derived WITHOUT consuming
//     draws (model.dart marketReadDirection documents what is knowable)
//   - both expire at OPERATE step 1 once their flat round has passed
//     (doc 02 §5.2 #7: no flag survives two OPERATE passes unconsumed)
//
// All money integer cents; no double anywhere.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

GameState actFixture({
  MarketState market = const MarketState(
    temp: MarketTemp.cold,
    roundsInState: 1,
    stateDurationRounds: 3, // mid-state: next round CANNOT transition
    liveRateBp: 1200,
  ),
  List<String> playsHeld = const ['PLY_HOT_WINDOW', 'PLY_MARKET_READ'],
}) =>
    GameState(
      ventures: const [
        Venture(
          id: 'v1',
          sector: Sector.software,
          ebitdaCents: 600000,
          multipleMilli: 6000,
          netDebtCents: 100000,
          ownershipBp: 8000,
        ),
      ],
      cashCents: 3000000,
      round: 2,
      tier: 1,
      phase: PhaseId.act,
      playsRemaining: 2,
      market: market,
      playsHeld: playsHeld,
    );

void main() {
  group('actionForCard maps the two flag plays (id-keyed glue)', () {
    test('PLY_HOT_WINDOW -> armsHotWindow, purchase mirror stripped', () {
      final a = actionForCard(kContent.byId('PLY_HOT_WINDOW'))
          as PlayConsumable;
      expect(a.armsHotWindow, isTrue);
      expect(a.readsMarket, isFalse);
      expect(a.deltas, isEmpty,
          reason: 'cash -500000 mirrors cost.cash — paid at the buy');
    });

    test('PLY_MARKET_READ -> readsMarket', () {
      final a = actionForCard(kContent.byId('PLY_MARKET_READ'))
          as PlayConsumable;
      expect(a.readsMarket, isTrue);
      expect(a.armsHotWindow, isFalse);
      expect(a.deltas, isEmpty);
    });

    test('every other slice consumable maps NO flag', () {
      for (final id in ['PLY_BRIDGE_LOAN', 'PLY_DOWN_ROUND',
          'PLY_DIVIDEND_RECAP', 'PLY_SECONDARY_SALE']) {
        final a = actionForCard(kContent.byId(id), targetVentureId: 'v1')
            as PlayConsumable;
        expect(a.armsHotWindow, isFalse, reason: id);
        expect(a.readsMarket, isFalse, reason: id);
      }
    });
  });

  group('HOT_WINDOW (doc 02 §3.6 / doc 01 §7.6)', () {
    test('playing arms the flag with a flat-round + 1 expiry and emits '
        'HOT_WINDOW_ARMED; no economic delta', () {
      final before = actFixture();
      final r = playCard(before, 'PLY_HOT_WINDOW', SplitMix64Rng(1),
          kContent);
      expect(r.events.where((e) => e.type == GameEventType.actionRejected),
          isEmpty);
      expect(r.state.market.hotWindowArmed, isTrue);
      // flatRound = tier*100 + round = 102; expiry = 103.
      expect(r.state.market.hotWindowExpiresRound, 103);
      expect(
          r.events.single.type, GameEventType.hotWindowArmed);
      expect(r.events.single.amount, 103);
      expect(r.state.cashCents, before.cashCents,
          reason: 'pure flag: the cost was paid at the SHOP buy');
      expect(r.state.netWorthCents, before.netWorthCents);
      expect(r.state.playsHeld, ['PLY_MARKET_READ']);
    });

    test('the next EXIT uses live x135/100 — overriding min(offer, live) '
        'even for a LOW offer — clears the flag, emits HOT_WINDOW_FIRED',
        () {
      final armed = playCard(actFixture(), 'PLY_HOT_WINDOW',
              SplitMix64Rng(1), kContent)
          .state;
      const exit = ExitVenture(
        ventureId: 'v1',
        offerMultipleMilli: 4000, // a lowball the hot window steamrolls
        liveMarketMultipleMilli: 6000,
      );
      final r = apply(armed, exit, SplitMix64Rng(1), kContent);
      // hot multiple = 6000 * 135 / 100 = 8100 milli.
      // EV = 600000 * 8100 / 1000 = 4,860,000; equity = 4,760,000;
      // proceeds = 4,760,000 * 8000 / 10000 = 3,808,000.
      final fired = r.events
          .singleWhere((e) => e.type == GameEventType.hotWindowFired);
      expect(fired.amount, 8100);
      final realized = r.events
          .singleWhere((e) => e.type == GameEventType.exitRealized);
      expect(realized.amount, 3808000);
      expect(r.state.cashCents, armed.cashCents + 3808000);
      expect(r.state.market.hotWindowArmed, isFalse,
          reason: 'one-window lifetime: cleared on use');
      expect(r.state.market.hotWindowExpiresRound, -1);
      expect(r.state.ventures, isEmpty);
    });

    test('without the flag the same exit takes min(offer, live) — the v4 '
        'behavior is unchanged', () {
      const exit = ExitVenture(
        ventureId: 'v1',
        offerMultipleMilli: 4000,
        liveMarketMultipleMilli: 6000,
      );
      final r = apply(actFixture(), exit, SplitMix64Rng(1), kContent);
      // EV = 600000 * 4000 / 1000 = 2,400,000; equity = 2,300,000;
      // proceeds = 1,840,000.
      expect(
          r.events
              .singleWhere((e) => e.type == GameEventType.exitRealized)
              .amount,
          1840000);
      expect(r.events.where((e) => e.type == GameEventType.hotWindowFired),
          isEmpty);
    });

    test('a rejected exit consumes NOTHING: the window stays armed', () {
      final armed = playCard(actFixture(), 'PLY_HOT_WINDOW',
              SplitMix64Rng(1), kContent)
          .state;
      final r = apply(
          armed,
          const ExitVenture(
              ventureId: 'ghost',
              offerMultipleMilli: 4000,
              liveMarketMultipleMilli: 6000),
          SplitMix64Rng(1),
          kContent);
      expect(r.events.single.reason, 'venture_not_found');
      expect(r.state, armed);
      expect(r.state.market.hotWindowArmed, isTrue);
    });
  });

  group('MARKET_READ (doc 02 §3.6; honest derivation, zero draws)', () {
    test('mid-state: the hint is the CURRENT temp — a certainty (the '
        'machine cannot transition mid-state)', () {
      final r = playCard(actFixture(), 'PLY_MARKET_READ', SplitMix64Rng(1),
          kContent);
      expect(r.state.market.marketReadHint, MarketTemp.cold);
      expect(r.state.market.marketReadExpiresRound, 103);
      expect(r.events.single.type, GameEventType.marketReadRevealed);
      expect(r.events.single.reason, 'market_read_cold');
    });

    test('at a boundary: the hint is the MODAL outcome (neutral, 64/100) — '
        'a forecast, never a stream peek', () {
      final boundary = actFixture(
        market: const MarketState(
          temp: MarketTemp.cold,
          roundsInState: 3,
          stateDurationRounds: 3, // next OPERATE rolls a transition
          liveRateBp: 1200,
        ),
      );
      final rng = SplitMix64Rng(1);
      final r = playCard(boundary, 'PLY_MARKET_READ', rng, kContent);
      expect(r.state.market.marketReadHint, MarketTemp.neutral);
      expect(rng.cursor, 0,
          reason: 'the derivation consumes NO draws — replay-safe');
    });

    test('marketReadDirection is the pure helper the UI can also call', () {
      expect(
          marketReadDirection(const MarketState(
              temp: MarketTemp.hot,
              roundsInState: 1,
              stateDurationRounds: 2,
              liveRateBp: 0)),
          MarketTemp.hot);
      expect(
          marketReadDirection(const MarketState(
              temp: MarketTemp.hot,
              roundsInState: 2,
              stateDurationRounds: 2,
              liveRateBp: 0)),
          MarketTemp.neutral);
    });
  });

  group('OPERATE step-1 expiry (doc 02 §2; §5.2 #7 flag lifetime)', () {
    GameState operateFixture({required int round, required MarketState market}) =>
        GameState(
          ventures: const [
            Venture(
              id: 'v1',
              sector: Sector.software,
              ebitdaCents: 600000,
              multipleMilli: 6000,
              netDebtCents: 0,
              ownershipBp: 10000,
            ),
          ],
          cashCents: 3000000,
          round: round,
          tier: 1,
          phase: PhaseId.operate,
          market: market,
        );

    const armedMidState = MarketState(
      temp: MarketTemp.neutral,
      roundsInState: 1,
      stateDurationRounds: 3,
      liveRateBp: 1200,
      hotWindowArmed: true,
      hotWindowExpiresRound: 103, // armed in round 2 (flat 102)
      marketReadHint: MarketTemp.neutral,
      marketReadExpiresRound: 103,
    );

    test('the OPERATE of round r+1 (flat == expiry) KEEPS the flags — the '
        'armed round survives into the next', () {
      final r = runOperate(operateFixture(round: 3, market: armedMidState),
          SplitMix64Rng(5), kContent);
      expect(r.state.market.hotWindowArmed, isTrue);
      expect(r.state.market.marketReadHint, MarketTemp.neutral);
      expect(
          r.events.where((e) => e.type == GameEventType.hotWindowExpired),
          isEmpty);
    });

    test('the OPERATE of round r+2 (flat > expiry) SWEEPS both flags '
        '(HOT_WINDOW_EXPIRED; the read clears silently per doc 02 §2)', () {
      final r = runOperate(operateFixture(round: 4, market: armedMidState),
          SplitMix64Rng(5), kContent);
      expect(r.state.market.hotWindowArmed, isFalse);
      expect(r.state.market.hotWindowExpiresRound, -1);
      expect(r.state.market.marketReadHint, isNull);
      expect(r.state.market.marketReadExpiresRound, -1);
      expect(
          r.events.where((e) => e.type == GameEventType.hotWindowExpired),
          hasLength(1));
    });

    test('a tier advance expires a stale window too (flatRound jumps with '
        'the tier)', () {
      final r = runOperate(
          operateFixture(round: 1, market: armedMidState)
              .copyWith(tier: 2), // flat 201 > 103
          SplitMix64Rng(5),
          kContent);
      expect(r.state.market.hotWindowArmed, isFalse);
    });

    test('flag lifetime (doc 02 §5.2 #7): an unconsumed flag NEVER survives '
        'two OPERATE passes — pinned over a seed sweep', () {
      for (var seed = 0; seed < 20; seed++) {
        // Pass 1: the round after arming (round 3; armed in 2).
        final pass1 = runOperate(
            operateFixture(round: 3, market: armedMidState),
            SplitMix64Rng(seed),
            kContent);
        if (pass1.state.phase != PhaseId.act) continue; // bankrupt corner
        // Pass 2: the OPERATE after that (round 4).
        final pass2 = runOperate(
            pass1.state.copyWith(round: 4, phase: PhaseId.operate),
            SplitMix64Rng(seed + 1000),
            kContent);
        expect(pass2.state.market.hotWindowArmed, isFalse,
            reason: 'seed $seed');
        expect(pass2.state.market.marketReadHint, isNull,
            reason: 'seed $seed');
      }
    });

    test('expiry is draw-free: cursor totals match a flag-less twin', () {
      final flagged = runOperate(
          operateFixture(round: 4, market: armedMidState),
          SplitMix64Rng(5),
          kContent);
      final plain = runOperate(
          operateFixture(
              round: 4,
              market: const MarketState(
                  temp: MarketTemp.neutral,
                  roundsInState: 1,
                  stateDurationRounds: 3,
                  liveRateBp: 1200)),
          SplitMix64Rng(5),
          kContent);
      expect(flagged.state.rngCursor, plain.state.rngCursor);
    });
  });
}
