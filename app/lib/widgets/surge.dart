/// THE NET-WORTH SURGE — the signature beat (docs/07 "two sacred
/// treatments" #2): whenever net worth rises on a player action, the NW
/// ghost box flips green and counts up (~900ms ease-out cubic), a
/// screen-wide green tint + inset glow rises, the screen shakes (~420ms),
/// the device vibrates (~80ms) — then everything settles back to ghost
/// (full beat ~1700ms, the mockup `nwSurge` timeline). Death screens get
/// NONE of this.
///
/// [SurgeController] is the reusable trigger watching net-worth
/// transitions: the run screen feeds it the before/after engine values
/// around every action dispatch; an arbitrage flash DEFERS the surge until
/// BOOK IT dismisses the takeover (the flash owns the first beat).
///
/// SKIN ONLY: the from/to values are engine net-worth cents; interpolation
/// is presentation-only (juice.dart [lerpFixed]); formatting is engine
/// money.dart.
library;

import 'package:engine/money.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'juice.dart';

/// Total surge beat length (mockup: settle at 1700ms).
const Duration kSurgeTotal = Duration(milliseconds: 1700);

/// The count-up window inside the beat (~900ms per the bible).
const double kSurgeCountFraction = 900 / 1700;

/// Watches net-worth transitions and broadcasts surge beats. The run
/// screen calls [fire] (or [defer] + [fireDeferred] around a flash);
/// [SurgeTint] and [SurgeNwBox] listen and animate; the tint calls
/// [settle] when the beat completes.
class SurgeController extends ChangeNotifier {
  /// Count-up start (engine cents).
  int fromCents = 0;

  /// Count-up end (engine cents).
  int toCents = 0;

  /// Monotone beat counter (listeners restart on change).
  int epoch = 0;

  /// True from [fire] until [settle].
  bool active = false;

  int? _defFrom;
  int? _defTo;

  /// True when a deferred rise is queued (the run screen's audio router
  /// rings sfx_nw_surge alongside [fireDeferred] on BOOK IT / CASHED OUT —
  /// presentation-only, no logic).
  bool get hasDeferredRise => _defFrom != null && _defTo != null;

  /// Starts a surge beat for a net-worth rise [from] -> [to] (engine
  /// cents). A non-increase is ignored — the surge NEVER fires downward
  /// (losses get no celebration).
  void fire(int from, int to) {
    if (to <= from) return;
    fromCents = from;
    toCents = to;
    epoch++;
    active = true;
    notifyListeners();
  }

  /// Holds a rise to celebrate AFTER the arbitrage flash is dismissed.
  void defer(int from, int to) {
    if (to <= from) return;
    _defFrom = from;
    _defTo = to;
  }

  /// Fires the held rise, if any (BOOK IT path).
  void fireDeferred() {
    final f = _defFrom, t = _defTo;
    _defFrom = null;
    _defTo = null;
    if (f != null && t != null) fire(f, t);
  }

  /// Ends the beat (the tint's animation-complete callback).
  void settle() {
    if (!active) return;
    active = false;
    notifyListeners();
  }
}

/// The screen-wide green tint + inset glow layer (mockup `#tint.surge`).
/// Also owns the beat side effects: haptic + shake at onset, [SurgeController.settle]
/// at the end. Mount once above the stage, below the CRT overlay.
class SurgeTint extends StatefulWidget {
  /// Builds the tint listening to [surge]; [shake] receives the onset kick.
  const SurgeTint({super.key, required this.surge, required this.shake});

  /// The beat source.
  final SurgeController surge;

  /// The screen shaker to kick at onset.
  final ShakeController shake;

  @override
  State<SurgeTint> createState() => _SurgeTintState();
}

class _SurgeTintState extends State<SurgeTint>
    with SingleTickerProviderStateMixin {
  // Created in initState (NEVER lazily: a late-final controller first
  // touched in dispose() would create its Ticker during teardown — an
  // unsafe ancestor lookup that crashes the widget-tree finalizer).
  late final AnimationController _t;
  int _seenEpoch = 0;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: kSurgeTotal)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.surge.settle();
      });
    _seenEpoch = widget.surge.epoch;
    widget.surge.addListener(_onBeat);
  }

  void _onBeat() {
    if (widget.surge.epoch != _seenEpoch) {
      _seenEpoch = widget.surge.epoch;
      widget.shake.shake();
      safeHapticHeavy();
      _t.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.surge.removeListener(_onBeat);
    _t.dispose();
    super.dispose();
  }

  /// Tint envelope: fast rise (0..15%), hold, fade out (85%..100%).
  static double _envelope(double t) {
    if (t <= 0 || t >= 1) return 0;
    if (t < .15) return t / .15;
    if (t > .85) return (1 - t) / .15;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final k = _t.isAnimating ? _envelope(_t.value) : 0.0;
          if (k == 0) return const SizedBox.shrink();
          return Stack(
            key: const Key('nwSurgeTint'),
            fit: StackFit.expand,
            children: [
              // rgba(77,255,138,.07) wash
              ColoredBox(color: kGain.withValues(alpha: .07 * k)),
              // inset 0 0 80px rgba(77,255,138,.22) — edge glow vignette
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.2,
                    colors: [
                      const Color(0x00000000),
                      const Color(0x00000000),
                      kGain.withValues(alpha: .22 * k),
                    ],
                    stops: const [0, .62, 1],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The NET WORTH quote box, surge-aware: renders the normal PAPER
/// [GhostBox] at rest; while a beat runs it flips green (dashed border and
/// ink go gain-green, the value glows) and counts up from the
/// controller's engine values, then settles back to ghost showing [value].
class SurgeNwBox extends StatefulWidget {
  /// Builds the box; [value] is the engine-formatted live net worth shown
  /// at rest.
  const SurgeNwBox({super.key, required this.surge, required this.value});

  /// The beat source.
  final SurgeController surge;

  /// Rest value (engine-formatted; the live state's net worth).
  final String value;

  @override
  State<SurgeNwBox> createState() => _SurgeNwBoxState();
}

class _SurgeNwBoxState extends State<SurgeNwBox>
    with SingleTickerProviderStateMixin {
  // initState-created (see _SurgeTintState: lazy creation in dispose is
  // an unsafe ancestor lookup).
  late final AnimationController _t;
  int _seenEpoch = 0;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: kSurgeTotal);
    _seenEpoch = widget.surge.epoch;
    widget.surge.addListener(_onBeat);
  }

  void _onBeat() {
    if (widget.surge.epoch != _seenEpoch) {
      _seenEpoch = widget.surge.epoch;
      _t.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.surge.removeListener(_onBeat);
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.surge.active) {
      return GhostBox(
        label: 'NET WORTH',
        tag: 'PAPER',
        value: widget.value,
        valueKey: const Key('netWorth'),
      );
    }
    // The surge skin: green dashed box, value counting up ~900ms.
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final raw = (_t.value / kSurgeCountFraction).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(raw);
        final cents =
            lerpFixed(widget.surge.fromCents, widget.surge.toCents, eased);
        return CustomPaint(
          foregroundPainter: const DashedRectPainter(color: kGain),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NET WORTH', style: labelStyle(color: kGain)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatMoney(cents),
                        key: const Key('nwSurgeValue'),
                        style: numStyle(38, color: kGain, glow: kGlowGain),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: CustomPaint(
                    painter: const DashedRectPainter(color: kGain),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('PAPER',
                          style: bodyStyle(size: 9, color: kGain)
                              .copyWith(letterSpacing: 1)),
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
}
