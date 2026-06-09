/// MULTIPLES — app entry + the run/meta SHELL (plan tasks 3.1-3.3 + Phase 4
/// save/persistence + S9 Desk meta).
///
/// Responsibilities of THIS file only: load the two bundled content JSON
/// strings at the edge (the engine parses them), open the [SaveStore], boot
/// the durable meta + any resumable run (docs/06), and route between the
/// title / THE DESK / the run screen. All game logic lives in the engine; all
/// skin tokens live in theme.dart (docs/07); all save I/O is the store's.
///
/// SEED (determinism note, .claude/rules): the ENGINE never reads a clock or
/// platform RNG — replay/save depend on its SplitMix64 stream alone. The APP
/// layer owns seed lifecycle and is allowed wall-clock, so a NEW RUN seeds
/// from `DateTime.now().millisecondsSinceEpoch` here; widget tests inject a
/// fixed seed + a temp-dir store through [MultiplesApp].
///
/// BOOT SAFETY (audit L5): the content load is wrapped in try/catch and a
/// failure mounts a terminal-styled ERROR screen instead of a blank crash.
library;

import 'dart:async';

import 'package:engine/content.dart';
import 'package:engine/model.dart';
import 'package:engine/serialize.dart' show RunLoadResult;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'audio.dart';
import 'audio_backend.dart';
import 'controller.dart';
import 'save_store.dart';
import 'screens/desk_screen.dart';
import 'screens/error_screen.dart';
import 'screens/glossary_screen.dart';
import 'screens/run_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/title_screen.dart';
import 'settings.dart';
import 'theme.dart';

/// Bundle key for the cards content asset (byte-identical copy of
/// /data/cards.json; see assets/data/README.md).
const String kCardsAsset = 'assets/data/cards.json';

/// Bundle key for the economy content asset.
const String kEconomyAsset = 'assets/data/economy-model.json';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // BOOT (audit L5): a corrupt/missing content asset must not blank-crash —
  // parse-test it here and mount the terminal ERROR screen on failure.
  String cardsJson;
  String economyJson;
  try {
    cardsJson = await rootBundle.loadString(kCardsAsset);
    economyJson = await rootBundle.loadString(kEconomyAsset);
    // Parse-validate at the edge (the engine throws a clear FormatException on
    // a bad asset); a success here means the run screen can safely load.
    loadCards(cardsJson);
    loadEconomy(economyJson);
  } catch (e, st) {
    debugPrint('MULTIPLES boot failed: $e\n$st');
    runApp(BootErrorApp(message: '$e'));
    return;
  }
  final store = await SaveStore.open();
  // AUDIO (R18, docs/08): build the controller over the real audioplayers
  // backend + the persisted settings store, hydrate the toggles, and hand it
  // to the app. Audio is non-essential — a failure here is swallowed by the
  // backend's guards, never blocking boot.
  final audio = AudioController(
    backend: const AudioplayersBackend(),
    settingsStore: const SharedPrefsAudioSettingsStore(),
  );
  await audio.load();
  // R20: the preference flags (haptics / tutorial-seen), hydrated from the
  // same shared_preferences store. load() also pushes the haptics flag into
  // the juice gate.
  final settings =
      AppSettingsController(store: const SharedPrefsAppSettingsStore());
  await settings.load();
  runApp(MultiplesApp(
    cardsJson: cardsJson,
    economyJson: economyJson,
    store: store,
    audio: audio,
    settings: settings,
  ));
}

/// App root. Takes the two content JSON strings and (optionally) the
/// [SaveStore] by constructor so tests can inject a temp-dir store; `main()`
/// passes the real documents-dir store. The optional [seed] pins NEW RUN's
/// stream in tests.
class MultiplesApp extends StatefulWidget {
  /// Builds the root.
  const MultiplesApp({
    super.key,
    required this.cardsJson,
    required this.economyJson,
    this.store,
    this.seed,
    this.audio,
    this.settings,
  });

  /// Raw cards.json content (engine `loadCards` input).
  final String cardsJson;

  /// Raw economy-model.json content (engine `loadEconomy` input).
  final String economyJson;

  /// The save layer (docs/06); null disables persistence (pure smoke runs).
  final SaveStore? store;

  /// A fixed NEW RUN seed for tests; null = wall-clock (app layer only).
  final int? seed;

  /// The R18 audio controller (docs/08); null in pure widget tests that
  /// don't exercise sound (the shell then runs silent).
  final AudioController? audio;

  /// The R20 preference controller (haptics / tutorial-seen); null in pure
  /// widget tests that don't open SETTINGS or the tutorial (a fresh in-memory
  /// one is then built so the shell still works).
  final AppSettingsController? settings;

  @override
  State<MultiplesApp> createState() => _MultiplesAppState();
}

/// Which top-level screen the shell is showing.
enum _Screen { title, desk, run, settings, glossary }

class _MultiplesAppState extends State<MultiplesApp>
    with WidgetsBindingObserver {
  /// The current screen.
  _Screen _screen = _Screen.title;

  /// The live run controller (built on NEW RUN / START RUN / CONTINUE); null
  /// while on the title/desk with no run in flight.
  GameController? _controller;

  /// The durable Track Record, loaded at boot and refreshed after each run.
  MetaState _meta = MetaState();

  /// The resumable run loaded at boot (docs/06): non-null enables the title
  /// CONTINUE slot. Cleared once consumed (resumed) or superseded.
  RunResumeResult? _resume;

  /// True until the boot meta/run load completes (a brief splash-less gate).
  bool _booting = true;

  /// The screen SETTINGS was opened from (so BACK returns there).
  _Screen _settingsReturn = _Screen.title;

  /// The R20 preference controller — the injected one, or an in-memory
  /// fallback for store-less widget tests. The fallback defaults
  /// tutorialSeen == TRUE so the first-run tutorial does NOT fire in tests
  /// that don't opt in (a test wanting the tutorial injects its own
  /// controller with tutorialSeen: false). Production always injects the real
  /// store-backed controller from main().
  late final AppSettingsController _settings = widget.settings ??
      AppSettingsController(
          initial: const AppSettings(tutorialSeen: true));

  /// Latched true when the next run should run the first-run tutorial: the
  /// player has never seen it. Read once at run start (so flipping the seen
  /// flag mid-run doesn't yank the overlay).
  bool _tutorialPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    // Only dispose the FALLBACK settings controller we created; the injected
    // one is owned by main()/the test.
    if (widget.settings == null) _settings.dispose();
    super.dispose();
  }

  /// docs/06 §4 lifecycle flush: a backgrounded app force-saves the in-flight
  /// run so a swipe-away / phone call never loses the current action.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_controller?.flush());
      // docs/08 lifecycle: pause the BGM when backgrounded.
      unawaited(widget.audio?.pause());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(widget.audio?.resume());
    }
  }

  /// Loads the durable meta + any resumable run (docs/06). A missing store
  /// (pure smoke runs) just defaults to a fresh meta and no resume.
  Future<void> _boot() async {
    final store = widget.store;
    if (store == null) {
      if (mounted) setState(() => _booting = false);
      return;
    }
    final meta = await store.loadMeta();
    final resume = await store.loadRun(
      economy: loadEconomy(widget.economyJson),
      content: loadCards(widget.cardsJson),
      meta: meta,
    );
    if (!mounted) return;
    setState(() {
      _meta = meta;
      _resume = resume.hasRun ? resume : null;
      _booting = false;
    });
  }

  int _newSeed() => widget.seed ?? DateTime.now().millisecondsSinceEpoch;

  /// NEW RUN (title) / START RUN (desk) / RETRY: opens a fresh run posed by
  /// [backgroundId] (the Desk's pick; the title's default Bootstrapper).
  void _startRun(String backgroundId, {bool forceTutorial = false}) {
    _controller?.dispose();
    _controller = GameController(
      cardsJson: widget.cardsJson,
      economyJson: widget.economyJson,
      seed: _newSeed(),
      backgroundId: backgroundId,
      store: widget.store,
      meta: _meta,
    );
    setState(() {
      // R20: the FIRST NEW RUN ever runs the tutorial (gated on the persisted
      // seen flag); a GUIDED RUN ([forceTutorial]) always runs it. CONTINUE/
      // resume never does. Captured here so a mid-run settings toggle doesn't
      // retroactively show/hide it.
      _tutorialPending = forceTutorial || !_settings.tutorialSeen;
      _resume = null; // a new run supersedes any old resumable save
      _screen = _Screen.run;
    });
  }

  /// Opens SETTINGS from [from] (title / desk); BACK returns there.
  void _openSettings(_Screen from) {
    setState(() {
      _settingsReturn = from;
      _screen = _Screen.settings;
    });
  }

  /// SETTINGS BACK: return to whoever opened it.
  void _closeSettings() => setState(() => _screen = _settingsReturn);

  /// WIPE SAVE (SETTINGS danger): erase run + meta on disk, reset the live
  /// meta + resume to a fresh install. The settings screen shows the
  /// "SAVE WIPED." confirmation.
  Future<void> _wipeSave() async {
    await widget.store?.wipeSave();
    if (!mounted) return;
    setState(() {
      _meta = MetaState();
      _resume = null;
    });
  }

  /// CONTINUE (title): resumes the replayed run (docs/06). The controller is
  /// seated at the replayed state + cursor; the run screen mounts in place.
  void _continueRun() {
    final resume = _resume;
    if (resume?.load == null) return;
    _controller?.dispose();
    _controller = GameController.resume(
      cardsJson: widget.cardsJson,
      economyJson: widget.economyJson,
      resume: resume!.load!,
      store: widget.store,
      meta: _meta,
    );
    setState(() {
      _screen = _Screen.run;
    });
  }

  /// Returns to THE DESK from anywhere (title key, or a finished run). Pulls
  /// the freshest meta off the controller (settlement updated it) so the Desk
  /// shows the just-earned reputation.
  void _toDesk() {
    final c = _controller;
    if (c != null) _meta = c.meta;
    setState(() => _screen = _Screen.desk);
  }

  /// Returns to the TITLE (Desk back / not used as a primary path).
  void _toTitle() {
    final c = _controller;
    if (c != null) _meta = c.meta;
    setState(() => _screen = _Screen.title);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MULTIPLES',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBezel,
        fontFamily: kFontBody,
      ),
      // CRT channel-change between the top-level screens (docs/07): the
      // shell's title↔desk↔run swaps sweep instead of hard-cutting. The boot
      // gate and each screen carry a distinct ValueKey so AnimatedSwitcher
      // detects the change; the incoming screen is in the tree immediately.
      home: CrtScreenSwitcher(
        child: _booting
            ? const _BootGate(key: ValueKey('boot'))
            : _buildScreen(),
      ),
    );
  }

  Widget _buildScreen() {
    // docs/08 BGM moods: the Title (S0) and THE DESK (S9) both ride the
    // title mood; the run screen owns its own act/tension/autopsy/victory
    // moods off the live phase. setMood dedupes, so this is cheap to call
    // on every build. (Deferred a frame so it never fires mid-build.)
    final audio = widget.audio;
    if (audio != null &&
        (_screen == _Screen.title ||
            _screen == _Screen.desk ||
            _screen == _Screen.glossary)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(audio.setMood(AudioMood.title));
      });
    }
    switch (_screen) {
      case _Screen.title:
        return TitleScreen(
          key: const ValueKey('screen-title'),
          seedTag: _seedTagPreview(),
          resumeLabel: _resume == null ? null : _resumeLabel(_resume!.load!),
          onContinue: _resume == null ? null : _continueRun,
          onNewRun: () => _startRun(kBootstrapperBackgroundId),
          onGuidedRun: () =>
              _startRun(kBootstrapperBackgroundId, forceTutorial: true),
          onGlossary: () => setState(() => _screen = _Screen.glossary),
          onDesk: _toDesk,
          onSettings:
              widget.audio == null ? null : () => _openSettings(_Screen.title),
        );
      case _Screen.desk:
        return DeskScreen(
          key: const ValueKey('screen-desk'),
          meta: _meta,
          onStartRun: _startRun,
          onBack: _toTitle,
          onSettings:
              widget.audio == null ? null : () => _openSettings(_Screen.desk),
        );
      case _Screen.run:
        return RunScreen(
          key: const ValueKey('screen-run'),
          controller: _controller!,
          onDesk: _toDesk,
          audio: widget.audio,
          settings: _settings,
          tutorialActive: _tutorialPending,
        );
      case _Screen.settings:
        return SettingsScreen(
          key: const ValueKey('screen-settings'),
          audio: widget.audio!,
          settings: _settings,
          onBack: _closeSettings,
          onWipeSave: widget.store == null ? null : _wipeSave,
        );
      case _Screen.glossary:
        return GlossaryScreen(
          key: const ValueKey('screen-glossary'),
          onBack: () => setState(() => _screen = _Screen.title),
        );
    }
  }

  /// The seed tag shown on the title before a run exists: the resumable run's
  /// own tag if present, else a fresh preview of the next NEW RUN seed.
  String _seedTagPreview() {
    final c = _controller;
    if (c != null && _screen != _Screen.run) return c.seedTag;
    final s = _resume?.load?.seed ?? _newSeed();
    final hex = s.toRadixString(16).toUpperCase().padLeft(4, '0');
    return hex.substring(hex.length - 4);
  }

  /// The CONTINUE slot label (mockup `T2 · R3 · #4F2A`).
  String _resumeLabel(RunLoadResult load) {
    final s = load.state;
    final hex =
        load.seed.toRadixString(16).toUpperCase().padLeft(4, '0');
    final tag = hex.substring(hex.length - 4);
    return 'T${s.tier} · R${s.round} · #$tag';
  }
}

/// A near-instant boot gate (the meta/run load is microseconds; this only
/// shows on a cold disk). Terminal-black, no spinner churn.
class _BootGate extends StatelessWidget {
  const _BootGate({super.key});

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: kBezel, child: SizedBox.expand());
}
