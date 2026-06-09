/// The first-run TUTORIAL — teach-by-play, not a wall of text (docs/05
/// §first-5-minutes; game-design-doc §Q3 "show the chips, hide the wisdom").
///
/// THREE SURFACES work together (synthesized from the R22 design pass):
///   1. INTRO CARDS (screens/intro_cards.dart) — a short swipe-through shown
///      once at the start of a tutorial run; teaches the ONE equation + the
///      loop + the goal up front (the abstract stuff you can't discover).
///   2. IN-RUN COACHMARKS (this file + tutorial_overlay.dart) — terse
///      spotlights that fire ON the live beat the player is already looking
///      at, during the ACT phase.
///   3. GLOSSARY (screens/glossary_screen.dart) — always-available reference
///      for every finance term, reachable from the title menu.
///
/// COACHMARK MODEL (opportunistic, never stalls): each step has a [trigger]
/// that must fire before it can show, and a [core] flag. CORE steps are
/// guaranteed to fire (the ACT phase always happens) and gate completion;
/// OPTIONAL steps (add-on, arbitrage, debt, dilution…) show only if that beat
/// occurs but NEVER block the tutorial from finishing. This fixes the old
/// strict-cursor design, which silently stalled forever if the player never
/// happened to acquire an add-on or trigger an arbitrage.
///
/// PURE UI: no game logic. Steps point at named HUD targets the run screen
/// maps to a rectangle; the engine never sees any of it.
library;

// The controller stores the `active` ctor param in the private `_active`
// field (a named param can't itself be private), so the initializing-formal
// lint is a false positive here.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

/// Which HUD region a tutorial step spotlights. The run screen owns the
/// GlobalKey for each and converts it to a screen rect for the cut-out.
enum SpotlightTarget {
  /// The CASH (REAL) and NET WORTH (PAPER) boxes — real vs paper money.
  moneyBoxes,

  /// The EBITDA / MULT / DEBT / OWN lever row — the equation and its levers.
  equationLevers,

  /// The DEALS blotter / current hand — your plays.
  addonTicket,

  /// No anchor — dim the whole stage; the line itself is the payoff.
  none,
}

/// What real beat must occur before a step is allowed to show. The run screen
/// reports these as they happen; a step surfaces only once its trigger fired.
enum TutorialTrigger {
  /// The run's first ACT phase is on screen (HUD + blotter visible). Always
  /// fires — the backbone trigger for the CORE steps.
  actReady,

  /// The same beat as [actReady] (kept distinct so back-to-back HUD steps can
  /// each gate on their own trigger).
  actReadyTwo,

  /// An ADD-ON ticket is present in the current hand.
  addonInHand,

  /// An arbitrage flash was just dismissed (the gap was just realized).
  arbitrageSeen,

  /// The platform is carrying net debt (leverage is live).
  debtTaken,

  /// Your ownership has dropped below 100% (you've diluted).
  diluted,

  /// A round has completed / the deadline pace is now meaningful.
  paceSeen,
}

/// One coachmark: a [trigger] that gates it, a [target] to spotlight, the
/// terse [line], and an optional [fact] (a real finance fact or PE-satire
/// tip). [core] steps gate completion; optional ones are opportunistic.
class TutorialStep {
  /// Builds a step.
  const TutorialStep({
    required this.trigger,
    required this.target,
    required this.title,
    required this.line,
    this.fact,
    this.core = false,
  });

  /// The beat that must fire before this step can show.
  final TutorialTrigger trigger;

  /// What to spotlight.
  final SpotlightTarget target;

  /// The Silkscreen mini-heading.
  final String title;

  /// The one-line body (terse, witty — "show the chips, hide the wisdom").
  final String line;

  /// An optional second line: a real finance FACT or a PE-satire TIP.
  final String? fact;

  /// True for the guaranteed backbone steps that gate completion. Optional
  /// steps show opportunistically but never block the tutorial from ending.
  final bool core;
}

/// THE COACHMARK SCRIPT. Three CORE beats always fire (the ACT phase is
/// guaranteed) and gate completion; the rest are opportunistic — they land if
/// the player hits that mechanic, but never stall the tutorial.
const List<TutorialStep> kTutorialScript = [
  // --- CORE (always fire on the first ACT) ---
  TutorialStep(
    trigger: TutorialTrigger.actReady,
    target: SpotlightTarget.moneyBoxes,
    title: 'REAL vs PAPER',
    line: 'CASH is real and spends. NET WORTH is paper — it can vanish.',
    fact: 'Plenty of paper billionaires couldn’t cover brunch. Cash is king.',
    core: true,
  ),
  TutorialStep(
    trigger: TutorialTrigger.actReadyTwo,
    target: SpotlightTarget.equationLevers,
    title: 'THE EQUATION',
    line: 'A company’s worth = EBITDA × MULT. Grow either lever, the whole thing grows.',
    fact: 'Real PE firms live and die by this one formula.',
    core: true,
  ),
  TutorialStep(
    trigger: TutorialTrigger.actReady,
    target: SpotlightTarget.addonTicket,
    title: 'YOUR MOVES',
    line: 'A few plays per round. Buy, borrow, hire, or sell — spend them well.',
    fact: 'Dry powder that never fires is just a sad pile of cash.',
    core: true,
  ),
  // --- OPTIONAL (land on the moment, never block completion) ---
  TutorialStep(
    trigger: TutorialTrigger.addonInHand,
    target: SpotlightTarget.addonTicket,
    title: 'THE ADD-ON',
    line: 'Buy a small one cheap. Fold it into your platform. Watch it revalue.',
    fact: 'PE calls this a “roll-up” — bolt enough together and they reprice upward.',
  ),
  TutorialStep(
    trigger: TutorialTrigger.arbitrageSeen,
    target: SpotlightTarget.none,
    title: 'THAT GAP',
    line: 'You paid little; it’s worth more the instant it lands. That gap is the game.',
    fact: 'Same profit, fatter multiple. You conjured value from nothing. Arbitrage.',
  ),
  TutorialStep(
    trigger: TutorialTrigger.debtTaken,
    target: SpotlightTarget.equationLevers,
    title: 'LEVERAGE',
    line: 'DEBT buys bigger than your cash — but interest accrues every round. It never sleeps.',
    fact: 'Over-leveraged into a cold market is how empires die. Ask anyone from 2008.',
  ),
  TutorialStep(
    trigger: TutorialTrigger.diluted,
    target: SpotlightTarget.equationLevers,
    title: 'DILUTION',
    line: 'Raising equity pays cash now, but your OWN% drops. Smaller slice, bigger pie.',
    fact: 'Dilution is why founders build giants yet own almost none of them.',
  ),
  TutorialStep(
    trigger: TutorialTrigger.paceSeen,
    target: SpotlightTarget.none,
    title: 'THE CLOCK',
    line: 'Clear the tier’s net-worth bar before rounds run out, or the run is over.',
    fact: 'The pace meter warns you. Green = on track. Red = start taking risks.',
  ),
];

/// Drives the first-run tutorial. OPPORTUNISTIC: [currentStep] is the
/// lowest-index not-yet-shown step whose trigger has fired, so steps land in
/// order as their beats occur and a missing optional beat never blocks the
/// rest. Render-only; the run screen reads [currentStep] (null = nothing to
/// show now), calls [advance] on TAP TO CONTINUE, [skip] on SKIP, and
/// [fireTrigger] as beats occur. [finished] (all CORE steps shown, or skipped)
/// is the moment to latch AppSettings.tutorialSeen.
class TutorialController extends ChangeNotifier {
  /// Builds the controller. [active] starts it live (the first NEW RUN with
  /// tutorialSeen == false, or a GUIDED RUN); when false it is inert.
  TutorialController({required bool active, List<TutorialStep>? script})
      : _active = active,
        _script = script ?? kTutorialScript;

  final List<TutorialStep> _script;
  bool _active;

  /// Triggers that have fired so far.
  final Set<TutorialTrigger> _fired = {};

  /// Indices of steps already shown (dismissed).
  final Set<int> _shown = {};

  /// Whether the tutorial is still live this run (false once skipped).
  bool get active => _active;

  /// True once every CORE step has been shown, or the player skipped — the
  /// moment to latch AppSettings.tutorialSeen so it never auto-shows again.
  /// (Optional steps may still surface this run; they don't affect this.)
  bool get finished {
    if (!_active) return true;
    for (var i = 0; i < _script.length; i++) {
      if (_script[i].core && !_shown.contains(i)) return false;
    }
    return true;
  }

  /// The step to show RIGHT NOW: the lowest-index step not yet shown whose
  /// trigger has fired. Null = wait (no fired-and-unshown step) or done.
  TutorialStep? get currentStep {
    final i = _currentIndex;
    return i == null ? null : _script[i];
  }

  int? get _currentIndex {
    if (!_active) return null;
    for (var i = 0; i < _script.length; i++) {
      if (!_shown.contains(i) && _fired.contains(_script[i].trigger)) {
        return i;
      }
    }
    return null;
  }

  /// Reports a beat. Surfaces any step it unblocks on the next build.
  void fireTrigger(TutorialTrigger trigger) {
    if (!_active) return;
    if (_fired.add(trigger)) notifyListeners();
  }

  /// TAP TO CONTINUE: dismisses the current step.
  void advance() {
    if (!_active) return;
    final i = _currentIndex;
    if (i == null) return; // nothing showing — ignore stray taps
    _shown.add(i);
    notifyListeners();
  }

  /// SKIP TUTORIAL: ends it immediately (the run screen latches it seen).
  void skip() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}
