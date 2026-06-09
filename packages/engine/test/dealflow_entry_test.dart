// The deal-flow player entry points (apply.dart): buyShopOffer — the SHOP
// counter (doc 02 §2 SHOP) — and playCard — play a card by id from the
// deck that owns its type (doc 04 §0 canonical paths).
//
// Covers, one behavior per test:
//   - buyShopOffer happy path: cash -= cost.cash, the offer moves from
//     shopOffers into playsHeld, logged; draws nothing
//   - buyShopOffer gates IN ORDER: wrong_phase, offer_not_in_shop,
//     offer_not_buyable (financing is exercised, not held),
//     plays_full (playsHeldMax 2/2/2/3/3), insufficient_cash —
//     every rejection value-identical
//   - playCard: venture/addon consume from the HAND (card_not_in_hand);
//     financing consumes from the OFFERS (offer_not_in_shop) and resolves
//     through the locked act-phase play-costing actions; consumables
//     delegate to apply's play_not_held gate; rejection by the UNDERLYING
//     action leaves the card unconsumed
//   - the documented financing timing: an offer dealt at endTurn is
//     exercisable in the NEXT round's ACT
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

Venture venture({String id = 'v1', int multipleMilli = 14000}) => Venture(
      id: id,
      sector: Sector.software,
      ebitdaCents: 600000,
      multipleMilli: multipleMilli,
      netDebtCents: 0,
      ownershipBp: 10000,
    );

GameState shopFixture({
  int cashCents = 2000000,
  int tier = 1,
  List<String> shopOffers = const [
    'PLY_MARKET_READ',
    'PLY_BRIDGE_LOAN',
    'FIN_TERM_LOAN',
  ],
  List<String> playsHeld = const [],
}) =>
    GameState(
      ventures: [venture()],
      cashCents: cashCents,
      round: 2,
      tier: tier,
      phase: PhaseId.shop,
      shopOffers: shopOffers,
      playsHeld: playsHeld,
    );

GameState actFixture({
  int cashCents = 2000000,
  int playsRemaining = 2,
  List<String> hand = const ['ADD_SW_PLUGIN', 'VEN_SVC_AGENCY'],
  List<String> shopOffers = const ['FIN_TERM_LOAN'],
  List<String> playsHeld = const [],
  List<Venture>? ventures,
  int tier = 1,
}) =>
    GameState(
      ventures: ventures ?? [venture()],
      cashCents: cashCents,
      round: 2,
      tier: tier,
      phase: PhaseId.act,
      playsRemaining: playsRemaining,
      hand: hand,
      shopOffers: shopOffers,
      playsHeld: playsHeld,
    );

bool rejected(ApplyResult r, String reason) => r.events.any((e) =>
    e.type == GameEventType.actionRejected && e.reason == reason);

void main() {
  group('buyShopOffer happy path (doc 02 §2 SHOP)', () {
    test('charges cost.cash and moves the offer into the held inventory',
        () {
      final before = shopFixture();
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(result.events, isEmpty);
      expect(result.state.cashCents, 2000000 - 100000); // the card's cost
      expect(result.state.playsHeld, ['PLY_MARKET_READ']);
      expect(result.state.shopOffers, ['PLY_BRIDGE_LOAN', 'FIN_TERM_LOAN'],
          reason: 'the bought offer left the counter');
      expect(result.state.actionLog, hasLength(1));
    });

    test('a zero-cost consumable buys for free (PLY_DOWN_ROUND face)', () {
      final before = shopFixture(shopOffers: const ['PLY_DOWN_ROUND']);
      final result = buyShopOffer(before, 'PLY_DOWN_ROUND', kContent);
      expect(result.events, isEmpty);
      expect(result.state.cashCents, before.cashCents);
      expect(result.state.playsHeld, ['PLY_DOWN_ROUND']);
    });

    test('cash exactly equal to the cost is allowed (PRE is >=)', () {
      final result = buyShopOffer(
          shopFixture(cashCents: 100000), 'PLY_MARKET_READ', kContent);
      expect(result.events, isEmpty);
      expect(result.state.cashCents, 0);
    });

    test('buying never touches playsRemaining (cash only, no PLAY)', () {
      final result =
          buyShopOffer(shopFixture(), 'PLY_MARKET_READ', kContent);
      expect(result.state.playsRemaining,
          shopFixture().playsRemaining,
          reason: 'doc 02 §2: SHOP buys cost cash only, never a PLAY');
    });
  });

  group('buyShopOffer gates (player input: rejections, never throws)', () {
    test('outside SHOP: wrong_phase, no mutation', () {
      final before = shopFixture().copyWith(phase: PhaseId.act);
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(rejected(result, 'wrong_phase'), isTrue);
      expect(result.state, before);
    });

    test('an id not on the counter: offer_not_in_shop', () {
      final before = shopFixture();
      final result = buyShopOffer(before, 'PLY_SECONDARY_SALE', kContent);
      expect(rejected(result, 'offer_not_in_shop'), isTrue);
      expect(result.state, before);
    });

    test('a FINANCING offer is not buyable-and-held: offer_not_buyable '
        '(it exercises as an action via playCard instead)', () {
      final before = shopFixture();
      final result = buyShopOffer(before, 'FIN_TERM_LOAN', kContent);
      expect(rejected(result, 'offer_not_buyable'), isTrue);
      expect(result.state, before);
    });

    test('at the held cap: plays_full (T1 cap is 2)', () {
      final before =
          shopFixture(playsHeld: const ['PLY_BRIDGE_LOAN', 'PLY_DOWN_ROUND']);
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(rejected(result, 'plays_full'), isTrue);
      expect(result.state, before);
    });

    test('one under the cap buys fine (boundary)', () {
      final before = shopFixture(playsHeld: const ['PLY_DOWN_ROUND']);
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(result.events, isEmpty);
      expect(result.state.playsHeld, hasLength(2));
    });

    test('T4 raises the cap to 3', () {
      final before = shopFixture(
          tier: 4,
          playsHeld: const ['PLY_BRIDGE_LOAN', 'PLY_DOWN_ROUND']);
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(result.events, isEmpty, reason: 'playsHeldMax(4) == 3');
      expect(result.state.playsHeld, hasLength(3));
    });

    test('insufficient cash rejects, no mutation', () {
      final before = shopFixture(cashCents: 99999);
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(rejected(result, 'insufficient_cash'), isTrue);
      expect(result.state, before);
    });

    test('the cap gate fires before the cash gate (gate order)', () {
      final before = shopFixture(
          cashCents: 0,
          playsHeld: const ['PLY_BRIDGE_LOAN', 'PLY_DOWN_ROUND']);
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(rejected(result, 'plays_full'), isTrue,
          reason: 'membership/cap precede the price check');
    });
  });

  group('playCard: ACT cards consume from the HAND', () {
    test('an addon merge plays from the hand and is consumed', () {
      final before = actFixture();
      final result = playCard(before, 'ADD_SW_PLUGIN', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(
          result.events.any((e) => e.type == GameEventType.multipleArbitrage),
          isTrue);
      expect(result.state.hand, ['VEN_SVC_AGENCY']);
      expect(result.state.cashCents, 2000000 - 900000);
      expect(result.state.playsRemaining, 1, reason: 'the merge costs 1');
    });

    test('a card NOT in the hand rejects with card_not_in_hand, even if '
        'its type is right', () {
      final before = actFixture(hand: const ['VEN_SVC_AGENCY']);
      final result = playCard(before, 'ADD_SW_PLUGIN', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(rejected(result, 'card_not_in_hand'), isTrue);
      expect(result.state, before);
    });

    test('an underlying-action rejection leaves the card IN the hand', () {
      // T1 slot is full: StartVenture rejects slots_full; the venture card
      // must stay playable.
      final before = actFixture();
      final result = playCard(before, 'VEN_SVC_AGENCY', SplitMix64Rng(1),
          kContent, targetVentureId: 'v2');
      expect(rejected(result, 'slots_full'), isTrue);
      expect(result.state, before,
          reason: 'a rejected play consumes nothing');
    });

    test('a venture card plays from the hand when a slot is open', () {
      final before = actFixture(ventures: const [], tier: 1);
      final result = playCard(before, 'VEN_SVC_AGENCY', SplitMix64Rng(1),
          kContent, targetVentureId: 'v2');
      expect(
          result.events.any((e) => e.type == GameEventType.actionRejected),
          isFalse);
      final v2 = result.state.ventures.single;
      expect(v2.id, 'v2');
      expect(v2.sector, Sector.services);
      expect(v2.ebitdaCents, 550000);
      expect(v2.ownershipBp, 10000);
      expect(result.state.hand, ['ADD_SW_PLUGIN'],
          reason: 'the played venture card left the hand');
    });
  });

  group('playCard: FINANCING exercises from the OFFERS (the documented '
      'engine decision)', () {
    test('a financing offer resolves as TakeDebt in ACT and is consumed '
        'from shopOffers', () {
      final before = actFixture();
      final result = playCard(before, 'FIN_TERM_LOAN', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(
          result.events.any((e) => e.type == GameEventType.actionRejected),
          isFalse);
      expect(result.state.cashCents, 2000000 + 1500000);
      expect(result.state.ventures.single.netDebtCents, 1500000);
      expect(result.state.shopOffers, isEmpty,
          reason: 'the exercised offer left the counter');
      expect(result.state.playsRemaining, 1,
          reason: 'TakeDebt stays a play-costing action (round-2 locked '
              'matrix; doc 04 §0\'s no-PLAY wording reconciled in '
              'apply.dart)');
    });

    test('a financing id NOT on the counter: offer_not_in_shop', () {
      final before = actFixture(shopOffers: const []);
      final result = playCard(before, 'FIN_TERM_LOAN', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(rejected(result, 'offer_not_in_shop'), isTrue);
      expect(result.state, before);
    });

    test('exercising financing in SHOP phase rejects wrong_phase (the '
        'underlying action is act-only)', () {
      final before = shopFixture();
      final result = playCard(before, 'FIN_TERM_LOAN', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(rejected(result, 'wrong_phase'), isTrue);
      expect(result.state, before);
    });
  });

  group('playCard: consumables delegate to apply\'s inventory gate', () {
    test('a held consumable plays and is consumed from playsHeld', () {
      final before = actFixture(playsHeld: const ['PLY_DOWN_ROUND']);
      final result = playCard(before, 'PLY_DOWN_ROUND', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(
          result.events.any((e) => e.type == GameEventType.actionRejected),
          isFalse);
      expect(result.state.cashCents, 2000000 + 2500000);
      expect(result.state.ventures.single.ownershipBp, 6000);
      expect(result.state.playsHeld, isEmpty);
      expect(result.state.playsRemaining, before.playsRemaining,
          reason: 'PLAY_CONSUMABLE is throughput-free (doc 02 §3 matrix)');
    });

    test('an unheld consumable rejects play_not_held (apply\'s gate)', () {
      final before = actFixture(playsHeld: const []);
      final result = playCard(before, 'PLY_DOWN_ROUND', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(rejected(result, 'play_not_held'), isTrue);
      expect(result.state, before);
    });
  });

  group('playCard refusals are caller bugs, not rejections', () {
    // (The partner UnsupportedError RETIRED at the PartnerEngine layer:
    // partner cards are ACT hand cards now — an out-of-hand partner play
    // REJECTS card_not_in_hand like any hand card; see
    // action_hire_partner_test.dart.)
    test('a partner card out of hand rejects card_not_in_hand', () {
      final before = actFixture();
      final result = playCard(before, 'PRT_SALES_LEAD', SplitMix64Rng(1),
          kContent, targetVentureId: 'v1');
      expect(rejected(result, 'card_not_in_hand'), isTrue);
      expect(result.state, before);
    });

    test('an event card throws (never player-played)', () {
      expect(
          () => playCard(actFixture(), 'EVT_SECTOR_BUBBLE', SplitMix64Rng(1),
              kContent),
          throwsArgumentError);
    });

    test('an unknown id throws (content drift fails loudly)', () {
      expect(
          () => playCard(actFixture(), 'GHOST_CARD', SplitMix64Rng(1),
              kContent),
          throwsArgumentError);
    });
  });
}
