// THE DESK (S9) + the background -> run wiring (R14 #3, #7).
//
// DeskScreen is mounted directly with an injected MetaState and a captured
// onStartRun, so these are fast and deterministic. The "VC Darling -> 80%
// own" test then proves the picked background actually flows into initRun via
// a real GameController (the app wiring the work order calls out), not just
// that the callback fired with the id.

import 'dart:io';

import 'package:engine/meta.dart';
import 'package:engine/model.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/controller.dart';
import 'package:multiples_app/screens/desk_screen.dart';

const int kSeed = 2;

void main() {
  final cardsJson = File('assets/data/cards.json').readAsStringSync();
  final economyJson =
      File('assets/data/economy-model.json').readAsStringSync();

  Widget desk(MetaState meta, void Function(String) onStart) => MaterialApp(
        home: DeskScreen(
          meta: meta,
          onStartRun: onStart,
          onBack: () {},
        ),
      );

  group('THE DESK renders the Track Record + the founder picker', () {
    testWidgets('shows level + rep total + the unlocked counts', (tester) async {
      final meta = MetaState(
        reputation: 1820000,
        metaLevel: metaLevelFor(1820000),
        unlockedCards: List.filled(22, 'c'),
      );
      await tester.pumpWidget(desk(meta, (_) {}));
      await tester.pump();

      expect(find.byKey(const Key('desk')), findsOneWidget);
      // TRACK RECORD line carries the level + the formatted rep total.
      final track = tester.widget<Text>(find.byKey(const Key('trackRecord')));
      expect(track.data, contains('Lv ${metaLevelFor(1820000)}'));
      expect(track.data, contains('1,820,000'));
      // UNLOCKED counts off the meta lists vs the display denominators.
      final counts =
          tester.widget<Text>(find.byKey(const Key('unlockedCounts')));
      expect(counts.data, contains('CARDS 22/35'));
      expect(counts.data, contains('SECTORS 4/6'));
    });

    testWidgets('renders every founder background; locked ones are inert',
        (tester) async {
      // Default meta unlocks only BOOTSTRAPPER.
      await tester.pumpWidget(desk(MetaState(), (_) {}));
      await tester.pump();
      for (final bg in kFounderBackgrounds) {
        expect(find.byKey(Key('founder-${bg.id}')), findsOneWidget,
            reason: '${bg.id} card present');
      }
      // BOOTSTRAPPER is unlocked + selectable; a non-default (e.g. VC_DARLING)
      // is locked under the default meta.
      expect(MetaState().unlockedBackgrounds, contains('BOOTSTRAPPER'));
      expect(MetaState().unlockedBackgrounds, isNot(contains('VC_DARLING')));
    });
  });

  group('selecting a background changes the run start', () {
    testWidgets('VC DARLING START RUN -> the new run opens at 80% ownership',
        (tester) async {
      // A meta that has unlocked VC_DARLING so the card is selectable.
      final meta = MetaState(
        unlockedBackgrounds: const ['BOOTSTRAPPER', 'VC_DARLING'],
      );
      String? picked;
      await tester.pumpWidget(desk(meta, (id) => picked = id));
      await tester.pump();

      await tester.tap(find.byKey(const Key('founder-VC_DARLING')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('startRun')));
      await tester.pump();

      expect(picked, 'VC_DARLING');

      // The app hands that id to a fresh controller -> initRun pre-dilutes the
      // seed venture to 80% (8000 bp). This is the visible run-start change.
      final c = GameController(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kSeed,
        backgroundId: picked!,
      );
      addTearDown(c.dispose);
      expect(c.state.ventures.first.ownershipBp, 8000);
      // And BOOTSTRAPPER stays the pinned 100% baseline.
      final b = GameController(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kSeed,
        backgroundId: 'BOOTSTRAPPER',
      );
      addTearDown(b.dispose);
      expect(b.state.ventures.first.ownershipBp, 10000);
    });
  });
}
