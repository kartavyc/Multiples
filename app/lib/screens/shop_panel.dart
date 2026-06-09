/// S5 — SHOP (mockup #scr-s5; docs/05 §3 S5): the between-rounds counter.
/// Offers render as tickets — consumables carry a BUY key (the engine's
/// buyShopOffer gates cash/cap and REJECTS; an insufficient_cash bounce
/// flashes the row red ~350ms), financing reads IN ACT (it exercises from
/// the ACT blotter, apply.dart's documented decision). Held plays list
/// under YOUR PLAYS showing the engine's trunc(price/2) liquidation face;
/// the key is INERT here because apply.dart's phase gate locks SellPlay
/// (like every non-Reroll action) to ACT — the same engine reconciliation
/// financing offers carry, surfaced the same way (`IN ACT`). The ACT-side
/// sell affordance is an R9 item. REROLL / ADVANCE keys live on the run
/// screen's key row.
library;

import 'package:engine/content.dart';
import 'package:engine/money.dart';
import 'package:flutter/material.dart' hide Card;

import '../controller.dart';
import '../theme.dart';
import '../widgets/card_kind.dart';

/// The shop stage body (offers + held plays).
class ShopPanel extends StatelessWidget {
  /// Builds the panel; [rejectFlashId]/[rejectFlashEpoch] drive the
  /// red bounce flash on the row whose BUY the engine just refused.
  const ShopPanel({
    super.key,
    required this.controller,
    required this.onBuy,
    required this.rejectFlashId,
    required this.rejectFlashEpoch,
  });

  /// The app-side game container.
  final GameController controller;

  /// BUY dispatch (run screen handler -> engine).
  final void Function(String cardId) onBuy;

  /// The card whose buy was last rejected (null = none).
  final String? rejectFlashId;

  /// Bumped per rejection so the same row can flash twice.
  final int rejectFlashEpoch;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    return ListView(
      key: const Key('shopPanel'),
      padding: const EdgeInsets.only(top: 2),
      children: [
        if (s.shopOffers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text('COUNTER EMPTY',
                  style: bodyStyle(size: 11, color: kDim)),
            ),
          ),
        for (final id in s.shopOffers)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _ShopTicket(
              key: Key('shop-$id'),
              card: controller.content.byId(id),
              onBuy: () => onBuy(id),
              flash: id == rejectFlashId,
              flashEpoch: rejectFlashEpoch,
            ),
          ),
        if (s.playsHeld.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('YOUR PLAYS', style: labelStyle(tracking: 2)),
                Text('SELL ~50%', style: numStyle(14)),
              ],
            ),
          ),
          for (final id in s.playsHeld)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _HeldRow(
                key: Key('held-$id'),
                card: controller.content.byId(id),
                sellCents: controller.sellValueCents(id),
              ),
            ),
        ],
      ],
    );
  }
}

/// One counter offer (ticket shape, dense).
class _ShopTicket extends StatefulWidget {
  const _ShopTicket({
    super.key,
    required this.card,
    required this.onBuy,
    required this.flash,
    required this.flashEpoch,
  });

  final Card card;
  final VoidCallback onBuy;
  final bool flash;
  final int flashEpoch;

  @override
  State<_ShopTicket> createState() => _ShopTicketState();
}

class _ShopTicketState extends State<_ShopTicket>
    with SingleTickerProviderStateMixin {
  /// The insufficient-cash red flash (~350ms, AnimationController only).
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 1, // at rest
  );

  @override
  void didUpdateWidget(_ShopTicket old) {
    super.didUpdateWidget(old);
    if (widget.flash &&
        (old.flashEpoch != widget.flashEpoch || !old.flash)) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final kind = cardKind(card);
    final buyable = card.type == CardType.consumable;
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final k = _flash.isAnimating ? 1 - _flash.value : 0.0;
        return Container(
          padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
          decoration: BoxDecoration(
            color: Color.lerp(kPanel, const Color(0xFF2A1015), k),
            border: Border(
              left: BorderSide(
                  color: Color.lerp(kind.color, kLoss, k)!, width: 3),
              top: BorderSide(color: Color.lerp(kLine, kLoss, k)!),
              right: BorderSide(color: Color.lerp(kLine, kLoss, k)!),
              bottom: BorderSide(color: Color.lerp(kLine, kLoss, k)!),
            ),
            boxShadow: k > 0
                ? [
                    BoxShadow(
                        color: kLoss.withValues(alpha: .35 * k),
                        blurRadius: 12),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: kind.color,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              card.type == CardType.consumable ? 'PLAY' : 'FINANCE',
              style: labelStyle(size: 8, color: kBadgeInk, tracking: .5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              card.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle(size: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            // Consumables price at their cost face; financing has no buy
            // price here (it exercises in ACT) — show the draw face.
            buyable
                ? formatMoney(card.cost.cashCents)
                : '+${formatMoney(card.deltas['cash'] ?? 0)}',
            style: numStyle(18, color: kAccentHi, glow: kGlowAcc),
          ),
          const SizedBox(width: 8),
          if (buyable)
            ChunkyKey(
              key: Key('buy-${card.id}'),
              label: 'BUY',
              dense: true,
              onTap: widget.onBuy,
            )
          else
            Text('IN ACT', style: labelStyle(size: 8, color: kFaint)),
        ],
      ),
    );
  }
}

/// One held play with its SELL face (the engine pays trunc(price/2);
/// controller.sellValueCents doc). The key is inert: SellPlay is
/// ACT-phase-gated engine-side (library header).
class _HeldRow extends StatelessWidget {
  const _HeldRow({
    super.key,
    required this.card,
    required this.sellCents,
  });

  final Card card;
  final int sellCents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      decoration: const BoxDecoration(
        color: kPanel,
        border: Border(
          left: BorderSide(color: kRaise, width: 3),
          top: BorderSide(color: kLine),
          right: BorderSide(color: kLine),
          bottom: BorderSide(color: kLine),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: kRaise,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text('HELD',
                style: labelStyle(size: 8, color: kBadgeInk, tracking: .5)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              card.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle(size: 12),
            ),
          ),
          const SizedBox(width: 8),
          ChunkyKey(
            key: Key('sell-${card.id}'),
            label: 'SELL ${formatMoney(sellCents)}',
            dense: true,
            onTap: null, // engine phase gate: sells exercise in ACT
          ),
          const SizedBox(width: 6),
          Text('IN ACT', style: labelStyle(size: 8, color: kFaint)),
        ],
      ),
    );
  }
}
