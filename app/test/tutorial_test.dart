// R22 TUTORIAL tests: the opportunistic TutorialController (core steps gate
// completion; optional steps surface on their beat but never stall), and the
// first-run flow through the real run screen — intro cards gate, then the
// coachmarks, then marking seen. Seed 2's opening hand carries ADD_SW_PLUGIN
// (matches the run_screen_test header).
//
// No pumpAndSettle (the terminal idles animate forever); beats are stepped
// with explicit pump(Duration)s.

import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/main.dart';
import 'package:multiples_app/settings.dart';
import 'package:multiples_app/tutorial.dart';
import 'package:multiples_app/widgets/juice.dart';

const int kTestSeed = 2;

void main() {
  group('TutorialController (opportunistic gating + core completion)', () {
    test('inactive controller shows nothing', () {
      final c = TutorialController(active: false);
      addTearDown(c.dispose);
      c.fireTrigger(TutorialTrigger.actReady);
      expect(c.active, isFalse);
      expect(c.currentStep, isNull);
      expect(c.finished, isTrue);
    });

    test('core steps gate completion; a step shows only once its trigger fires',
        () {
      final c = TutorialController(active: true);
      addTearDown(c.dispose);
      expect(c.currentStep, isNull); // nothing fired yet

      // actReady unblocks the two actReady-gated CORE steps (money, moves).
      c.fireTrigger(TutorialTrigger.actReady);
      expect(c.currentStep!.target, SpotlightTarget.moneyBoxes);
      expect(c.finished, isFalse);

      c.advance(); // money shown -> next fired+unshown is the MOVES step
      expect(c.currentStep!.target, SpotlightTarget.addonTicket);
      expect(c.currentStep!.title, 'YOUR MOVES');

      // The equation step is gated on actReadyTwo — fire it and it jumps
      // ahead of the (later-indexed) moves step.
      c.fireTrigger(TutorialTrigger.actReadyTwo);
      expect(c.currentStep!.target, SpotlightTarget.equationLevers);

      c.advance(); // equation shown -> moves step again
      expect(c.currentStep!.title, 'YOUR MOVES');
      c.advance(); // moves shown -> all 3 CORE steps done

      expect(c.finished, isTrue, reason: 'all core steps shown');
      expect(c.active, isTrue, reason: 'still live so optional beats can land');
      expect(c.currentStep, isNull, reason: 'no optional trigger fired yet');

      // An optional beat (add-on) still surfaces its coachmark.
      c.fireTrigger(TutorialTrigger.addonInHand);
      expect(c.currentStep!.target, SpotlightTarget.addonTicket);
      expect(c.currentStep!.title, 'THE ADD-ON');
    });

    test('a missing optional beat never blocks completion', () {
      final c = TutorialController(active: true);
      addTearDown(c.dispose);
      // Only the core triggers ever fire (player never arbitrages/borrows).
      c.fireTrigger(TutorialTrigger.actReady);
      c.fireTrigger(TutorialTrigger.actReadyTwo);
      c.advance();
      c.advance();
      c.advance();
      expect(c.finished, isTrue, reason: 'optional steps do not stall it');
    });

    test('skip ends it immediately', () {
      final c = TutorialController(active: true);
      addTearDown(c.dispose);
      c.fireTrigger(TutorialTrigger.actReady);
      expect(c.currentStep, isNotNull);
      c.skip();
      expect(c.active, isFalse);
      expect(c.finished, isTrue);
      expect(c.currentStep, isNull);
    });
  });

  group('first-run flow (intro cards -> coachmarks -> seen)', () {
    final cardsJson = File('assets/data/cards.json').readAsStringSync();
    final economyJson =
        File('assets/data/economy-model.json').readAsStringSync();

    // Pumps a store-less app to the ACT beat. On a tutorial run it dismisses
    // the intro-cards gate first, then the opening digest, landing on the
    // first coachmark.
    Future<AppSettingsController> pumpToAct(
      WidgetTester tester, {
      required bool tutorialSeen,
    }) async {
      final settings = AppSettingsController(
        initial: AppSettings(tutorialSeen: tutorialSeen),
      );
      addTearDown(settings.dispose);
      addTearDown(() => setHapticsEnabledGate(true));
      await tester.pumpWidget(MultiplesApp(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kTestSeed,
        settings: settings,
      ));
      await tester.tap(find.byKey(const Key('newRun')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Tutorial run: the intro cards cover everything until dismissed.
      if (find.byKey(const Key('introSkip')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('introSkip')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }
      // The first OPERATE auto-ran -> YEAR PASSED digest; CONTINUE lands ACT.
      if (find.byKey(const Key('continue')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('continue')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }
      return settings;
    }

    testWidgets('a returning player (seen) sees no intro and no coachmark',
        (tester) async {
      await pumpToAct(tester, tutorialSeen: true);
      expect(find.byKey(const Key('introCards')), findsNothing);
      expect(find.byKey(const Key('tutorialOverlay')), findsNothing);
    });

    testWidgets('the first run shows intro cards, then the coachmarks, '
        'then marks seen', (tester) async {
      final settings = AppSettingsController(
        initial: const AppSettings(tutorialSeen: false),
      );
      addTearDown(settings.dispose);
      addTearDown(() => setHapticsEnabledGate(true));
      await tester.pumpWidget(MultiplesApp(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kTestSeed,
        settings: settings,
      ));
      await tester.tap(find.byKey(const Key('newRun')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // INTRO CARDS gate appears first.
      expect(find.byKey(const Key('introCards')), findsOneWidget);
      expect(find.text("YOU'RE A DEALMAKER"), findsOneWidget);
      await tester.tap(find.byKey(const Key('introSkip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      if (find.byKey(const Key('continue')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('continue')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }

      // First coachmark: CASH vs NET WORTH.
      expect(find.byKey(const Key('tutorialOverlay')), findsOneWidget);
      expect(find.text('REAL vs PAPER'), findsOneWidget);

      // TAP TO CONTINUE walks to the equation step.
      await tester.tap(find.byKey(const Key('tutorialOverlay')));
      await tester.pump();
      expect(find.text('THE EQUATION'), findsOneWidget);

      // SKIP ends the tutorial and latches seen.
      await tester.tap(find.byKey(const Key('tutorialSkip')));
      await tester.pump();
      expect(find.byKey(const Key('tutorialOverlay')), findsNothing);
      expect(settings.tutorialSeen, isTrue);
    });

    testWidgets('SKIP on the intro cards still starts the run', (tester) async {
      final settings = await pumpToAct(tester, tutorialSeen: false);
      // After dismissing intro + digest we're in ACT with the first coachmark
      // (or, if a tap raced, at least no intro gate remains).
      expect(find.byKey(const Key('introCards')), findsNothing);
      expect(settings.tutorialSeen, isFalse,
          reason: 'skipping intro does not by itself finish the coachmarks');
    });
  });
}
