// R20 TUTORIAL tests: the TutorialController gating/advance/skip (unit), and
// the first-run overlay showing once + marking seen (widget, through the real
// run screen). Seed 2's stream facts match the run_screen_test header (the
// opening hand carries ADD_SW_PLUGIN, so the ADD-ON step's trigger fires).
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
  group('TutorialController (gating + advance + skip)', () {
    test('inactive controller shows nothing', () {
      final c = TutorialController(active: false);
      addTearDown(c.dispose);
      c.fireTrigger(TutorialTrigger.actReady);
      expect(c.active, isFalse);
      expect(c.currentStep, isNull);
      expect(c.finished, isTrue);
    });

    test('a step shows only once its trigger fires; advance walks the script',
        () {
      final c = TutorialController(active: true);
      addTearDown(c.dispose);
      // Step 1 (money) is gated on actReady — nothing before the beat.
      expect(c.currentStep, isNull);

      c.fireTrigger(TutorialTrigger.actReady);
      expect(c.currentStep, isNotNull);
      expect(c.currentStep!.target, SpotlightTarget.moneyBoxes);

      // Advance to the equation step (its trigger fired too in a real run;
      // fire it so the gate opens).
      c.fireTrigger(TutorialTrigger.actReadyTwo);
      c.advance();
      expect(c.currentStep!.target, SpotlightTarget.equationLevers);

      // Advance to the add-on step — gated until addonInHand fires.
      c.advance();
      expect(c.currentStep, isNull, reason: 'waits for the add-on beat');
      c.fireTrigger(TutorialTrigger.addonInHand);
      expect(c.currentStep!.target, SpotlightTarget.addonTicket);

      // Advance to the arbitrage step — gated until arbitrageSeen.
      c.advance();
      expect(c.currentStep, isNull);
      c.fireTrigger(TutorialTrigger.arbitrageSeen);
      expect(c.currentStep!.target, SpotlightTarget.none);

      // The final advance ends the tutorial.
      c.advance();
      expect(c.currentStep, isNull);
      expect(c.finished, isTrue);
      expect(c.active, isFalse);
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

  group('first-run overlay (shows once, marks seen)', () {
    final cardsJson = File('assets/data/cards.json').readAsStringSync();
    final economyJson =
        File('assets/data/economy-model.json').readAsStringSync();

    // A store-less app seeded so NEW RUN runs without disk I/O; the injected
    // settings controller decides whether the tutorial fires.
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
      // The first OPERATE auto-ran -> YEAR PASSED digest; CONTINUE lands ACT.
      if (find.byKey(const Key('continue')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('continue')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }
      return settings;
    }

    testWidgets('a returning player (seen) sees no coachmark',
        (tester) async {
      await pumpToAct(tester, tutorialSeen: true);
      expect(find.byKey(const Key('tutorialOverlay')), findsNothing);
    });

    testWidgets('the first run shows step 1, advances, and marks seen',
        (tester) async {
      final settings = await pumpToAct(tester, tutorialSeen: false);

      // Step 1: CASH vs NET WORTH.
      expect(find.byKey(const Key('tutorialOverlay')), findsOneWidget);
      expect(find.byKey(const Key('tutorialTitle')), findsOneWidget);
      expect(find.text('REAL vs PAPER'), findsOneWidget);

      // TAP TO CONTINUE walks to the equation step.
      await tester.tap(find.byKey(const Key('tutorialOverlay')));
      await tester.pump();
      expect(find.text('VALUE IS A PRODUCT'), findsOneWidget);

      // Walk through the add-on step (seed 2's hand carries ADD_SW_PLUGIN, so
      // its trigger fired) and onward.
      await tester.tap(find.byKey(const Key('tutorialOverlay')));
      await tester.pump();
      expect(find.text('THE ADD-ON'), findsOneWidget);

      // SKIP from here ends the tutorial and latches seen.
      await tester.tap(find.byKey(const Key('tutorialSkip')));
      await tester.pump();
      expect(find.byKey(const Key('tutorialOverlay')), findsNothing);
      expect(settings.tutorialSeen, isTrue);
    });

    testWidgets('SKIP on step 1 dismisses + marks seen', (tester) async {
      final settings = await pumpToAct(tester, tutorialSeen: false);
      expect(find.byKey(const Key('tutorialOverlay')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorialSkip')));
      await tester.pump();
      expect(find.byKey(const Key('tutorialOverlay')), findsNothing);
      expect(settings.tutorialSeen, isTrue);
    });
  });
}
