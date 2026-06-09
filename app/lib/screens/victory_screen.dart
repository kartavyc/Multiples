/// S10 — VICTORY (mockup #scr-s10): the $1B screen. Entry juice (mockup
/// `s10enter`): the big number counts up ~1400ms ease-out in green, ~20
/// sparks burst, green tint washes, shake + heavy haptic — then settles.
/// The number is the run's real derived net worth (the engine declared the
/// win; nothing here computes it). ENDLESS re-enters at tier 5 via the
/// controller; NEW RUN reseeds.
library;

import 'package:engine/money.dart';
import 'package:engine/resolver.dart' show tierDeadlineRounds;
import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/juice.dart';

/// Total entry-beat length (count 1400ms + settle).
const Duration _kBeat = Duration(milliseconds: 1900);

/// The win stage.
class VictoryScreen extends StatefulWidget {
  /// Builds the victory over [controller]; [onNewRun] reseeds; [shake]
  /// gets the entry kick.
  const VictoryScreen({
    super.key,
    required this.controller,
    required this.onNewRun,
    required this.shake,
    this.onDesk,
  });

  /// The app-side game container.
  final GameController controller;

  /// NEW RUN key handler.
  final VoidCallback onNewRun;

  /// THE DESK key handler (meta screen); null in standalone smoke tests.
  final VoidCallback? onDesk;

  /// The screen shaker (kicked on entry).
  final ShakeController shake;

  @override
  State<VictoryScreen> createState() => _VictoryScreenState();
}

class _VictoryScreenState extends State<VictoryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: _kBeat);

  late final Animation<double> _count = CurvedAnimation(
    parent: _t,
    curve: const Interval(0, 1400 / 1900, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _sparks = CurvedAnimation(
    parent: _t,
    curve: const Interval(0, 800 / 1900),
  );

  @override
  void initState() {
    super.initState();
    widget.shake.shake();
    safeHapticHeavy();
    _t.forward();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.state;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            key: const Key('victory'),
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The billion, counting up in green (settles green: this
              // screen IS the celebration).
              AnimatedBuilder(
                animation: _count,
                builder: (context, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(lerpFixed(0, s.netWorthCents, _count.value)),
                    key: const Key('vicNum'),
                    style: const TextStyle(
                      fontFamily: kFontNum,
                      fontSize: 55,
                      height: 1,
                      color: kGain,
                      shadows: [
                        Shadow(color: Color(0x8C4DFF8A), blurRadius: 6),
                        Shadow(color: Color(0x734DFF8A), blurRadius: 60),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'YOU BECAME THE MONEY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kFontLabel,
                  fontSize: 12,
                  letterSpacing: 3,
                  color: kFg,
                  shadows: kGlowFg,
                ),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: _stat('ROUNDS USED (T4)',
                        '${s.round} / ${tierDeadlineRounds(4)}'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    // RUNS TO GET HERE (mockup S10): the lifetime run count
                    // off the just-settled meta (settleRun bumped runsPlayed;
                    // the rebuild after notifyListeners shows the new total).
                    child: _stat('RUNS TO GET HERE',
                        '${widget.controller.meta.runsPlayed}',
                        valueKey: 'runsToGetHere'),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              ChunkyKey(
                key: const Key('endless'),
                icon: '∞',
                label: 'ENDLESS',
                variant: ChunkyKeyVariant.exec,
                onTap: widget.controller.enterEndless,
              ),
              const SizedBox(height: 9),
              ChunkyKey(
                key: const Key('newRunVictory'),
                icon: '＋',
                label: 'NEW RUN',
                onTap: widget.onNewRun,
              ),
              if (widget.onDesk != null) ...[
                const SizedBox(height: 9),
                ChunkyKey(
                  key: const Key('victoryDesk'),
                  icon: '▤',
                  label: 'THE DESK',
                  onTap: widget.onDesk,
                ),
              ],
            ],
          ),
        ),
        // Entry juice: green tint wash + the spark burst.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final k = _t.isAnimating ? (1 - _t.value) : 0.0;
              if (k == 0) return const SizedBox.shrink();
              return ColoredBox(color: kGain.withValues(alpha: .06 * k));
            },
          ),
        ),
        SparkBurst(animation: _sparks),
      ],
    );
  }

  Widget _stat(String label, String value, {String? valueKey}) => Container(
        padding: const EdgeInsets.fromLTRB(2, 7, 2, 8),
        decoration: BoxDecoration(
          border: Border.all(color: kLine),
          color: const Color(0x05E6EDF3),
        ),
        child: Column(
          children: [
            Text(label,
                style: labelStyle(size: 8, color: kDim, tracking: 1)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  key: valueKey == null ? null : Key(valueKey),
                  style: numStyle(30)),
            ),
          ],
        ),
      );
}
