/// S4 — CARD FACE + NAPKIN (mockup #napkin; docs/05 §3 S4): the two-stage
/// confirm overlay. Stage 1 = the enlarged face, RAW INPUTS ONLY (§Q3
/// "show the chips"); INSPECT → stage 2 = the napkin, the mechanical
/// post-deal preview. For an ADD-ON the napkin rows are the engine's:
/// PAY (resolver addonPrice) / EBITDA (face) / SECTOR ✓ SAME · ✕ CROSS /
/// SYNERGY (absorbSameSector composition) / MULT held-or-dragged
/// (absorbCrossSectorMultiple + floor) — all via [GameController
/// .addonPreview]; NO arithmetic here beyond laying the values out. The
/// judgment (good deal?) is NEVER shown (§Q3). REINVEST uses a one-stage
/// confirm (cheap, reversible-feel — docs/05 §0.8).
library;

import 'package:engine/content.dart';
import 'package:engine/model.dart';
import 'package:engine/money.dart';
import 'package:flutter/material.dart' hide Card;

import '../controller.dart';
import '../theme.dart';
import '../widgets/card_kind.dart';
import '../widgets/rejection_line.dart';

/// The bottom-anchored confirm overlay (dark backdrop, panel-up entrance).
class NapkinOverlay extends StatefulWidget {
  /// Builds the overlay for [cardId] (or the [reinvest] / [exit] /
  /// [heldPlay] confirms).
  const NapkinOverlay({
    super.key,
    required this.controller,
    required this.cardId,
    required this.reinvest,
    required this.rejection,
    required this.onBack,
    required this.onExecute,
    this.exit = false,
    this.heldPlay = false,
    this.targetVentureId,
    this.onSell,
  });

  /// The app-side game container.
  final GameController controller;

  /// Selected card id; null when [reinvest] or [exit].
  final String? cardId;

  /// REINVEST confirm instead of a card.
  final bool reinvest;

  /// EXIT OFFER confirm (round 11): the engine-derived stage rows —
  /// exit multiple fork / equity at exit / own% / proceeds — all off
  /// [GameController.exitPreview].
  final bool exit;

  /// Held-consumable USE/SELL sheet (round 11): [cardId] is the held
  /// play; EXECUTE = USE, [onSell] = liquidate at the engine's
  /// trunc(price/2).
  final bool heldPlay;

  /// The aimed venture (rail target picker); null = platform.
  final String? targetVentureId;

  /// Inline engine rejection to show, if the last EXECUTE bounced.
  final String? rejection;

  /// BACK / backdrop-tap handler.
  final VoidCallback onBack;

  /// EXECUTE handler (dispatches through the controller upstream).
  final VoidCallback onExecute;

  /// SELL handler for the held-play sheet (engine trunc(price/2)).
  final VoidCallback? onSell;

  @override
  State<NapkinOverlay> createState() => _NapkinOverlayState();
}

class _NapkinOverlayState extends State<NapkinOverlay>
    with SingleTickerProviderStateMixin {
  /// Stage 2 (the napkin) open? Stage 1 (the face) otherwise. REINVEST
  /// renders its single-stage confirm regardless.
  bool _inspecting = false;

  /// Mockup `panelup`: .25s rise with a soft overshoot. initState-created
  /// (lazy creation in dispose = unsafe ancestor lookup).
  late final AnimationController _up;

  @override
  void initState() {
    super.initState();
    _up = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();
  }

  @override
  void dispose() {
    _up.dispose();
    super.dispose();
  }

  void _inspect() => setState(() => _inspecting = true);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onBack, // backdrop tap = BACK (tap-only law)
        child: ColoredBox(
          color: const Color(0xE0000000), // mockup rgba(0,0,0,.88)
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {}, // absorb panel taps
                child: AnimatedBuilder(
                  animation: _up,
                  builder: (context, child) {
                    final t =
                        const Cubic(.34, 1.3, .64, 1).transform(_up.value);
                    return FractionalTranslation(
                      translation: Offset(0, (1 - t) * .4),
                      child: Opacity(
                        opacity: (.3 + .7 * t).clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: _panel(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    return Container(
      key: const Key('napkin'),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: kBg,
        border: Border.all(color: kAccent, width: 2),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Color(0x594DA3FF), blurRadius: 9)],
      ),
      child: widget.reinvest
          ? _reinvestBody()
          : widget.exit
              ? _exitBody()
              : widget.heldPlay
                  ? _heldBody()
                  : (_inspecting ? _napkinBody() : _faceBody()),
    );
  }

  // --- shared bits ---

  String _targetName() =>
      widget.controller
          .targetVenture(widget.targetVentureId)
          ?.displayName ??
      'NO TARGET';

  Widget _header(String text) => Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kLine)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: labelStyle(size: 10, color: kAccentHi, tracking: 2)
              .copyWith(shadows: kGlowAcc),
        ),
      );

  Widget _row(String k, String v, Color color, {Key? key}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF14191F))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('> $k', style: bodyStyle(size: 12, color: kDim)),
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

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child:
            Text(text, style: numStyle(13, color: kFaint, glow: const [])),
      );

  Widget _keys({required bool withInspect, bool withExecute = true}) {
    return Column(
      children: [
        if (widget.rejection != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: RejectionLine(reason: widget.rejection!),
          ),
        Row(
          children: [
            Expanded(
              child: ChunkyKey(
                key: const Key('back'),
                icon: '✕',
                label: 'BACK',
                onTap: widget.onBack,
              ),
            ),
            if (withInspect) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyKey(
                  key: const Key('inspect'),
                  icon: '✎',
                  label: 'INSPECT',
                  variant: ChunkyKeyVariant.primary,
                  onTap: _inspect,
                ),
              ),
            ],
            if (withExecute) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyKey(
                  key: const Key('execute'),
                  icon: '▸',
                  label: 'EXECUTE',
                  variant: ChunkyKeyVariant.exec,
                  onTap: widget.onExecute,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // --- REINVEST (single-stage confirm + the round-11 amount picker) ---

  Widget _reinvestBody() {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('✎ CONFIRM · REINVEST → ${_targetName()}'),
        // The 25/50/100% quick keys (controller UI dial; the engine
        // accepts any amount).
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Row(
            children: [
              for (final pct in GameController.kReinvestPcts) ...[
                if (pct != GameController.kReinvestPcts.first)
                  const SizedBox(width: 6),
                Expanded(
                  child: ChunkyKey(
                    key: Key('reinvestPct-$pct'),
                    label: '$pct%',
                    dense: true,
                    variant: pct == c.reinvestPct
                        ? ChunkyKeyVariant.primary
                        : ChunkyKeyVariant.normal,
                    onTap: () => setState(() => c.setReinvestPct(pct)),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        _row('PAY', '−${formatMoney(c.reinvestAmountCents)}', kLoss,
            key: const Key('reinvestPay')),
        // The engine efficiency preview: +$X EBITDA at Y% (resolver
        // reinvestEfficiencyBp; controller.reinvestGainCents mirror).
        _row(
          'GET',
          '+${formatMoney(c.reinvestGainCents)} EBITDA '
              'AT ${bpToPctTrunc(c.reinvestEffBp)}%',
          kGain,
          key: const Key('reinvestGet'),
        ),
        _note('// brute-force growth; efficiency decays toward the deadline'),
        _keys(withInspect: false),
      ],
    );
  }

  // --- EXIT OFFER (round 11; single-stage — docs/05 confirm strip) ---

  Widget _exitBody() {
    final c = widget.controller;
    final p = c.exitPreview();
    if (p == null) {
      // The offer went stale under the overlay (cannot happen mid-ACT;
      // belt and braces).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header('EXIT · NO OFFER'),
          _note('// the buyer walked'),
          _keys(withInspect: false, withExecute: false),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('✎ CONFIRM · EXIT → '
            '${widget.controller.targetVenture(p.ventureId)?.displayName ?? p.ventureId.toUpperCase()}'),
        _row('OFFER', formatMultiple2(p.offerMultipleMilli), kFg),
        _row('LIVE MARK', formatMultiple2(p.liveMultipleMilli), kFg),
        _row(
          'EXIT MULTIPLE',
          p.hot
              ? '${formatMultiple2(p.exitMultipleMilli)} HOT'
              : formatMultiple2(p.exitMultipleMilli),
          p.hot ? kGain : kAccentHi,
          key: const Key('exitMultiple'),
        ),
        _row('EQUITY AT EXIT', formatMoney(p.equityAtExitCents), kFg,
            key: const Key('exitEquity')),
        _row('YOUR OWNERSHIP', '${bpToPctTrunc(p.ownershipBp)}%', kFg),
        _row(
          'PROCEEDS → CASH',
          '${p.proceedsCents >= 0 ? '+' : ''}${formatMoney(p.proceedsCents)}',
          p.proceedsCents >= 0 ? kGain : kLoss,
          key: const Key('exitProceeds'),
        ),
        if (p.hot)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              '〔 HOT WINDOW ARMED: WILL ROLL '
              '${formatMultiple2(p.exitMultipleMilli)} 〕',
              key: const Key('hotOverrideLine'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kFontNum,
                fontSize: 16,
                letterSpacing: 1,
                color: kGain,
                shadows: kGlowGain,
              ),
            ),
          )
        else
          _note('// the engine rolls min(offer, live) — paper to real'),
        _keys(withInspect: false),
      ],
    );
  }

  // --- HELD PLAY (round 11: the ACT use/sell sheet) ---

  Widget _heldBody() {
    final c = widget.controller;
    final card = c.content.byId(widget.cardId!);
    final rows = <(String, String, Color)>[];
    // Raw faces only (§Q3) — the deltas the play will apply.
    for (final entry in card.deltas.entries) {
      final v = entry.value;
      switch (entry.key) {
        case 'cash':
          // Purchase mirrors are stripped at play (dealflow glue); show
          // only a non-mirror cash face.
          if (!(card.cost.cashCents > 0 && v == -card.cost.cashCents)) {
            rows.add((
              'CASH',
              v >= 0 ? '+${formatMoney(v)}' : formatMoney(v),
              v >= 0 ? kGain : kLoss
            ));
          }
        case 'ebitda':
          rows.add((
            'EBITDA',
            v >= 0 ? '+${formatMoney(v)}' : formatMoney(v),
            v >= 0 ? kGain : kLoss
          ));
        case 'netDebt':
          rows.add((
            'DEBT',
            v >= 0 ? '+${formatMoney(v)}' : formatMoney(v),
            v >= 0 ? kLoss : kGain
          ));
        case 'own':
          rows.add((
            'OWN',
            '${v >= 0 ? '+' : '−'}${bpToPctTrunc(v < 0 ? -v : v)}%',
            v >= 0 ? kGain : kLoss
          ));
        case 'multiple':
          rows.add((
            'MULT',
            v >= 0 ? '+${formatMultiple2(v)}' : formatMultiple2(v),
            v >= 0 ? kGain : kLoss
          ));
      }
    }
    if (card.id == 'PLY_HOT_WINDOW') {
      rows.add(('ARMS', 'HOT WINDOW · NEXT EXIT', kGain));
    }
    if (card.id == 'PLY_MARKET_READ') {
      rows.add(('REVEALS', 'NEXT ROUND DIRECTION', kGain));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('PLAY · ${card.name.toUpperCase()}'),
        for (final r in rows) _row(r.$1, r.$2, r.$3),
        _row(
          'SELL VALUE',
          '+${formatMoney(c.sellValueCents(widget.cardId!))}',
          kAccentHi,
          key: const Key('heldSellValue'),
        ),
        _note('// USE applies the play; SELL liquidates at ~50%'),
        if (widget.rejection != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: RejectionLine(reason: widget.rejection!),
          ),
        Row(
          children: [
            Expanded(
              child: ChunkyKey(
                key: const Key('back'),
                icon: '✕',
                label: 'BACK',
                onTap: widget.onBack,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChunkyKey(
                key: const Key('sellHeld'),
                label: 'SELL '
                    '${formatMoney(c.sellValueCents(widget.cardId!))}',
                onTap: widget.onSell,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChunkyKey(
                key: const Key('useHeld'),
                icon: '▸',
                label: 'USE',
                variant: ChunkyKeyVariant.exec,
                onTap: widget.onExecute,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- STAGE 1: the enlarged face (raw inputs only, §Q3) ---

  Widget _faceBody() {
    final c = widget.controller;
    final card = c.content.byId(widget.cardId!);
    final kind = cardKind(card);
    final rows = <(String, String, Color)>[];
    switch (card.type) {
      case CardType.addon:
        rows.add(
            ('EBITDA ON OFFER', formatMoney(card.deltas['ebitda'] ?? 0), kFg));
        rows.add((
          'BUY MULTIPLE',
          formatMultiple(c.addonBuyMultipleMilli(widget.cardId!)),
          kFg
        ));
        rows.add(('PRICE', formatMoney(card.cost.cashCents), kAccentHi));
        rows.add(('DEBT IT BRINGS', formatMoney(card.cost.debtCents), kFg));
      case CardType.venture:
        rows.add(
            ('EBITDA', formatMoney(card.deltas['ebitda'] ?? 0), kFg));
        rows.add(
            ('MULTIPLE', formatMultiple(card.deltas['multiple'] ?? 0), kFg));
        rows.add(('PRICE', formatMoney(card.cost.cashCents), kAccentHi));
        rows.add(('DEBT IT BRINGS', formatMoney(card.cost.debtCents), kFg));
      case CardType.financing:
        final cash = card.deltas['cash'] ?? 0;
        rows.add((
          'CASH',
          cash >= 0 ? '+${formatMoney(cash)}' : formatMoney(cash),
          kFg
        ));
        if (card.cost.dilutionBp > 0) {
          rows.add((
            'DILUTION (NOMINAL)',
            '−${bpToPctTrunc(card.cost.dilutionBp)}%',
            kFg
          ));
        } else {
          final debt = card.deltas['netDebt'] ?? 0;
          rows.add((
            'DEBT',
            debt >= 0 ? '+${formatMoney(debt)}' : formatMoney(debt),
            kFg
          ));
        }
      case CardType.partner:
        // The face is the engine's: actionForCard's HirePartner payload
        // (per-round accrual + price + any story bump).
        final p = c.partnerPreview(widget.cardId!);
        rows.add((
          'EBITDA / ROUND',
          '+${formatMoney(p.perRoundEbitdaCents)}',
          kFg
        ));
        if (p.multipleDeltaMilli != 0) {
          rows.add(
              ('MULTIPLE BUMP', '+${formatMultiple2(p.multipleDeltaMilli)}', kFg));
        }
        rows.add(('PRICE', formatMoney(p.costCents), kAccentHi));
      case CardType.consumable:
      case CardType.event:
        rows.add(('CARD', card.name.toUpperCase(), kFg));
    }
    final target =
        card.type == CardType.venture ? 'NEW SLOT' : _targetName();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('${kind.badge} · ${card.name.toUpperCase()} → $target'),
        for (final r in rows) _row(r.$1, r.$2, r.$3),
        _note('// raw inputs. INSPECT for the napkin math.'),
        _keys(withInspect: true),
      ],
    );
  }

  // --- STAGE 2: the napkin (mechanical preview; engine numbers) ---

  Widget _napkinBody() {
    final c = widget.controller;
    final card = c.content.byId(widget.cardId!);
    final kind = cardKind(card);
    final target =
        card.type == CardType.venture ? 'NEW SLOT' : _targetName();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('✎ CONFIRM · ${kind.badge} → $target'),
        ..._napkinRows(card),
        _note(_napkinNote(card)),
        _keys(withInspect: false),
      ],
    );
  }

  List<Widget> _napkinRows(Card card) {
    final c = widget.controller;
    switch (card.type) {
      case CardType.addon:
        // ALL values engine-derived (controller.addonPreview header).
        final p = c.addonPreview(widget.cardId!,
            targetVentureId: widget.targetVentureId);
        final sectorName = sectorToJson(p.sector);
        return [
          _row('PAY', '−${formatMoney(p.payCents)}', kLoss),
          _row('EBITDA', '+${formatMoney(p.addonEbitdaCents)}', kGain),
          if (p.faceDebtCents > 0)
            _row('DEBT', '+${formatMoney(p.faceDebtCents)}', kLoss),
          _row(
            'SECTOR',
            p.sameSector ? '$sectorName ✓ SAME' : '$sectorName ✕ CROSS',
            p.sameSector ? kGain : kLoss,
          ),
          _row(
            'SYNERGY',
            '+${formatMoney(p.synergyCents)}',
            p.synergyCents > 0 ? kGain : kFaint,
          ),
          _row(
            'MULT',
            p.multToMilli == p.multFromMilli
                ? '${formatMultiple(p.multFromMilli)} HELD'
                : '${formatMultiple(p.multFromMilli)} → '
                    '${formatMultiple(p.multToMilli)}',
            p.multToMilli == p.multFromMilli ? kFg : kLoss,
          ),
        ];
      case CardType.venture:
        return [
          _row('PAY', '−${formatMoney(card.cost.cashCents)}', kLoss),
          _row('EBITDA', '+${formatMoney(card.deltas['ebitda'] ?? 0)}',
              kGain),
          _row('MULT', formatMultiple(card.deltas['multiple'] ?? 0), kFg),
          _row('OWN', '100%', kFg),
        ];
      case CardType.financing:
        final cash = card.deltas['cash'] ?? 0;
        if (card.cost.dilutionBp > 0) {
          return [
            _row('GET', '+${formatMoney(cash)}', kGain),
            _row('OWN', '−${bpToPctTrunc(card.cost.dilutionBp)}% NOMINAL',
                kLoss),
          ];
        }
        final debt = card.deltas['netDebt'] ?? 0;
        return [
          _row(
            'CASH',
            cash >= 0 ? '+${formatMoney(cash)}' : formatMoney(cash),
            cash >= 0 ? kGain : kLoss,
          ),
          _row(
            'DEBT',
            debt >= 0 ? '+${formatMoney(debt)}' : formatMoney(debt),
            debt >= 0 ? kLoss : kGain,
          ),
        ];
      case CardType.partner:
        // The napkin: the engine accrual line + the fixed-cost warning
        // channel (live in HirePartner; 0 for every v1 slice card).
        final p = c.partnerPreview(widget.cardId!);
        return [
          _row('PAY', '−${formatMoney(p.costCents)}', kLoss),
          _row(
            'ENGINE',
            '+${formatMoney(p.perRoundEbitdaCents)} EBITDA / ROUND',
            kGain,
            key: const Key('partnerEngineRow'),
          ),
          if (p.multipleDeltaMilli != 0)
            _row('MULT', '+${formatMultiple2(p.multipleDeltaMilli)}', kGain),
          if (p.fixedCostCents > 0)
            _row(
              'FIXED COST',
              '−${formatMoney(p.fixedCostCents)} / ROUND',
              kLoss,
              key: const Key('partnerFixedCostRow'),
            ),
        ];
      case CardType.consumable:
      case CardType.event:
        return [_row('CARD', card.name.toUpperCase(), kFg)];
    }
  }

  String _napkinNote(Card card) {
    final c = widget.controller;
    final target = c.targetVenture(widget.targetVentureId);
    switch (card.type) {
      case CardType.addon:
        final same = card.sector != null &&
            target != null &&
            card.sector == target.sector;
        return same
            ? '// same sector: synergy fires, multiple holds'
            : '// cross sector: zero synergy, multiple drags';
      case CardType.venture:
        return '// founding takes a slot at 100% ownership';
      case CardType.financing:
        return card.cost.dilutionBp > 0
            ? '// engine reprices your slice on real cap-table math'
            : '// interest charges on net debt every round';
      case CardType.partner:
        final p = c.partnerPreview(widget.cardId!);
        return p.fixedCostCents > 0
            ? '// WARNING: the salary bills every round, paid or not'
            : '// a permanent engine: accrues before yield every OPERATE';
      case CardType.consumable:
      case CardType.event:
        return '//';
    }
  }
}
