// R19 juice-pass widget tests (the FULL animation/juice pass): floating
// deltas on every HUD stat, the ticket deal-in, the attract-pulse on the
// suggested deal, the MK nameplate stamp firing on a tier-clear, and the
// CRT screen transition settling without orphaned controllers.
//
// Same harness as run_screen_test (seed 2, JSON off the app package root,
// pinned pump(Duration) steps — every beat runs off an AnimationController,
// so no real timer leaks and pumpAndSettle is NEVER used: the terminal
// idles (cursor, tape, CRT flicker, key pulse, attract-pulse) loop forever
// by design).

import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/main.dart';
import 'package:multiples_app/screens/run_screen.dart';
import 'package:multiples_app/widgets/juice.dart';

const int kTestSeed = 2;

void main() {
  final cardsJson = File('assets/data/cards.json').readAsStringSync();
  final economyJson =
      File('assets/data/economy-model.json').readAsStringSync();

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MultiplesApp(
      cardsJson: cardsJson,
      economyJson: economyJson,
      seed: kTestSeed,
    ));
    await tester.tap(find.byKey(const Key('newRun')));
    await tester.pump();
    // Settle the CRT screen transition (title → run, 300ms) + the deal-in.
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> dismissDigest(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // deal-in lands
  }

  RunScreen runScreenOf(WidgetTester tester) =>
      tester.widget<RunScreen>(find.byType(RunScreen));

  group('floating deltas on every HUD stat (item 1)', () {
    testWidgets('an EBITDA move floats a lever delta chip + pops',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);

      // No float at rest.
      expect(find.byKey(const Key('leverFloat-ebitda')), findsNothing);

      // Execute the addon (same path as run_screen_test). The engine merge
      // lands AT EXECUTE — so the HUD lever rebuilds with the new EBITDA
      // immediately (under the flash overlay) and its FloatingDeltaBox fires.
      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump(); // EBITDA changed this build
      await tester.pump(const Duration(milliseconds: 50)); // float rising
      expect(find.byKey(const Key('leverFloat-ebitda')), findsOneWidget);

      // It clears after its ~900ms float (well within the flash beat).
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byKey(const Key('leverFloat-ebitda')), findsNothing);
    });

    testWidgets('the four levers each wrap a FloatingDeltaBox', (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);
      // CASH + the four levers = five FloatingDeltaBoxes in the HUD.
      expect(find.byType(FloatingDeltaBox), findsNWidgets(5));
    });
  });

  group('ticket deal-in (item 2)', () {
    testWidgets('a fresh hand deals in, then settles fully visible',
        (tester) async {
      await pumpApp(tester);
      // While the digest covers the stage, dismiss it: the blotter deal-in
      // starts. The DealIn wrappers wrap each ticket.
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30)); // mid deal-in
      expect(find.byType(DealIn), findsWidgets);

      // After the stagger + slide the tickets are present + opaque.
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('ticket-ADD_SW_PLUGIN')), findsOneWidget);
      final op = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byKey(const Key('dealin-ADD_SW_PLUGIN')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(op.opacity, 1.0); // deal-in finished, fully faded in
    });
  });

  group('attract-pulse on the suggested ticket (item 2)', () {
    testWidgets('the first ADD-ON breathes while the blotter is idle',
        (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);

      // The suggested ADD-ON ticket is wrapped in an active AttractPulse.
      final pulses = tester
          .widgetList<AttractPulse>(find.byType(AttractPulse))
          .where((p) => p.active)
          .toList();
      expect(pulses, isNotEmpty,
          reason: 'the suggested deal pulses while idle');

      // Selecting a ticket drops the pulse (the selection glow takes over).
      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump();
      final active = tester
          .widgetList<AttractPulse>(find.byType(AttractPulse))
          .where((p) => p.active);
      expect(active, isEmpty, reason: 'a selection stops the attract-pulse');
    });
  });

  group('MK nameplate stamp on tier-clear (item 3)', () {
    testWidgets('a tier increase stamps MK·I → MK·II', (tester) async {
      await pumpApp(tester);
      await dismissDigest(tester);

      expect(find.byKey(const Key('npMark')), findsOneWidget);
      expect(find.text('MK·I'), findsOneWidget);
      // The closest Transform ancestor of the mark is the stamp's scale.
      double markScale() => tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.byKey(const Key('npMark')),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getMaxScaleOnAxis();

      // At rest the mark is settled (scale 1).
      expect(markScale(), moreOrLessEquals(1.0, epsilon: 0.001));

      // Drive a tier-clear: bump the live tier; the nameplate rebuilds and
      // fires the stamp (shrink → 1.5× overshoot → settle). Sample across the
      // 900ms beat; the scale must leave 1.0 at some frame.
      final c = runScreenOf(tester).controller;
      c.debugSetState(c.state.copyWith(tier: 2));
      await tester.pump(); // schedules the stamp's first tick
      expect(find.text('MK·II'), findsOneWidget); // mark relabeled
      var leftRest = false;
      var sawOvershoot = false;
      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final s = markScale();
        if ((s - 1.0).abs() > 0.05) leftRest = true;
        if (s > 1.2) sawOvershoot = true;
      }
      expect(leftRest, isTrue, reason: 'the mark stamped (left rest scale)');
      expect(sawOvershoot, isTrue, reason: 'the stamp overshoots ~1.5×');

      // It settles back to 1.
      await tester.pump(const Duration(milliseconds: 400));
      expect(markScale(), moreOrLessEquals(1.0, epsilon: 0.001));
    });
  });

  group('CRT screen transition (item 4) — no orphaned controllers', () {
    testWidgets('title → run sweeps and settles clean', (tester) async {
      await tester.pumpWidget(MultiplesApp(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kTestSeed,
      ));
      await tester.pump(const Duration(milliseconds: 400)); // boot → title
      expect(find.byKey(const Key('newRun')), findsOneWidget);

      await tester.tap(find.byKey(const Key('newRun')));
      await tester.pump(); // sweep starts
      await tester.pump(const Duration(milliseconds: 150)); // mid-sweep
      await tester.pump(const Duration(milliseconds: 400)); // settled
      // The run screen is mounted and the title gone (transition disposed
      // the outgoing screen — no leaked ticker fails the test teardown).
      expect(find.byType(RunScreen), findsOneWidget);
      expect(find.byKey(const Key('newRun')), findsNothing);
    });
  });
}
