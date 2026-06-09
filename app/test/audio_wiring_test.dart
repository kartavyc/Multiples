// R18 audio WIRING tests (docs/08): the run screen routes engine events +
// UI taps to the right AudioController calls. Driven through the REAL screens
// with a REAL AudioController over a FAKE backend (the fake records every
// channel call; no native audio plays). Seed 2's stream facts are the same
// the run_screen_test header pins.

import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/audio.dart';
import 'package:multiples_app/main.dart';

import 'audio_fakes.dart';

const int kTestSeed = 2;

void main() {
  final cardsJson = File('assets/data/cards.json').readAsStringSync();
  final economyJson =
      File('assets/data/economy-model.json').readAsStringSync();

  // A controller over the recording fake; near-instant ramps so the widget
  // pumps don't wait on real crossfade delays.
  ({AudioController audio, FakeBackend backend}) newAudio() {
    final backend = FakeBackend();
    final audio = AudioController(
      backend: backend,
      crossfadeMs: 4,
      crossfadeSteps: 1,
      duckMs: 20,
    );
    return (audio: audio, backend: backend);
  }

  Future<FakeBackend> pumpToAct(WidgetTester tester) async {
    final a = newAudio();
    await tester.pumpWidget(MultiplesApp(
      cardsJson: cardsJson,
      economyJson: economyJson,
      seed: kTestSeed,
      audio: a.audio,
    ));
    // Title → NEW RUN mounts the run screen; initState auto-runs OPERATE +
    // opens the digest. Let the post-frame mood callbacks fire.
    await tester.tap(find.byKey(const Key('newRun')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return a.backend;
  }

  group('BGM mood follows the screen (docs/08 screen→mood)', () {
    testWidgets('title rides the title loop; the run screen swaps to act',
        (tester) async {
      final a = newAudio();
      await tester.pumpWidget(MultiplesApp(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kTestSeed,
        audio: a.audio,
      ));
      await tester.pump(const Duration(milliseconds: 20)); // title mood
      expect(a.audio.mood, AudioMood.title);

      await tester.tap(find.byKey(const Key('newRun')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      // The run screen's OPERATE/ACT phase rides the act loop.
      expect(a.audio.mood, AudioMood.act);
      expect(a.backend.bgm.lastAsset, 'audio/bgm_act.ogg');
    });
  });

  group('event → SFX routing', () {
    testWidgets('the opening hand rings sfx_ticket', (tester) async {
      final backend = await pumpToAct(tester);
      expect(backend.playedSfx('audio/sfx_ticket.ogg'), isTrue);
    });

    testWidgets('CONTINUE (digest) thunks sfx_key', (tester) async {
      final backend = await pumpToAct(tester);
      // Clear the opening churn, then dismiss the digest.
      for (final p in backend.players) {
        p.calls.clear();
      }
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pump();
      expect(backend.playedSfx('audio/sfx_key.ogg'), isTrue);
    });

    testWidgets('a ticket tap rings sfx_select then opens the napkin',
        (tester) async {
      final backend = await pumpToAct(tester);
      await tester.tap(find.byKey(const Key('continue'))); // → ACT
      await tester.pump();
      for (final p in backend.players) {
        p.calls.clear();
      }
      // Single venture at T1 → the ticket auto-targets and opens the napkin.
      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(backend.playedSfx('audio/sfx_select.ogg'), isTrue);
      expect(backend.playedSfx('audio/sfx_napkin.ogg'), isTrue);
    });

    testWidgets(
        'an ADD-ON EXECUTE fires sfx_arbitrage (ducks) + sfx_nw_surge',
        (tester) async {
      final backend = await pumpToAct(tester);
      await tester.tap(find.byKey(const Key('continue'))); // → ACT
      await tester.pump();
      await tester.tap(find.byKey(const Key('ticket-ADD_SW_PLUGIN')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final p in backend.players) {
        p.calls.clear();
      }
      // EXECUTE → MULTIPLE_ARBITRAGE event → sfx_arbitrage (ducking).
      await tester.tap(find.byKey(const Key('execute')));
      await tester.pump();
      expect(backend.playedSfx('audio/sfx_arbitrage.ogg'), isTrue);
      // The ducking dipped the BGM to ~40%.
      expect(backend.bgm.volume, closeTo(0.40, 0.001));

      // The flash takeover owns the first beat; BOOK IT releases the
      // deferred net-worth surge (sfx_nw_surge).
      await tester.pump(const Duration(milliseconds: 2600));
      for (final p in backend.players) {
        p.calls.clear();
      }
      await tester.tap(find.byKey(const Key('bookIt')));
      await tester.pump();
      expect(backend.playedSfx('audio/sfx_nw_surge.ogg'), isTrue);
      // Let the duck timer + surge beat drain (no leaked timers).
      await tester.pump(const Duration(milliseconds: 1800));
    });

    testWidgets('END TURN thunks sfx_key', (tester) async {
      final backend = await pumpToAct(tester);
      await tester.tap(find.byKey(const Key('continue'))); // → ACT
      await tester.pump();
      for (final p in backend.players) {
        p.calls.clear();
      }
      await tester.tap(find.byKey(const Key('endTurn')));
      await tester.pump();
      expect(backend.playedSfx('audio/sfx_key.ogg'), isTrue);
    });
  });
}
