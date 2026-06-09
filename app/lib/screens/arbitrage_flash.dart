/// S6 — THE MULTIPLE ARBITRAGE FLASH (mockup #arb; docs/07 commit beat):
/// the full-screen takeover after a committed AcquireAddOn. Timeline (the
/// mockup's, verbatim): banner-in 500ms overshoot → EBITDA count-up
/// 700ms ease-out at t=350 → EV count-up 700ms at t=1100 (the 350ms
/// stagger after the first lands) → t=1900 the +$ accretion headline POPS
/// (VT323 64, scale overshoot 1.25) + screen shake (~420ms) + ~20 sparks +
/// heavy haptic → BOOK IT. The headline is the MULTIPLE_ARBITRAGE event's
/// RENDER-ONLY amount; every other number is an engine value off
/// [ArbitrageFlashData]. One master AnimationController — no timers.
library;

import 'package:engine/money.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/juice.dart';

/// Master timeline length.
const Duration _kTimeline = Duration(milliseconds: 2700);

/// The takeover overlay.
class ArbitrageFlash extends StatefulWidget {
  /// Builds the flash for [data]; [onBookIt] dismisses (and releases the
  /// deferred NW surge upstream); [shake] gets the headline kick.
  const ArbitrageFlash({
    super.key,
    required this.data,
    required this.onBookIt,
    required this.shake,
  });

  /// Engine values captured at commit (controller doc).
  final ArbitrageFlashData data;

  /// BOOK IT handler.
  final VoidCallback onBookIt;

  /// The screen shaker (kicked when the headline pops).
  final ShakeController shake;

  @override
  State<ArbitrageFlash> createState() => _ArbitrageFlashState();
}

class _ArbitrageFlashState extends State<ArbitrageFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: _kTimeline);
  bool _kicked = false;

  // Interval anchors (ms over the 2700ms master).
  static const double _len = 2700;
  late final Animation<double> _banner = CurvedAnimation(
    parent: _t,
    curve: const Interval(0, 500 / _len, curve: kBannerInCurve),
  );
  late final Animation<double> _ebitda = CurvedAnimation(
    parent: _t,
    curve: const Interval(350 / _len, 1050 / _len, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _ev = CurvedAnimation(
    parent: _t,
    curve: const Interval(1100 / _len, 1800 / _len, curve: Curves.easeOutCubic),
  );

  /// Headline pop progress (linear 1900..2450; the overshoot shape is
  /// juice.overshootScale).
  late final Animation<double> _pop = CurvedAnimation(
    parent: _t,
    curve: const Interval(1900 / _len, 2450 / _len),
  );

  /// Spark scatter (1900..2700).
  late final Animation<double> _sparks = CurvedAnimation(
    parent: _t,
    curve: const Interval(1900 / _len, 1, curve: Curves.linear),
  );

  @override
  void initState() {
    super.initState();
    _t.addListener(_onTick);
    _t.forward();
  }

  void _onTick() {
    // The headline beat: shake + haptic exactly once as the pop starts.
    if (!_kicked && _t.value >= 1900 / _len) {
      _kicked = true;
      widget.shake.shake();
      safeHapticHeavy();
    }
  }

  @override
  void dispose() {
    _t.removeListener(_onTick);
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final rowStyle = numStyle(24);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // takeover: absorb everything
        child: ColoredBox(
          color: const Color(0xF5000000), // mockup rgba(0,0,0,.96)
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // *** MULTIPLE ARBITRAGE *** banner-in.
                      AnimatedBuilder(
                        animation: _banner,
                        builder: (context, child) => Transform.scale(
                          scale: .3 + .7 * _banner.value,
                          child: Opacity(
                            opacity: _banner.value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                        child: Text(
                          '*** MULTIPLE\nARBITRAGE ***',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: kFontLabel,
                            fontSize: 22,
                            letterSpacing: 2,
                            height: 1.25,
                            color: kFg,
                            shadows: [
                              Shadow(
                                  color: Color(0x59E6EDF3), blurRadius: 5),
                              Shadow(
                                  color: Color(0x40E6EDF3), blurRadius: 40),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // What you paid for ⟶ where it bolted in.
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                              fontFamily: kFontNum,
                              fontSize: 20,
                              color: kDim),
                          children: [
                            TextSpan(
                                text: formatMoney(d.addonEbitdaCents)),
                            TextSpan(
                              text:
                                  ' @ ${formatMultiple(d.buyMultipleMilli)}',
                              style: const TextStyle(
                                  color: kAccentHi, shadows: kGlowAcc),
                            ),
                            const TextSpan(text: ' ⟶ '),
                            TextSpan(
                              text:
                                  formatMultiple(d.boltInMultipleMilli),
                              style: const TextStyle(
                                  color: kAccentHi, shadows: kGlowAcc),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      // The math box: staged count-ups.
                      Center(
                        child: Container(
                          constraints:
                              const BoxConstraints(minWidth: 260),
                          padding:
                              const EdgeInsets.fromLTRB(14, 8, 14, 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: kLine),
                            color: const Color(0x06E6EDF3),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              _mathRow(
                                'EBITDA',
                                CountUpText(
                                  key: const Key('arbEbitda'),
                                  animation: _ebitda,
                                  from: d.ebitdaFromCents,
                                  to: d.ebitdaToCents,
                                  fmt: formatMoney,
                                  style: rowStyle,
                                ),
                              ),
                              _mathRow(
                                'MULT',
                                Text(
                                  d.multToMilli == d.multFromMilli
                                      ? '${formatMultiple(d.multToMilli)} HELD'
                                      : '${formatMultiple(d.multFromMilli)} → '
                                          '${formatMultiple(d.multToMilli)}',
                                  style: d.multToMilli == d.multFromMilli
                                      ? rowStyle
                                      : numStyle(24,
                                          color: kLoss, glow: kGlowLoss),
                                ),
                              ),
                              _mathRow(
                                'ENT. VALUE',
                                CountUpText(
                                  key: const Key('arbEv'),
                                  animation: _ev,
                                  from: d.evFromCents,
                                  to: d.evToCents,
                                  fmt: formatMoney,
                                  style: rowStyle,
                                ),
                                last: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // THE HEADLINE: +$accretion (event amount), pop 1.25,
                      // with a chromatic-aberration FLARE at the peak — two
                      // low-alpha offset echoes (warm/cool) split out then
                      // converge as the pop settles, so the crisp green
                      // number reads sharp the instant it lands (legibility
                      // untouched; the split is garnish behind it).
                      AnimatedBuilder(
                        animation: _pop,
                        builder: (context, child) {
                          final t = _pop.value;
                          // Split widest mid-pop, zero by the time it settles.
                          final split = 6 * (1 - (t - .4).abs() / .6)
                              .clamp(0.0, 1.0);
                          return Opacity(
                            opacity: t > 0 ? 1 : 0,
                            child: Transform.scale(
                              scale: overshootScale(t),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (split > 0.2) ...[
                                    Transform.translate(
                                      offset: Offset(-split, 0),
                                      child: _headlineGhost(
                                          d, const Color(0x66FF5566)),
                                    ),
                                    Transform.translate(
                                      offset: Offset(split, 0),
                                      child: _headlineGhost(
                                          d, const Color(0x664DA3FF)),
                                    ),
                                  ],
                                  child!,
                                ],
                              ),
                            ),
                          );
                        },
                        child: Text(
                          '+${formatMoney(d.accretionCents)}',
                          key: const Key('arbHeadline'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: kFontNum,
                            fontSize: 64,
                            height: 1,
                            color: kGain,
                            shadows: [
                              Shadow(
                                  color: Color(0x8C4DFF8A), blurRadius: 6),
                              Shadow(
                                  color: Color(0x664DFF8A),
                                  blurRadius: 50),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "THAT'S ALLOWED?!",
                        textAlign: TextAlign.center,
                        style: labelStyle(
                                size: 10, color: kGain, tracking: 2)
                            .copyWith(shadows: kGlowGain),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: SizedBox(
                          width: 200,
                          child: ChunkyKey(
                            key: const Key('bookIt'),
                            icon: '✓',
                            label: 'BOOK IT',
                            variant: ChunkyKeyVariant.exec,
                            onTap: widget.onBookIt,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ~20 sparks bursting from the headline zone.
              SparkBurst(animation: _sparks),
            ],
          ),
        ),
      ),
    );
  }

  /// A flat-color echo of the headline used for the chromatic split (no glow
  /// so it stays a soft fringe behind the crisp green number).
  Widget _headlineGhost(ArbitrageFlashData d, Color color) => Text(
        '+${formatMoney(d.accretionCents)}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: kFontNum,
          fontSize: 64,
          height: 1,
          color: color,
        ),
      );

  Widget _mathRow(String label, Widget value, {bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: last
            ? null
            : const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: Color(0xFF14191F))),
              ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('> $label', style: bodyStyle(size: 12, color: kDim)),
            const SizedBox(width: 30),
            value,
          ],
        ),
      );
}
