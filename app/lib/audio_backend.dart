/// Production wiring for the R18 audio system: the real `audioplayers`
/// backend + the `shared_preferences` settings store. Kept in a SEPARATE
/// file from audio.dart so the controller + its seams stay plugin-free and
/// the unit tests never link the native plugin.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio.dart';
import 'settings.dart';

/// Wraps one `audioplayers.AudioPlayer` as an [AudioPlayerHandle]. All calls
/// are guarded — a plugin error on one channel must never crash the game
/// (audio is non-essential), so failures are logged and swallowed.
class _AudioplayersHandle implements AudioPlayerHandle {
  _AudioplayersHandle() : _player = AudioPlayer() {
    // Low-latency mode suits short SFX; the BGM loop overrides ReleaseMode
    // via setLoop. Errors here are non-fatal.
    _player.setPlayerMode(PlayerMode.lowLatency);
  }

  final AudioPlayer _player;

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e, st) {
      debugPrint('audio channel op failed: $e\n$st');
    }
  }

  @override
  Future<void> setVolume(double volume) =>
      _guard(() => _player.setVolume(volume.clamp(0.0, 1.0)));

  @override
  Future<void> play(String assetPath, {double volume = 1.0}) => _guard(() async {
        await _player.setVolume(volume.clamp(0.0, 1.0));
        await _player.play(AssetSource(assetPath));
      });

  @override
  Future<void> setLoop(bool loop) => _guard(() async {
        await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
        // A looping BGM channel MUST use mediaPlayer mode: lowLatency does not
        // loop reliably (notably on web), so once a track ended the music went
        // silent — the "randomly goes quiet" bug. One-shot SFX keep lowLatency
        // for snappy, overlap-friendly playback.
        await _player.setPlayerMode(
            loop ? PlayerMode.mediaPlayer : PlayerMode.lowLatency);
      });

  @override
  Future<void> stop() => _guard(_player.stop);

  @override
  Future<void> pause() => _guard(_player.pause);

  @override
  Future<void> resume() => _guard(_player.resume);

  @override
  Future<void> dispose() => _guard(_player.dispose);
}

/// The production backend: one real `audioplayers` player per channel.
class AudioplayersBackend implements AudioBackend {
  /// Builds the backend.
  const AudioplayersBackend();

  @override
  AudioPlayerHandle createPlayer() => _AudioplayersHandle();
}

/// Persists the [AudioSettings] flags in `shared_preferences`. Keys are
/// namespaced `audio.*`; absent keys default ON (a fresh install plays
/// everything). R20's settings screen drives the same flags through the
/// [AudioController]; this store is where they land on disk.
class SharedPrefsAudioSettingsStore implements AudioSettingsStore {
  /// Builds the store.
  const SharedPrefsAudioSettingsStore();

  static const String _kMaster = 'audio.masterMuted';
  static const String _kMusic = 'audio.musicOn';
  static const String _kSfx = 'audio.sfxOn';

  @override
  Future<AudioSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AudioSettings(
        masterMuted: prefs.getBool(_kMaster) ?? false,
        musicOn: prefs.getBool(_kMusic) ?? true,
        sfxOn: prefs.getBool(_kSfx) ?? true,
      );
    } catch (e) {
      debugPrint('audio settings load failed: $e — defaulting all ON');
      return const AudioSettings();
    }
  }

  @override
  Future<void> save(AudioSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMaster, settings.masterMuted);
      await prefs.setBool(_kMusic, settings.musicOn);
      await prefs.setBool(_kSfx, settings.sfxOn);
    } catch (e) {
      debugPrint('audio settings save failed: $e');
    }
  }
}

/// Persists the [AppSettings] preference flags (haptics / tutorial-seen) in
/// `shared_preferences`. Keys are namespaced `app.*`; absent keys default to
/// the fresh-install values (haptics ON, tutorial unseen). The R20 SETTINGS
/// screen drives these through the [AppSettingsController]; this store is
/// where they land on disk.
class SharedPrefsAppSettingsStore implements AppSettingsStore {
  /// Builds the store.
  const SharedPrefsAppSettingsStore();

  static const String _kHaptics = 'app.hapticsOn';
  static const String _kTutorialSeen = 'app.tutorialSeen';

  @override
  Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppSettings(
        hapticsOn: prefs.getBool(_kHaptics) ?? true,
        tutorialSeen: prefs.getBool(_kTutorialSeen) ?? false,
      );
    } catch (e) {
      debugPrint('app settings load failed: $e — defaulting fresh');
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHaptics, settings.hapticsOn);
      await prefs.setBool(_kTutorialSeen, settings.tutorialSeen);
    } catch (e) {
      debugPrint('app settings save failed: $e');
    }
  }
}
