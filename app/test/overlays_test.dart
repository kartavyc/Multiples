// Round-8 overlay/juice tests (plan 3.4-3.6): the S4 napkin's
// engine-derived preview, the S6 arbitrage flash (headline == the
// MULTIPLE_ARBITRAGE event amount), the NW surge trigger + settle, the S2
// digest rows vs the OperateResult, the S8 autopsy on a forced-bankruptcy
// fixture driven through the real controller, and the S0 title -> run
// flow.
//
// Same harness as run_screen_test: dart:io JSON injection, fixed seed 2
// (stream facts in that file's header), explicit pump(Duration)s for every
// beat (all R8 juice runs off AnimationControllers — no real timers), and
// no pumpAndSettle (the terminal idles forever by design).

import 'dart:io';

import 'package:engine/apply.dart' show GameEventType;
import 'package:engine/content.dart' show CardType;
import 'package:engine/model.dart';
import 'package:engine/money.dart';
import 'package:engine/operate.dart' show cashYieldCents, organicGrowthCents;
import 'package:engine/resolver.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/controller.dart';
import 'package:multiples_app/main.dart';
import 'package:multiples_app/screens/run_screen.dart';
import 'package:multiples_app/widgets/surge.dart';

const int kTestSeed = 2;

void main() {
  final cardsJson = File('assets/data/cards.json').readAsStringSync();
  final economyJson =
      File('assets/data/economy-model.json').readAsStringSync();

  GameController newController() => GameController(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kTestSeed,
      );

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MultiplesApp(
      cardsJson: cardsJson,
      economyJson: economyJson,
      seed: kTestSeed,
    ));
    await tester.tap(find.byKey(const Key('newRun')));
    await tester.pump();
  }

  Future<void> dismissDigest(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pump();
  }

  group('S0 title -> run flow', () {
    testWidgets('wordmark + tagline + NEW RUN starts the run',
        (tester) async {
      await tester.pumpWidget(MultiplesApp(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kTestSeed,
      ));

      expect(find.byKey(const Key('wordmark')), findsOneWidget);
      expect(
        find.text("get in. get rich. get out. Wait, that's allowed?!"),
        findsOneWidget,
      );
      expect(find.text('NO ACCOUNT · OFFLINE · SAVED ON DEVICE'),
          findsOneWidget);
      expect(find.byKey(const Key('newRun')), findsOneWidget);
      // The run has not started: no digest yet.
      expect(find.text('THE YEAR PASSED'), findsNothing);

      await tester.tap(find.byKey(const Key('newRun')));
      await tester.pump();

      // The run screen mounted and auto-ran the first OPERATE.
      expect(find.text('THE YEAR PASSED'), findsOneWidget);
    });
  });

  group('S2 digest (rows == the OperateResult)', () {
    testWidgets('seed-2 round 1: yield, zero interest, net line, runway',
        (tester) async {
      await pumpApp(tester);

      // OPERATIONS: the engine's exact step-3 yield on the seed venture's
      // organically grown base (600000 + organicGrowthCents, the founding
      // operator's 20% — doc 01 §3.2 at the R12-tuned 0.20) —
      // cross-checked against the pure helpers.
      final grownBase = 600000 + organicGrowthCents(600000, passive: false);
      final expectedYield = cashYieldCents(grownBase, passive: false);
      expect(expectedYield, 252000); // 35% of $7,200
      expect(textOf(tester, 'digestOperations'),
          '+${formatMoney(expectedYield)} CASH');

      // INTEREST: debt-free round — the row restates the zero.
      expect(textOf(tester, 'digestInterest'), '−\$0 CASH');

      // Em-dash placeholder rows render for the empty digest lines
      // (v5 stream note: seed-2 round 1 fires EVT_KEY_CLIENT_LOSS, which
      // touches no SOFTWARE venture and no cash — the money rows above
      // are event-proof).
      expect(find.text('—'), findsWidgets);

      // NET line = post − pre cash (yield only this round).
      expect(textOf(tester, 'digestNet'), '+${formatMoney(expectedYield)}');

      // RUNWAY restated in words (telegraph #1).
      expect(textOf(tester, 'digestRunway'), '〔 RUNWAY OK NEXT ROUND 〕');
    });

    test('digest data mirrors the engine events (programmatic)', () {
      final c = newController();
      c.beginRound();
      final d = c.yearDigest!;
      var interestFromEvents = 0;
      for (final e in c.lastOperateEvents) {
        if (e.type == GameEventType.interestCharged) {
          interestFromEvents = e.amount;
        }
      }
      expect(d.interestCents, interestFromEvents);
      expect(d.decay, isEmpty); // round 1: nothing neglected yet
      // Under the v5 stream, seed-2 round 1 FIRES the client-loss event.
      // It hits SERVICES ventures only — the SOFTWARE seed venture and
      // the cash rows are untouched, so the digest still reconciles.
      expect(d.eventCardId, 'EVT_KEY_CLIENT_LOSS');
      expect(d.netCashCents, d.operationsCents - d.interestCents);
    });
  });

  group('S4 napkin (engine-derived preview, same-sector addon)', () {
    testWidgets('stage 1 face -> INSPECT -> stage 2 napkin rows',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);

      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump(); // napkin mounts; the rise starts
      await tester.pump(const Duration(milliseconds: 300)); // rise done

      // STAGE 1 — raw inputs only (§Q3): face EBITDA, implied buy
      // multiple, price; INSPECT key present. (Row labels render with
      // the terminal's `> ` prompt prefix; finds are scoped to the
      // napkin panel — the blotter beneath shows the same faces.)
      final napkin = find.byKey(const Key('napkin'));
      Finder inNapkin(String text) =>
          find.descendant(of: napkin, matching: find.text(text));
      expect(inNapkin('> EBITDA ON OFFER'), findsOneWidget);
      expect(inNapkin(r'$3,000'), findsOneWidget);
      expect(inNapkin('3.0x'), findsOneWidget); // m_buy = 9000/3000
      expect(inNapkin(r'$9,000'), findsOneWidget);
      // No post-deal math on the face.
      expect(inNapkin('> SYNERGY'), findsNothing);

      await tester.tap(find.byKey(const Key('inspect')));
      await tester.pump();

      // STAGE 2 — the napkin: every value the engine's.
      expect(find.text(r'−$9,000'), findsOneWidget); // resolver addonPrice
      expect(find.text(r'+$3,000'), findsOneWidget); // face EBITDA
      expect(find.text('SOFTWARE ✓ SAME'), findsOneWidget); // sector match
      expect(find.text(r'+$600'), findsOneWidget); // +20% synergy
      expect(
        find.descendant(
            of: napkin, matching: find.textContaining('HELD')),
        findsOneWidget, // multiple holds (same-sector)
      );
      expect(find.text('// same sector: synergy fires, multiple holds'),
          findsOneWidget);
      expect(find.byKey(const Key('execute')), findsOneWidget);
      expect(find.byKey(const Key('back')), findsOneWidget);
    });

    test('preview values == engine pure helpers (programmatic)', () {
      final c = newController();
      c.beginRound();
      final p = c.platform!;
      final prev = c.addonPreview('ADD_SW_PLUGIN');

      // PAY = the resolver's addonPrice off the implied m_buy.
      expect(prev.payCents,
          enterpriseValue(prev.addonEbitdaCents, prev.buyMultipleMilli));
      // SYNERGY = absorbSameSector minus the raw parts.
      expect(
        prev.synergyCents,
        absorbSameSector(
              platformEbitda: p.ebitdaCents,
              addonEbitda: prev.addonEbitdaCents,
            ) -
            p.ebitdaCents -
            prev.addonEbitdaCents,
      );
      expect(prev.sameSector, isTrue);
      expect(prev.multToMilli, prev.multFromMilli); // held
      expect(prev.multFromMilli, p.multipleMilli);
    });
  });

  group('S6 arbitrage flash + the NW surge', () {
    testWidgets('flash fires on MULTIPLE_ARBITRAGE; headline == event '
        'amount; surge follows BOOK IT', (tester) async {
      // Twin programmatic controller (same seed): learn the event's
      // render-only accretion first.
      final twin = newController();
      twin.beginRound();
      twin.dismissDigest();
      final events = twin.playBlotterCard('ADD_SW_PLUGIN');
      final accretion = events
          .firstWhere((e) => e.type == GameEventType.multipleArbitrage)
          .amount;
      final nwAfter = twin.state.netWorthCents;

      await pumpApp(tester);
      await dismissDigest(tester);
      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump(); // napkin mounts
      await tester.pump(const Duration(milliseconds: 300)); // rise done
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();

      // The takeover: banner, staged count-ups, the headline pop.
      expect(find.textContaining('MULTIPLE\nARBITRAGE'), findsOneWidget);
      expect(textOf(tester, 'arbHeadline'), '+${formatMoney(accretion)}');
      await tester.pump(const Duration(milliseconds: 400)); // EBITDA stage
      await tester.pump(const Duration(milliseconds: 800)); // EV stage
      await tester.pump(const Duration(milliseconds: 1500)); // pop+sparks

      // The count-ups landed on the engine's post-merge values
      // (CountUpText renders a Text descendant).
      expect(
        find.descendant(
          of: find.byKey(const Key('arbEbitda')),
          // The $7,200 organically grown base (R12 organic 0.20) + the
          // $3,600 merge.
          matching: find.text(formatMoney(1080000)),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('bookIt')));
      await tester.pump(); // surge beat starts
      await tester.pump(const Duration(milliseconds: 100));

      // THE SIGNATURE: deferred surge released — green box counting,
      // screen tint up.
      expect(find.byKey(const Key('nwSurgeValue')), findsOneWidget);
      expect(find.byKey(const Key('nwSurgeTint')), findsOneWidget);

      // ~900ms count-up inside a ~1700ms beat, then settle to ghost.
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.byKey(const Key('nwSurgeValue')), findsNothing);
      expect(find.byKey(const Key('nwSurgeTint')), findsNothing);
      expect(textOf(tester, 'netWorth'), formatMoney(nwAfter));
    });

    test('surge controller: fires on rises only; defers across a flash',
        () {
      final s = SurgeController();
      expect(s.active, isFalse);
      s.fire(100, 90); // a drop never surges
      expect(s.active, isFalse);
      s.defer(100, 200);
      expect(s.active, isFalse); // held for BOOK IT
      s.fireDeferred();
      expect(s.active, isTrue);
      expect(s.fromCents, 100);
      expect(s.toCents, 200);
      s.settle();
      expect(s.active, isFalse);
    });
  });

  group('S8 autopsy (forced bankruptcy through the real controller)', () {
    testWidgets('GREED copy + the fatal interest-vs-cash numbers',
        (tester) async {
      final c = newController();
      addTearDown(c.dispose);
      // Doom the opening state: crushing debt, pocket change. The REAL
      // runOperate then charges interest it cannot cover (F6) when the
      // run screen's initState begins the round.
      c.debugSetState(c.state.copyWith(
        ventures: [
          c.state.ventures.first.copyWith(netDebtCents: 5000000000),
        ],
        cashCents: 100000,
      ));

      await tester.pumpWidget(MaterialApp(
        home: RunScreen(controller: c),
      ));
      await tester.pump();

      // Dead: the autopsy owns the stage; the digest never opened.
      expect(c.state.phase, PhaseId.runOver);
      expect(c.state.death, DeathCause.bankruptcy);
      expect(find.text('THE YEAR PASSED'), findsNothing);
      expect(find.byKey(const Key('autopsy')), findsOneWidget);
      expect(textOf(tester, 'deathCause'), 'GREED.');
      expect(find.text('You ran out of cash paying debt.'), findsOneWidget);

      // THE NUMBER: the real bill off the last OperateResult — interest
      // from the event; the cash it broke against (post + interest).
      final interest = c.lastOperateEvents
          .firstWhere((e) => e.type == GameEventType.interestCharged)
          .amount;
      expect(interest, greaterThan(0));
      expect(
        textOf(tester, 'killNumber'),
        'INTEREST DUE ${formatMoney(interest)} > '
        'CASH ${formatMoney(c.state.cashCents + interest)}',
      );

      // No celebration juice on death — RETRY + the red pulse only.
      expect(find.byKey(const Key('nwSurgeValue')), findsNothing);
      expect(find.byKey(const Key('victory')), findsNothing);
      expect(find.byKey(const Key('retry')), findsOneWidget);
    });

    testWidgets('missed-deadline copy quotes the meters', (tester) async {
      final c = newController();
      addTearDown(c.dispose);
      // A run that died at the bar: phase RUN_OVER, missedDeadline.
      c.debugSetState(c.state.copyWith(
        phase: PhaseId.runOver,
        death: DeathCause.missedDeadline,
        round: 8,
        netWorthAtTierEntry: c.state.netWorthCents,
      ));

      await tester.pumpWidget(MaterialApp(
        home: RunScreen(controller: c),
      ));
      await tester.pump();

      expect(textOf(tester, 'deathCause'), 'TOO SLOW.');
      expect(find.text('The market would not wait.'), findsOneWidget);
      // The growth-rate tail reads straight off the engine meters.
      final m = c.meters;
      expect(
        find.textContaining(
            '${formatMultiple2(m.growthRateThisTierMilli)}/round',
            findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const Key('retry')), findsOneWidget);
    });
  });

  group('S5 shop beats', () {
    testWidgets('insufficient cash BUY flashes the row red (engine reject)',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);

      // Drain the pocket: REINVEST half, then half again, then reroll
      // would reject — simplest drain: reinvest twice via the controller.
      final controller = tester
          .widget<RunScreen>(find.byType(RunScreen))
          .controller;
      controller.reinvest();
      controller.reinvest();
      controller.reinvest();
      controller.reinvest();
      controller.reinvest();
      controller.reinvest(); // cash now < ~$350 (halves each time)
      await tester.pump();

      await tester.tap(find.byKey(const Key('endTurn')));
      await tester.pump();

      // Find a consumable offer to bounce off (financing has no BUY key).
      final s = controller.state;
      final buyable = s.shopOffers.where((id) =>
          controller.content.byId(id).type == CardType.consumable &&
          controller.content.byId(id).cost.cashCents >
              controller.state.cashCents);
      if (buyable.isEmpty) {
        // Stream dealt no over-priced consumable: nothing to bounce.
        return;
      }
      final target = buyable.first;
      await tester.ensureVisible(find.byKey(Key('buy-$target')));
      await tester.tap(find.byKey(Key('buy-$target')));
      await tester.pump();

      // The engine rejected; the row flash + the rejection line render.
      expect(find.byKey(const Key('rejection')), findsOneWidget);
      expect(find.text('! NOT ENOUGH CASH'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400)); // flash decays
      expect(controller.state.playsHeld, isEmpty); // value-identical reject
    });

    test('SELL face mirrors the engine trunc(price/2); sells in ACT',
        () {
      final c = newController();
      c.beginRound();
      c.dismissDigest();
      c.endTurnToShop();

      final consumables = c.state.shopOffers
          .where((id) => c.content.byId(id).type == CardType.consumable)
          .toList();
      if (consumables.isEmpty) return; // stream dealt none: nothing to pin
      final id = consumables.first;
      final price = c.content.byId(id).cost.cashCents;
      if (c.state.cashCents < price) return;

      c.buyOffer(id);
      expect(c.state.playsHeld, contains(id));
      expect(c.sellValueCents(id), price ~/ 2);

      // SellPlay is ACT-phase-gated engine-side (apply.dart's plays
      // matrix): from SHOP it rejects wrong_phase...
      final rejected = c.sellPlay(id);
      expect(
        rejected.any((e) =>
            e.type == GameEventType.actionRejected &&
            e.reason == 'wrong_phase'),
        isTrue,
      );
      expect(c.state.playsHeld, contains(id)); // value-identical reject

      // ...so liquidate from the NEXT round's ACT.
      c.advance();
      c.proceedFromDeadline();
      expect(c.state.phase, PhaseId.act);
      final cashBefore = c.state.cashCents;
      final events = c.sellPlay(id);
      expect(
          events.any((e) => e.type == GameEventType.actionRejected), isFalse);
      expect(c.state.cashCents, cashBefore + price ~/ 2);
      expect(c.state.playsHeld, isNot(contains(id)));
    });
  });
}
