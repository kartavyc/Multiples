/// AppSettings — the R20 player-preference flags + their persistence seam.
///
/// Two flags the engine NEVER sees (pure UX preferences): [hapticsOn]
/// (gates the device-vibration calls in widgets/juice.dart) and
/// [tutorialSeen] (the first-run TUTORIAL fires once, then this latches it
/// off — re-showable from SETTINGS). The audio toggles live in their own
/// [AudioSettings] (audio.dart, R18); this is the rest.
///
/// TESTABILITY: the store is behind [AppSettingsStore] so headless tests use
/// [InMemoryAppSettingsStore] (no plugin); production uses
/// [SharedPrefsAppSettingsStore] (audio_backend.dart wires it at boot,
/// alongside the audio store). All defaults are the "fresh install" values:
/// haptics ON, tutorial NOT yet seen.
library;

import 'package:flutter/foundation.dart';

import 'widgets/juice.dart' show setHapticsEnabledGate;

/// The two preference flags (immutable value type). Defaults = fresh install.
class AppSettings {
  /// Builds the settings (haptics ON, tutorial unseen by default).
  const AppSettings({
    this.hapticsOn = true,
    this.tutorialSeen = false,
  });

  /// Device vibration on/off (gates safeHaptic* in widgets/juice.dart).
  final bool hapticsOn;

  /// True once the first-run tutorial has been completed or skipped. The
  /// tutorial overlay checks this to fire exactly once; SETTINGS "REPLAY
  /// TUTORIAL" flips it back to false.
  final bool tutorialSeen;

  /// Returns a copy with the given fields overridden.
  AppSettings copyWith({bool? hapticsOn, bool? tutorialSeen}) => AppSettings(
        hapticsOn: hapticsOn ?? this.hapticsOn,
        tutorialSeen: tutorialSeen ?? this.tutorialSeen,
      );
}

/// Loads/saves [AppSettings]. Production = [SharedPrefsAppSettingsStore]
/// (audio_backend.dart); tests = [InMemoryAppSettingsStore].
abstract class AppSettingsStore {
  /// Reads the persisted flags (defaults haptics-ON / tutorial-unseen on a
  /// fresh install).
  Future<AppSettings> load();

  /// Persists the flags (fire-and-forget from the controller's setters).
  Future<void> save(AppSettings settings);
}

/// An in-memory store (tests + a null-store fallback). Holds the last saved
/// value; defaults to a fresh install.
class InMemoryAppSettingsStore implements AppSettingsStore {
  /// Builds the store seeded with [initial] (default fresh install).
  InMemoryAppSettingsStore([this._current = const AppSettings()]);

  AppSettings _current;

  @override
  Future<AppSettings> load() async => _current;

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
  }
}

/// The live app-settings holder (a [ChangeNotifier] so the SETTINGS screen
/// rebuilds on a toggle). Hydrates from an [AppSettingsStore] at boot, drives
/// the haptics gate in widgets/juice.dart live on every change, and persists
/// fire-and-forget. The single source of truth for [hapticsOn] /
/// [tutorialSeen] across the app.

class AppSettingsController extends ChangeNotifier {
  /// Builds the controller over [store] (defaults to an in-memory store) and
  /// [initial] flags. Call [load] once after construction to hydrate from
  /// disk; that also pushes the haptics flag into the juice gate.
  AppSettingsController({
    AppSettingsStore? store,
    AppSettings initial = const AppSettings(),
  })  : _store = store ?? InMemoryAppSettingsStore(),
        _settings = initial {
    _applyHaptics();
  }

  final AppSettingsStore _store;
  AppSettings _settings;

  /// The live flags (the SETTINGS screen reads these).
  AppSettings get settings => _settings;

  /// Convenience: device-vibration enabled.
  bool get hapticsOn => _settings.hapticsOn;

  /// Convenience: the first-run tutorial has already been seen.
  bool get tutorialSeen => _settings.tutorialSeen;

  /// Hydrates the persisted flags (call once at boot) and pushes the haptics
  /// flag into the widgets/juice.dart gate. Fresh install -> haptics ON,
  /// tutorial unseen.
  Future<void> load() async {
    _settings = await _store.load();
    _applyHaptics();
    notifyListeners();
  }

  /// Toggles device vibration; re-applies the juice gate live + persists.
  Future<void> setHapticsOn(bool on) =>
      _apply(_settings.copyWith(hapticsOn: on));

  /// Latches the first-run tutorial as seen (it never auto-shows again).
  Future<void> setTutorialSeen(bool seen) =>
      _apply(_settings.copyWith(tutorialSeen: seen));

  /// SETTINGS "REPLAY TUTORIAL": clears the seen flag so the overlay fires on
  /// the next NEW RUN.
  Future<void> replayTutorial() => setTutorialSeen(false);

  Future<void> _apply(AppSettings next) async {
    _settings = next;
    _applyHaptics();
    notifyListeners();
    await _store.save(next);
  }

  void _applyHaptics() => setHapticsEnabledGate(_settings.hapticsOn);
}
