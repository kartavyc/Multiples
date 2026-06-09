/// S6-EXIT — the paper→cash beat (mockup #scr-s6; docs/07 "two sacred
/// treatments" #2: "Exits additionally collapse the dashed paper box INTO
/// the solid cash box"). Full takeover on a successful EXIT: the stage
/// rows (exit multiple / equity at exit / your ownership), then the thesis
/// visual — the dashed PAPER box collapses into the solid CASH box
/// (mockup #paper-box.collapse: translateX + scale .08 + fade, .6s
/// cubic-bezier(.6,0,.8,.4)) while the proceeds count up in the cash box —
/// then the slot-freed line and CASHED OUT. The NW surge is DEFERRED by
/// the run screen until CASHED OUT (the flash owns the first beat; a hot
/// exit can rise).
///
/// RENDER-ONLY: every number is an [ExitFlashData] engine value
/// (controller header); the count-up is presentation interpolation
/// (juice.dart lerpFixed). All motion is AnimationController-driven.
library;

import 'package:engine/money.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/juice.dart';

/// Total beat length: collapse 600ms, count-up 600..1500ms.
const Duration kExitBeatTotal = Duration(milliseconds: 1500);

/// The mockup #paper-box.collapse ease.
const Curve kCollapseCurve = Cubic(.6, 0, .8, .4);

/// The full-screen EXIT takeover.
class ExitFlash extends StatefulWidget {
  /// Builds the takeover for [data]; CASHED OUT calls [onCashedOut].
  const ExitFlash({
    super.key,
    required this.data,
    required this.onCashedOut,
    required this.shake,
  });

  /// The engine-made beat payload.
  final ExitFlashData data;

  /// Dismiss handler (the run screen then releases any deferred surge).
  final VoidCallback onCashedOut;

  /// The screen shaker (kicked when the paper box lands in the cash box).
  final ShakeController shake;

  @override
  State<ExitFlash> createState() => _ExitFlashState();
}

class _ExitFlashState extends State<ExitFlash>
    with SingleTickerProviderStateMixin {
  // initState-created (lazy creation in dispose = unsafe ancestor lookup).
  late final AnimationController _t;
  bool _kicked = false;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: kExitBeatTotal)
      ..addListener(_onTick)
      ..forward();
  }

  void _onTick() {
    // The landing kick: when the collapse completes (~600ms / 40%).
    if (!_kicked && _t.value >= .4) {
      _kicked = true;
      widget.shake.shake();
      safeHapticHeavy();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// Collapse progress 0..1 over the first 40% of the beat.
  double _collapseT(double t) => (t / .4).clamp(0.0, 1.0);

  /// Count-up progress 0..1 over 40%..100% of the beat.
  double _countT(double t) => ((t - .4) / .6).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // absorb; CASHED OUT is the only way out
        child: ColoredBox(
          color: const Color(0xF2000000),
          child: Column(
            key: const Key('exitFlash'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The stage rows (mockup .bigpanel).
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
                decoration: BoxDecoration(
                  color: kPanel,
                  border: Border.all(color: kLine),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.only(bottom: 8),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: kLine)),
                      ),
                      child: Text(
                        'EXIT · ${d.ventureName}'
                        '${d.hot ? ' · HOT WINDOW' : ''}',
                        style: labelStyle(size: 11, color: kFg, tracking: 3)
                            .copyWith(shadows: kGlowFg),
                      ),
                    ),
                    _row('EXIT MULTIPLE',
                        formatMultiple2(d.exitMultipleMilli),
                        hot: d.hot),
                    _row('EQUITY AT EXIT', formatMoney(d.equityAtExitCents)),
                    _row('YOUR OWNERSHIP',
                        '${bpToPctTrunc(d.ownershipBp)}%'),
                  ],
                ),
              ),

              // The thesis visual: ghost paper collapses into solid cash.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
                child: AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) {
                    final ct =
                        kCollapseCurve.transform(_collapseT(_t.value));
                    final count = Curves.easeOutCubic
                        .transform(_countT(_t.value));
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // PAPER (mockup #paper-box; .collapse keyframes).
                        Transform.translate(
                          offset: Offset(74 * ct, 0),
                          child: Transform.scale(
                            scale: 1 - .92 * ct,
                            child: Opacity(
                              opacity: 1 - ct,
                              child: CustomPaint(
                                foregroundPainter:
                                    const DashedRectPainter(color: kGhost),
                                child: Container(
                                  key: const Key('exitPaperBox'),
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 10, 16, 12),
                                  child: Column(
                                    children: [
                                      Text('PAPER',
                                          style:
                                              labelStyle(size: 8,
                                                  color: kGhost)),
                                      const SizedBox(height: 3),
                                      Text(
                                        formatMoney(d.proceedsCents),
                                        style: numStyle(34,
                                            color: kGhost,
                                            glow: const []),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('⟶',
                              style: numStyle(26,
                                  color: kDim, glow: const [])),
                        ),
                        // CASH (mockup #cash-box): solid blue, counts up.
                        Container(
                          key: const Key('exitCashBox'),
                          padding:
                              const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: kAccent, width: 2),
                            color: const Color(0x124DA3FF),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x8C4DA3FF), blurRadius: 6),
                              BoxShadow(
                                  color: Color(0x294DA3FF),
                                  blurRadius: 18),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text('CASH',
                                  style: labelStyle(
                                      size: 8, color: kAccent)),
                              const SizedBox(height: 3),
                              Text(
                                '+${formatMoney(lerpFixed(
                                    0, d.proceedsCents, count))}',
                                key: const Key('exitCashCount'),
                                style: numStyle(34,
                                    color: kAccentHi, glow: kGlowAcc),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // The slot-freed line (mockup #exit-foot).
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Text(
                  'SLOT FREED ${d.slotsUsedAfter}/${d.slotsCap}',
                  key: const Key('exitSlotLine'),
                  style: labelStyle(size: 9, color: kDim, tracking: 1.5),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: ChunkyKey(
                  key: const Key('cashedOut'),
                  icon: '✓',
                  label: 'CASHED OUT',
                  variant: ChunkyKeyVariant.exec,
                  onTap: widget.onCashedOut,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool hot = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF14191F))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('> $k', style: bodyStyle(size: 12, color: kDim)),
            Text(v,
                style: numStyle(18,
                    color: hot ? kGain : kFg,
                    glow: hot ? kGlowGain : kGlowFg)),
          ],
        ),
      );
}
