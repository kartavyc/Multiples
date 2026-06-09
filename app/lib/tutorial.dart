/// The first-run TUTORIAL — teach-by-play, not a wall of text (docs/05
/// §first-5-minutes "teach by reward not lecture"; game-design-doc §Q3 "show
/// the chips, hide the wisdom"). On the very first NEW RUN ever (the persisted
/// AppSettings.tutorialSeen flag), a few SPOTLIGHT coachmarks fire, each timed
/// to a beat the player is already looking at: it dims everything but one HUD
/// target, drops one terse line, and waits for a TAP TO CONTINUE. Skippable
/// at any time. Marked seen on finish/skip so it never auto-shows again
/// (re-showable from SETTINGS → REPLAY TUTORIAL).
///
/// PURE UI: this file holds NO game logic. The steps point at named HUD
/// targets (the CASH box, the EBITDA×MULT levers, an ADD-ON ticket, the
/// arbitrage flash) by an enum the run screen maps to a rectangle; the engine
/// never sees any of it. The controller is a plain [ChangeNotifier] the run
/// screen drives — it ADVANCES a step when the matching beat occurs (a step
/// is shown only once its trigger fires, so the copy lands on the live
/// moment, not before).
library;

// The TutorialController stores a `bool active` ctor param in the PRIVATE
// `_active` field (a named param cannot itself be private), so the
// initializing-formal lint is a false positive here.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

/// Which HUD region a tutorial step spotlights. The run screen owns the
/// GlobalKey for each and converts it to a screen rect for the cut-out.
enum SpotlightTarget {
  /// The CASH (REAL / solid blue) box and the NET WORTH (PAPER / dashed) box,
  /// side by side — step 1 contrasts the two.
  moneyBoxes,

  /// The EBITDA and MULT levers — step 2 ("value is a product").
  equationLevers,

  /// The first ADD-ON ticket in the blotter — step 3 ("fold it in").
  addonTicket,

  /// The whole stage — step 4 fires over the dismissed arbitrage flash, so it
  /// points at nothing specific; the line IS the payoff.
  none,
}

/// What real beat must occur before a step is allowed to show. The run screen
/// reports these as they happen; the controller only surfaces a step once its
/// trigger has fired (teach ON the moment).
enum TutorialTrigger {
  /// The run's first ACT phase is on screen (HUD + blotter visible).
  actReady,

  /// The same — the equation step rides the same beat as the money step
  /// (both are HUD, shown back-to-back).
  actReadyTwo,

  /// An ADD-ON ticket is present in the current hand.
  addonInHand,

  /// An arbitrage flash was just dismissed (the gap was just realized).
  arbitrageSeen,
}

/// One coachmark: a [trigger] that gates it, a [target] to spotlight, and the
/// terse line (the game's voice — tagline energy, no lecture).
class TutorialStep {
  /// Builds a step.
  const TutorialStep({
    required this.trigger,
    required this.target,
    required this.title,
    required this.line,
  });

  /// The beat that must fire before this step can show.
  final TutorialTrigger trigger;

  /// What to spotlight.
  final SpotlightTarget target;

  /// The Silkscreen mini-heading (e.g. REAL vs PAPER).
  final String title;

  /// The one-line body (terse, witty — "show the chips, hide the wisdom").
  final String line;
}

/// THE SCRIPT (docs/05 onboarding; design-doc §Q3). Four beats, each landing
/// on a live moment:
///   1. CASH vs NET WORTH — one is real, one is a promise.
///   2. EBITDA × MULT — value is a product, not a pile.
///   3. the first ADD-ON — buy cheap, fold it in, watch it revalue.
///   4. after the first arbitrage flash — the gap is free money. that's the game.
const List<TutorialStep> kTutorialScript = [
  TutorialStep(
    trigger: TutorialTrigger.actReady,
    target: SpotlightTarget.moneyBoxes,
    title: 'REAL vs PAPER',
    line: 'CASH is yours. NET WORTH is a promise. '
        'One spends. One can vanish.',
  ),
  TutorialStep(
    trigger: TutorialTrigger.actReadyTwo,
    target: SpotlightTarget.equationLevers,
    title: 'VALUE IS A PRODUCT',
    line: 'EBITDA × MULT. Grow either side, the whole thing grows. '
        'That is the equation.',
  ),
  TutorialStep(
    trigger: TutorialTrigger.addonInHand,
    target: SpotlightTarget.addonTicket,
    title: 'THE ADD-ON',
    line: 'Buy a small one cheap. Fold it into your platform. '
        'Watch it revalue at YOUR multiple.',
  ),
  TutorialStep(
    trigger: TutorialTrigger.arbitrageSeen,
    target: SpotlightTarget.none,
    title: 'THAT GAP',
    line: 'You paid little. It is worth more the instant it lands. '
        "That gap is free money. That's the game.",
  ),
];

/// Drives the first-run tutorial: a cursor into [kTutorialScript] gated by the
/// triggers the run screen reports. Render-only; the run screen reads
/// [currentStep] (null = nothing to show right now) and calls [advance] on a
/// TAP TO CONTINUE, [skip] on SKIP TUTORIAL, and [fireTrigger] as beats occur.
class TutorialController extends ChangeNotifier {
  /// Builds the controller. [active] starts the tutorial live (the first NEW
  /// RUN with tutorialSeen == false); when false it is inert from the start
  /// (every getter empty) so a returning player sees nothing.
  TutorialController({required bool active, List<TutorialStep>? script})
      : _active = active,
        _script = script ?? kTutorialScript;

  final List<TutorialStep> _script;
  bool _active;

  /// The triggers that have fired so far (a step shows only once its trigger
  /// is in here AND it is the cursor's step).
  final Set<TutorialTrigger> _fired = {};

  /// The cursor into the script (steps before it are done).
  int _cursor = 0;

  /// Whether the tutorial is still running (not skipped / finished).
  bool get active => _active && _cursor < _script.length;

  /// True once every step has been shown OR the player skipped — the moment
  /// to latch AppSettings.tutorialSeen. Idempotent to read.
  bool get finished => _active == false || _cursor >= _script.length;

  /// The step to show RIGHT NOW: the cursor's step, but only if its trigger
  /// has fired. Null means "wait" (the beat hasn't happened) or "done".
  TutorialStep? get currentStep {
    if (!active) return null;
    final step = _script[_cursor];
    return _fired.contains(step.trigger) ? step : null;
  }

  /// Reports a beat. If it unblocks the cursor's step (or a later one whose
  /// earlier triggers already fired), the overlay appears on the next build.
  void fireTrigger(TutorialTrigger trigger) {
    if (!active) return;
    if (_fired.add(trigger)) notifyListeners();
  }

  /// TAP TO CONTINUE: advances past the current step. If that finishes the
  /// script the tutorial ends (the run screen then latches it seen).
  void advance() {
    if (!active) return;
    if (currentStep == null) return; // nothing showing — ignore stray taps
    _cursor++;
    notifyListeners();
  }

  /// SKIP TUTORIAL: ends it immediately (the run screen latches it seen).
  void skip() {
    if (!_active) return;
    _active = false;
    _cursor = _script.length;
    notifyListeners();
  }
}
