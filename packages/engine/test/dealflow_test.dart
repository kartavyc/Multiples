// The deal-flow library (doc 03 §3.1 step 1; doc 02 §1 hand/shopOffers;
// doc 04 §0 type semantics) — pools, the hand/shop draw routines, event-card
// application, the card->action glue, playsHeldMax.
//
// Covers, one behavior per test:
//   - pool membership + ORDER (slice order is the replay contract):
//     handPool = slice ventures+addons+partners gated by tier (the v5
//     contract: partners re-included, ventures dead-draw-filtered at full
//     slots); shopPool = slice financing+consumables; eventPool = events
//   - drawHand: one nextInt(3) size draw (3-5), then size draws WITHOUT
//     replacement over the shrinking pool (twin-probed id-by-id); hand
//     REPLACED wholesale; cursor reconciled; size clamps to pool
//   - drawShop: exactly kShopOfferCount draws, same shrinking-pool routine
//   - applyEventCard: sector-matched events hit every venture OF THAT
//     SECTOR; sector-null events hit EVERY venture; cash deltas land once,
//     globally; per-venture results clamp per resolverInputs.clamps;
//     ventures of other sectors untouched; counters untouched
//   - actionForCard: exact payload pins for every slice card (and the
//     non-slice financing shapes), the addon implied-multiple derivation,
//     the consumable purchase-mirror strip, partner/event refusals
//   - playsHeldMax: 2/2/2/3/3
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/content.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

GameState state({
  int tier = 1,
  List<String> hand = const [],
  List<String> shopOffers = const [],
}) =>
    GameState(
      ventures: const [],
      cashCents: 0,
      tier: tier,
      hand: hand,
      shopOffers: shopOffers,
    );

List<String> ids(List<Card> cards) => [for (final c in cards) c.id];

void main() {
  // -------------------------------------------------------------------------
  // Pools (slice order = the replay contract)
  // -------------------------------------------------------------------------
  group('handPool (the v5 pool contract: ventures + addons + partners, '
      'tier-gated, dead-draw-filtered)', () {
    test('T1 pool (slots open) is the 4 starter ventures + the 2 gate-1 '
        'addons + the gate-1 partner, in slice order', () {
      expect(ids(handPool(kContent, 1, slotsFull: false)), [
        'VEN_SW_GARAGE',
        'VEN_SVC_AGENCY',
        'VEN_RET_KIOSK',
        'VEN_IND_WORKSHOP',
        'ADD_SW_PLUGIN',
        'ADD_SW_MICRO',
        'PRT_SALES_LEAD',
      ]);
    });

    test('T2 admits the gate-2 cross-sector addon (and nothing else)', () {
      expect(ids(handPool(kContent, 2, slotsFull: false)), [
        'VEN_SW_GARAGE',
        'VEN_SVC_AGENCY',
        'VEN_RET_KIOSK',
        'VEN_IND_WORKSHOP',
        'ADD_SW_PLUGIN',
        'ADD_SW_MICRO',
        'ADD_SVC_TEAM',
        'PRT_SALES_LEAD',
      ]);
    });

    test('THE DEAD-DRAW FILTER (v5): slotsFull excludes every venture-type '
        'card, keeping addons + partners, order preserved', () {
      expect(ids(handPool(kContent, 1, slotsFull: true)), [
        'ADD_SW_PLUGIN',
        'ADD_SW_MICRO',
        'PRT_SALES_LEAD',
      ]);
      expect(ids(handPool(kContent, 5, slotsFull: true)),
          isNot(anyElement(startsWith('VEN_'))));
    });

    test('PARTNER cards are INCLUDED at every tier since v5 (the round-4 '
        'exclusion closed with the PartnerEngine layer)', () {
      for (var tier = 1; tier <= 5; tier++) {
        expect(ids(handPool(kContent, tier, slotsFull: false)),
            contains('PRT_SALES_LEAD'),
            reason: 'tier $tier');
      }
    });

    test('only slice cards qualify (the full-DB pool is post-slice)', () {
      expect(ids(handPool(kContent, 5, slotsFull: false)),
          isNot(contains('VEN_SW_PLATFORM')),
          reason: 'VEN_SW_PLATFORM is held out of the vertical slice');
    });
  });

  group('shopPool (slice SHOP counter: financing + consumables)', () {
    test('T1 pool in slice order (gate-2 offers held back)', () {
      expect(ids(shopPool(kContent, 1)), [
        'FIN_TERM_LOAN',
        'PLY_BRIDGE_LOAN',
        'PLY_SECONDARY_SALE',
        'PLY_DOWN_ROUND',
        'PLY_MARKET_READ',
      ]);
    });

    test('T2 admits the raise and the gate-2 plays', () {
      expect(ids(shopPool(kContent, 2)), [
        'FIN_SEED_RAISE',
        'FIN_TERM_LOAN',
        'PLY_BRIDGE_LOAN',
        'PLY_SECONDARY_SALE',
        'PLY_DOWN_ROUND',
        'PLY_DIVIDEND_RECAP',
        'PLY_HOT_WINDOW',
        'PLY_MARKET_READ',
      ]);
    });
  });

  group('eventPool (slice events, auto-resolved in OPERATE)', () {
    test('all three slice events qualify from T1, in slice order', () {
      expect(ids(eventPool(kContent, 1)), [
        'EVT_SECTOR_BUBBLE',
        'EVT_CREDIT_CRUNCH',
        'EVT_KEY_CLIENT_LOSS',
      ]);
    });
  });

  // -------------------------------------------------------------------------
  // drawHand (the contract: 1 size draw + size card draws, no replacement)
  // -------------------------------------------------------------------------
  group('drawHand (dealflow.dart header contract)', () {
    test('hand size is 3 + nextInt(3), i.e. 3..5 across seeds', () {
      final seen = <int>{};
      for (var seed = 0; seed < 40; seed++) {
        final after = drawHand(state(), SplitMix64Rng(seed), kContent);
        expect(after.hand.length, inInclusiveRange(3, 5), reason: 'seed $seed');
        seen.add(after.hand.length);
      }
      expect(seen, {3, 4, 5},
          reason: 'the 40-seed sweep should realize every legal size');
    });

    test('the id sequence IS the shrinking-pool draw (twin probe)', () {
      final pool = handPool(kContent, 1, slotsFull: false);
      final probe = SplitMix64Rng(7);
      var size = kHandSizeMin + probe.nextInt(kHandSizeSpan);
      if (size > pool.length) size = pool.length;
      final remaining = [...pool];
      final expected = <String>[
        for (var i = 0; i < size; i++)
          remaining.removeAt(probe.nextInt(remaining.length)).id,
      ];

      final rng = SplitMix64Rng(7);
      final after = drawHand(state(), rng, kContent);
      expect(after.hand, expected,
          reason: 'each card draw indexes the REMAINING pool in slice '
              'order — without replacement');
      expect(rng.cursor, 1 + size, reason: '1 size draw + size card draws');
      expect(after.rngCursor, 1 + size,
          reason: 'the state mirror reconciles to the stream');
    });

    test('never deals a duplicate and only deals from the pool', () {
      for (var seed = 0; seed < 40; seed++) {
        final after = drawHand(state(), SplitMix64Rng(seed), kContent);
        expect(after.hand.toSet().length, after.hand.length,
            reason: 'seed $seed dealt a duplicate');
        final poolIds = ids(handPool(kContent, 1, slotsFull: false)).toSet();
        for (final id in after.hand) {
          expect(poolIds, contains(id), reason: 'seed $seed dealt off-pool');
        }
      }
    });

    test('REPLACES the previous hand wholesale (unplayed cards expire)', () {
      final stale = state(hand: const ['VEN_SW_GARAGE', 'GHOST']);
      final after = drawHand(stale, SplitMix64Rng(3), kContent);
      expect(after.hand, isNot(contains('GHOST')));
      expect(after.hand.length, inInclusiveRange(3, 5));
    });

    test('a size draw above the pool size clamps to the pool (tiny '
        'synthetic content)', () {
      // Two-card pool: every draw must clamp the 3..5 size down to 2.
      final tiny = loadCards('''
[
  {"id": "T_V1", "name": "v", "type": "venture", "sector": "SOFTWARE",
   "rarity": "common", "tierGate": 1,
   "cost": {"cash": 100, "debt": 0, "dilution": 0},
   "deltas": {"cash": -100, "ebitda": 10, "multiple": 14000, "own": 10000},
   "lesson": "l", "flavor": "f", "inVerticalSlice": true},
  {"id": "T_A1", "name": "a", "type": "addon", "sector": "SOFTWARE",
   "rarity": "common", "tierGate": 1,
   "cost": {"cash": 100, "debt": 0, "dilution": 0},
   "deltas": {"cash": -100, "ebitda": 10},
   "lesson": "l", "flavor": "f", "inVerticalSlice": true}
]
''');
      // The synthetic ids must be in the run's frozen unlocked set (v10:
      // the pool is `content.cards ∩ run.unlockedCardIds`), so unlock them.
      final tinyState = GameState(
        ventures: const [],
        cashCents: 0,
        tier: 1,
        unlockedCardIds: const ['T_V1', 'T_A1'],
      );
      for (var seed = 0; seed < 10; seed++) {
        final rng = SplitMix64Rng(seed);
        final after = drawHand(tinyState, rng, tiny);
        expect(after.hand.toSet(), {'T_V1', 'T_A1'}, reason: 'seed $seed');
        expect(rng.cursor, 1 + 2,
            reason: 'the size draw always happens; card draws clamp');
      }
    });

    test('everything else on the state is untouched', () {
      final before = state(shopOffers: const ['FIN_TERM_LOAN']);
      final after = drawHand(before, SplitMix64Rng(5), kContent);
      expect(after.shopOffers, before.shopOffers);
      expect(after.ventures, before.ventures);
      expect(after.cashCents, before.cashCents);
      expect(after.phase, before.phase);
      expect(after.actionLog, before.actionLog);
    });
  });

  // -------------------------------------------------------------------------
  // drawShop
  // -------------------------------------------------------------------------
  group('drawShop (dealflow.dart header contract)', () {
    test('deals exactly kShopOfferCount offers via the shrinking-pool draw '
        '(twin probe)', () {
      final pool = shopPool(kContent, 1);
      final probe = SplitMix64Rng(11);
      final remaining = [...pool];
      final expected = <String>[
        for (var i = 0; i < kShopOfferCount; i++)
          remaining.removeAt(probe.nextInt(remaining.length)).id,
      ];

      final rng = SplitMix64Rng(11);
      final after = drawShop(state(), rng, kContent);
      expect(after.shopOffers, expected);
      expect(after.shopOffers.length, kShopOfferCount);
      expect(rng.cursor, kShopOfferCount,
          reason: 'NO size draw — the offer count is fixed');
      expect(after.rngCursor, kShopOfferCount);
    });

    test('never deals a duplicate; only financing/consumables; REPLACES '
        'wholesale', () {
      for (var seed = 0; seed < 40; seed++) {
        final after = drawShop(
            state(shopOffers: const ['GHOST']), SplitMix64Rng(seed), kContent);
        expect(after.shopOffers.toSet().length, after.shopOffers.length,
            reason: 'seed $seed dealt a duplicate');
        expect(after.shopOffers, isNot(contains('GHOST')));
        for (final id in after.shopOffers) {
          final card = kContent.byId(id);
          expect(
              card.type == CardType.financing ||
                  card.type == CardType.consumable,
              isTrue,
              reason: 'seed $seed dealt a ${card.type.name} into SHOP');
        }
      }
    });

    test('tier gating: T1 never offers the gate-2 raise', () {
      for (var seed = 0; seed < 40; seed++) {
        final after = drawShop(state(tier: 1), SplitMix64Rng(seed), kContent);
        expect(after.shopOffers, isNot(contains('FIN_SEED_RAISE')),
            reason: 'seed $seed');
      }
    });
  });

  // -------------------------------------------------------------------------
  // applyEventCard (OPERATE step 5's delta application)
  // -------------------------------------------------------------------------
  group('applyEventCard (doc 01 §6.1 step 5; doc 04 events)', () {
    Venture sw({int multiple = 8000, int ebitda = 600000}) => Venture(
        id: 'sw',
        sector: Sector.software,
        ebitdaCents: ebitda,
        multipleMilli: multiple,
        netDebtCents: 0,
        ownershipBp: 10000,
        roundsNeglected: 2);
    Venture svc() => const Venture(
        id: 'svc',
        sector: Sector.services,
        ebitdaCents: 400000,
        multipleMilli: 5000,
        netDebtCents: 0,
        ownershipBp: 10000);

    test('a sector event hits EVERY venture of that sector and no other', () {
      final bubble = kContent.byId('EVT_SECTOR_BUBBLE'); // SOFTWARE +4200
      final out = applyEventCard(
          ventures: [sw(), svc(), sw().copyWith(id: 'sw2', multipleMilli: 9000)],
          cashCents: 1000,
          card: bubble);
      expect(out.ventures[0].multipleMilli, 12200);
      expect(out.ventures[1].multipleMilli, 5000,
          reason: 'SERVICES is untouched by a SOFTWARE shock');
      expect(out.ventures[2].multipleMilli, 13200);
      expect(out.cashCents, 1000, reason: 'no cash delta on this card');
    });

    test('a sector-NULL event is market-wide: every venture is hit', () {
      final crunch = kContent.byId('EVT_CREDIT_CRUNCH'); // null, -2800
      final out = applyEventCard(
          ventures: [sw(), svc()], cashCents: 0, card: crunch);
      expect(out.ventures[0].multipleMilli, 5200);
      expect(out.ventures[1].multipleMilli, 2200);
    });

    test('an ebitda event clamps at the 0 floor', () {
      final loss = kContent.byId('EVT_KEY_CLIENT_LOSS'); // SERVICES -250000
      final out = applyEventCard(
          ventures: [svc().copyWith(ebitdaCents: 100000)],
          cashCents: 0,
          card: loss);
      expect(out.ventures.single.ebitdaCents, 0,
          reason: 'resolverInputs.clamps: ebitda >= 0');
    });

    test('a multiple event clamps at the 1000-milli live-venture floor', () {
      final crunch = kContent.byId('EVT_CREDIT_CRUNCH');
      final out = applyEventCard(
          ventures: [sw(multiple: 2000)], cashCents: 0, card: crunch);
      expect(out.ventures.single.multipleMilli, 1000);
    });

    test('cash deltas land ONCE, globally, regardless of venture count '
        '(synthetic +cash event)', () {
      final viral = loadCards('''
[
  {"id": "T_EVT", "name": "e", "type": "event", "sector": null,
   "rarity": "common", "tierGate": 1,
   "cost": {"cash": 0, "debt": 0, "dilution": 0},
   "deltas": {"cash": 600000, "ebitda": 100000},
   "lesson": "l", "flavor": "f", "inVerticalSlice": true}
]
''').byId('T_EVT');
      final out = applyEventCard(
          ventures: [sw(), svc()], cashCents: 1000, card: viral);
      expect(out.cashCents, 601000,
          reason: 'cash is the GLOBAL input — never multiplied per venture');
      expect(out.ventures[0].ebitdaCents, 700000);
      expect(out.ventures[1].ebitdaCents, 500000);
    });

    test('no matching venture: the event still resolves (cash only)', () {
      final loss = kContent.byId('EVT_KEY_CLIENT_LOSS'); // SERVICES
      final out =
          applyEventCard(ventures: [sw()], cashCents: 500, card: loss);
      expect(out.ventures.single, sw(), reason: 'no SERVICES venture to hit');
      expect(out.cashCents, 500);
    });

    test('events never touch the neglect counter (not a targeting Act)', () {
      final bubble = kContent.byId('EVT_SECTOR_BUBBLE');
      final out =
          applyEventCard(ventures: [sw()], cashCents: 0, card: bubble);
      expect(out.ventures.single.roundsNeglected, 2);
    });
  });

  // -------------------------------------------------------------------------
  // actionForCard (the glue)
  // -------------------------------------------------------------------------
  group('actionForCard: venture -> StartVenture', () {
    test('maps faces exactly (VEN_SW_GARAGE)', () {
      final action = actionForCard(kContent.byId('VEN_SW_GARAGE'),
          targetVentureId: 'v9');
      expect(
          action,
          const StartVenture(
            ventureId: 'v9',
            sector: Sector.software,
            ebitdaCents: 400000,
            multipleMilli: 14000,
            priceCents: 1200000, // cost.cash (mirrors -deltas.cash)
            faceDebtCents: 0,
          ));
    });

    test('requires the new venture id', () {
      expect(() => actionForCard(kContent.byId('VEN_SW_GARAGE')),
          throwsArgumentError);
    });
  });

  group('actionForCard: addon -> AcquireAddOn (implied buy multiple)', () {
    test('derives m_buy = trunc(price * 1000 / ebitda) — exact for '
        'ADD_SW_PLUGIN (3.0x)', () {
      final action = actionForCard(kContent.byId('ADD_SW_PLUGIN'),
          targetVentureId: 'plat');
      expect(
          action,
          const AcquireAddOn(
            targetVentureId: 'plat',
            addonSector: Sector.software,
            addonEbitdaCents: 300000,
            addonBuyMultipleMilli: 3000, // 900000*1000/300000
            addonFaceDebtCents: 0,
          ));
    });

    test('ADD_SW_MICRO derives 2777 (trunc), so the resolver recomputes a '
        'price 140 cents under the face — the documented truncation '
        'consequence', () {
      final action = actionForCard(kContent.byId('ADD_SW_MICRO'),
          targetVentureId: 'plat') as AcquireAddOn;
      expect(action.addonBuyMultipleMilli, 2777); // 500000*1000 ~/ 180000
      // The engine's addonPrice (economy formulas.addonPrice) will charge
      // trunc(180000 * 2777 / 1000) = 499860, not the 500000 face. The
      // implied multiple is the only multiple the v1 card schema carries;
      // the sub-dollar truncation goes to the player.
      expect((action.addonEbitdaCents * action.addonBuyMultipleMilli) ~/ 1000,
          499860);
    });

    test('ADD_SVC_TEAM: cross-sector faces map (m_buy 2.0x; the card\'s '
        'illustrative -640 drag is IGNORED — the resolver computes the '
        'real x0.92 live drag, doc 03 §4.2 / doc 04 §4)', () {
      final action = actionForCard(kContent.byId('ADD_SVC_TEAM'),
          targetVentureId: 'plat');
      expect(
          action,
          const AcquireAddOn(
            targetVentureId: 'plat',
            addonSector: Sector.services,
            addonEbitdaCents: 350000,
            addonBuyMultipleMilli: 2000, // 700000*1000/350000
            addonFaceDebtCents: 0,
          ));
    });

    test('requires the platform id', () {
      expect(() => actionForCard(kContent.byId('ADD_SW_PLUGIN')),
          throwsArgumentError);
    });
  });

  group('actionForCard: financing dispatch by SHAPE (dilution face = raise; '
      'else debt instrument)', () {
    test('FIN_SEED_RAISE -> RaiseEquity WITH its growth riders (live since '
        'round 10)', () {
      final action = actionForCard(kContent.byId('FIN_SEED_RAISE'),
          targetVentureId: 'v1');
      expect(
          action,
          const RaiseEquity(
            ventureId: 'v1',
            raiseCents: 3000000,
            ebitdaDeltaCents: 200000,
            multipleDeltaMilli: 1000,
          ));
    });

    test('FIN_GROWTH_RAISE -> RaiseEquity 8M with its riders', () {
      expect(
          actionForCard(kContent.byId('FIN_GROWTH_RAISE'),
              targetVentureId: 'v1'),
          const RaiseEquity(
            ventureId: 'v1',
            raiseCents: 8000000,
            ebitdaDeltaCents: 500000,
            multipleDeltaMilli: 2000,
          ));
    });

    test('FIN_TERM_LOAN -> TakeDebt (proceeds = deltas.cash, face = '
        'deltas.netDebt)', () {
      expect(
          actionForCard(kContent.byId('FIN_TERM_LOAN'), targetVentureId: 'v1'),
          const TakeDebt(
              ventureId: 'v1',
              proceedsCents: 1500000,
              faceDebtCents: 1500000));
    });

    test('FIN_LBO_LOAN -> TakeDebt 20M/20M', () {
      expect(
          actionForCard(kContent.byId('FIN_LBO_LOAN'), targetVentureId: 'v1'),
          const TakeDebt(
              ventureId: 'v1',
              proceedsCents: 20000000,
              faceDebtCents: 20000000));
    });

    test('FIN_REFI -> TakeDebt with NEGATIVE payloads: pay the fee, retire '
        'the debt', () {
      expect(
          actionForCard(kContent.byId('FIN_REFI'), targetVentureId: 'v1'),
          const TakeDebt(
              ventureId: 'v1',
              proceedsCents: -300000,
              faceDebtCents: -2500000));
    });

    test('requires the target venture id', () {
      expect(() => actionForCard(kContent.byId('FIN_TERM_LOAN')),
          throwsArgumentError);
    });
  });

  group('actionForCard: consumable -> PlayConsumable (purchase-mirror '
      'strip)', () {
    test('PLY_BRIDGE_LOAN keeps its play-time deltas (the +1M is proceeds, '
        'not a mirror)', () {
      final action = actionForCard(kContent.byId('PLY_BRIDGE_LOAN'),
          targetVentureId: 'v1');
      expect(
          action,
          PlayConsumable(
            playId: 'PLY_BRIDGE_LOAN',
            targetVentureId: 'v1',
            deltas: const {'cash': 1000000, 'netDebt': 1150000},
          ));
    });

    test('PLY_HOT_WINDOW strips the purchase mirror: the -500k was paid at '
        'the SHOP counter; playing must not charge it twice', () {
      final action = actionForCard(kContent.byId('PLY_HOT_WINDOW'))
          as PlayConsumable;
      expect(action.deltas, isEmpty,
          reason: 'v1 models HOT_WINDOW as a pure cost — the market-flag '
              'arming is future work (dealflow.dart documents the cut)');
    });

    test('PLY_MARKET_READ strips the purchase mirror too', () {
      final action = actionForCard(kContent.byId('PLY_MARKET_READ'))
          as PlayConsumable;
      expect(action.deltas, isEmpty);
    });

    test('PLY_DOWN_ROUND keeps everything (zero cost: nothing to mirror)',
        () {
      final action = actionForCard(kContent.byId('PLY_DOWN_ROUND'),
          targetVentureId: 'v1') as PlayConsumable;
      expect(action.deltas, {'cash': 2500000, 'own': -4000});
    });

    test('PLY_SECONDARY_SALE strips its illustrative faces and routes the '
        'ownership magnitude to secondaryBp (schemaVersion 9; the live-mark '
        'proceeds are computed at resolve time, doc 02 §3.6)', () {
      final action = actionForCard(kContent.byId('PLY_SECONDARY_SALE'),
          targetVentureId: 'v1') as PlayConsumable;
      // The $0 proceeds placeholder + the own face are stripped; the slice
      // to sell (1000 bp magnitude) rides secondaryBp instead.
      expect(action.deltas, isEmpty,
          reason: 'cash:0 + own:-1000 are placeholders, stripped like the '
              'recap faces');
      expect(action.secondaryBp, 1000,
          reason: 'the |own| magnitude becomes the bp to sell at the mark');
      expect(action.recapBp, 0);
      expect(action.targetVentureId, 'v1');
    });

    test('a context-free consumable needs no target', () {
      final action = actionForCard(kContent.byId('PLY_DIVIDEND_RECAP'));
      expect(action, isA<PlayConsumable>());
      expect((action as PlayConsumable).targetVentureId, isNull);
    });
  });

  group('actionForCard: refusals', () {
    // (The old partner UnsupportedError refusal RETIRED at the
    // PartnerEngine layer: partner cards now map onto HirePartner —
    // covered in action_hire_partner_test.dart.)
    test('event cards are never player-played (auto-resolve in OPERATE)',
        () {
      expect(() => actionForCard(kContent.byId('EVT_SECTOR_BUBBLE')),
          throwsArgumentError);
    });
  });

  // -------------------------------------------------------------------------
  // Partner FIXED-COST face (audit L3 decision: stays OUT of the v1 slice;
  // the HirePartner.fixedCostCents channel is live + tested separately)
  // -------------------------------------------------------------------------
  group('partner fixed-cost face (PRT_COO_FIXED — documented out-of-slice)',
      () {
    test('PRT_COO_FIXED exists in content but is NOT in the v1 vertical '
        'slice', () {
      final coo = kContent.byId('PRT_COO_FIXED');
      expect(coo.type, CardType.partner);
      expect(coo.inVerticalSlice, isFalse,
          reason: 'the COO-with-a-recurring-salary card is deferred — the '
              'v1 card SCHEMA has no fixed-cost-per-round face to carry its '
              'salary, so it stays out of the slice rather than half-adding '
              'it (audit L3 decision)');
    });

    test('the glue maps a partner card with no fixed-cost face to '
        'fixedCostCents 0 (the channel is live, the v1 face is not)', () {
      // Map the reachable in-slice partner: it carries no recurring salary,
      // so the HirePartner fixedCostCents is 0. The channel ITSELF (a
      // non-zero fixedCostCents registering a recurring ScheduledCost) is
      // proven end-to-end in action_hire_partner_test.dart — so it is not
      // half-added: it is fully wired and merely unused by v1 content.
      final action = actionForCard(kContent.byId('PRT_SALES_LEAD'),
          targetVentureId: 'v1') as HirePartner;
      expect(action.fixedCostCents, 0,
          reason: 'no v1 partner card carries a fixed-cost face yet');
    });
  });

  // -------------------------------------------------------------------------
  // playsHeldMax (doc 02 §3: {1:2, 2:2, 3:2, 4:3, 5:3})
  // -------------------------------------------------------------------------
  group('playsHeldMax (doc 02 §3 PLAYS/SLOTS table)', () {
    test('caps held plays at 2/2/2/3/3 across tiers 1..5', () {
      expect(playsHeldMax(1), 2);
      expect(playsHeldMax(2), 2);
      expect(playsHeldMax(3), 2);
      expect(playsHeldMax(4), 3);
      expect(playsHeldMax(5), 3);
    });

    test('throws on a tier outside 1..5', () {
      expect(() => playsHeldMax(0), throwsArgumentError);
      expect(() => playsHeldMax(6), throwsArgumentError);
    });
  });

  // -------------------------------------------------------------------------
  // The tuning dials are pinned where they live
  // -------------------------------------------------------------------------
  group('tuning dials (loud constants, not canon)', () {
    test('hand size draw shape: 3 + nextInt(3)', () {
      expect(kHandSizeMin, 3);
      expect(kHandSizeSpan, 3);
    });

    test('shop offer count: 3', () {
      expect(kShopOfferCount, 3);
    });

    test('event chance: 25 of 100', () {
      expect(kEventChancePct, 25);
    });
  });
}
