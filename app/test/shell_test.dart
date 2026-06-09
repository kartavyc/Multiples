// Shell-level tests (R14 #7): CONTINUE-gating on the title, the victory
// RUNS-TO-GET-HERE meta stat, and the venture-name render (not "V1").
//
// The CONTINUE slot is tested at the TitleScreen widget level (the resume
// descriptor in / out), and the boot's loadRun that DECIDES it is proven in
// save_store_test — separating the render from the flaky real-I/O boot
// bridging. The venture-name test mounts a STORE-LESS app (instant boot, no
// autosave I/O). No pumpAndSettle (the terminal idles animate forever).

import 'dart:io';

import 'package:engine/model.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/controller.dart';
import 'package:multiples_app/main.dart';
import 'package:multiples_app/screens/title_screen.dart';
import 'package:multiples_app/screens/victory_screen.dart';
import 'package:multiples_app/widgets/juice.dart';

const int kSeed = 2;

void main() {
  final cardsJson = File('assets/data/cards.json').readAsStringSync();
  final economyJson =
      File('assets/data/economy-model.json').readAsStringSync();

  // A STORE-LESS app: boot is instant (no real I/O), no autosave timers.
  Widget noStoreApp() => MultiplesApp(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kSeed,
      );

  group('title CONTINUE appears only with a resumable save', () {
    testWidgets('no resume -> NEW RUN + THE DESK, no CONTINUE',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TitleScreen(
          seedTag: '4F2A',
          onNewRun: () {},
          onDesk: () {},
          // No resume: the boot's loadRun found nothing (proven in
          // save_store_test), so the shell passes onContinue: null.
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('newRun')), findsOneWidget);
      expect(find.byKey(const Key('theDesk')), findsOneWidget);
      expect(find.byKey(const Key('continue')), findsNothing);
    });

    testWidgets('a resume -> CONTINUE shows with the T·R·# slot',
        (tester) async {
      var continued = false;
      await tester.pumpWidget(MaterialApp(
        home: TitleScreen(
          seedTag: '4F2A',
          onNewRun: () {},
          onDesk: () {},
          // With a resumable run the shell supplies the descriptor + handler
          // (the label it builds from RunLoadResult.state, see main.dart).
          resumeLabel: 'T2 · R3 · #4F2A',
          onContinue: () => continued = true,
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('continue')), findsOneWidget);
      final sub = tester.widget<Text>(find.byKey(const Key('continueSub')));
      expect(sub.data, 'T2 · R3 · #4F2A');
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pump();
      expect(continued, isTrue);
    });
  });

  group('victory shows RUNS TO GET HERE off meta', () {
    testWidgets('the RUNS stat reads meta.runsPlayed', (tester) async {
      final c = GameController(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kSeed,
        meta: MetaState(runsPlayed: 14),
      );
      addTearDown(c.dispose);
      // Park a won terminal state through the test hook (the engine declares
      // the win in real play; the screen just reads the state + meta).
      c.debugSetState(c.state.copyWith(
        won: true,
        phase: PhaseId.runOver,
        tier: 4,
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VictoryScreen(
            controller: c,
            onNewRun: () {},
            shake: ShakeController(),
          ),
        ),
      ));
      await tester.pump();
      final runs =
          tester.widget<Text>(find.byKey(const Key('runsToGetHere')));
      expect(runs.data, '14');
    });
  });

  group('venture names render (not the raw V1 id)', () {
    testWidgets('the holdings rail shows the seed venture display name',
        (tester) async {
      // Store-less: NEW RUN runs the first OPERATE with no autosave I/O.
      await tester.pumpWidget(noStoreApp());
      await tester.pump();
      await tester.tap(find.byKey(const Key('newRun')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // The first OPERATE auto-ran -> YEAR PASSED digest; its CONTINUE lands
      // ACT (the holdings rail shows there).
      if (find.byKey(const Key('continue')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('continue')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }
      final name = GameController(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kSeed,
      ).state.ventures.first.displayName;
      expect(name, isNot('V1'));
      expect(find.text(name), findsWidgets);
      expect(find.text('V1'), findsNothing);
    });
  });
}
