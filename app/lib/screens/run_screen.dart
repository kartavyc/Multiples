/// The run frame — S1 HUD + S3 ACT blotter, wiring every R8 overlay/beat:
/// S4 napkin (napkin_overlay.dart), S6 arbitrage flash
/// (arbitrage_flash.dart), the NW surge (widgets/surge.dart), S2 digest
/// (digest_overlay.dart), S5 shop (shop_panel.dart), S7 deadline
/// (deadline_panel.dart), S8 autopsy / S10 victory. Visual spec:
/// docs/mockups/layout-a-v4.html + ui-v4-all-screens.html (canonical);
/// rules: docs/07 + docs/05 §0 (canonical order, thumb zone, static
/// legibility).
///
/// LOGIC-FREE widgets: everything economic is read off the engine state or
/// formatted by engine money.dart helpers; actions dispatch through
/// [GameController]. The surge watcher compares the DERIVED net worth
/// before/after each dispatched action (display delta; never fed back).
library;

import 'package:engine/apply.dart' show GameEvent, GameEventType, slotsMax;
import 'package:engine/content.dart';
import 'package:engine/dealflow.dart' show playsHeldMax;
import 'package:engine/model.dart';
import 'package:engine/money.dart';
import 'package:engine/operate.dart' show playsPerRound;
import 'package:engine/resolver.dart' show tierDeadlineRounds;
import 'package:engine/round.dart' show tierBarCents;
import 'package:flutter/material.dart' hide Card;

import '../audio.dart';
import '../controller.dart';
import '../settings.dart';
import '../theme.dart';
import '../tutorial.dart';
import '../widgets/card_kind.dart';
import '../widgets/juice.dart';
import '../widgets/rejection_line.dart';
import '../widgets/surge.dart';
import 'arbitrage_flash.dart';
import 'autopsy_screen.dart';
import 'deadline_panel.dart';
import 'digest_overlay.dart';
import 'exit_flash.dart';
import 'napkin_overlay.dart';
import 'shop_panel.dart';
import 'tutorial_overlay.dart';
import 'victory_screen.dart';

/// Roman numerals for the nameplate MARK (docs/07: MK = net-worth tier).
const List<String> _kMarks = ['I', 'II', 'III', 'IV', 'V'];

/// The persistent run screen: HUD frame + phase stage (library header).
class RunScreen extends StatefulWidget {
  /// Builds the screen over [controller]; [onDesk] routes the end screens to
  /// THE DESK (after settlement).
  const RunScreen({
    super.key,
    required this.controller,
    this.onDesk,
    this.audio,
    this.settings,
    this.tutorialActive = false,
  });

  /// The app-side game container.
  final GameController controller;

  /// THE DESK key handler on the victory/autopsy screens (null in the smoke
  /// run-screen widget tests that mount RunScreen standalone).
  final VoidCallback? onDesk;

  /// The R20 preference controller; null in standalone widget tests. On the
  /// first-run tutorial's finish/skip the run screen latches
  /// AppSettings.tutorialSeen through this.
  final AppSettingsController? settings;

  /// True when THIS run should run the first-run tutorial (the shell passes
  /// it once, on the very first NEW RUN with tutorialSeen == false).
  final bool tutorialActive;

  /// The R18 audio controller (docs/08); null in widget tests that run
  /// silent. The run screen is the central audio ROUTER: it maps engine
  /// events + phase/screen transitions + UI taps to playback (thin
  /// listener calls — no logic).
  final AudioController? audio;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  /// Selected blotter ticket (UI-only state; opens the S4 napkin).
  String? _selectedCardId;

  /// True while the REINVEST confirm is open.
  bool _reinvestConfirm = false;

  /// True while the EXIT OFFER confirm is open (round 11).
  bool _exitConfirm = false;

  /// Held play whose USE/SELL sheet is open (round 11), if any.
  String? _heldSelected;

  /// TARGET PICKER (round 11): true while a targeted ticket waits for a
  /// rail tap (only when ventures > 1 — single venture auto-targets).
  bool _aiming = false;

  /// The aimed venture for the open napkin (null = platform).
  String? _targetVentureId;

  /// Last engine rejection reason key, rendered inline.
  String? _rejection;

  /// The shop offer whose BUY the engine last refused (red row flash).
  String? _shopRejectId;
  int _shopRejectEpoch = 0;

  /// THE SIGNATURE: the net-worth surge watcher + the screen shaker
  /// (widgets/surge.dart, widgets/juice.dart).
  final SurgeController _surge = SurgeController();
  final ShakeController _shake = ShakeController();

  /// The first-run TUTORIAL driver (tutorial.dart). Active only when the
  /// shell flagged this run; inert otherwise (every getter empty).
  late final TutorialController _tutorial =
      TutorialController(active: widget.tutorialActive);

  /// Spotlight anchors: the run screen resolves these GlobalKeys to screen
  /// rects for the coachmark cut-out (tutorial_overlay.dart).
  final GlobalKey _moneyBoxesKey = GlobalKey();
  final GlobalKey _equationKey = GlobalKey();
  final GlobalKey _blotterKey = GlobalKey();

  GameController get _c => widget.controller;
  AudioController? get _audio => widget.audio;

  /// The BGM mood this build's phase implies (docs/08 screen→mood). ACT /
  /// digest / shop ride the act loop; the deadline panel goes TENSION when
  /// the run is behind pace or in the final round; runOver splits
  /// victory / autopsy. setMood dedupes, so calling this every build is
  /// cheap and never restarts the loop.
  void _syncMood(GameState s) {
    final audio = _audio;
    if (audio == null) return;
    final AudioMood mood;
    if (s.phase == PhaseId.runOver) {
      mood = s.won ? AudioMood.victory : AudioMood.autopsy;
    } else if (_c.deadlineOpen && _behindPace(s)) {
      mood = AudioMood.tension;
    } else {
      mood = AudioMood.act;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      audio.setMood(mood);
    });
  }

  /// BEHIND-PACE / final-round tension (docs/08): the deadline panel is up
  /// and the engine meter says the realized growth trails what's needed, or
  /// it's the tier's last allowed round. Read-only off the engine meters.
  bool _behindPace(GameState s) {
    if (s.tier > 4) return true; // endless antes always ride tension
    final d = _c.deadline;
    if (d == null) return false;
    if (d.realizedMilli < d.neededMilli) return true;
    return d.roundsUsed >= d.deadlineRounds;
  }

  /// Fires the SFX for each engine event in [events] (docs/08 trigger map),
  /// via the pure name→sfx map. Thin listener — no logic.
  void _emit(List<GameEvent> events) {
    final audio = _audio;
    if (audio == null) return;
    for (final e in events) {
      final sfx = sfxForEventName(e.type.name);
      if (sfx != null) audio.play(sfx);
    }
  }

  /// A chunky-key thunk (docs/08 sfx_key).
  void _key() => _audio?.play(Sfx.key);

  /// A ticket / card / venture select (docs/08 sfx_select).
  void _sel() => _audio?.play(Sfx.select);

  @override
  void initState() {
    super.initState();
    // The operate phase auto-runs (S2 is a read-only digest of what the
    // engine already did) — run start lands here in phase OPERATE.
    if (_c.state.phase == PhaseId.operate) {
      _c.beginRound();
      // The opening hand was dealt (docs/08 sfx_ticket — shuffle).
      _audio?.play(Sfx.ticket);
      // A debt-crushed opening OPERATE can already be fatal (sfx_bankruptcy;
      // the autopsy BGM follows from _syncMood).
      _emit(_c.lastOperateEvents);
    }
  }

  @override
  void dispose() {
    _surge.dispose();
    _shake.dispose();
    _tutorial.dispose();
    super.dispose();
  }

  // --- TUTORIAL wiring (tutorial.dart) ---

  /// Reports the live beats to the tutorial driver (a step shows only once
  /// its trigger has fired). Called every build off the engine state; the
  /// driver dedupes triggers so repeated calls are cheap. Deferred a frame so
  /// fireTrigger's notifyListeners never runs mid-build.
  void _syncTutorialTriggers(GameState s) {
    if (!_tutorial.active) return;
    final fire = <TutorialTrigger>[];
    if (s.phase == PhaseId.act) {
      fire.add(TutorialTrigger.actReady);
      fire.add(TutorialTrigger.actReadyTwo);
      // An ADD-ON in the current hand unblocks step 3.
      final hasAddon = s.hand.any(
          (id) => _c.content.byId(id).type == CardType.addon);
      if (hasAddon) fire.add(TutorialTrigger.addonInHand);
    }
    if (fire.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final t in fire) {
        _tutorial.fireTrigger(t);
      }
    });
  }

  /// TAP TO CONTINUE on the coachmark.
  void _tutorialAdvance() {
    _tutorial.advance();
    _maybeLatchTutorialSeen();
    setState(() {});
  }

  /// SKIP TUTORIAL.
  void _tutorialSkip() {
    _tutorial.skip();
    _maybeLatchTutorialSeen();
    setState(() {});
  }

  /// Persists tutorialSeen once the tutorial finishes (last step) or is
  /// skipped, so it never auto-shows again.
  void _maybeLatchTutorialSeen() {
    if (_tutorial.finished) {
      widget.settings?.setTutorialSeen(true);
    }
  }

  /// Resolves a [SpotlightTarget] to a rect in the overlay's coordinate space
  /// (the run stage). Null when the anchor isn't laid out yet (the overlay
  /// then dims everything — still legible, never blocks).
  Rect? _spotlightRect(SpotlightTarget target, BuildContext overlayContext) {
    final key = switch (target) {
      SpotlightTarget.moneyBoxes => _moneyBoxesKey,
      SpotlightTarget.equationLevers => _equationKey,
      SpotlightTarget.addonTicket => _blotterKey,
      SpotlightTarget.none => null,
    };
    if (key == null) return null;
    final targetCtx = key.currentContext;
    final overlayBox = overlayContext.findRenderObject();
    if (targetCtx == null || overlayBox is! RenderBox) return null;
    final box = targetCtx.findRenderObject();
    if (box is! RenderBox || !box.attached || !overlayBox.attached) {
      return null;
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    return topLeft & box.size;
  }

  void _clearUiState() {
    _selectedCardId = null;
    _reinvestConfirm = false;
    _exitConfirm = false;
    _heldSelected = null;
    _aiming = false;
    _targetVentureId = null;
    _rejection = null;
    _shopRejectId = null;
  }

  /// Targeted card types aim at a venture (docs/05 §3: ADD-ON, RAISE,
  /// PARTNER target the rail; venture cards found a NEW slot).
  bool _isTargeted(Card card) =>
      card.type == CardType.addon ||
      card.type == CardType.financing ||
      card.type == CardType.partner;

  void _selectTicket(String cardId) {
    final willAim = _isTargeted(_c.content.byId(cardId)) &&
        _c.state.ventures.length > 1;
    _sel(); // docs/08 sfx_select — ticket tap
    // A single-venture ticket opens the napkin straight away (sfx_napkin);
    // a targeted multi-venture ticket waits for a rail tap (the napkin —
    // and its chatter — lands at _pickTarget).
    if (!willAim) _audio?.play(Sfx.napkin);
    setState(() {
      _clearUiState();
      _selectedCardId = cardId;
      if (willAim) _aiming = true;
    });
  }

  /// Rail tap while aiming: locks the target and opens the napkin.
  void _pickTarget(String ventureId) {
    if (!_aiming) return;
    _audio?.play(Sfx.napkin); // the napkin opens now (dot-matrix chatter)
    setState(() {
      _aiming = false;
      _targetVentureId = ventureId;
    });
  }

  void _selectExit() {
    _sel();
    _audio?.play(Sfx.napkin);
    setState(() {
      _clearUiState();
      _exitConfirm = true;
    });
  }

  void _selectHeld(String cardId) {
    _sel();
    _audio?.play(Sfx.napkin);
    setState(() {
      _clearUiState();
      _heldSelected = cardId;
    });
  }

  void _openReinvest() {
    _key(); // REINVEST is a chunky key (docs/08 sfx_key)
    _audio?.play(Sfx.napkin);
    setState(() {
      _clearUiState();
      _reinvestConfirm = true;
    });
  }

  void _back() => setState(_clearUiState);

  /// Dispatches an engine action capturing the DERIVED net worth around
  /// it: a rise fires the surge — unless an arbitrage flash opened, which
  /// owns the first beat (the surge is deferred to BOOK IT). Death gets
  /// nothing (actions cannot kill; only OPERATE can).
  List<GameEvent> _withSurge(List<GameEvent> Function() dispatch) {
    final before = _c.state.netWorthCents;
    final events = dispatch();
    final rejected =
        events.any((e) => e.type == GameEventType.actionRejected);
    // AUDIO (docs/08): the engine events drive their stingers (arbitrage,
    // exit-cash, dilution→raise, error on a rejection). Fired for both
    // accepted and rejected dispatches so the buzzer lands on a bounce.
    _emit(events);
    if (!rejected) {
      final after = _c.state.netWorthCents;
      if (_c.pendingFlash != null || _c.pendingExitFlash != null) {
        // A takeover owns the first beat; the surge releases on its
        // dismiss key (BOOK IT / CASHED OUT). The nw_surge SFX defers too
        // (fired at _bookIt / _cashedOut).
        _surge.defer(before, after);
      } else {
        _surge.fire(before, after); // ignores non-increases
        // THE SIGNATURE (docs/08 sfx_nw_surge): an actual rise rings the
        // bell. Mirrors the surge watcher's up-only gate.
        if (after > before) _audio?.play(Sfx.nwSurge);
      }
    }
    return events;
  }

  void _execute() {
    // docs/08: PARTNER commits ring sfx_partner — the engine emits no
    // distinct partner event, so the card TYPE at dispatch is the trigger
    // (read-only content lookup). RAISE rides the engine `dilution` event
    // (→ sfx_raise) handled in _emit.
    final committingPartner = !_reinvestConfirm &&
        !_exitConfirm &&
        _heldSelected == null &&
        _selectedCardId != null &&
        _c.content.byId(_selectedCardId!).type == CardType.partner;
    final events = _withSurge(() {
      if (_reinvestConfirm) return _c.reinvest();
      if (_exitConfirm) return _c.exitVenture();
      if (_heldSelected != null) {
        return _c.playHeld(_heldSelected!,
            targetVentureId: _targetVentureId);
      }
      return _c.playBlotterCard(_selectedCardId!,
          targetVentureId: _targetVentureId);
    });
    final committed =
        !events.any((e) => e.type == GameEventType.actionRejected);
    if (committed && committingPartner) _audio?.play(Sfx.partner);
    final rejected = events
        .where((e) => e.type == GameEventType.actionRejected)
        .toList();
    setState(() {
      if (rejected.isEmpty) {
        _clearUiState();
      } else {
        _rejection = rejected.first.reason;
      }
    });
  }

  /// SELL from the held-play sheet (the engine's trunc(price/2)).
  void _sellHeld() {
    _key(); // SELL is a chunky key (docs/08 sfx_key)
    final events = _c.sellPlay(_heldSelected!);
    final rejected = events
        .where((e) => e.type == GameEventType.actionRejected)
        .toList();
    _emit(rejected); // buzzer on a bounce
    setState(() {
      if (rejected.isEmpty) {
        _clearUiState();
      } else {
        _rejection = rejected.first.reason;
      }
    });
  }

  void _reroll() {
    final events = _c.reroll();
    final rejected = events
        .where((e) => e.type == GameEventType.actionRejected)
        .toList();
    // docs/08: REROLL rings sfx_reroll on success, the buzzer on a bounce.
    if (rejected.isEmpty) {
      _audio?.play(Sfx.reroll);
    } else {
      _emit(rejected);
    }
    setState(() {
      _clearUiState();
      if (rejected.isNotEmpty) _rejection = rejected.first.reason;
    });
  }

  void _endTurn() {
    _key(); // END TURN — chunky-key thunk (docs/08 sfx_key)
    setState(_clearUiState);
    _c.endTurnToShop();
  }

  void _buy(String cardId) {
    final events = _c.buyOffer(cardId);
    final rejected = events
        .where((e) => e.type == GameEventType.actionRejected)
        .toList();
    // docs/08: a successful SHOP buy is a select; a refused buy buzzes.
    if (rejected.isEmpty) {
      _sel();
    } else {
      _emit(rejected);
    }
    setState(() {
      if (rejected.isEmpty) {
        _rejection = null;
        _shopRejectId = null;
      } else {
        _rejection = rejected.first.reason;
        if (rejected.first.reason == 'insufficient_cash') {
          _shopRejectId = cardId;
          _shopRejectEpoch++;
        }
      }
    });
  }

  void _advance() {
    _key(); // ADVANCE — chunky-key thunk (docs/08 sfx_key)
    setState(_clearUiState);
    _c.advance(); // opens the S7 panel or lands the end screens
    // tier-clear / win / missed-deadline stingers ride the engine events
    // the deadline check emitted.
    _emit(_c.lastDeadlineEvents);
  }

  void _proceed() {
    _key(); // NEXT TIER / NEXT ROUND — chunky-key thunk
    _c.proceedFromDeadline();
    // The next OPERATE deals a fresh hand (docs/08 sfx_ticket — shuffle).
    _audio?.play(Sfx.ticket);
    // …and may bankrupt the run (sfx_bankruptcy off the OPERATE events).
    _emit(_c.lastOperateEvents);
  }

  /// BOOK IT: closes the S6 takeover, then releases the deferred surge —
  /// the flash → surge hand-off is the full commit beat (docs/07).
  void _bookIt() {
    _c.dismissFlash();
    if (_surge.hasDeferredRise) _audio?.play(Sfx.nwSurge);
    _surge.fireDeferred();
    // TUTORIAL step 4: the gap was just realized — point at it.
    _tutorial.fireTrigger(TutorialTrigger.arbitrageSeen);
  }

  /// CASHED OUT: closes the S6-EXIT beat, then releases the deferred
  /// surge (a hot exit can rise; a min(offer, live) exit never does —
  /// the surge only ever fires upward).
  void _cashedOut() {
    _c.dismissExitFlash();
    if (_surge.hasDeferredRise) _audio?.play(Sfx.nwSurge);
    _surge.fireDeferred();
  }

  void _retry() {
    _key(); // NEW RUN / RETRY — chunky-key thunk (docs/08 sfx_key)
    setState(_clearUiState);
    // New wall-clock seed (app layer owns seed lifecycle; engine never
    // reads a clock), then the new run's first OPERATE.
    _c.newRun();
    _c.beginRound();
    _audio?.play(Sfx.ticket); // the fresh hand
    _emit(_c.lastOperateEvents);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final s = _c.state;
        // docs/08 BGM: the run screen's phase picks the mood (act / tension /
        // autopsy / victory); setMood dedupes so this is cheap every build.
        _syncMood(s);
        // TUTORIAL (tutorial.dart): report the live beats so coachmarks land
        // on the moment the player is already looking at.
        _syncTutorialTriggers(s);
        // RUN_OVER settlement (doc 02 §2 / docs/06 §5.1): the moment the end
        // screen is about to show, settle the run into meta + delete the save
        // (off the build frame; one-shot + idempotent in the controller).
        if (s.phase == PhaseId.runOver) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _c.settleRunOver();
          });
        }
        return Scaffold(
          backgroundColor: kBezel,
          body: SafeArea(
            child: Column(
              children: [
                _Nameplate(
                  tier: s.won ? 5 : s.tier,
                  seedTag: _c.seedTag,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: kBg,
                        child: ShakeWidget(
                          controller: _shake,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (s.phase == PhaseId.runOver)
                                s.won
                                    ? VictoryScreen(
                                        controller: _c,
                                        onNewRun: _retry,
                                        onDesk: widget.onDesk,
                                        shake: _shake,
                                      )
                                    : AutopsyScreen(
                                        controller: _c,
                                        onRetry: _retry,
                                        onDesk: widget.onDesk,
                                      )
                              else
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      10, 8, 10, 8),
                                  child: _buildFrame(s),
                                ),
                              if (s.phase == PhaseId.act &&
                                  (_selectedCardId != null ||
                                      _reinvestConfirm ||
                                      _exitConfirm ||
                                      _heldSelected != null) &&
                                  !_aiming &&
                                  _c.pendingFlash == null &&
                                  _c.pendingExitFlash == null)
                                NapkinOverlay(
                                  key: ValueKey(_heldSelected ??
                                      _selectedCardId ??
                                      (_exitConfirm
                                          ? 'exit'
                                          : 'reinvest')),
                                  controller: _c,
                                  cardId: _heldSelected ?? _selectedCardId,
                                  reinvest: _reinvestConfirm,
                                  exit: _exitConfirm,
                                  heldPlay: _heldSelected != null,
                                  targetVentureId: _targetVentureId,
                                  rejection: _rejection,
                                  onBack: _back,
                                  onExecute: _execute,
                                  onSell: _heldSelected != null
                                      ? _sellHeld
                                      : null,
                                ),
                              if (_c.deadlineOpen)
                                DeadlinePanel(
                                  data: _c.deadline!,
                                  onProceed: _proceed,
                                ),
                              if (_c.digestOpen)
                                DigestOverlay(
                                  controller: _c,
                                  onContinue: () {
                                    _key(); // docs/08 sfx_key
                                    _c.dismissDigest();
                                  },
                                ),
                              if (_c.pendingFlash != null)
                                ArbitrageFlash(
                                  data: _c.pendingFlash!,
                                  onBookIt: _bookIt,
                                  shake: _shake,
                                ),
                              if (_c.pendingExitFlash != null)
                                ExitFlash(
                                  data: _c.pendingExitFlash!,
                                  onCashedOut: _cashedOut,
                                  shake: _shake,
                                ),
                              SurgeTint(surge: _surge, shake: _shake),
                              // TUTORIAL coachmark (tutorial.dart): only while
                              // a step is live AND no other overlay owns the
                              // stage (it teaches between beats, never over a
                              // flash/digest/deadline panel — non-destructive).
                              if (s.phase == PhaseId.act &&
                                  _tutorial.currentStep != null &&
                                  !_c.digestOpen &&
                                  !_c.deadlineOpen &&
                                  _c.pendingFlash == null &&
                                  _c.pendingExitFlash == null)
                                Builder(builder: (overlayContext) {
                                  final step = _tutorial.currentStep!;
                                  return TutorialOverlay(
                                    step: step,
                                    spotlight: _spotlightRect(
                                        step.target, overlayContext),
                                    onContinue: _tutorialAdvance,
                                    onSkip: _tutorialSkip,
                                  );
                                }),
                              const CrtOverlay(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFrame(GameState s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HudPanel(
          controller: _c,
          surge: _surge,
          moneyBoxesKey: _moneyBoxesKey,
          equationKey: _equationKey,
        ),
        _SectHead(
          left: 'HOLDINGS',
          hint: _aiming ? 'TAP A VENTURE TO AIM ▼' : null,
          right: '${s.ventures.length}/${slotsMax(s.tier)}',
        ),
        _HoldingsRail(
          ventures: s.ventures,
          controller: _c,
          pickerActive: _aiming,
          onPick: _pickTarget,
        ),
        ..._buildStage(s),
      ],
    );
  }

  List<Widget> _buildStage(GameState s) {
    switch (s.phase) {
      case PhaseId.act:
        final confirmOpen = (_selectedCardId != null && !_aiming) ||
            _reinvestConfirm ||
            _exitConfirm ||
            _heldSelected != null;
        return [
          _PlaysStrip(controller: _c, onTapHeld: _selectHeld),
          _SectHead(
            left: 'DEALS',
            hint: confirmOpen || _aiming
                ? null
                : (s.playsRemaining > 0
                    ? 'TAP A TICKET ▼'
                    : 'OUT OF PLAYS · END TURN'),
            // U+21AF (never emoji) — U+26A1 ⚡ force-renders as the
            // color-emoji bolt on Android and leaks a stale Impeller
            // glyph layer over later overlays.
            right: '↯ ${s.playsRemaining}/${playsPerRound(s.tier)} PLAYS',
          ),
          Expanded(
            child: KeyedSubtree(
              key: _blotterKey,
              child: _Blotter(
              controller: _c,
              selectedCardId: _selectedCardId,
              exitSelected: _exitConfirm,
              dimmed: s.playsRemaining < 1,
              onTapTicket: _selectTicket,
              onTapExit: _selectExit,
            ),
            ),
          ),
          if (_rejection != null && !confirmOpen)
            RejectionLine(reason: _rejection!),
          // The S4 napkin renders as an OVERLAY above this stage
          // (mockup #napkin: absolute, bottom-anchored, dark backdrop).
          _FkeyRow(
            onReinvest: _openReinvest,
            // The key disables cash-short (round 11) — the engine still
            // gates at apply.
            onReroll: _c.canReroll ? _reroll : null,
            onEndTurn: _endTurn,
            rerollCostCents: _c.rerollCostCents,
          ),
        ];
      case PhaseId.shop:
        return [
          _SectHead(
            left: 'SHOP · CASH ONLY',
            right: 'HELD ${s.playsHeld.length}/${playsHeldMax(s.tier)}',
          ),
          Expanded(
            child: ShopPanel(
              controller: _c,
              onBuy: _buy,
              rejectFlashId: _shopRejectId,
              rejectFlashEpoch: _shopRejectEpoch,
            ),
          ),
          if (_rejection != null) RejectionLine(reason: _rejection!),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: ChunkyKey(
                  key: const Key('shopReroll'),
                  icon: '↻',
                  label: 'REROLL ${formatMoney(_c.rerollCostCents)}',
                  // Disables cash-short (round 11; engine still gates).
                  onTap: _c.canReroll ? _reroll : null,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                flex: 14,
                child: ChunkyKey(
                  key: const Key('advance'),
                  icon: '▸',
                  label: 'ADVANCE',
                  variant: ChunkyKeyVariant.primary,
                  onTap: _advance,
                ),
              ),
            ],
          ),
        ];
      case PhaseId.operate:
      case PhaseId.deadlineCheck:
        // Transient: the S7 panel / digest overlay own these beats.
        return [const Spacer()];
      case PhaseId.runOver:
        return [const Spacer()]; // handled a level up
    }
  }
}

// ---------------------------------------------------------------------------
// Nameplate (the bezel strip; docs/07 "the machine levels with you") — the
// MARK STAMPS on a tier upgrade: shrink → 1.5x overshoot + green flash →
// settle, ~900ms (mockup `mkstamp`; bible S7/S10 beat).
// ---------------------------------------------------------------------------

class _Nameplate extends StatefulWidget {
  const _Nameplate({required this.tier, required this.seedTag});

  final int tier;
  final String seedTag;

  @override
  State<_Nameplate> createState() => _NameplateState();
}

class _NameplateState extends State<_Nameplate>
    with SingleTickerProviderStateMixin {
  // initState-created (lazy creation in dispose = unsafe ancestor lookup).
  late final AnimationController _stamp;

  @override
  void initState() {
    super.initState();
    _stamp = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1, // at rest
    );
  }

  @override
  void didUpdateWidget(_Nameplate old) {
    super.didUpdateWidget(old);
    if (widget.tier > old.tier) {
      _stamp.forward(from: 0);
      safeHapticLight();
    }
  }

  @override
  void dispose() {
    _stamp.dispose();
    super.dispose();
  }

  /// Mockup `mkstamp` keyframes: scale 1 → .7@25% (ink lifts) → 1.5@55%
  /// (green flash) → 1; eased upstream by [kStampCurve] timing feel.
  static double _scale(double t) {
    if (t >= 1) return 1;
    if (t < .25) return 1 - (1 - .7) * (t / .25);
    if (t < .55) return .7 + (1.5 - .7) * ((t - .25) / .30);
    return 1.5 + (1 - 1.5) * ((t - .55) / .45);
  }

  static double _opacity(double t) {
    if (t >= 1) return 1;
    if (t < .25) return 1 - .8 * (t / .25);
    if (t < .55) return .2 + .8 * ((t - .25) / .30);
    return 1;
  }

  /// Green flash strength peaking at the overshoot.
  static double _flash(double t) {
    if (t >= 1 || t < .25) return 0;
    if (t < .55) return (t - .25) / .30;
    return 1 - (t - .55) / .45;
  }

  @override
  Widget build(BuildContext context) {
    final mark =
        _kMarks[(widget.tier - 1).clamp(0, _kMarks.length - 1)];
    final style = labelStyle(color: const Color(0xFF9AA4AD), tracking: 2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A2E33), Color(0xFF17191C)],
          ),
          border: Border.all(color: kBezel),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('MULTIPLES ', style: style),
            AnimatedBuilder(
              animation: _stamp,
              builder: (context, _) {
                final t = _stamp.value;
                final f = _flash(t);
                return Transform.scale(
                  scale: _scale(t),
                  child: Opacity(
                    opacity: _opacity(t),
                    child: Text(
                      'MK·$mark',
                      key: const Key('npMark'),
                      style: style.copyWith(
                        color: Color.lerp(
                            const Color(0xFF9AA4AD), kFg, f),
                        shadows: f > 0
                            ? [
                                Shadow(
                                  color:
                                      kGain.withValues(alpha: .8 * f),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
            Text(' · №${widget.seedTag}', style: style),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HudPanel — statline + quote board + meters + tape (S1; component C-HUD +
// C-METERS). Public: the canonical-order widget test renders it standalone.
// ---------------------------------------------------------------------------

/// The persistent HUD: statline, CASH/NET WORTH boxes, the four levers,
/// the two forward meters, the news tape — in the docs/05 §0.3 canonical
/// order, always. With a [surge] attached the NET WORTH box becomes the
/// surge-aware signature box (widgets/surge.dart).
class HudPanel extends StatelessWidget {
  /// Builds the HUD over [controller]; [surge] is optional (standalone
  /// renders skip the signature wiring).
  const HudPanel({
    super.key,
    required this.controller,
    this.surge,
    this.moneyBoxesKey,
    this.equationKey,
  });

  /// The app-side game container.
  final GameController controller;

  /// The net-worth surge watcher, when the full run frame hosts us.
  final SurgeController? surge;

  /// TUTORIAL spotlight anchor for the CASH / NET WORTH row (run screen
  /// resolves it to a rect); null in standalone renders.
  final GlobalKey? moneyBoxesKey;

  /// TUTORIAL spotlight anchor for the EBITDA / MULT levers; null standalone.
  final GlobalKey? equationKey;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final p = controller.platform;
    final m = controller.meters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Statline(state: s, seedTag: controller.seedTag),
        const SizedBox(height: 7),
        KeyedSubtree(
          key: moneyBoxesKey,
          child: Row(
          children: [
            Expanded(
              // Small-delta juice (R14 / audit L2): the CASH box pops + floats
              // a +$/−$ chip on every change (the NW box owns the up-only
              // signature surge; this answers losses too).
              child: FloatingDeltaBox(
                cents: s.cashCents,
                fmt: formatMoney,
                child: SolidBox(
                  label: 'CASH',
                  tag: 'REAL',
                  value: formatMoney(s.cashCents),
                  valueKey: const Key('cash'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: surge != null
                  ? SurgeNwBox(
                      surge: surge!,
                      value: formatMoney(s.netWorthCents),
                    )
                  : GhostBox(
                      label: 'NET WORTH',
                      tag: 'PAPER',
                      value: formatMoney(s.netWorthCents),
                      valueKey: const Key('netWorth'),
                    ),
            ),
          ],
        ),
        ),
        const SizedBox(height: 7),
        KeyedSubtree(
          key: equationKey,
          child: Row(
          children: [
            Expanded(
              child: _Lever(
                label: 'EBITDA',
                valueKey: const Key('lever-ebitda'),
                floatKey: const Key('leverFloat-ebitda'),
                value: p == null ? '—' : formatMoney(p.ebitdaCents),
                rawValue: p?.ebitdaCents,
                chip: controller.ebitdaChip,
                chipFmt: formatMoney,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Lever(
                label: 'MULT',
                valueKey: const Key('lever-mult'),
                floatKey: const Key('leverFloat-mult'),
                value: p == null ? '—' : formatMultiple(p.multipleMilli),
                rawValue: p?.multipleMilli,
                chip: controller.multipleChip,
                chipFmt: formatMultiple,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Lever(
                label: 'DEBT',
                valueKey: const Key('lever-debt'),
                floatKey: const Key('leverFloat-debt'),
                value: p == null ? '—' : formatMoney(p.netDebtCents),
                rawValue: p?.netDebtCents,
                // The float delta follows the SAME raw signed-delta coloring
                // as the round-snapshot chip beneath (chipColor): a rise is
                // green, a fall red. Consistent with the established lever
                // convention — no per-stat semantic re-coloring here.
                chip: controller.netDebtChip,
                chipFmt: formatMoney,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Lever(
                label: 'OWN',
                valueKey: const Key('lever-own'),
                floatKey: const Key('leverFloat-own'),
                value: p == null ? '—' : '${bpToPctTrunc(p.ownershipBp)}%',
                rawValue: p?.ownershipBp,
                chip: controller.ownershipChip,
                chipFmt: (bp) => '${bpToPctTrunc(bp)}',
              ),
            ),
          ],
        ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: kLine),
              bottom: BorderSide(color: kLine),
            ),
          ),
          child: Row(
            children: [
              Expanded(child: _RunwayMeter(controller: controller)),
              const SizedBox(width: 10),
              Expanded(
                child: _MarketMeter(
                  temp: m.marketTempGauge,
                  // Consumable-flag affordances (round 11): the armed
                  // chip + the unexpired MARKET READ hint, straight off
                  // the engine market flags (expiry is engine-side).
                  hotWindowArmed: s.market.hotWindowArmed,
                  readHint: s.market.marketReadHint,
                ),
              ),
            ],
          ),
        ),
        NewsTape(text: _tapeText(s)),
      ],
    );
  }
}

/// Market-temp-driven tape fragments (the live rate read through the
/// engine's bp helper; everything else is flavor copy).
String _tapeText(GameState s) {
  final rate = s.market.liveRateBp > 0
      ? ' ··· RATE ~${bpToPctTrunc(s.market.liveRateBp)}%'
      : '';
  switch (s.market.temp) {
    case MarketTemp.hot:
      return '*** MARKET HOT ▲ ··· MULTIPLES RICH ··· '
          'SELL > BUY$rate ··· ***';
    case MarketTemp.neutral:
      return '*** MARKET NEUTRAL ··· MULTIPLES DRIFTING ··· '
          'STEADY TAPE$rate ··· ***';
    case MarketTemp.cold:
      return '*** CREDIT CRUNCH ▼ ··· MULTIPLES COMPRESSING ··· '
          'DEBT DEAR$rate ··· ***';
  }
}

class _Statline extends StatelessWidget {
  const _Statline({required this.state, required this.seedTag});

  final GameState state;
  final String seedTag;

  @override
  Widget build(BuildContext context) {
    final deadline =
        state.tier <= 4 ? '${tierDeadlineRounds(state.tier)}' : '∞';
    final bar =
        state.tier <= 4 ? formatMoney(tierBarCents(state.tier)) : '∞';
    return Container(
      padding: const EdgeInsets.only(bottom: 5),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: Row(
        children: [
          _seg(
            Text(
              'TIER ${state.tier}',
              style: bodyStyle(size: 13)
                  .copyWith(fontWeight: FontWeight.w700, shadows: kGlowFg),
            ),
            first: true,
          ),
          _seg(_labeledNum('RND', '${state.round}/$deadline')),
          _seg(_labeledNum('BAR', bar)),
          const Spacer(),
          Row(
            children: [
              Text('#$seedTag', style: numStyle(15, color: kDim, glow: [])),
              const BlinkingCursor(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seg(Widget child, {bool first = false}) => Container(
        padding: EdgeInsets.only(left: first ? 0 : 8, right: 8),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: kLine)),
        ),
        child: child,
      );

  Widget _labeledNum(String g, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(g, style: labelStyle(size: 10, tracking: 1)),
          const SizedBox(width: 4),
          Text(value, style: numStyle(15)),
        ],
      );
}

/// A HUD lever (EBITDA / MULT / DEBT / OWN). On a value change the number
/// tick-pops 1.3× and floats a `+X` / `−Y` chip up off the top-right (docs/07
/// "Small deltas: stat ticks scale-pop 1.3×; floating drift up and fade") —
/// the same FloatingDeltaBox machinery the CASH box uses (R14 → R19 extended
/// to EVERY stat). The round-snapshot change chip beneath also tick-pops when
/// it moves. [rawValue] is the live engine fixed-point int the float delta is
/// computed from (null while no platform exists — the box shows `—`, inert).
class _Lever extends StatelessWidget {
  const _Lever({
    required this.label,
    required this.value,
    required this.rawValue,
    required this.chip,
    required this.chipFmt,
    this.valueKey,
    this.floatKey,
  });

  final String label;
  final String value;

  /// The live engine value (cents / milli / bp) the float-delta watches;
  /// null = no platform (`—`), no animation.
  final int? rawValue;
  final int? chip;
  final String Function(int) chipFmt;
  final Key? valueKey;

  /// Per-lever float-delta chip key (so each animates independently in tests).
  final Key? floatKey;

  @override
  Widget build(BuildContext context) {
    final number = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(value, key: valueKey, style: numStyle(26)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
      decoration: BoxDecoration(
        border: Border.all(color: kLine),
        color: const Color(0x05E6EDF3),
      ),
      child: Column(
        children: [
          Text(label, style: labelStyle(size: 8, color: kDim, tracking: 1)),
          const SizedBox(height: 3),
          // The tick-pop + floating delta (bible 1.3×). Only wired when a
          // live value exists; the `—` resting state stays static.
          rawValue == null
              ? number
              : FloatingDeltaBox(
                  cents: rawValue!,
                  fmt: chipFmt,
                  peak: 1.3,
                  floatFontSize: 13,
                  popAlignment: Alignment.center,
                  deltaKey: floatKey ?? const Key('leverFloatDelta'),
                  child: number,
                ),
          const SizedBox(height: 2),
          // The round-snapshot change chip — pops 1.3× on the frame its
          // signed value moves (mockup `.lv.tick`).
          _LeverChip(chip: chip, chipFmt: chipFmt),
        ],
      ),
    );
  }
}

/// The lever's round-snapshot change chip (`▲$4,800` / `▼9%`), wrapped so it
/// scale-pops 1.3× whenever the signed delta changes (mockup `tickpop` on
/// `.lv`). Static-legible at rest.
class _LeverChip extends StatefulWidget {
  const _LeverChip({required this.chip, required this.chipFmt});

  final int? chip;
  final String Function(int) chipFmt;

  @override
  State<_LeverChip> createState() => _LeverChipState();
}

class _LeverChipState extends State<_LeverChip>
    with SingleTickerProviderStateMixin {
  // initState-created (a late-final controller first touched in dispose would
  // build its Ticker during teardown — the unsafe ancestor lookup the bible
  // warns against).
  late final AnimationController _t;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // mockup tickpop .5s
      value: 1,
    );
  }

  @override
  void didUpdateWidget(_LeverChip old) {
    super.didUpdateWidget(old);
    if (widget.chip != old.chip && widget.chip != null && widget.chip != 0) {
      _t.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// Mockup tickpop: 1 → 1.3 @35% → 1 (linear segments; the .5s ease feel).
  double _scale(double t) {
    if (t >= 1) return 1;
    if (t < .35) return 1 + (1.3 - 1) * (t / .35);
    return 1.3 - (1.3 - 1) * ((t - .35) / .65);
  }

  @override
  Widget build(BuildContext context) {
    final chip = widget.chip;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.scale(
        scale: _t.value >= 1 ? 1 : _scale(_t.value),
        child: child,
      ),
      child: Text(
        chipText(chip, widget.chipFmt),
        style: numStyle(12, color: chipColor(chip), glow: chipGlow(chip)),
      ),
    );
  }
}

class _RunwayMeter extends StatelessWidget {
  const _RunwayMeter({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final m = controller.meters;
    final lit = controller.runwaySegmentsLit;
    final ok = m.runwayOk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RUNWAY', style: labelStyle()),
            Text(
              ok ? '✓ OK' : '! LOW',
              style: numStyle(14,
                  color: ok ? kGain : kLoss,
                  glow: ok ? kGlowGain : kGlowLoss),
            ),
          ],
        ),
        const SizedBox(height: 3),
        SegBar(segs: [
          for (var i = 0; i < 10; i++)
            i < lit ? (ok ? SegState.on : SegState.onLoss) : SegState.off,
        ]),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('due ${formatMoney(m.debtServiceNextRoundCents)}',
                style: bodyStyle(size: 10, color: kDim)),
            Text('proj ${formatMoney(m.projectedCashNextRoundCents)}',
                style: bodyStyle(size: 10, color: kDim)),
          ],
        ),
      ],
    );
  }
}

class _MarketMeter extends StatelessWidget {
  const _MarketMeter({
    required this.temp,
    this.hotWindowArmed = false,
    this.readHint,
  });

  final MarketTemp temp;

  /// HOT WINDOW armed (engine flag): the small armed chip shows.
  final bool hotWindowArmed;

  /// Unexpired MARKET READ direction (engine flag); null = no read.
  final MarketTemp? readHint;

  @override
  Widget build(BuildContext context) {
    final segs = [
      for (var i = 0; i < 8; i++)
        if (i < 2)
          temp == MarketTemp.cold ? SegState.onCold : SegState.onColdDim
        else if (i >= 6)
          temp == MarketTemp.hot ? SegState.onHot : SegState.onHotDim
        else
          SegState.onWhite,
    ];
    final needle = switch (temp) {
      MarketTemp.cold => 1,
      MarketTemp.neutral => 3,
      MarketTemp.hot => 6,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('MARKET', style: labelStyle()),
            if (hotWindowArmed)
              // The armed chip (round 11): the next exit rolls hot.
              Container(
                key: const Key('hotArmedChip'),
                padding: const EdgeInsets.symmetric(
                    horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x594DFF8A)),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text('↯ARMED',
                    style: bodyStyle(size: 9, color: kGain)),
              ),
            Text(temp.name.toUpperCase(), style: numStyle(14)),
          ],
        ),
        const SizedBox(height: 3),
        SegBar(segs: segs, markerIndex: needle),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('COLD', style: bodyStyle(size: 10, color: kDim)),
            if (readHint != null)
              // The unexpired MARKET READ result (round 11; direction
              // only, never magnitude — doc 01 §7.3).
              Text(
                '(READ: ${readHint!.name.toUpperCase()}→)',
                key: const Key('marketReadHint'),
                style: bodyStyle(size: 10, color: kAccentHi),
              ),
            Text('HOT', style: bodyStyle(size: 10, color: kDim)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section head (mockup .secthead)
// ---------------------------------------------------------------------------

class _SectHead extends StatelessWidget {
  const _SectHead({required this.left, this.right, this.hint});

  final String left;
  final String? right;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 3),
      child: Row(
        children: [
          Text(left, style: labelStyle(tracking: 2)),
          if (hint != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint!,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: labelStyle(color: kAccentHi, tracking: 1)
                    .copyWith(shadows: kGlowAcc),
              ),
            ),
          ] else
            const Spacer(),
          if (right != null)
            Text(right!, style: numStyle(14)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Holdings rail (mockup #holdings)
// ---------------------------------------------------------------------------

class _HoldingsRail extends StatelessWidget {
  const _HoldingsRail({
    required this.ventures,
    required this.controller,
    this.pickerActive = false,
    this.onPick,
  });

  final List<Venture> ventures;

  /// For the partner `+$X/RD` tag (engine-value composition lives there).
  final GameController controller;

  /// TARGET PICKER mode (round 11): rows glow (mockup tglow) and a tap
  /// aims the selected targeted card.
  final bool pickerActive;

  /// Picker tap handler.
  final void Function(String ventureId)? onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: pickerActive ? kAccent : kLine),
        color: const Color(0x05E6EDF3),
        boxShadow: pickerActive
            ? const [BoxShadow(color: Color(0x384DA3FF), blurRadius: 14)]
            : null,
      ),
      child: ventures.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(6),
              child: Text('NO HOLDINGS · ALL CASH',
                  style: bodyStyle(size: 11, color: kDim)),
            )
          : Column(
              children: [
                for (final v in ventures)
                  _HoldingRow(
                    key: Key('holding-${v.id}'),
                    venture: v,
                    partnerPerRoundCents:
                        controller.partnerPerRoundCents(v),
                    pickerActive: pickerActive,
                    onPick:
                        pickerActive ? () => onPick?.call(v.id) : null,
                  ),
              ],
            ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    super.key,
    required this.venture,
    this.partnerPerRoundCents = 0,
    this.pickerActive = false,
    this.onPick,
  });

  final Venture venture;

  /// Partner engines' total accrual (controller composition); 0 = none.
  final int partnerPerRoundCents;

  /// Row renders the aim glow + tap affordance (mockup tglow).
  final bool pickerActive;

  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final v = venture;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (pickerActive) ...[
            Text('▸',
                style: numStyle(15, color: kAccentHi, glow: kGlowAcc)),
            const SizedBox(width: 5),
          ],
          Text(
            // The deterministic per-sector flavor name (QUANTA…) the R13
            // engine added — never the raw "V1" id (work order #5).
            v.displayName,
            style: bodyStyle(size: 13, color: kAccentHi).copyWith(
              fontWeight: FontWeight.w600,
              shadows: kGlowAcc,
            ),
          ),
          const SizedBox(width: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: kDim,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              sectorToJson(v.sector),
              style: labelStyle(size: 8, color: kBadgeInk, tracking: 1),
            ),
          ),
          if (partnerPerRoundCents > 0) ...[
            const SizedBox(width: 6),
            // The hired-partner tag (round 11): the engines' per-round
            // accrual, engine values composed in the controller.
            Container(
              key: Key('partnerTag-${v.id}'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x594DFF8A)),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '+${formatMoney(partnerPerRoundCents)}/RD',
                style: bodyStyle(size: 9, color: kGain),
              ),
            ),
          ],
          const SizedBox(width: 9),
          _stat('EBITDA', formatMoney(v.ebitdaCents)),
          const SizedBox(width: 9),
          _stat(null, formatMultiple(v.multipleMilli)),
          const Spacer(),
          _stat('OWN', '${bpToPctTrunc(v.ownershipBp)}%'),
        ],
      ),
    );
    if (onPick == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPick,
      child: row,
    );
  }

  Widget _stat(String? label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (label != null) ...[
            Text(label, style: bodyStyle(size: 11, color: kDim)),
            const SizedBox(width: 3),
          ],
          Text(value, style: numStyle(17)),
        ],
      );
}

// ---------------------------------------------------------------------------
// PLAYS strip (docs/05 §3 S3: held consumables, spatially decoupled from
// the hand so the two scarcities never blur — `PLAYS [ x ] [ + ] held 1/2`)
// ---------------------------------------------------------------------------

class _PlaysStrip extends StatelessWidget {
  const _PlaysStrip({required this.controller, this.onTapHeld});

  final GameController controller;

  /// Held-chip tap (round 11: opens the USE/SELL sheet); null = inert.
  final void Function(String cardId)? onTapHeld;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final max = playsHeldMax(s.tier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      child: Row(
        children: [
          Text('PLAYS', style: labelStyle(tracking: 2)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final id in s.playsHeld)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: GestureDetector(
                        key: Key('play-$id'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onTapHeld == null
                            ? null
                            : () => onTapHeld!(id),
                        child: _playChip(
                          controller.content.byId(id).name.toUpperCase(),
                          kAccentHi,
                        ),
                      ),
                    ),
                  for (var i = s.playsHeld.length; i < max; i++)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: _EmptyPlaySlot(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'HELD ${s.playsHeld.length}/$max',
            key: const Key('playsHeldCount'),
            style: numStyle(14),
          ),
        ],
      ),
    );
  }

  Widget _playChip(String name, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: kPanel,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(name, style: bodyStyle(size: 10, color: color)),
      );
}

/// An unfilled inventory slot (`[ + ]` in the wireframe).
class _EmptyPlaySlot extends StatelessWidget {
  const _EmptyPlaySlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: kFaint),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text('+', style: bodyStyle(size: 10, color: kFaint)),
    );
  }
}

// ---------------------------------------------------------------------------
// The order blotter (mockup #blotter) — one ticket per hand card +
// lingering financing offers
// ---------------------------------------------------------------------------

class _Blotter extends StatelessWidget {
  const _Blotter({
    required this.controller,
    required this.selectedCardId,
    required this.exitSelected,
    required this.dimmed,
    required this.onTapTicket,
    required this.onTapExit,
  });

  final GameController controller;
  final String? selectedCardId;

  /// The EXIT OFFER ticket is the open confirm.
  final bool exitSelected;

  final bool dimmed;
  final void Function(String cardId) onTapTicket;

  /// EXIT OFFER ticket tap (opens the exit napkin).
  final VoidCallback onTapExit;

  @override
  Widget build(BuildContext context) {
    final ids = controller.blotterIds;
    final exit = controller.exitOfferPending
        ? controller.state.exitOffer
        : null;
    if (ids.isEmpty && exit == null) {
      return Center(
        child: Text('NO DEALS ON THE TAPE',
            style: bodyStyle(size: 11, color: kDim)),
      );
    }
    // THE SUGGESTED TICKET (docs/07 idle: attract-pulse on the suggested
    // deal): the first ADD-ON in the hand if any, else the EXIT OFFER. The
    // pulse runs only when the blotter is idle (nothing selected/aimed and
    // not dimmed/out-of-plays) — a selection's own glow takes over on tap.
    final suggestedAddonId = ids.firstWhere(
      (id) => controller.content.byId(id).type == CardType.addon,
      orElse: () => '',
    );
    final idle = !dimmed && selectedCardId == null && !exitSelected;
    final attractAddon = idle && suggestedAddonId.isNotEmpty;
    final attractExit = idle && suggestedAddonId.isEmpty && exit != null;
    return ListView(
      padding: const EdgeInsets.only(top: 2),
      children: [
        for (var i = 0; i < ids.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: DealIn(
              // Keyed by id so a fresh hand (new ids) remounts + deals in,
              // while a select (same ids) preserves the element (no replay).
              key: Key('dealin-${ids[i]}'),
              index: i,
              child: Opacity(
                opacity: dimmed ? 0.38 : 1,
                child: AttractPulse(
                  active: attractAddon && ids[i] == suggestedAddonId,
                  child: _Ticket(
                    key: Key('ticket-${ids[i]}'),
                    card: controller.content.byId(ids[i]),
                    market: controller.state.market,
                    // Engine-derived (dealflow glue), render-only.
                    addonBuyMultipleMilli:
                        controller.content.byId(ids[i]).type == CardType.addon
                            ? controller.addonBuyMultipleMilli(ids[i])
                            : null,
                    selected: ids[i] == selectedCardId,
                    onTap: () => onTapTicket(ids[i]),
                  ),
                ),
              ),
            ),
          ),
        // The per-round EXIT OFFER ticket (round 11; mockup .t-exit:
        // red badge, venture @ offer multiple, SELL / PAPER→CASH).
        if (exit != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: DealIn(
              key: Key('dealin-EXIT-${exit.ventureId}'),
              index: ids.length,
              child: Opacity(
                opacity: dimmed ? 0.38 : 1,
                child: AttractPulse(
                  active: attractExit,
                  child: _ExitTicket(
                    key: const Key('ticket-EXIT'),
                    offer: exit,
                    ventureName: controller.targetVenture(exit.ventureId)
                            ?.displayName ??
                        exit.ventureId.toUpperCase(),
                    selected: exitSelected,
                    onTap: onTapExit,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The EXIT OFFER blotter ticket (mockup `.ticket.t-exit`): red left
/// border + red EXIT badge, `VENTURE @ offer×` midline, SELL /
/// PAPER→CASH price column. Faces only — the fork math lives on the exit
/// napkin.
class _ExitTicket extends StatelessWidget {
  const _ExitTicket({
    super.key,
    required this.offer,
    required this.ventureName,
    required this.selected,
    required this.onTap,
  });

  final ExitOffer offer;

  /// The offered venture's flavor name (QUANTA…), resolved by the caller off
  /// the engine venture; falls back to the id if the venture is gone.
  final String ventureName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final side = selected
        ? const BorderSide(color: kAccent)
        : const BorderSide(color: kLine);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Transform.translate(
        offset: Offset(selected ? 3 : 0, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          decoration: BoxDecoration(
            color: kPanel,
            border: Border(
              left: BorderSide(
                  color: selected ? kAccentHi : kLoss, width: 3),
              top: side,
              right: side,
              bottom: side,
            ),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x384DA3FF), blurRadius: 14)]
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: kLoss,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Column(
                    children: [
                      Text('EXIT',
                          style: labelStyle(
                              color: Colors.white, tracking: .5)),
                      const SizedBox(height: 2),
                      Text(
                        'OFFER',
                        style: labelStyle(
                            size: 7,
                            color: const Color(0xBFFFFFFF),
                            tracking: .5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: ventureName,
                        style: numStyle(21)),
                    TextSpan(
                        text: ' @ ',
                        style: numStyle(17,
                            color: kFaint, glow: const [])),
                    TextSpan(
                        text:
                            formatMultiple(offer.offerMultipleMilli),
                        style: numStyle(21)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 84,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('SELL',
                          style: numStyle(22,
                              color: kAccentHi, glow: kGlowAcc)),
                    ),
                    const SizedBox(height: 2),
                    Text('PAPER→CASH',
                        style: labelStyle(size: 8, tracking: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket({
    super.key,
    required this.card,
    required this.market,
    this.addonBuyMultipleMilli,
    required this.selected,
    required this.onTap,
  });

  final Card card;
  final MarketState market;

  /// The engine-implied m_buy for an addon ticket (mockup `@ 4.5×`);
  /// null for every other type.
  final int? addonBuyMultipleMilli;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = cardKind(card);
    final side = selected
        ? const BorderSide(color: kAccent)
        : const BorderSide(color: kLine);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Transform.translate(
        offset: Offset(selected ? 3 : 0, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          decoration: BoxDecoration(
            color: kPanel,
            border: Border(
              left: BorderSide(
                  color: selected ? kAccentHi : kind.color, width: 3),
              top: side,
              right: side,
              bottom: side,
            ),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x384DA3FF), blurRadius: 14)]
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: kind.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Column(
                    children: [
                      Text(kind.badge,
                          style:
                              labelStyle(color: kBadgeInk, tracking: .5)),
                      if (kind.sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          kind.sub,
                          style: labelStyle(
                              size: 7,
                              color: const Color(0xBF0A0D10),
                              tracking: .5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _midline()),
              const SizedBox(width: 6),
              SizedBox(
                width: 84,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_px().$1,
                          style:
                              numStyle(22, color: kAccentHi, glow: kGlowAcc)),
                    ),
                    const SizedBox(height: 2),
                    Text(_px().$2,
                        style: labelStyle(size: 8, tracking: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The number-first midline, from card FACES only (raw inputs — the
  /// post-deal math is the engine's, revealed at commit; docs/05 §0.4).
  Widget _midline() {
    final big = numStyle(21);
    final small = bodyStyle(size: 12, color: kDim);
    final sep = numStyle(17, color: kFaint, glow: const []);
    List<InlineSpan> spans;
    switch (card.type) {
      case CardType.addon:
        // Mockup shape: `40k EBITDA @ 4.5×` — face EBITDA at the
        // engine-implied buy multiple.
        spans = [
          TextSpan(
              text: formatMoney(card.deltas['ebitda'] ?? 0), style: big),
          TextSpan(text: ' EBITDA ', style: small),
          if (addonBuyMultipleMilli != null) ...[
            TextSpan(text: '@', style: sep),
            TextSpan(
                text: ' ${formatMultiple(addonBuyMultipleMilli!)}',
                style: big),
          ],
        ];
      case CardType.venture:
        spans = [
          TextSpan(
              text: formatMoney(card.deltas['ebitda'] ?? 0), style: big),
          TextSpan(text: ' EBITDA ', style: small),
          TextSpan(text: '@', style: sep),
          TextSpan(
              text: ' ${formatMultiple(card.deltas['multiple'] ?? 0)}',
              style: big),
        ];
      case CardType.financing:
        final cash = card.deltas['cash'] ?? 0;
        final cashText =
            cash >= 0 ? '+${formatMoney(cash)}' : formatMoney(cash);
        if (card.cost.dilutionBp > 0) {
          spans = [
            TextSpan(text: cashText, style: big),
            TextSpan(text: ' · ', style: sep),
            TextSpan(
                text: '−${bpToPctTrunc(card.cost.dilutionBp)}%', style: big),
            TextSpan(text: ' OWN', style: small),
          ];
        } else {
          spans = [
            TextSpan(text: cashText, style: big),
            TextSpan(text: ' @ ', style: sep),
            TextSpan(
                text: market.liveRateBp > 0
                    ? '${bpToPctTrunc(market.liveRateBp)}%'
                    : '—',
                style: big),
          ];
        }
      case CardType.partner:
        // The partner face: the per-round engine accrual (mockup
        // wireframe `PARTNER … +EB/rd $30k`).
        spans = [
          TextSpan(
              text: '+${formatMoney(card.deltas['ebitda'] ?? 0)}',
              style: big),
          TextSpan(text: ' EBITDA ', style: small),
          TextSpan(text: '/RD', style: small),
        ];
      case CardType.consumable:
      case CardType.event:
        spans = [TextSpan(text: card.name.toUpperCase(), style: small)];
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Right column: (value, label).
  (String, String) _px() {
    switch (card.type) {
      case CardType.addon:
        return (formatMoney(card.cost.cashCents), 'BUY');
      case CardType.venture:
        return (formatMoney(card.cost.cashCents), 'FOUND');
      case CardType.financing:
        return card.cost.dilutionBp > 0
            ? ('TERMS', 'REVIEW')
            : ('DRAW', 'LEVER UP');
      case CardType.consumable:
        return (formatMoney(card.cost.cashCents), 'BUY');
      case CardType.partner:
        return (formatMoney(card.cost.cashCents), 'HIRE');
      case CardType.event:
        return ('—', '');
    }
  }
}

// ---------------------------------------------------------------------------
// Function key row (mockup #fkeys)
// ---------------------------------------------------------------------------

class _FkeyRow extends StatelessWidget {
  const _FkeyRow({
    required this.onReinvest,
    required this.onReroll,
    required this.onEndTurn,
    required this.rerollCostCents,
  });

  final VoidCallback onReinvest;

  /// Null renders the key dimmed and inert (cash-short reroll).
  final VoidCallback? onReroll;

  final VoidCallback onEndTurn;

  /// The engine's live scaling reroll fee in cents (controller.rerollCostCents,
  /// doc 02 §3.8/§4) — printed on the key, no longer a flat constant.
  final int rerollCostCents;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            flex: 10,
            child: ChunkyKey(
              key: const Key('reinvest'),
              icon: '⟳',
              label: 'REINVEST',
              onTap: onReinvest,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            flex: 10,
            child: ChunkyKey(
              key: const Key('reroll'),
              icon: '↻',
              label: 'REROLL ${formatMoney(rerollCostCents)}',
              onTap: onReroll,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            flex: 14,
            child: ChunkyKey(
              key: const Key('endTurn'),
              icon: '▸',
              label: 'END TURN',
              variant: ChunkyKeyVariant.primary,
              onTap: onEndTurn,
            ),
          ),
        ],
      ),
    );
  }
}
