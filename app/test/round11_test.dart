// Round-11 tests: the R10 engine systems surfaced in the UI.
//   - EXIT OFFER ticket -> exit napkin (engine-derived fork rows) ->
//     EXECUTE -> the S6-EXIT paper-collapses-into-cash beat -> cash up,
//     venture gone, slot freed (preview pinned == the engine events).
//   - PARTNER tickets playable (hire -> +EBITDA accrual next OPERATE,
//     rail tag, digest PARTNERS row).
//   - TARGET PICKER: >1 ventures -> the holdings rail aims a targeted
//     ticket; the engine resolves onto the aimed venture.
//   - REINVEST amount picker (25/50/100% quick keys + the engine
//     reinvestEfficiencyBp preview line == the resolver's exact gain).
//   - HOT WINDOW armed chip + the exit napkin override line; MARKET READ
//     hint on the market meter; held-play USE/SELL sheet.
//   - Digest: scheduled-cost rows + the EXIT OFFER tease.
//
// Same harness as run_screen_test: dart:io JSON injection, fixed seed 2
// (stream facts in that file's header), explicit pump(Duration)s, no
// pumpAndSettle (the terminal idles forever by design).

import 'dart:io';

import 'package:engine/apply.dart'
    show GameEventType, hotExitMulDen, hotExitMulNum;
import 'package:engine/model.dart';
import 'package:engine/money.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/controller.dart';
import 'package:multiples_app/main.dart';
import 'package:multiples_app/screens/run_screen.dart';

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

  /// A controller already at seed-2 round-1 ACT (digest dismissed).
  GameController actController() {
    final c = newController();
    c.beginRound();
    c.dismissDigest();
    return c;
  }

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

  Future<void> pumpRun(WidgetTester tester, GameController c) async {
    await tester.pumpWidget(MaterialApp(home: RunScreen(controller: c)));
    await tester.pump();
  }

  group('EXIT flow (offer ticket -> napkin -> beat; seed 2)', () {
    testWidgets('end to end: ticket, engine rows, paper->cash, slot freed',
        (tester) async {
      await pumpApp(tester);

      // The digest teases the offer the hand routine drew.
      expect(find.byKey(const Key('digestExitOffer')), findsOneWidget);

      await dismissDigest(tester);
      final c =
          tester.widget<RunScreen>(find.byType(RunScreen)).controller;
      final offer = c.state.exitOffer!;
      final preview = c.exitPreview()!;
      expect(preview.hot, isFalse);
      final cashBefore = c.state.cashCents;

      // The EXIT ticket renders on the blotter (mockup .t-exit shape) —
      // scroll the lazy list to the bottom row first.
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pump();
      expect(find.byKey(const Key('ticket-EXIT')), findsOneWidget);
      expect(find.text('SELL'), findsOneWidget);
      expect(find.text('PAPER→CASH'), findsOneWidget);
      expect(
        find.textContaining(formatMultiple(offer.offerMultipleMilli),
            findRichText: true),
        findsWidgets,
      );

      // Tap -> the exit napkin: every row engine-derived (ExitPreview
      // pins the apply.dart mirror; the engine events pin it below).
      await tester.tap(find.byKey(const Key('ticket-EXIT')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // rise
      expect(textOf(tester, 'exitMultiple'),
          formatMultiple2(preview.exitMultipleMilli));
      expect(textOf(tester, 'exitEquity'),
          formatMoney(preview.equityAtExitCents));
      expect(textOf(tester, 'exitProceeds'),
          '+${formatMoney(preview.proceedsCents)}');
      // min(offer, live) held: no hot override line.
      expect(find.byKey(const Key('hotOverrideLine')), findsNothing);

      // EXECUTE -> the S6-EXIT beat (paper collapses INTO cash).
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();
      expect(find.byKey(const Key('exitFlash')), findsOneWidget);
      expect(find.byKey(const Key('exitPaperBox')), findsOneWidget);
      expect(find.byKey(const Key('exitCashBox')), findsOneWidget);
      // T1 has 1 slot; the exit freed it.
      expect(textOf(tester, 'exitSlotLine'), 'SLOT FREED 0/1');

      // Step the beat: collapse (~600ms) then the proceeds count-up.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 900));
      expect(textOf(tester, 'exitCashCount'),
          '+${formatMoney(preview.proceedsCents)}');

      await tester.tap(find.byKey(const Key('cashedOut')));
      await tester.pump();

      // Engine truth: cash up by the proceeds, venture gone, ticket dead.
      expect(find.byKey(const Key('exitFlash')), findsNothing);
      expect(c.state.cashCents, cashBefore + preview.proceedsCents);
      expect(c.state.ventures, isEmpty);
      expect(c.state.exitOffer, isNull);
      expect(find.byKey(const Key('ticket-EXIT')), findsNothing);
      expect(find.text('NO HOLDINGS · ALL CASH'), findsOneWidget);
    });

    test('preview == the engine events (programmatic cross-check)', () {
      final c = actController();
      final preview = c.exitPreview()!;
      final playsBefore = c.state.playsRemaining;

      final events = c.exitVenture();
      final realized = events
          .firstWhere((e) => e.type == GameEventType.exitRealized)
          .amount;
      // The render-only preview matched the resolver to the cent.
      expect(realized, preview.proceedsCents);
      expect(events.any((e) => e.type == GameEventType.hotWindowFired),
          isFalse);
      expect(c.pendingExitFlash, isNotNull);
      expect(c.pendingExitFlash!.proceedsCents, realized);
      expect(c.pendingExitFlash!.exitMultipleMilli,
          preview.exitMultipleMilli);
      expect(c.state.playsRemaining, playsBefore - 1); // EXIT costs a play
      c.dismissExitFlash();
      expect(c.pendingExitFlash, isNull);
    });
  });

  group('HOT WINDOW (armed chip + the exit override)', () {
    testWidgets('chip on the meter; napkin override line; engine fires it',
        (tester) async {
      final c = actController();
      addTearDown(c.dispose);
      c.debugSetState(c.state.copyWith(
        market: c.state.market.copyWith(
          hotWindowArmed: true,
          hotWindowExpiresRound: 999,
        ),
      ));
      await pumpRun(tester, c);

      // The armed chip sits by the market meter.
      expect(find.byKey(const Key('hotArmedChip')), findsOneWidget);

      final preview = c.exitPreview()!;
      expect(preview.hot, isTrue);
      // The documented mirror of apply.dart's hot fork.
      expect(
        preview.exitMultipleMilli,
        (preview.liveMultipleMilli * hotExitMulNum) ~/ hotExitMulDen,
      );

      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ticket-EXIT')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('hotOverrideLine')), findsOneWidget);
      expect(textOf(tester, 'exitMultiple'),
          '${formatMultiple2(preview.exitMultipleMilli)} HOT');

      // EXECUTE: the engine fires the window; proceeds == the preview.
      final cashBefore = c.state.cashCents;
      final nwBefore = c.state.netWorthCents;
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();
      expect(c.state.cashCents, cashBefore + preview.proceedsCents);
      expect(c.state.market.hotWindowArmed, isFalse);
      expect(c.state.netWorthCents, greaterThan(nwBefore)); // hot rises

      // CASHED OUT releases the deferred NW surge (the signature).
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.tap(find.byKey(const Key('cashedOut')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('nwSurgeValue')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1700)); // settle
      expect(find.byKey(const Key('nwSurgeValue')), findsNothing);
    });
  });

  group('PARTNER hire (ticket -> napkin -> engine accrual)', () {
    testWidgets('hire through the napkin; rail tag; next-round digest row',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);
      final c =
          tester.widget<RunScreen>(find.byType(RunScreen)).controller;
      final cashBefore = c.state.cashCents;

      // The partner ticket face: per-round engine accrual + HIRE price.
      await tester
          .ensureVisible(find.byKey(const Key('ticket-PRT_SALES_LEAD')));
      expect(
        find.descendant(
          of: find.byKey(const Key('ticket-PRT_SALES_LEAD')),
          matching: find.textContaining('/RD', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.text('HIRE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ticket-PRT_SALES_LEAD')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Face: raw inputs (the actionForCard payload).
      expect(find.text('> EBITDA / ROUND'), findsOneWidget);
      expect(find.text(r'+$1,500'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inspect')));
      await tester.pump();
      // The napkin: the engine per-round line; no fixed-cost warning in
      // the v1 slice (the schema has no fixed-cost face).
      expect(textOf(tester, 'partnerEngineRow'),
          r'+$1,500 EBITDA / ROUND');
      expect(find.byKey(const Key('partnerFixedCostRow')), findsNothing);

      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();

      // The engine hired: cash down, the engine attached, the rail tag.
      // v6: the founding operator (0-face, initRun) is partners.first;
      // the hire appends.
      expect(c.state.cashCents, cashBefore - 600000);
      expect(c.platform!.partners.length, 2);
      expect(c.platform!.partners.last.perRoundEbitdaCents, 150000);
      expect(find.byKey(const Key('partnerTag-v1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('partnerTag-v1')),
          matching: find.text(r'+$1,500/RD'),
        ),
        findsOneWidget,
      );

      // Next OPERATE: step 3a accrues +$1,500 — the digest PARTNERS row.
      final ebitdaBefore = c.platform!.ebitdaCents;
      await tester.tap(find.byKey(const Key('endTurn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('advance')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500)); // bar fill
      await tester.tap(find.byKey(const Key('proceed')));
      await tester.pump();
      expect(c.yearDigest!.partnerAccrualCents, 150000);
      expect(textOf(tester, 'digestPartners'), r'+$1,500 EBITDA');
      // The accrual landed on the venture (drift moves only multiples;
      // round-2 v1 was just targeted so no decay; events may add more
      // but never remove SOFTWARE EBITDA in the T1 slice).
      expect(c.platform!.ebitdaCents,
          greaterThanOrEqualTo(ebitdaBefore + 150000));
    });
  });

  group('TARGET PICKER (>1 ventures: the rail aims)', () {
    GameController twoVentureController() {
      final c = actController();
      c.debugSetState(c.state.copyWith(
        tier: 2,
        ventures: [
          c.state.ventures.first,
          const Venture(
            id: 'v2',
            sector: Sector.services,
            ebitdaCents: 400000,
            multipleMilli: 5000,
            netDebtCents: 0,
            ownershipBp: 10000,
          ),
        ],
        hand: ['ADD_SW_PLUGIN'],
        playsRemaining: 3,
      ));
      return c;
    }

    testWidgets('aim flow: ticket -> rail glow -> venture tap -> napkin',
        (tester) async {
      final c = twoVentureController();
      addTearDown(c.dispose);
      await pumpRun(tester, c);

      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump();

      // Aiming: the napkin waits; the rail is the picker.
      expect(find.byKey(const Key('napkin')), findsNothing);
      expect(find.text('TAP A VENTURE TO AIM ▼'), findsOneWidget);

      await tester.tap(find.byKey(const Key('holding-v2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The napkin opened aimed at v2 — now shown by its flavor display
      // name (R14 work order #5: venture rows/tickets/napkins render
      // Venture.displayName, never the raw "V2" id).
      expect(find.byKey(const Key('napkin')), findsOneWidget);
      final v2Name = c.targetVenture('v2')!.displayName;
      expect(find.textContaining('→ $v2Name'), findsOneWidget);

      // EXECUTE: the ENGINE resolves onto v2 — raw absorb, multiple
      // dragged x0.92 (cross-sector), v1 untouched.
      final v1Before = c.state.ventures.first;
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();
      final v2 = c.state.ventures[1];
      expect(v2.ebitdaCents, 400000 + 300000); // zero synergy
      expect(v2.multipleMilli, (5000 * 92) ~/ 100); // the drag
      expect(c.state.ventures.first.ebitdaCents, v1Before.ebitdaCents);

      // The arbitrage flash fired for the commit; book it closed.
      expect(find.byKey(const Key('arbHeadline')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.tap(find.byKey(const Key('bookIt')));
      await tester.pump(const Duration(milliseconds: 1800));
    });

    test('single venture auto-targets (no aim step) — programmatic', () {
      final c = actController();
      expect(c.state.ventures.length, 1);
      final events = c.playBlotterCard('ADD_SW_PLUGIN');
      expect(events.any((e) => e.type == GameEventType.actionRejected),
          isFalse);
      expect(c.platform!.ebitdaCents, 1080000,
          reason: r'$7,200 organically grown base (R12 organic 0.20) + '
              r'$3,600 merge');
    });
  });

  group('REINVEST picker (quick keys + the engine efficiency line)', () {
    testWidgets('25/50/100 keys move the amount; GET == resolver gain',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);
      final c =
          tester.widget<RunScreen>(find.byType(RunScreen)).controller;

      await tester.tap(find.byKey(const Key('reinvest')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Default = the R7 half-pocket dial.
      expect(c.reinvestPct, 50);
      expect(textOf(tester, 'reinvestPay'),
          '−${formatMoney(c.reinvestAmountCents)}');

      await tester.tap(find.byKey(const Key('reinvestPct-25')));
      await tester.pump();
      expect(c.reinvestPct, 25);
      expect(c.reinvestAmountCents, (c.state.cashCents * 25) ~/ 100);
      expect(textOf(tester, 'reinvestPay'),
          '−${formatMoney(c.reinvestAmountCents)}');
      // The engine efficiency preview line: +$X EBITDA at Y% (round 1
      // tier 1 = the 5500bp curve start).
      expect(c.reinvestEffBp, 5500);
      expect(
        textOf(tester, 'reinvestGet'),
        '+${formatMoney(c.reinvestGainCents)} EBITDA AT '
        '${bpToPctTrunc(c.reinvestEffBp)}%',
      );

      // EXECUTE: the resolver lands EXACTLY the previewed gain.
      final gain = c.reinvestGainCents;
      final amount = c.reinvestAmountCents;
      final ebitdaBefore = c.platform!.ebitdaCents;
      final cashBefore = c.state.cashCents;
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();
      expect(c.platform!.ebitdaCents, ebitdaBefore + gain);
      expect(c.state.cashCents, cashBefore - amount);
    });

    testWidgets('REROLL disables cash-short (the real fee on the cap)',
        (tester) async {
      final c = actController();
      addTearDown(c.dispose);
      c.debugSetState(c.state.copyWith(cashCents: 100000)); // < $15k fee
      await pumpRun(tester, c);

      expect(c.canReroll, isFalse);
      final cashBefore = c.state.cashCents;
      await tester.tap(find.byKey(const Key('reroll')));
      await tester.pump();
      // Inert key: nothing dispatched, nothing charged.
      expect(c.state.cashCents, cashBefore);
      expect(c.state.rerollsUsed, 0);
    });
  });

  group('MARKET READ hint + held-play USE/SELL sheet', () {
    testWidgets('unexpired read shows on the meter', (tester) async {
      final c = actController();
      addTearDown(c.dispose);
      c.debugSetState(c.state.copyWith(
        market: c.state.market.copyWith(
          marketReadHint: MarketTemp.neutral,
          marketReadExpiresRound: 999,
        ),
      ));
      await pumpRun(tester, c);
      expect(textOf(tester, 'marketReadHint'), '(READ: NEUTRAL→)');
    });

    testWidgets('held play: SELL pays the engine trunc(price/2)',
        (tester) async {
      final c = actController();
      addTearDown(c.dispose);
      c.debugSetState(c.state.copyWith(playsHeld: ['PLY_MARKET_READ']));
      await pumpRun(tester, c);

      await tester.tap(find.byKey(const Key('play-PLY_MARKET_READ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The sheet: the engine sell face (cost $1,000 -> $500).
      expect(textOf(tester, 'heldSellValue'), r'+$500');
      expect(find.byKey(const Key('useHeld')), findsOneWidget);

      final cashBefore = c.state.cashCents;
      await tester.tap(find.byKey(const Key('sellHeld')));
      await tester.pump();
      expect(c.state.cashCents, cashBefore + 50000);
      expect(c.state.playsHeld, isEmpty);
      expect(find.byKey(const Key('napkin')), findsNothing);
    });

    testWidgets('held play: USE arms the read through the engine',
        (tester) async {
      final c = actController();
      addTearDown(c.dispose);
      c.debugSetState(c.state.copyWith(playsHeld: ['PLY_MARKET_READ']));
      await pumpRun(tester, c);

      await tester.tap(find.byKey(const Key('play-PLY_MARKET_READ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('useHeld')));
      await tester.pump();

      // The engine consumed the play and set the hint; the meter shows it.
      expect(c.state.playsHeld, isEmpty);
      expect(c.state.market.marketReadHint, isNotNull);
      expect(find.byKey(const Key('marketReadHint')), findsOneWidget);
    });
  });

  group('digest touches (round 11)', () {
    test('scheduled-cost rows mirror the SCHEDULED_EFFECT_FIRED events',
        () {
      final c = newController();
      // A recurring fixed cost on the seed venture, fired by the REAL
      // runOperate at step 3c (phase is still the opening OPERATE).
      c.debugSetState(c.state.copyWith(
        scheduled: [
          const ScheduledCost(
            ventureId: 'v1',
            cashDeltaCents: -25000,
            recurring: true,
          ),
        ],
      ));
      c.beginRound();
      final d = c.yearDigest!;
      expect(d.scheduled.length, 1);
      expect(d.scheduled.first.amount, -25000);
      expect(d.scheduled.first.ventureId, 'v1');
      // NET CASH still reconciles as post − pre (event-proof).
      expect(c.lastOperateEvents
          .any((e) => e.type == GameEventType.scheduledEffectFired),
          isTrue);
    });

    testWidgets('scheduled row renders in THE YEAR PASSED',
        (tester) async {
      final c = newController();
      addTearDown(c.dispose);
      c.debugSetState(c.state.copyWith(
        scheduled: [
          const ScheduledCost(
            ventureId: 'v1',
            cashDeltaCents: -25000,
            recurring: true,
          ),
        ],
      ));
      await pumpRun(tester, c); // initState runs the OPERATE; digest opens
      expect(textOf(tester, 'digestScheduled'), r'-$250 CASH');
    });
  });
}
