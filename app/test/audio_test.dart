// AudioController unit tests (R18, docs/08): the BGM crossfade + mood
// dedupe, the SFX pool round-robin, mute suppression, the event→sfx map, and
// the ducking restore — all against a FAKE backend that RECORDS calls. No
// native audio is ever played (headless-safe).

import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/audio.dart';

import 'audio_fakes.dart';

/// Builds a controller with near-zero ramp timings so tests don't wait on
/// real crossfade delays (1 step, 0ms duck/crossfade where it helps).
AudioController build(
  FakeBackend backend, {
  AudioSettings initial = const AudioSettings(),
  int sfxPoolSize = 4,
  int duckMs = 700,
}) =>
    AudioController(
      backend: backend,
      settingsStore: InMemoryAudioSettingsStore(initial),
      initialSettings: initial,
      sfxPoolSize: sfxPoolSize,
      crossfadeMs: 8,
      crossfadeSteps: 2,
      duckMs: duckMs,
    );

void main() {
  group('construction', () {
    test('builds one BGM channel + the SFX pool, all-ON default', () async {
      final b = FakeBackend();
      build(b, sfxPoolSize: 4);
      expect(b.players.length, 5); // 1 BGM + 4 SFX
      expect(b.bgm.looping, isTrue); // BGM loops
      expect(b.sfxPool.every((p) => !p.looping), isTrue); // SFX don't
    });
  });

  group('setMood — crossfade + dedupe', () {
    test('first setMood plays the mapped looping asset', () async {
      final b = FakeBackend();
      final c = build(b);
      await c.setMood(AudioMood.act);
      expect(c.mood, AudioMood.act);
      expect(b.bgm.plays.single.arg, 'audio/bgm_act.ogg');
    });

    test('a mood CHANGE crossfades: down-ramp, stop, swap, up-ramp',
        () async {
      final b = FakeBackend();
      final c = build(b);
      await c.setMood(AudioMood.title);
      b.bgm.calls.clear();
      await c.setMood(AudioMood.tension);
      // Stopped the old loop and played the new asset.
      expect(b.bgm.calls.any((x) => x.op == 'stop'), isTrue);
      expect(b.bgm.lastAsset, 'audio/bgm_tension.ogg');
      // Fades down to 0 then up — at least one setVolume(0) then a >0.
      final vols = b.bgm.calls
          .where((x) => x.op == 'setVolume')
          .map((x) => x.value!)
          .toList();
      expect(vols.contains(0.0), isTrue);
      expect(vols.last, greaterThan(0.0));
    });

    test('setMood with the LIVE mood is a no-op (loop never restarts)',
        () async {
      final b = FakeBackend();
      final c = build(b);
      await c.setMood(AudioMood.victory);
      final playCount = b.bgm.plays.length;
      b.bgm.calls.clear();
      await c.setMood(AudioMood.victory); // same mood
      expect(b.bgm.calls, isEmpty); // nothing happened
      expect(playCount, 1);
    });
  });

  group('SFX pool', () {
    test('play maps the SFX to its asset on a pool channel', () async {
      final b = FakeBackend();
      final c = build(b);
      await c.play(Sfx.ticket);
      final fired =
          b.sfxPool.where((p) => p.plays.isNotEmpty).toList();
      expect(fired.single.lastAsset, 'audio/sfx_ticket.ogg');
    });

    test('overlapping one-shots round-robin across channels (no cut)',
        () async {
      final b = FakeBackend();
      final c = build(b, sfxPoolSize: 3);
      await c.play(Sfx.key);
      await c.play(Sfx.select);
      await c.play(Sfx.reroll);
      // Three distinct channels each fired once.
      final firedChannels =
          b.sfxPool.where((p) => p.plays.isNotEmpty).length;
      expect(firedChannels, 3);
    });
  });

  group('mute suppression', () {
    test('masterMuted suppresses SFX entirely', () async {
      final b = FakeBackend();
      final c = build(b, initial: const AudioSettings(masterMuted: true));
      await c.play(Sfx.arbitrage);
      expect(b.sfxPool.every((p) => p.plays.isEmpty), isTrue);
    });

    test('sfxOff suppresses SFX but music stays', () async {
      final b = FakeBackend();
      final c = build(b, initial: const AudioSettings(sfxOn: false));
      await c.play(Sfx.key);
      expect(b.sfxPool.every((p) => p.plays.isEmpty), isTrue);
      // BGM still plays (and at audible volume).
      await c.setMood(AudioMood.act);
      expect(b.bgm.lastAsset, 'audio/bgm_act.ogg');
      expect(b.bgm.volume, greaterThan(0.0));
    });

    test('music off keeps the BGM channel at volume 0', () async {
      final b = FakeBackend();
      final c = build(b, initial: const AudioSettings(musicOn: false));
      await c.setMood(AudioMood.act);
      // The mood is tracked but the channel is silent.
      expect(c.mood, AudioMood.act);
      expect(b.bgm.volume, 0.0);
    });

    test('toggling master mute live re-applies BGM volume', () async {
      final b = FakeBackend();
      final c = build(b);
      await c.setMood(AudioMood.act);
      expect(b.bgm.volume, greaterThan(0.0));
      await c.setMasterMuted(true);
      expect(b.bgm.volume, 0.0);
      await c.setMasterMuted(false);
      expect(b.bgm.volume, greaterThan(0.0));
    });
  });

  group('ducking', () {
    test('a ducking stinger dips the BGM then restores after duckMs',
        () async {
      final b = FakeBackend();
      final c = build(b, duckMs: 30);
      await c.setMood(AudioMood.act);
      final full = b.bgm.volume;
      await c.play(Sfx.arbitrage); // ducks
      expect(b.bgm.volume, lessThan(full));
      expect(b.bgm.volume, closeTo(0.40, 0.001));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(b.bgm.volume, closeTo(full, 0.001)); // restored
    });

    test('a NON-ducking SFX leaves the BGM at full', () async {
      final b = FakeBackend();
      final c = build(b);
      await c.setMood(AudioMood.act);
      final full = b.bgm.volume;
      await c.play(Sfx.select); // does not duck
      expect(b.bgm.volume, full);
    });

    test('the three docs/08 stingers duck, others do not', () {
      expect(sfxDucks(Sfx.arbitrage), isTrue);
      expect(sfxDucks(Sfx.tierClear), isTrue);
      expect(sfxDucks(Sfx.bankruptcy), isTrue);
      expect(sfxDucks(Sfx.nwSurge), isFalse);
      expect(sfxDucks(Sfx.key), isFalse);
    });
  });

  group('lifecycle', () {
    test('pause silences + pauses BGM; resume restores', () async {
      final b = FakeBackend();
      final c = build(b);
      await c.setMood(AudioMood.act);
      final full = b.bgm.volume;
      await c.pause();
      expect(b.bgm.calls.any((x) => x.op == 'pause'), isTrue);
      await c.resume();
      expect(b.bgm.calls.any((x) => x.op == 'resume'), isTrue);
      expect(b.bgm.volume, closeTo(full, 0.001));
    });
  });

  group('settings persistence seam (R20)', () {
    test('a setter writes through to the store', () async {
      final store = InMemoryAudioSettingsStore();
      final c = AudioController(
        backend: FakeBackend(),
        settingsStore: store,
      );
      await c.setSfxOn(false);
      final reloaded = await store.load();
      expect(reloaded.sfxOn, isFalse);
      expect(c.settings.sfxOn, isFalse);
    });

    test('load hydrates persisted flags', () async {
      final store =
          InMemoryAudioSettingsStore(const AudioSettings(masterMuted: true));
      final c = AudioController(backend: FakeBackend(), settingsStore: store);
      await c.load();
      expect(c.settings.masterMuted, isTrue);
    });
  });
}
