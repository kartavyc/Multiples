/// The shared juice toolkit (docs/07 "Juice rules"): count-ups, the
/// screen shake, the spark burst, the overshoot pop, and the safe haptic
/// wrappers. SKIN ONLY — every number rendered through these widgets is an
/// engine value formatted by an engine helper; the only math here is
/// presentation interpolation between two engine numbers (never fed back).
///
/// Timings are SPECIFIED by the bible + the v4 mockup keyframes:
/// count-ups ~700ms ease-out cubic staged 350ms apart; headline pop
/// overshoot 1.25 (mockup `bigpop` .55s); shake ~420ms (mockup `shake`);
/// sparks ~20 particles over ~800ms; NW surge count ~900ms.
///
/// Everything animates off AnimationControllers — no Timer / Future.delayed
/// anywhere, so `tester.pump(Duration)` steps every beat deterministically
/// and nothing leaks real timers into widget tests.
library;

import 'dart:math' as math; // app layer only; the ENGINE bans dart:math

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Linear interpolation between two engine fixed-point ints for count-up
/// display. Presentation-only; rounded back to int so the engine formatter
/// gets a real fixed-point value.
int lerpFixed(int from, int to, double t) => from + ((to - from) * t).round();

/// The HAPTICS gate (R20 SETTINGS): when false, every safeHaptic* call is a
/// no-op. Driven live by AppSettingsController.setHapticsOn (settings.dart);
/// defaults ON (a fresh install vibrates). A module-level flag (not threaded
/// through every call site) so the four scattered beats stay one-liners.
bool _hapticsEnabled = true;

/// Sets the haptics gate (settings.dart calls this on load + every toggle).
void setHapticsEnabledGate(bool enabled) => _hapticsEnabled = enabled;

/// Whether device vibration is currently enabled (visible for tests).
@visibleForTesting
bool get hapticsEnabledForTest => _hapticsEnabled;

/// The injectable haptic SINK so tests can assert a beat fired (or did NOT)
/// without a platform channel. Production drives [HapticFeedback]; the
/// suppression test swaps in a recording sink. 'heavy' | 'light'.
typedef HapticSink = void Function(String impact);

HapticSink _hapticSink = _platformHaptic;

/// Overrides the haptic sink (tests record instead of buzzing). Pass null to
/// restore the real platform sink.
@visibleForTesting
void setHapticSinkForTest(HapticSink? sink) =>
    _hapticSink = sink ?? _platformHaptic;

void _platformHaptic(String impact) {
  try {
    final f = impact == 'heavy'
        ? HapticFeedback.heavyImpact()
        : HapticFeedback.lightImpact();
    f.catchError((_) {});
  } catch (_) {
    // No platform: juice degrades silently (docs/05 §0.2 — garnish).
  }
}

/// Device vibration for the big beats (bible: vibrate 80ms ~ heavyImpact).
/// Gated by the R20 haptics setting; a missing platform channel (widget
/// tests, desktop) is also a silent no-op.
void safeHapticHeavy() {
  if (!_hapticsEnabled) return;
  _hapticSink('heavy');
}

/// Light tick (tier-bar fill completion). Gated by the haptics setting.
void safeHapticLight() {
  if (!_hapticsEnabled) return;
  _hapticSink('light');
}

/// The mockup `bigpop` scale curve: .3 -> overshoot [peak] at 60% -> 1.0.
double overshootScale(double t, {double peak = 1.25}) {
  if (t <= 0) return .3;
  if (t < .6) return .3 + (peak - .3) * (t / .6);
  if (t >= 1) return 1;
  return peak + (1 - peak) * ((t - .6) / .4);
}

/// The mockup `bannerin` ease: cubic-bezier(.34,1.7,.64,1) — overshoots.
const Curve kBannerInCurve = Cubic(.34, 1.7, .64, 1);

/// The mockup `mkstamp` ease: cubic-bezier(.34,1.6,.64,1).
const Curve kStampCurve = Cubic(.34, 1.6, .64, 1);

/// A count-up text: while [animation] runs the value lerps [fromCents] ->
/// [toCents] in gain green (mockup `countUp` paints green during the
/// climb), then settles to [style] at rest. [fmt] MUST be an engine
/// formatter (formatMoney / formatMultiple).
class CountUpText extends StatelessWidget {
  /// Builds the count-up over an externally driven 0..1 [animation]
  /// (already curved/intervaled by the owning screen's master controller).
  const CountUpText({
    super.key,
    required this.animation,
    required this.from,
    required this.to,
    required this.fmt,
    required this.style,
    this.greenWhileCounting = true,
  });

  /// The 0..1 progress (curved upstream).
  final Animation<double> animation;

  /// Start value (engine fixed-point int).
  final int from;

  /// End value (engine fixed-point int).
  final int to;

  /// Engine formatter for the lerped value.
  final String Function(int) fmt;

  /// Rest style (the value settles here at t == 1).
  final TextStyle style;

  /// Mockup behavior: the number burns green while climbing.
  final bool greenWhileCounting;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final counting = greenWhileCounting && t < 1;
        return Text(
          fmt(lerpFixed(from, to, t)),
          style: counting
              ? style.copyWith(color: kGain, shadows: kGlowGain)
              : style,
        );
      },
    );
  }
}

/// Re-triggerable shake signal: screens own a [ShakeController]; any beat
/// calls [shake] and every listening [ShakeWidget] plays the mockup's
/// 420ms translate keyframes once.
class ShakeController extends ChangeNotifier {
  /// Monotone trigger count (listeners restart on change).
  int epoch = 0;

  /// Fires one ~420ms shake on every listening [ShakeWidget].
  void shake() {
    epoch++;
    notifyListeners();
  }
}

/// Plays the mockup `shake` keyframes (~420ms linear) on [child] whenever
/// [controller] fires. Identity transform at rest.
class ShakeWidget extends StatefulWidget {
  /// Builds the shaker.
  const ShakeWidget({super.key, required this.controller, required this.child});

  /// The trigger.
  final ShakeController controller;

  /// The shaken subtree.
  final Widget child;

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  // initState-created (a late-final controller first touched in dispose
  // would create its Ticker during teardown — unsafe ancestor lookup).
  late final AnimationController _t;
  int _seenEpoch = 0;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1, // at rest until fired
    );
    _seenEpoch = widget.controller.epoch;
    widget.controller.addListener(_onFire);
  }

  void _onFire() {
    if (widget.controller.epoch != _seenEpoch) {
      _seenEpoch = widget.controller.epoch;
      _t.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFire);
    _t.dispose();
    super.dispose();
  }

  /// Mockup `shake` keyframes: 0(0,0) 15%(-5,3) 30%(5,-3) 45%(-4,-2)
  /// 60%(4,2) 80%(-2,1) 100%(0,0); linear between stops.
  static const List<(double, Offset)> _keys = [
    (0, Offset.zero),
    (.15, Offset(-5, 3)),
    (.30, Offset(5, -3)),
    (.45, Offset(-4, -2)),
    (.60, Offset(4, 2)),
    (.80, Offset(-2, 1)),
    (1, Offset.zero),
  ];

  Offset _offsetAt(double t) {
    for (var i = 1; i < _keys.length; i++) {
      if (t <= _keys[i].$1) {
        final (t0, a) = _keys[i - 1];
        final (t1, b) = _keys[i];
        final k = (t - t0) / (t1 - t0);
        return Offset(a.dx + (b.dx - a.dx) * k, a.dy + (b.dy - a.dy) * k);
      }
    }
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.translate(
        offset: _t.value >= 1 ? Offset.zero : _offsetAt(_t.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// The ~20-particle spark burst (mockup `burstSparks`): squares scatter
/// from the center, fading and shrinking over [animation]. Directions come
/// from a seeded dart:math Random (app layer; deterministic per [seed],
/// purely cosmetic — the engine never sees it).
class SparkBurst extends StatelessWidget {
  /// Builds the burst over an externally driven 0..1 [animation].
  const SparkBurst({
    super.key,
    required this.animation,
    this.count = 20,
    this.seed = 14,
  });

  /// The 0..1 scatter progress.
  final Animation<double> animation;

  /// Particle count (bible: ~20 sparks).
  final int count;

  /// Cosmetic RNG seed for the scatter directions.
  final int seed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => CustomPaint(
          painter: _SparkPainter(t: animation.value, count: count, seed: seed),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.t, required this.count, required this.seed});

  final double t;
  final int count;
  final int seed;

  static const List<Color> _cols = [kAccent, kGain, kFg];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final rng = math.Random(seed);
    final center = Offset(size.width / 2, size.height / 2);
    final eased = Curves.easeOut.transform(t);
    for (var i = 0; i < count; i++) {
      final ang = rng.nextDouble() * math.pi * 2;
      // Per-particle reach + a speed jitter so the burst scatters at varied
      // rates (richer than a uniform ring; bible ~20 sparks).
      final dist = 50 + rng.nextDouble() * 130;
      final speed = 0.7 + rng.nextDouble() * 0.6;
      final reach = (dist * eased * speed).clamp(0.0, dist);
      // A touch of gravity so a few sparks arc down — reads less mechanical.
      final drop = 26 * t * t * rng.nextDouble();
      final pos = center +
          Offset(math.cos(ang), math.sin(ang)) * reach +
          Offset(0, drop);
      final base = 4 + rng.nextDouble() * 5; // varied seed size 4..9
      final color = _cols[i % 3].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      final paint = Paint()..color = color;
      // Mix squares and diamonds so the confetti isn't one shape.
      if (i.isEven) {
        final side = base * (1 - t * .8);
        canvas.drawRect(
            Rect.fromCenter(center: pos, width: side, height: side), paint);
      } else {
        final r = base * .6 * (1 - t * .8);
        final path = Path()
          ..moveTo(pos.dx, pos.dy - r)
          ..lineTo(pos.dx + r, pos.dy)
          ..lineTo(pos.dx, pos.dy + r)
          ..lineTo(pos.dx - r, pos.dy)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.t != t || old.count != count || old.seed != seed;
}


/// Small-delta HUD juice (R14 polish / audit L2): a value box that, whenever
/// its engine [cents] changes, (1) pops the number with a brief scale kick
/// and (2) floats a small `+$X` / `−$Y` chip up off the top-right, fading
/// over ~900ms. Unlike the NW surge (signature, gains only), this fires on
/// EVERY change, up OR down — green for a gain, loss-red for a drop — so the
/// CASH box always answers an action with motion.
///
/// SKIN ONLY: [cents] is an engine value, [fmt] an engine formatter; the
/// only math is the presentation delta between two engine numbers (never fed
/// back). Driven by an AnimationController, so `pump(Duration)` steps it and
/// no real timer leaks. The first build (no prior value) does NOT animate.
class FloatingDeltaBox extends StatefulWidget {
  /// Wraps [child] (the value box), watching [cents] for changes; [fmt] is
  /// the engine formatter for the floating delta amount.
  const FloatingDeltaBox({
    super.key,
    required this.cents,
    required this.fmt,
    required this.child,
    this.peak = 1.12,
    this.floatFontSize = 16,
    this.deltaKey = const Key('cashFloatDelta'),
    this.popAlignment = Alignment.centerLeft,
  });

  /// The live engine value the box shows (the delta is computed vs the
  /// previous build's value).
  final int cents;

  /// Engine formatter for the floated delta magnitude (formatMoney).
  final String Function(int) fmt;

  /// Scale-pop peak (the CASH box uses a gentle 1.12; the four levers tick
  /// at the bible's `tickpop` 1.3 — docs/07 "stat ticks scale-pop 1.3×").
  final double peak;

  /// The floated `+$X` chip font size (smaller on the narrow levers).
  final double floatFontSize;

  /// Test key for the floated delta chip (each lever gets its own so the
  /// pump-and-settle tests can target one).
  final Key deltaKey;

  /// Scale-pop anchor (CASH pops from its left-aligned hero number; the
  /// centered levers pop from their center).
  final Alignment popAlignment;

  /// The value box to pop on change.
  final Widget child;

  @override
  State<FloatingDeltaBox> createState() => _FloatingDeltaBoxState();
}

class _FloatingDeltaBoxState extends State<FloatingDeltaBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  int _delta = 0;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1, // at rest (no float) until the value changes
    );
  }

  @override
  void didUpdateWidget(FloatingDeltaBox old) {
    super.didUpdateWidget(old);
    if (widget.cents != old.cents) {
      _delta = widget.cents - old.cents;
      _t.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// Scale-pop: a quick 1.0 -> [widget.peak] -> 1.0 kick over the first
  /// ~280ms (the mockup `tickpop` shape: peak at ~35%, settle by 100%).
  double _pop(double t) {
    final peak = widget.peak;
    const window = 280 / 900;
    if (t >= window) return 1;
    final k = t / window;
    return k < .5 ? 1 + (peak - 1) * (k / .5) : peak - (peak - 1) * ((k - .5) / .5);
  }

  @override
  Widget build(BuildContext context) {
    final gain = _delta >= 0;
    final sign = gain ? '+' : '−';
    final color = gain ? kGain : kLoss;
    final glow = gain ? kGlowGain : kGlowLoss;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final running = _t.value < 1;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.scale(
              scale: running ? _pop(_t.value) : 1,
              alignment: widget.popAlignment,
              child: child,
            ),
            if (running && _delta != 0)
              Positioned(
                top: -6 - 18 * _t.value, // drifts up
                right: 4,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1 - _t.value).clamp(0.0, 1.0),
                    child: Text(
                      '$sign${widget.fmt(_delta.abs())}',
                      key: widget.deltaKey,
                      style: numStyle(widget.floatFontSize,
                          color: color, glow: glow),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}


/// THE DEAL-IN (docs/07 idle/commit: a fresh hand slides in, never a hard
/// appear; mockup ticket `transition: transform .12s`). When a new ticket
/// MOUNTS — which happens exactly when a fresh hand is dealt, since the hand
/// ids (and thus the ticket keys) change — it slides in from the right and
/// fades up over ~260ms, staggered by [index] so the blotter deals like a
/// dot-matrix print head. Selecting a ticket keeps the same keys (no
/// remount), so the deal-in does NOT replay on a tap. Pure mount-driven
/// AnimationController; `pump(Duration)` steps it, no real timer leaks.
class DealIn extends StatefulWidget {
  /// Wraps a freshly-dealt [child] (a blotter ticket) with the slide+fade-in.
  const DealIn({
    super.key,
    required this.index,
    required this.child,
    this.stagger = const Duration(milliseconds: 55),
    this.duration = const Duration(milliseconds: 260),
  });

  /// Row position in the blotter (drives the stagger delay).
  final int index;

  /// The ticket.
  final Widget child;

  /// Per-row stagger between deal-in starts.
  final Duration stagger;

  /// One ticket's slide-in length.
  final Duration duration;

  @override
  State<DealIn> createState() => _DealInState();
}

class _DealInState extends State<DealIn> with SingleTickerProviderStateMixin {
  // initState-created. The controller runs `duration + index*stagger` so the
  // first fraction is the stagger HOLD (value pinned at 0 = off-screen) and
  // the tail is the slide.
  late final AnimationController _t;
  late final double _holdFraction;

  @override
  void initState() {
    super.initState();
    final total = widget.duration + widget.stagger * widget.index;
    _holdFraction = total.inMicroseconds == 0
        ? 0
        : (widget.stagger * widget.index).inMicroseconds / total.inMicroseconds;
    _t = AnimationController(vsync: this, duration: total)..forward();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        // Map [holdFraction..1] -> [0..1]; the hold keeps the ticket parked.
        final raw =
            ((_t.value - _holdFraction) / (1 - _holdFraction)).clamp(0.0, 1.0);
        final k = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: k,
          child: Transform.translate(
            offset: Offset(34 * (1 - k), 0), // slides in from the right
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// THE ATTRACT-PULSE (docs/07 idle list: "attract-pulse on the suggested
/// ticket"; mockup `.ticket.attract` 1.4s ease-in-out infinite — the box
/// glow + border breathe blue). Wraps the SUGGESTED ticket (the first ADD-ON,
/// or the EXIT OFFER) and pulses until it is tapped/selected. [active] gates
/// it: a selected/aimed ticket drops the pulse (the selection glow takes
/// over). One looping controller; legible static when [active] is false.
class AttractPulse extends StatefulWidget {
  /// Wraps [child] (a ticket); pulses while [active].
  const AttractPulse({
    super.key,
    required this.active,
    required this.child,
  });

  /// Whether to pulse (false = inert, the child renders plain).
  final bool active;

  /// The ticket to breathe.
  final Widget child;

  @override
  State<AttractPulse> createState() => _AttractPulseState();
}

class _AttractPulseState extends State<AttractPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400), // mockup attract 1.4s
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AttractPulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Start/stop the loop to match [widget.active]. The repeat is deferred to
  /// the next frame (never started synchronously during mount) — starting a
  /// repeating ticker mid-build can trip fake-async's `elapsedInSeconds >= 0`
  /// assertion when several loops mount in one pump (the keypulse keys + this
  /// pulse). Idempotent: re-checks `active` when the callback fires.
  void _sync() {
    if (widget.active) {
      if (!_t.isAnimating) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.active && !_t.isAnimating) {
            _t.repeat(reverse: true);
          }
        });
      }
    } else if (_t.isAnimating) {
      _t
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        // mockup attract: shadow 0 -> 14px blue @50%; a soft outer glow that
        // does NOT shift layout (legibility is untouched).
        final k = Curves.easeInOut.transform(_t.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: kAccent.withValues(alpha: .35 * k),
                blurRadius: 14 * k,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
