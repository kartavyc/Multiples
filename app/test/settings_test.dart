// R20 SETTINGS tests: the AppSettingsController persists + drives the haptics
// gate; the SETTINGS screen toggles drive the AudioController setters (which
// persist through the audio settings store) and the haptics flag; and
// haptics-OFF suppresses the safeHaptic* sink. All headless (in-memory stores,
// a fake audio backend, a recording haptic sink) — no plugins, no native audio.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/audio.dart';
import 'package:multiples_app/screens/settings_screen.dart';
import 'package:multiples_app/settings.dart';
import 'package:multiples_app/widgets/juice.dart';

import 'audio_fakes.dart';

void main() {
  group('AppSettingsController (persist + the haptics gate)', () {
    test('load hydrates flags + pushes the haptics gate', () async {
      final store =
          InMemoryAppSettingsStore(const AppSettings(hapticsOn: false));
      final c = AppSettingsController(store: store);
      await c.load();
      expect(c.hapticsOn, isFalse);
      expect(hapticsEnabledForTest, isFalse);
      addTearDown(() => setHapticsEnabledGate(true));
      addTearDown(c.dispose);
    });

    test('setHapticsOn persists + re-applies the gate live', () async {
      final store = InMemoryAppSettingsStore();
      final c = AppSettingsController(store: store);
      addTearDown(c.dispose);
      addTearDown(() => setHapticsEnabledGate(true));
      await c.setHapticsOn(false);
      expect(c.hapticsOn, isFalse);
      expect(hapticsEnabledForTest, isFalse);
      // Persisted: a fresh controller over the same store reads it back.
      final reload = AppSettingsController(store: store);
      addTearDown(reload.dispose);
      await reload.load();
      expect(reload.hapticsOn, isFalse);
    });

    test('replayTutorial clears the seen flag (persisted)', () async {
      final store =
          InMemoryAppSettingsStore(const AppSettings(tutorialSeen: true));
      final c = AppSettingsController(store: store);
      addTearDown(c.dispose);
      await c.load();
      expect(c.tutorialSeen, isTrue);
      await c.replayTutorial();
      expect(c.tutorialSeen, isFalse);
      final reload = AppSettingsController(store: store);
      addTearDown(reload.dispose);
      await reload.load();
      expect(reload.tutorialSeen, isFalse);
    });
  });

  group('haptics-off suppresses the device-vibration sink', () {
    test('the sink fires when ON, is silent when OFF', () {
      final fired = <String>[];
      setHapticSinkForTest(fired.add);
      addTearDown(() => setHapticSinkForTest(null));
      addTearDown(() => setHapticsEnabledGate(true));

      setHapticsEnabledGate(true);
      safeHapticHeavy();
      safeHapticLight();
      expect(fired, ['heavy', 'light']);

      fired.clear();
      setHapticsEnabledGate(false);
      safeHapticHeavy();
      safeHapticLight();
      expect(fired, isEmpty, reason: 'haptics OFF => no sink call');
    });
  });

  group('SETTINGS screen (toggles drive the audio setters + persist)', () {
    ({AudioController audio, FakeBackend backend}) newAudio() {
      final backend = FakeBackend();
      final audio = AudioController(
        backend: backend,
        crossfadeMs: 4,
        crossfadeSteps: 1,
      );
      return (audio: audio, backend: backend);
    }

    Future<void> pumpSettings(
      WidgetTester tester, {
      required AudioController audio,
      required AppSettingsController settings,
      Future<void> Function()? onWipeSave,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          audio: audio,
          settings: settings,
          onBack: () {},
          onWipeSave: onWipeSave,
        ),
      ));
      await tester.pump();
    }

    testWidgets('MUSIC toggle flips the AudioController flag + persists',
        (tester) async {
      final a = newAudio();
      addTearDown(a.audio.dispose);
      final store = InMemoryAppSettingsStore();
      final settings = AppSettingsController(store: store);
      addTearDown(settings.dispose);
      addTearDown(() => setHapticsEnabledGate(true));

      await pumpSettings(tester, audio: a.audio, settings: settings);
      expect(a.audio.settings.musicOn, isTrue);

      await tester.tap(find.byKey(const Key('toggleMusic')));
      await tester.pump();
      expect(a.audio.settings.musicOn, isFalse);

      await tester.tap(find.byKey(const Key('toggleSfx')));
      await tester.pump();
      expect(a.audio.settings.sfxOn, isFalse);

      await tester.tap(find.byKey(const Key('toggleMaster')));
      await tester.pump();
      expect(a.audio.settings.masterMuted, isTrue);
    });

    testWidgets('HAPTICS toggle drives the AppSettingsController + gate',
        (tester) async {
      final a = newAudio();
      addTearDown(a.audio.dispose);
      final settings = AppSettingsController();
      addTearDown(settings.dispose);
      addTearDown(() => setHapticsEnabledGate(true));

      await pumpSettings(tester, audio: a.audio, settings: settings);
      expect(settings.hapticsOn, isTrue);

      await tester.tap(find.byKey(const Key('toggleHaptics')));
      await tester.pump();
      expect(settings.hapticsOn, isFalse);
      expect(hapticsEnabledForTest, isFalse);
    });

    testWidgets('REPLAY TUTORIAL clears the seen flag', (tester) async {
      final a = newAudio();
      addTearDown(a.audio.dispose);
      final settings = AppSettingsController(
        initial: const AppSettings(tutorialSeen: true),
      );
      addTearDown(settings.dispose);
      addTearDown(() => setHapticsEnabledGate(true));

      await pumpSettings(tester, audio: a.audio, settings: settings);
      await tester.tap(find.byKey(const Key('replayTutorial')));
      await tester.pump();
      expect(settings.tutorialSeen, isFalse);
    });

    testWidgets('WIPE SAVE confirms then fires the callback', (tester) async {
      final a = newAudio();
      addTearDown(a.audio.dispose);
      final settings = AppSettingsController();
      addTearDown(settings.dispose);
      addTearDown(() => setHapticsEnabledGate(true));
      var wiped = false;

      await pumpSettings(
        tester,
        audio: a.audio,
        settings: settings,
        onWipeSave: () async => wiped = true,
      );

      // First tap arms the confirm (no wipe yet).
      await tester.tap(find.byKey(const Key('wipeSave')));
      await tester.pump();
      expect(wiped, isFalse);
      expect(find.text('ERASE EVERYTHING?'), findsOneWidget);

      // Confirm wipes.
      await tester.tap(find.byKey(const Key('wipeConfirm')));
      await tester.pump();
      expect(wiped, isTrue);
      expect(find.byKey(const Key('wipeDone')), findsOneWidget);
    });
  });
}
