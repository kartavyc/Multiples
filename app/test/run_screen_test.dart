// Round-7/8 run-screen tests (plan 3.1-3.6): HUD canonical order + the
// $56k opening contract, the blotter -> napkin -> EXECUTE -> flash ->
// BOOK IT -> surge path, END TURN -> SHOP, and the full programmatic loop
// operate -> act -> shop -> deadline panel -> round 2.
//
// JSON is injected via dart:io off the app package root (the smoke_test
// pattern); the SEED IS FIXED at [kTestSeed] so the engine stream is
// deterministic. Seed 2's first OPERATE (re-derivable by scanning
// runOperate over seeds) deals the hand [ADD_SW_PLUGIN, VEN_SW_GARAGE,
// VEN_SVC_AGENCY], fires NO event card, and stays NEUTRAL — so at ACT:
//   - cash = $20,000 + 35% yield on $6,000 EBITDA = $22,100 (no debt, no
//     interest);
//   - v1 EBITDA is still exactly $6,000 (drift moves only the multiple;
//     no decay on round 1; no event fired).
// Exact DRIFTED multiples are deliberately not pinned (streams are the
// engine golden's contract, not the UI's); action math (the same-sector
// synergy merge: +$3,000 absorbed +20% = +$3,600) is engine-canon and
// stable for any seed, so the post-EXECUTE $9,600 IS pinned.
//
// No pumpAndSettle anywhere: the terminal idles (cursor blink, tape,
// key pulse, CRT flicker) animate forever by design. Beats are stepped
// with explicit pump(Duration)s — every R8 animation runs off
// AnimationControllers, so no real timer can leak.

import 'dart:io';

import 'package:engine/model.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/controller.dart';
import 'package:multiples_app/main.dart';
import 'package:multiples_app/screens/run_screen.dart';

/// The pinned test seed (header explains the seed-2 stream facts).
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

  group(r'HUD (canonical order + the $56k opening contract)', () {
    testWidgets('renders CASH solid, NET WORTH ghost, levers in order',
        (tester) async {
      // A fresh controller has NOT begun the round: this is the canonical
      // initRun opening state ($56,000 derived net worth).
      final controller = newController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HudPanel(controller: controller)),
      ));

      // The contract numbers, formatted by the engine.
      expect(textOf(tester, 'netWorth'), r'$56,000');
      expect(textOf(tester, 'cash'), r'$20,000');

      // Paper-vs-real tags.
      expect(find.text('REAL'), findsOneWidget);
      expect(find.text('PAPER'), findsOneWidget);

      // Canonical order (docs/05 §0.3): CASH then NET WORTH on the money
      // row; the four levers EBITDA -> MULT -> DEBT -> OWN left to right.
      final cashX = tester.getTopLeft(find.text('CASH')).dx;
      final nwX = tester.getTopLeft(find.text('NET WORTH')).dx;
      expect(cashX, lessThan(nwX));
      final leverXs = ['EBITDA', 'MULT', 'DEBT', 'OWN']
          .map((label) => tester.getTopLeft(find.text(label)).dx)
          .toList();
      for (var i = 1; i < leverXs.length; i++) {
        expect(leverXs[i - 1], lessThan(leverXs[i]),
            reason: 'lever order is law (docs/05 §0.3)');
      }

      // The seed venture's levers off engine formatters.
      expect(textOf(tester, 'lever-ebitda'), r'$6,000');
      expect(textOf(tester, 'lever-mult'), '6.0x');
      expect(textOf(tester, 'lever-debt'), r'$0');
      expect(textOf(tester, 'lever-own'), '100%');

      // Both forward meters present (death is telegraphed statically),
      // WITH their literal numbers (docs/05 §0.2: legible with zero
      // motion). Debt-free book: due $0; proj = $20,000 + the 35% yield.
      expect(find.text('RUNWAY'), findsOneWidget);
      expect(find.text(r'due $0'), findsOneWidget);
      expect(find.text(r'proj $22,100'), findsOneWidget);
      expect(find.text('MARKET'), findsOneWidget);
      expect(find.text('NEUTRAL'), findsOneWidget);
      expect(find.text('COLD'), findsOneWidget);
      expect(find.text('HOT'), findsOneWidget);
      // Statline: tier, round/deadline, bar.
      expect(find.text('TIER 1'), findsOneWidget);
      expect(find.text('1/9'), findsOneWidget); // T1 deadline 9 (R12 tune)
      expect(find.text(r'$1M'), findsOneWidget);
    });
  });

  group('run screen flow (widget, seed 2)', () {
    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(MultiplesApp(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kTestSeed,
      ));
      // S0 title gates the run; NEW RUN mounts the run screen, whose
      // initState auto-runs the first OPERATE.
      await tester.tap(find.byKey(const Key('newRun')));
      await tester.pump();
    }

    Future<void> dismissDigest(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pump();
    }

    testWidgets('opens on THE YEAR PASSED digest; CONTINUE lands ACT',
        (tester) async {
      await pumpApp(tester);

      // The first OPERATE auto-ran; the digest interstitial covers the
      // stage.
      expect(find.text('THE YEAR PASSED'), findsOneWidget);

      await dismissDigest(tester);

      expect(find.text('THE YEAR PASSED'), findsNothing);
      expect(find.text('DEALS'), findsOneWidget);
      // T1 grants 2 plays (engine playsPerRound contract).
      expect(find.text('↯ 2/2 PLAYS'), findsOneWidget);
      // The seed-2 hand as tickets — the v5 pool contract: T1's one slot
      // is full from the opening, so the dead-draw filter leaves the
      // 3-card addon+partner pool and every T1 hand is all of it.
      expect(find.byKey(const Key('ticket-ADD_SW_PLUGIN')), findsOneWidget);
      expect(find.byKey(const Key('ticket-ADD_SW_MICRO')), findsOneWidget);
      expect(
          find.byKey(const Key('ticket-PRT_SALES_LEAD')), findsOneWidget);
      // PLAYS strip: held inventory rendered apart from the hand
      // (docs/05 §3 — the two scarcities never blur).
      expect(find.byKey(const Key('playsHeldCount')), findsOneWidget);
      expect(find.text('HELD 0/2'), findsOneWidget);
      // The addon midline carries the ENGINE-implied buy multiple
      // (mockup `EBITDA @ m`): $9,000 price / $3,000 EBITDA = 3.0x.
      expect(
        find.descendant(
          of: find.byKey(const Key('ticket-ADD_SW_PLUGIN')),
          matching: find.textContaining('3.0x', findRichText: true),
        ),
        findsOneWidget,
      );
      // Post-operate cash on the HUD: $20,000 + $2,520 yield (35% of the
      // organically grown $7,200 — doc 01 §3.2 at the R12-tuned 0.20).
      expect(textOf(tester, 'cash'), r'$22,520');
    });

    testWidgets(
        'addon EXECUTE: flash takeover -> BOOK IT -> surge -> levers move',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);

      // Round-1 EBITDA after the organic compounding: $6,000 + 20%
      // (the founding operator's attribution, doc 01 §3.2, R12-tuned
      // 0.20); drift/decay/events leave it alone (header).
      expect(textOf(tester, 'lever-ebitda'), r'$7,200');

      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump(); // napkin mounts; the rise starts
      await tester.pump(const Duration(milliseconds: 300)); // rise done

      // S4 stage 1: the raw face with BACK / INSPECT / EXECUTE keys.
      expect(find.byKey(const Key('execute')), findsOneWidget);
      expect(find.byKey(const Key('back')), findsOneWidget);
      expect(find.byKey(const Key('inspect')), findsOneWidget);

      // A confident player executes straight from the face (docs/05 §3).
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();

      // S6: the MULTIPLE ARBITRAGE takeover fired on the engine event.
      expect(find.byKey(const Key('arbHeadline')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2600)); // count-ups

      await tester.tap(find.byKey(const Key('bookIt')));
      await tester.pump(); // surge beat starts
      await tester.pump(const Duration(milliseconds: 100));

      // THE SIGNATURE: the NW surge runs (green count-up box + tint)...
      expect(find.byKey(const Key('nwSurgeValue')), findsOneWidget);
      expect(find.byKey(const Key('nwSurgeTint')), findsOneWidget);
      // ...then settles back to the ghost box.
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.byKey(const Key('nwSurgeValue')), findsNothing);
      expect(find.byKey(const Key('netWorth')), findsOneWidget);

      // The engine merged same-sector: +$3,000 absorbed +20% synergy,
      // onto the organically grown $7,200 base (organic 0.20, R12).
      expect(textOf(tester, 'lever-ebitda'), r'$10,800');
      // The change chip reads against the round-start snapshot ($6,000):
      // +$1,200 organic (R12) + $3,600 merge.
      expect(find.text(r'▲$4,800'), findsOneWidget); // the change chip
      expect(textOf(tester, 'cash'), r'$13,520'); // $22,520 − $9,000
      expect(find.text('↯ 1/2 PLAYS'), findsOneWidget); // play spent
      // Overlays closed; the played card left the hand.
      expect(find.byKey(const Key('execute')), findsNothing);
      expect(find.byKey(const Key('ticket-ADD_SW_PLUGIN')), findsNothing);
    });

    testWidgets('END TURN reaches the SHOP panel', (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);

      await tester.tap(find.byKey(const Key('endTurn')));
      await tester.pump();

      expect(find.text('SHOP · CASH ONLY'), findsOneWidget);
      expect(find.byKey(const Key('shopPanel')), findsOneWidget);
      expect(find.byKey(const Key('advance')), findsOneWidget);
      // The engine dealt exactly kShopOfferCount offers.
      final controller = tester
          .widget<RunScreen>(find.byType(RunScreen))
          .controller;
      expect(controller.state.phase, PhaseId.shop);
      expect(controller.state.shopOffers.length, 3);
    });

    testWidgets('ADVANCE opens the S7 deadline panel; proceed -> round 2',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);
      await tester.tap(find.byKey(const Key('endTurn')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('advance')));
      await tester.pump();

      // T1 round 1, NW ~$58k vs the $1M bar: NOT cleared, rounds left.
      expect(find.byKey(const Key('deadlineCheck')), findsOneWidget);
      expect(find.text('DEADLINE CHECK'), findsOneWidget);
      // Telegraph #2 off the engine meters, red.
      expect(find.byKey(const Key('paceNote')), findsOneWidget);
      expect(textOf(tester, 'paceNote'), contains('NEED'));
      expect(find.text('NEXT ROUND'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500)); // bar fill

      await tester.tap(find.byKey(const Key('proceed')));
      await tester.pump();

      // The next OPERATE ran; round 2's digest covers the stage.
      expect(find.text('THE YEAR PASSED'), findsOneWidget);
      final controller = tester
          .widget<RunScreen>(find.byType(RunScreen))
          .controller;
      expect(controller.state.round, 2);
      expect(controller.state.phase, PhaseId.act);
    });
  });

  group('full loop (programmatic, seed 2)', () {
    test('operate -> act -> endTurn -> deadline panel -> round 2', () {
      final c = newController();

      // Run start: initRun left phase OPERATE; the screen auto-begins.
      expect(c.state.phase, PhaseId.operate);
      expect(c.state.round, 1);
      c.beginRound();
      expect(c.state.phase, PhaseId.act);
      expect(c.digestOpen, isTrue);
      c.dismissDigest();

      // One real deal through the engine path.
      final events = c.playBlotterCard('ADD_SW_PLUGIN');
      expect(
        events.any((e) => e.reason != null && e.reason!.contains('reject')),
        isFalse,
      );
      expect(c.platform!.ebitdaCents, 1080000,
          reason: r'$7,200 organically grown base (R12 organic 0.20) + '
              r'$3,600 merge');
      // The commit captured the S6 flash payload off the event.
      expect(c.pendingFlash, isNotNull);
      expect(c.pendingFlash!.ebitdaToCents, 1080000);
      c.dismissFlash();
      expect(c.pendingFlash, isNull);

      c.endTurnToShop();
      expect(c.state.phase, PhaseId.shop);
      expect(c.state.shopOffers.length, 3);

      // ADVANCE: the deadline check runs; bar not met + rounds remain ->
      // the S7 panel opens with the round already advanced; the digest
      // waits for the proceed key.
      c.advance();
      expect(c.deadlineOpen, isTrue);
      expect(c.deadline!.cleared, isFalse);
      expect(c.deadline!.roundsUsed, 1);
      expect(c.deadline!.deadlineRounds, 9); // T1 deadline 9 (R12 tune)
      expect(c.state.round, 2);
      expect(c.state.phase, PhaseId.operate);
      expect(c.digestOpen, isFalse);

      c.proceedFromDeadline();
      expect(c.deadlineOpen, isFalse);
      expect(c.state.phase, PhaseId.act);
      expect(c.digestOpen, isTrue);
      expect(c.state.netWorthCents, greaterThan(0));
    });

    test('REINVEST dial: half the pocket cash in, EBITDA up', () {
      final c = newController();
      c.beginRound();
      c.dismissDigest();

      final cashBefore = c.state.cashCents;
      final ebitdaBefore = c.platform!.ebitdaCents;
      final amount = c.reinvestAmountCents;
      expect(amount, cashBefore ~/ 2); // the documented UI dial

      final events = c.reinvest();
      expect(events, isEmpty); // ReinvestBaseline emits no events on success
      expect(c.state.cashCents, cashBefore - amount);
      expect(c.platform!.ebitdaCents, greaterThan(ebitdaBefore));
    });

    test('REROLL fee: the first reroll of a round is the \$15k base '
        '(engine scaling fee), hand redrawn engine-side', () {
      final c = newController();
      c.beginRound();
      c.dismissDigest();

      // First reroll of the round: rerollsUsed 0 -> the base fee ($15k).
      expect(c.state.rerollsUsed, 0);
      final feeFirst = c.rerollCostCents;
      expect(feeFirst, 1500000, reason: 'doc 02 §3.8/§4 base fee');

      final cashBefore = c.state.cashCents;
      final events = c.reroll();
      expect(events, isEmpty);
      expect(c.state.cashCents, cashBefore - feeFirst);
      expect(c.state.rerollsUsed, 1);
      expect(c.state.hand.length, inInclusiveRange(3, 5));

      // The SECOND reroll escalates one step ($30k) — the scaling kicks in.
      expect(c.rerollCostCents, 3000000,
          reason: 'base + 1 step after one reroll this round');
    });
  });
}
