/// AudioController — the R18 audio system (docs/08 audio manifest).
///
/// A PURE UI-SIDE LISTENER. It computes NOTHING economic: it maps screen /
/// phase moods to a looping BGM channel and engine `GameEvent` types + UI
/// taps to one-shot SFX, per the docs/08 trigger map. All game logic stays
/// in the engine (.claude/rules/flutter-app.md); the controllers/screens
/// call this as thin fire-and-forget hooks.
///
/// TESTABILITY: the real `audioplayers` plugin is held behind the injectable
/// [AudioBackend] / [AudioPlayerHandle] seam, and the settings flags behind
/// [AudioSettingsStore]. Headless tests inject a fake backend that RECORDS
/// calls (no native audio is ever played) and an in-memory settings store.
/// Production wires [AudioplayersBackend] + [SharedPrefsAudioSettingsStore]
/// at boot.
///
/// CHANNELS (docs/08):
///   - ONE looping BGM player, crossfaded ~400ms on a mood change; calling
///     [setMood] with the live mood is a no-op (the loop is never restarted).
///   - A small POOL of SFX players (round-robin) so overlapping one-shots
///     don't cut each other.
///   - DUCKING: the BGM dips to ~40% for ~700ms under the arbitrage,
///     tier-clear and bankruptcy stingers, then restores.
library;

import 'dart:async';

/// The five BGM moods (docs/08 screen→mood map). Each maps to one looping
/// asset; the active screen/phase picks the mood.
enum AudioMood {
  /// `bgm_title.ogg` — S0 Title + S9 Desk (moody, driving, inviting).
  title,

  /// `bgm_act.ogg` — S3 ACT + S2 digest + S5 shop (the main gameplay loop).
  act,

  /// `bgm_tension.ogg` — S7 deadline when BEHIND pace / final round.
  tension,

  /// `bgm_autopsy.ogg` — S8 Autopsy (somber dirge, no payoff).
  autopsy,

  /// `bgm_victory.ogg` — S10 Victory (triumphant fanfare loop).
  victory,
}

/// The asset path (under assets/) for a BGM mood's looping track.
String bgmAsset(AudioMood mood) => switch (mood) {
      AudioMood.title => 'audio/bgm_title.ogg',
      AudioMood.act => 'audio/bgm_act.ogg',
      AudioMood.tension => 'audio/bgm_tension.ogg',
      AudioMood.autopsy => 'audio/bgm_autopsy.ogg',
      AudioMood.victory => 'audio/bgm_victory.ogg',
    };

/// The 13 one-shot SFX (docs/08 trigger table).
enum Sfx {
  /// `sfx_key.ogg` — any chunky-key press (END TURN, ADVANCE, CONTINUE…).
  key,

  /// `sfx_select.ogg` — ticket / card / venture tap-select.
  select,

  /// `sfx_ticket.ogg` — new hand dealt (shuffle).
  ticket,

  /// `sfx_napkin.ogg` — napkin overlay opens (dot-matrix chatter).
  napkin,

  /// `sfx_reroll.ogg` — REROLL (hand or shop).
  reroll,

  /// `sfx_partner.ogg` — HirePartner committed.
  partner,

  /// `sfx_raise.ogg` — RaiseEquity committed (dilution motif).
  raise,

  /// `sfx_nw_surge.ogg` — THE NET-WORTH SURGE (rising arpeggio + bell).
  nwSurge,

  /// `sfx_arbitrage.ogg` — MULTIPLE_ARBITRAGE flash (sweep + chord stab).
  arbitrage,

  /// `sfx_exit_cash.ogg` — EXIT realized (paper→cash collapse).
  exitCash,

  /// `sfx_tier_clear.ogg` — TIER_CLEARED (triumphant stinger).
  tierClear,

  /// `sfx_bankruptcy.ogg` — BANKRUPTCY death (descending drone + dial-tone).
  bankruptcy,

  /// `sfx_error.ogg` — ACTION_REJECTED (buzzer).
  error,
}

/// The asset path (under assets/) for a one-shot SFX.
String sfxAsset(Sfx sfx) => switch (sfx) {
      Sfx.key => 'audio/sfx_key.ogg',
      Sfx.select => 'audio/sfx_select.ogg',
      Sfx.ticket => 'audio/sfx_ticket.ogg',
      Sfx.napkin => 'audio/sfx_napkin.ogg',
      Sfx.reroll => 'audio/sfx_reroll.ogg',
      Sfx.partner => 'audio/sfx_partner.ogg',
      Sfx.raise => 'audio/sfx_raise.ogg',
      Sfx.nwSurge => 'audio/sfx_nw_surge.ogg',
      Sfx.arbitrage => 'audio/sfx_arbitrage.ogg',
      Sfx.exitCash => 'audio/sfx_exit_cash.ogg',
      Sfx.tierClear => 'audio/sfx_tier_clear.ogg',
      Sfx.bankruptcy => 'audio/sfx_bankruptcy.ogg',
      Sfx.error => 'audio/sfx_error.ogg',
    };

/// Maps engine [GameEventType]-equivalent keys to their SFX (docs/08 trigger
/// table). Pure + render-only — the caller passes the event's type NAME so
/// audio.dart stays engine-import-free (no economic coupling). Returns null
/// for event types that carry no sound. The recognized keys mirror the
/// engine enum's `.name`s:
///   multipleArbitrage → arbitrage, exitRealized → exitCash,
///   tierCleared/endlessAnteCleared → tierClear, bankruptcy/missedDeadline
///   → bankruptcy, actionRejected → error, won → tierClear (the victory
///   stinger lands as the screen swaps to the victory BGM).
Sfx? sfxForEventName(String eventTypeName) => switch (eventTypeName) {
      'multipleArbitrage' => Sfx.arbitrage,
      'exitRealized' => Sfx.exitCash,
      'tierCleared' => Sfx.tierClear,
      'endlessAnteCleared' => Sfx.tierClear,
      'won' => Sfx.tierClear,
      'bankruptcy' => Sfx.bankruptcy,
      'missedDeadline' => Sfx.bankruptcy,
      'actionRejected' => Sfx.error,
      'dilution' => Sfx.raise,
      _ => null,
    };

/// The stingers that DUCK the BGM (docs/08 ducking rule): arbitrage,
/// tier-clear, bankruptcy.
bool sfxDucks(Sfx sfx) =>
    sfx == Sfx.arbitrage ||
    sfx == Sfx.tierClear ||
    sfx == Sfx.bankruptcy;

// ---------------------------------------------------------------------------
// The injectable BACKEND seam (so headless tests record calls).
// ---------------------------------------------------------------------------

/// One audio channel: the thin slice of `audioplayers.AudioPlayer` the
/// controller drives. Production wraps a real player; tests record calls.
abstract class AudioPlayerHandle {
  /// Sets volume (0..1). Used for mute, ducking and crossfade ramps.
  Future<void> setVolume(double volume);

  /// Starts a one-shot of [assetPath] (relative to assets/). Looping is
  /// configured separately by [setLoop] before the BGM's first play.
  Future<void> play(String assetPath, {double volume});

  /// Configures whether this channel loops (BGM) or releases (SFX).
  Future<void> setLoop(bool loop);

  /// Stops playback (the BGM channel on mood teardown).
  Future<void> stop();

  /// Pauses (lifecycle background).
  Future<void> pause();

  /// Resumes (lifecycle foreground).
  Future<void> resume();

  /// Releases native resources.
  Future<void> dispose();
}

/// Builds channels. Production = one real `audioplayers` player per call;
/// tests = a recording fake.
abstract class AudioBackend {
  /// Creates one channel.
  AudioPlayerHandle createPlayer();
}

// ---------------------------------------------------------------------------
// Settings flags + their persistence seam (R18 wires; R20 surfaces the UI).
// ---------------------------------------------------------------------------

/// The three audio toggles (docs/08), all default ON. Master mute silences
/// everything; music/sfx gate their channel. Immutable value type.
class AudioSettings {
  /// Builds settings (all default ON).
  const AudioSettings({
    this.masterMuted = false,
    this.musicOn = true,
    this.sfxOn = true,
  });

  /// Master mute: when true, NOTHING plays (BGM + SFX both silent).
  final bool masterMuted;

  /// Music channel on/off.
  final bool musicOn;

  /// SFX channel on/off.
  final bool sfxOn;

  /// True when the BGM channel should be audible.
  bool get bgmAudible => !masterMuted && musicOn;

  /// True when SFX should play.
  bool get sfxAudible => !masterMuted && sfxOn;

  /// Returns a copy with the given fields overridden.
  AudioSettings copyWith({bool? masterMuted, bool? musicOn, bool? sfxOn}) =>
      AudioSettings(
        masterMuted: masterMuted ?? this.masterMuted,
        musicOn: musicOn ?? this.musicOn,
        sfxOn: sfxOn ?? this.sfxOn,
      );
}

/// Loads/saves the [AudioSettings] flags. The PERSISTENCE SEAM R20 reuses:
/// R20's settings SCREEN just toggles [AudioController] flags, which flow
/// back through this store. Production = [SharedPrefsAudioSettingsStore];
/// tests = [InMemoryAudioSettingsStore].
abstract class AudioSettingsStore {
  /// Reads the persisted flags (defaults all-ON on a fresh install).
  Future<AudioSettings> load();

  /// Persists the flags (fire-and-forget from the controller's setters).
  Future<void> save(AudioSettings settings);
}

/// An in-memory store (tests + a null-store fallback). Holds the last saved
/// value; defaults all-ON.
class InMemoryAudioSettingsStore implements AudioSettingsStore {
  /// Builds the store seeded with [initial] (default all-ON).
  InMemoryAudioSettingsStore([this._current = const AudioSettings()]);

  AudioSettings _current;

  @override
  Future<AudioSettings> load() async => _current;

  @override
  Future<void> save(AudioSettings settings) async {
    _current = settings;
  }
}

// ---------------------------------------------------------------------------
// AudioController — the BGM channel + SFX pool + ducking/crossfade.
// ---------------------------------------------------------------------------

/// The R18 audio controller (library header = the full contract). Holds one
/// looping BGM channel and a small SFX pool over an injected [AudioBackend],
/// reads/writes the [AudioSettings] toggles through an [AudioSettingsStore],
/// and exposes the docs/08 [setMood] / [play] API the screens hook.
class AudioController {
  /// Builds the controller over [backend] (one BGM channel + [sfxPoolSize]
  /// SFX channels) and [settingsStore] (defaults to an in-memory all-ON
  /// store). [bgmVolume] is the full (un-ducked, un-muted) BGM level.
  /// Call [load] once after construction to hydrate the persisted flags.
  AudioController({
    required AudioBackend backend,
    AudioSettingsStore? settingsStore,
    AudioSettings initialSettings = const AudioSettings(),
    int sfxPoolSize = 4,
    this.bgmVolume = 0.55,
    this.duckedVolume = 0.40,
    this.crossfadeMs = 400,
    this.duckMs = 700,
    this.crossfadeSteps = 8,
  })  : _settingsStore = settingsStore ?? InMemoryAudioSettingsStore(),
        _settings = initialSettings {
    _bgm = backend.createPlayer();
    _bgm.setLoop(true);
    for (var i = 0; i < sfxPoolSize; i++) {
      final p = backend.createPlayer();
      p.setLoop(false);
      _sfxPool.add(p);
    }
  }

  final AudioSettingsStore _settingsStore;

  /// Full BGM volume (un-ducked, un-muted).
  final double bgmVolume;

  /// The ducked BGM level (~40% of full per docs/08).
  final double duckedVolume;

  /// Crossfade duration (ms) on a mood change (~400 per docs/08).
  final int crossfadeMs;

  /// Duck hold duration (ms) under a stinger (~700 per docs/08).
  final int duckMs;

  /// How many discrete volume steps a crossfade/duck ramp uses.
  final int crossfadeSteps;

  late final AudioPlayerHandle _bgm;
  final List<AudioPlayerHandle> _sfxPool = [];
  int _sfxCursor = 0;

  AudioSettings _settings;

  /// The live settings flags (the R20 screen reads these).
  AudioSettings get settings => _settings;

  /// The currently playing BGM mood (null before the first [setMood]).
  AudioMood? get mood => _mood;
  AudioMood? _mood;

  bool _ducked = false;
  bool _paused = false;
  Timer? _duckTimer;
  // A monotonically rising token cancels stale crossfade/duck ramps when a
  // newer one supersedes them (so an in-flight fade never fights the latest).
  int _rampToken = 0;

  /// Hydrates the persisted flags (call once at boot). On a fresh install
  /// this returns the all-ON default.
  Future<void> load() async {
    _settings = await _settingsStore.load();
  }

  // --- settings setters (R20's screen drives these; persisted here) ---

  /// Toggles master mute (silences both channels) and re-applies it live.
  Future<void> setMasterMuted(bool muted) =>
      _applySettings(_settings.copyWith(masterMuted: muted));

  /// Toggles the music channel; a now-inaudible BGM is silenced/restored.
  Future<void> setMusicOn(bool on) =>
      _applySettings(_settings.copyWith(musicOn: on));

  /// Toggles the SFX channel.
  Future<void> setSfxOn(bool on) =>
      _applySettings(_settings.copyWith(sfxOn: on));

  Future<void> _applySettings(AudioSettings next) async {
    _settings = next;
    // Re-apply to the live BGM channel immediately (mute = volume 0).
    await _bgm.setVolume(_targetBgmVolume());
    unawaited(_settingsStore.save(next));
  }

  /// The BGM channel's CURRENT target volume given mute/duck/pause state.
  double _targetBgmVolume() {
    if (!_settings.bgmAudible || _paused) return 0;
    return _ducked ? duckedVolume : bgmVolume;
  }

  // --- BGM (docs/08: looping, crossfade ~400ms, no-op on the live mood) ---

  /// Sets the looping BGM mood. A change CROSSFADES (~[crossfadeMs]) from the
  /// live loop to the new one; calling with the CURRENT mood is a NO-OP — the
  /// loop is never restarted. A muted/music-off channel still tracks the mood
  /// (so unmuting resumes the right track) but plays at volume 0.
  Future<void> setMood(AudioMood next) async {
    if (_mood == next) return; // dedupe — never restart the live loop
    _mood = next;
    final token = ++_rampToken;
    // Crossfade: fade the old loop down, swap the source, fade the new up.
    // The BGM is a single channel (one looping player), so the "crossfade"
    // is a quick down-ramp → source swap → up-ramp; inaudible channels skip
    // straight to the swap at volume 0.
    final target = _targetBgmVolume();
    if (_settings.bgmAudible && !_paused) {
      await _ramp(_bgm, from: target, to: 0, token: token);
      if (token != _rampToken) return; // superseded mid-fade
    }
    await _bgm.stop();
    await _bgm.play(bgmAsset(next), volume: 0);
    if (token != _rampToken) return;
    await _ramp(_bgm, from: 0, to: _targetBgmVolume(), token: token);
  }

  /// Ramps [player] from→to over [crossfadeMs] in [crossfadeSteps] steps,
  /// bailing if a newer ramp ([token] stale) supersedes this one.
  Future<void> _ramp(
    AudioPlayerHandle player, {
    required double from,
    required double to,
    required int token,
  }) async {
    final steps = crossfadeSteps;
    final stepMs = (crossfadeMs / steps).round();
    for (var i = 1; i <= steps; i++) {
      if (token != _rampToken) return;
      final v = from + (to - from) * (i / steps);
      await player.setVolume(v);
      if (i < steps) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }
  }

  // --- SFX (docs/08: fire-and-forget one-shots from a round-robin pool) ---

  /// Fires a one-shot [sfx] from the next pool channel (round-robin so
  /// overlapping one-shots don't cut each other). A no-op when SFX are
  /// muted/off. Ducking stingers (arbitrage/tier-clear/bankruptcy) dip the
  /// BGM to ~40% for ~[duckMs] then restore.
  Future<void> play(Sfx sfx) async {
    if (!_settings.sfxAudible) return;
    if (sfxDucks(sfx)) _duck();
    final player = _sfxPool[_sfxCursor];
    _sfxCursor = (_sfxCursor + 1) % _sfxPool.length;
    await player.play(sfxAsset(sfx), volume: 1);
  }

  // --- DUCKING (docs/08: BGM → ~40% for ~700ms under stingers) ---

  void _duck() {
    _ducked = true;
    // Dip now (respecting mute/pause), hold, then ALWAYS restore. Ducking is
    // deliberately INDEPENDENT of the crossfade [_rampToken]: a stinger must
    // not cancel an in-flight mood crossfade, and the restore must fire even
    // if a crossfade or a second duck happened in between. Gating the restore
    // on the token (the old behaviour) could strand the BGM permanently dipped
    // or silent — the "randomly goes quiet" bug.
    unawaited(_bgm.setVolume(_targetBgmVolume()));
    _duckTimer?.cancel();
    _duckTimer = Timer(Duration(milliseconds: duckMs), () {
      _ducked = false;
      unawaited(_bgm.setVolume(_targetBgmVolume()));
    });
  }

  // --- lifecycle (main.dart's WidgetsBindingObserver) ---

  /// Pauses the BGM (AppLifecycleState.paused/inactive).
  Future<void> pause() async {
    _paused = true;
    await _bgm.pause();
  }

  /// Resumes the BGM (AppLifecycleState.resumed) at its live target volume.
  Future<void> resume() async {
    _paused = false;
    await _bgm.setVolume(_targetBgmVolume());
    if (_mood != null) await _bgm.resume();
  }

  /// Releases all channels.
  Future<void> dispose() async {
    _duckTimer?.cancel();
    await _bgm.dispose();
    for (final p in _sfxPool) {
      await p.dispose();
    }
  }
}
