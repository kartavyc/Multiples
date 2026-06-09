/// S2 — THE YEAR PASSED operate digest (mockup #scr-s2; docs/05 §3 S2):
/// the read-only "what just happened" beat after every OPERATE. Static
/// rows, mockup style: OPERATIONS / INTEREST ON DEBT / MARKET DRIFT per
/// venture / NEGLECT / EVENT / the net line — every value an engine event
/// amount, an engine pure-helper output, or a documented display delta
/// (controller.YearDigest); RUNWAY restated in words (the telegraph);
/// CONTINUE. No other input.
library;

import 'package:engine/apply.dart' show GameEvent;
import 'package:engine/model.dart' show sectorToJson;
import 'package:engine/money.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';

/// The bottom-anchored digest interstitial.
class DigestOverlay extends StatelessWidget {
  /// Builds the overlay over [controller]. [onContinue] overrides the
  /// CONTINUE key handler (R18 audio: the run screen wraps the dismiss with
  /// an sfx_key thunk); defaults to a plain dismiss.
  const DigestOverlay({super.key, required this.controller, this.onContinue});

  /// The app-side game container.
  final GameController controller;

  /// CONTINUE key handler (defaults to [GameController.dismissDigest]).
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final d = controller.yearDigest;
    final m = controller.meters;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // absorb taps; the stage beneath is frozen
        child: ColoredBox(
          color: const Color(0xE0000000),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: kBg,
                  border: Border.all(color: kAccent, width: 2),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: Color(0x594DA3FF), blurRadius: 9),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.only(bottom: 8),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: kLine)),
                      ),
                      child: Text(
                        'THE YEAR PASSED',
                        textAlign: TextAlign.center,
                        style: labelStyle(
                                size: 10, color: kAccentHi, tracking: 2)
                            .copyWith(shadows: kGlowAcc),
                      ),
                    ),
                    if (d != null) ..._rows(d),
                    const SizedBox(height: 6),
                    // RUNWAY restated in words — telegraph #1 (docs/05 §3
                    // S2 note: a full round ahead of any F6).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: m.runwayOk
                              ? const Color(0x594DFF8A)
                              : const Color(0x66FF5566),
                        ),
                        color: m.runwayOk
                            ? const Color(0x0A4DFF8A)
                            : const Color(0x0AFF5566),
                      ),
                      child: Text(
                        m.runwayOk
                            ? '〔 RUNWAY OK NEXT ROUND 〕'
                            : '〔 WARNING: INTEREST NEXT ROUND '
                                '${formatMoney(m.debtServiceNextRoundCents)}'
                                ' > PROJECTED '
                                '${formatMoney(m.projectedCashNextRoundCents)} 〕',
                        key: const Key('digestRunway'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: kFontNum,
                          fontSize: 17,
                          letterSpacing: 1,
                          color: m.runwayOk ? kGain : kLoss,
                          shadows: m.runwayOk ? kGlowGain : kGlowLoss,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('CASH ${formatMoney(s.cashCents)}',
                            style: bodyStyle(size: 11, color: kAccentHi)),
                        Text('NET WORTH ${formatMoney(s.netWorthCents)}',
                            style: bodyStyle(size: 11, color: kGhost)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ChunkyKey(
                      key: const Key('continue'),
                      icon: '▸',
                      label: 'CONTINUE',
                      variant: ChunkyKeyVariant.primary,
                      onTap: onContinue ?? controller.dismissDigest,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _rows(YearDigest d) {
    final rows = <Widget>[
      _row(
        'OPERATIONS',
        '+${formatMoney(d.operationsCents)} CASH',
        d.operationsCents > 0 ? kGain : kFaint,
        key: const Key('digestOperations'),
      ),
      // Partner accrual (round 11: OPERATE step 3a — the controller
      // composition of the engine PartnerEngine values).
      if (d.partnerAccrualCents > 0)
        _row(
          'PARTNERS',
          '+${formatMoney(d.partnerAccrualCents)} EBITDA',
          kGain,
          key: const Key('digestPartners'),
        ),
      // Scheduled costs (round 11: step 3c SCHEDULED_EFFECT_FIRED).
      for (final e in d.scheduled)
        _row(
          'FIXED COST ${e.ventureId?.toUpperCase() ?? ''}',
          '${e.amount >= 0 ? '+' : ''}${formatMoney(e.amount)} CASH',
          e.amount >= 0 ? kGain : kLoss,
          key: const Key('digestScheduled'),
        ),
      _row(
        'INTEREST ON DEBT',
        '−${formatMoney(d.interestCents)} CASH',
        d.interestCents > 0 ? kLoss : kFaint,
        key: const Key('digestInterest'),
      ),
    ];
    if (d.marketTurn != null) {
      final temp = d.marketTurn!.split('_').last.toUpperCase();
      rows.add(_row('MARKET TURNS', temp, temp == 'COLD' ? kLoss : kFg));
    }
    for (final r in d.drift) {
      rows.add(_row(
        'MARKET DRIFT · ${sectorToJson(r.sector)}',
        '${r.deltaMilli > 0 ? '+' : '−'}'
            '${formatMultiple(r.deltaMilli < 0 ? -r.deltaMilli : r.deltaMilli)}',
        r.deltaMilli > 0 ? kGain : kLoss,
      ));
    }
    for (final GameEvent e in d.decay) {
      rows.add(_row(
        'NEGLECT ${e.ventureId?.toUpperCase() ?? ''}',
        '${formatMoney(e.amount)} EBITDA',
        kLoss,
      ));
    }
    rows.add(d.eventCardId != null
        ? _row('EVENT',
            controller.content.byId(d.eventCardId!).name.toUpperCase(), kFg)
        : _row('EVENT', '—', kFaint));
    // The EXIT OFFER tease (round 11): the hand routine drew one this
    // OPERATE — it waits on the ACT blotter.
    final offer = controller.state.exitOffer;
    if (offer != null) {
      // Resolve the deterministic flavor name (QUANTA…) the engine carries
      // (work order R16/R19 #7) — never the raw "V1" id; fall back to the id
      // only if the venture has since exited.
      final exitName = controller.targetVenture(offer.ventureId)?.displayName ??
          offer.ventureId.toUpperCase();
      rows.add(_row(
        'EXIT OFFER',
        '$exitName @ '
            '${formatMultiple(offer.offerMultipleMilli)}',
        kLoss,
        key: const Key('digestExitOffer'),
      ));
    }
    rows.add(_row(
      'NET CASH THIS ROUND',
      '${d.netCashCents >= 0 ? '+' : ''}${formatMoney(d.netCashCents)}',
      d.netCashCents >= 0 ? kGain : kLoss,
      key: const Key('digestNet'),
      netLine: true,
    ));
    return rows;
  }

  Widget _row(String k, String v, Color color,
      {Key? key, bool netLine = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: netLine
            ? const Border(top: BorderSide(color: kLine))
            : const Border(bottom: BorderSide(color: Color(0xFF14191F))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('> $k',
              style:
                  bodyStyle(size: 12, color: netLine ? kFg : kDim)),
          Text(
            v,
            key: key,
            style: numStyle(
              18,
              color: color,
              glow: color == kGain
                  ? kGlowGain
                  : color == kLoss
                      ? kGlowLoss
                      : color == kFaint
                          ? const []
                          : kGlowFg,
            ),
          ),
        ],
      ),
    );
  }
}
