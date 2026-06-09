/// S8 — AUTOPSY (mockup #scr-s8; docs/05 §3 S8, §Q5): the three-row death
/// screen. CAUSE (plain words, by DeathCause) → THE NUMBER THAT KILLED YOU
/// (the literal line item: the fatal OPERATE's interest-vs-cash for a
/// bankruptcy — real amounts off the last OperateResult events — or the
/// realized-vs-needed growth rates off the engine meters for a missed
/// deadline) → THE ROUND IT BROKE (the last meaningful actionLog entry,
/// never a re-sim). A slow red pulse on the cause panel is the ONLY
/// motion: death screens get NO celebration juice (docs/07 — no surge, no
/// sparks, no count-ups). RETRY starts a new run.
library;

import 'package:engine/model.dart';
import 'package:engine/money.dart';
import 'package:engine/round.dart' show tierBarCents;
import 'package:engine/apply.dart' show GameEventType;
import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';

/// The death stage (fills the screen frame when phase == runOver, died).
class AutopsyScreen extends StatefulWidget {
  /// Builds the autopsy over [controller]; [onRetry] starts a new run;
  /// [onDesk] opens the meta screen.
  const AutopsyScreen({
    super.key,
    required this.controller,
    required this.onRetry,
    this.onDesk,
  });

  /// The app-side game container (read-only here).
  final GameController controller;

  /// RETRY key handler.
  final VoidCallback onRetry;

  /// THE DESK key handler (meta screen); null in standalone smoke tests.
  final VoidCallback? onDesk;

  @override
  State<AutopsyScreen> createState() => _AutopsyScreenState();
}

class _AutopsyScreenState extends State<AutopsyScreen>
    with SingleTickerProviderStateMixin {
  /// The mockup `redpulse`: a slow 3s glow loop on the cause panel.
  /// initState-created (lazy creation in dispose = unsafe lookup).
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.state;
    final bankrupt = s.death == DeathCause.bankruptcy;

    // THE NUMBER: bankruptcy quotes the fatal OPERATE's real bill —
    // interest off the INTEREST_CHARGED event; the cash it broke against
    // is the pre-charge pocket (post cash is negative; pre = post +
    // interest, a display composition of the two engine numbers).
    var interest = 0;
    for (final e in c.lastOperateEvents) {
      if (e.type == GameEventType.interestCharged) interest = e.amount;
    }
    final cashBefore = s.cashCents + interest;
    final m = c.meters;

    final killNumber = bankrupt
        ? 'INTEREST DUE ${formatMoney(interest)} > '
            'CASH ${formatMoney(cashBefore)}'
        : 'NW ${formatMoney(s.netWorthCents)} < '
            'BAR ${formatMoney(s.tier <= 4 ? tierBarCents(s.tier) : 0)}';

    // THE ROUND: the last DECISIVE player move, money-formatted by the
    // engine's describeRunStep off the typed replay journal (doc 02 §Q5;
    // fixes the R9 raw-cents leak — "exited QUANTA at 6.0x", not a debug
    // dump). Null when the player never moved.
    final broke = c.brokeLine;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        key: const Key('autopsy'),
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kLine, width: 2)),
            ),
            child: Text(
              'AUTOPSY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kFontLabel,
                fontSize: 16,
                letterSpacing: 8,
                color: kFg,
                shadows: kGlowFg,
              ),
            ),
          ),
          _label('CAUSE OF DEATH'),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final k = _pulse.value;
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                decoration: BoxDecoration(
                  color: kPanel,
                  border: Border.all(color: kLoss),
                  boxShadow: [
                    BoxShadow(
                        color: kLoss.withValues(alpha: .28 * k),
                        blurRadius: 16),
                  ],
                ),
                child: child,
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bankrupt ? 'GREED.' : 'TOO SLOW.',
                  key: const Key('deathCause'),
                  style: bodyStyle(size: 19)
                      .copyWith(fontWeight: FontWeight.w700, shadows: kGlowFg),
                ),
                const SizedBox(height: 3),
                Text(
                  bankrupt
                      ? 'You ran out of cash paying debt.'
                      : 'The market would not wait.',
                  style: bodyStyle(size: 12, color: kDim),
                ),
              ],
            ),
          ),
          _label('THE NUMBER THAT KILLED YOU'),
          _panel(
            Text(
              killNumber,
              key: const Key('killNumber'),
              style: TextStyle(
                fontFamily: kFontNum,
                fontSize: 29,
                height: 1.05,
                color: kLoss,
                shadows: kGlowLoss,
              ),
            ),
          ),
          _label('THE ROUND IT BROKE'),
          _panel(
            Text(
              broke ?? 'Round ${s.round}: you stood still.',
              key: const Key('brokeLine'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: numStyle(20),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: kLine)),
            ),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                    fontFamily: kFontNum,
                    fontSize: 17,
                    letterSpacing: .5,
                    color: kDim),
                children: bankrupt
                    ? [
                        const TextSpan(text: 'Paper net worth '),
                        TextSpan(
                            text: formatMoney(s.netWorthLastRound),
                            style: const TextStyle(color: kFg)),
                        const TextSpan(text: '. Cash '),
                        TextSpan(
                            text: formatMoney(s.cashCents),
                            style: const TextStyle(color: kFg)),
                        const TextSpan(
                            text: '. The score was never yours.'),
                      ]
                    : [
                        const TextSpan(text: 'You grew '),
                        TextSpan(
                            text:
                                '${formatMultiple2(m.growthRateThisTierMilli)}/round',
                            style: const TextStyle(color: kFg)),
                        const TextSpan(text: '. You needed '),
                        TextSpan(
                            text: formatMultiple2(m.growthRateNeededMilli),
                            style: const TextStyle(color: kFg)),
                        const TextSpan(text: '. Growth has a deadline.'),
                      ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              'FURTHEST TIER: ${s.tier}',
              style: labelStyle(size: 8, tracking: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          ChunkyKey(
            key: const Key('retry'),
            icon: '▸',
            label: 'RETRY',
            variant: ChunkyKeyVariant.primary,
            onTap: widget.onRetry,
          ),
          if (widget.onDesk != null) ...[
            const SizedBox(height: 9),
            ChunkyKey(
              key: const Key('autopsyDesk'),
              icon: '▤',
              label: 'THE DESK',
              onTap: widget.onDesk,
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 9, 2, 4),
        child: Text(text, style: labelStyle(size: 8, tracking: 2)),
      );

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: kPanel,
          border: Border.all(color: kLine),
        ),
        child: child,
      );
}
