/// S7 — DEADLINE CHECK / TIER CLEAR (mockup #scr-s7; docs/05 §3 S7): the
/// bar moment. Cleared → "TIER CLEARED", the NW-vs-bar rows, the
/// 16-segment fill animating PAST the bar marker (segments light every
/// ~75ms, mockup `s7fill`), ROUNDS USED x/y, "YOU ARE NOW: TIER n" →
/// NEXT TIER. Not cleared (rounds left) → "DEADLINE CHECK", NOT YET, the
/// red behind-pace line `NEED a/RD · AT b` straight off the engine meters
/// (telegraph #2) → NEXT ROUND. All values engine-made
/// (controller.DeadlineData); the bar-percent is the documented
/// presentation discretization. The terminal outcomes (win / missed
/// deadline) never reach this panel — they land on S10/S8.
library;

import 'package:engine/money.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/juice.dart';

/// Segments in the tier bar (mockup #tierbar).
const int _kSegs = 16;

/// The segment index carrying the BAR marker: lighting past it = cleared.
const int _kBarSeg = 13;

/// The full-stage S7 panel.
class DeadlinePanel extends StatefulWidget {
  /// Builds the panel for [data]; [onProceed] = NEXT TIER / NEXT ROUND.
  const DeadlinePanel({
    super.key,
    required this.data,
    required this.onProceed,
  });

  /// The captured check outcome (controller doc).
  final DeadlineData data;

  /// Proceed key handler (controller.proceedFromDeadline upstream).
  final VoidCallback onProceed;

  @override
  State<DeadlinePanel> createState() => _DeadlinePanelState();
}

class _DeadlinePanelState extends State<DeadlinePanel>
    with SingleTickerProviderStateMixin {
  /// The fill timeline: ~200ms lead + 75ms per segment (mockup s7fill).
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 200 + 75 * _kSegs),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) safeHapticLight();
    });

  @override
  void initState() {
    super.initState();
    _fill.forward();
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  /// Target segments lit: the bar marker sits at seg [_kBarSeg], i.e.
  /// (13+1)/14 of the bar — lit = pct mapped onto that scale, clamped.
  int get _litTarget {
    final lit = (widget.data.pctOfBar * (_kBarSeg + 1)) ~/ 100;
    return lit > _kSegs ? _kSegs : (lit < 0 ? 0 : lit);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final deadlineText = d.deadlineRounds > 0 ? '${d.deadlineRounds}' : '∞';
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: kBg,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              key: Key(d.cleared ? 'tierCleared' : 'deadlineCheck'),
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 9),
                  decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: kLine, width: 2)),
                  ),
                  child: Text(
                    d.cleared ? 'TIER CLEARED' : 'DEADLINE CHECK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: kFontLabel,
                      fontSize: 14,
                      letterSpacing: 4,
                      color: kFg,
                      shadows: kGlowFg,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // NW (ghost) vs BAR (solid) — paper-vs-real held even here.
                _barRow(
                  label: 'NET WORTH',
                  value: formatMoney(d.nwCents),
                  ghost: true,
                ),
                const SizedBox(height: 7),
                _barRow(
                  label: d.prevTier == 5
                      ? 'ENDLESS · NO BAR'
                      : 'TIER ${d.prevTier} BAR',
                  value: d.prevTier == 5 ? '∞' : formatMoney(d.barCents),
                  ghost: false,
                  check: d.cleared
                      ? '✓ CLEARED'
                      : (d.prevTier == 5 ? '' : 'NOT YET'),
                  checkColor: d.cleared ? kGain : kDim,
                ),
                const SizedBox(height: 16),
                // The segmented fill animating past the bar marker.
                AnimatedBuilder(
                  animation: _fill,
                  builder: (context, _) {
                    final t = _fill.value;
                    final lit = (t * _litTarget).floor();
                    final shownPct = (d.pctOfBar * t).round();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 14,
                          child: SegBar(
                            segs: [
                              for (var i = 0; i < _kSegs; i++)
                                i < lit
                                    ? (i > _kBarSeg
                                        ? SegState.on
                                        : SegState.onWhite)
                                    : SegState.off,
                            ],
                            markerIndex: _kBarSeg,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(r'$0',
                                style:
                                    bodyStyle(size: 10, color: kDim)),
                            Text(
                              d.prevTier == 5
                                  ? ''
                                  : 'BAR ${formatMoney(d.barCents)} ▲',
                              style: bodyStyle(size: 10, color: kDim),
                            ),
                            Text(
                              '$shownPct%',
                              key: const Key('tierPct'),
                              style: numStyle(22,
                                  color: d.cleared ? kGain : kFg,
                                  glow: d.cleared
                                      ? kGlowGain
                                      : kGlowFg),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                _statRow('ROUNDS USED', '${d.roundsUsed} / $deadlineText'),
                if (d.cleared)
                  _statRow('YOU ARE NOW', 'TIER ${d.newTier}', acc: true),
                if (!d.cleared) ...[
                  const SizedBox(height: 14),
                  // Telegraph #2: the engine meters' pace line, in red.
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 9),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x66FF5566)),
                      color: const Color(0x0AFF5566),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PACE TO BAR',
                            style: labelStyle(
                                size: 7, color: kFaint, tracking: 1)),
                        const SizedBox(height: 3),
                        Text(
                          // Two-decimal rates: NEED/AT routinely differ
                          // only in the hundredths (engine formatter).
                          'NEED ${formatMultiple2(d.neededMilli)}/RD · '
                          'AT ${formatMultiple2(d.realizedMilli)}',
                          key: const Key('paceNote'),
                          style: numStyle(19, color: kLoss, glow: kGlowLoss),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ChunkyKey(
                  key: const Key('proceed'),
                  icon: '▸',
                  label: d.cleared ? 'NEXT TIER' : 'NEXT ROUND',
                  variant: ChunkyKeyVariant.primary,
                  onTap: widget.onProceed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barRow({
    required String label,
    required String value,
    required bool ghost,
    String check = '',
    Color checkColor = kGain,
  }) {
    final color = ghost ? kGhost : kFg;
    final inner = Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      decoration: ghost
          ? null
          : BoxDecoration(border: Border.all(color: kFg, width: 2)),
      child: Row(
        children: [
          Text(label,
              style: labelStyle(size: 9, color: color, tracking: 1.5)),
          const Spacer(),
          Text(value,
              style: numStyle(32,
                  color: color, glow: ghost ? const [] : kGlowFg)),
          if (check.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(check,
                style: labelStyle(size: 9, color: checkColor, tracking: 1)
                    .copyWith(
                        shadows:
                            checkColor == kGain ? kGlowGain : const [])),
          ],
        ],
      ),
    );
    if (!ghost) return inner;
    return CustomPaint(
      foregroundPainter: const DashedRectPainter(color: kGhost),
      child: inner,
    );
  }

  Widget _statRow(String k, String v, {bool acc = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF14191F))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: labelStyle(size: 8, tracking: 1)),
            Text(
              v,
              style: numStyle(19,
                  color: acc ? kAccentHi : kFg,
                  glow: acc ? kGlowAcc : kGlowFg),
            ),
          ],
        ),
      );
}
