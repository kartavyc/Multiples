/// Shared ticket flavor derived from a card's TYPE (mockup .t-addon /
/// .t-raise / .t-loan / ...): the badge word, its ink color, and the small
/// sub-line. Used by the blotter tickets, the shop rows, and the napkin
/// header. Pure presentation lookup — no economics.
library;

import 'package:engine/content.dart';
import 'package:engine/model.dart' show sectorToJson;
import 'package:flutter/material.dart' hide Card;

import '../theme.dart';

/// Ticket flavor for [card]: left-border/badge color, badge word, sub-line.
({Color color, String badge, String sub}) cardKind(Card card) {
  switch (card.type) {
    case CardType.addon:
      return (
        color: kGain,
        badge: 'ADD-ON',
        sub: card.sector == null ? '' : sectorToJson(card.sector!),
      );
    case CardType.venture:
      return (
        color: kFg,
        badge: 'VENTURE',
        sub: card.sector == null ? '' : sectorToJson(card.sector!),
      );
    case CardType.financing:
      return card.cost.dilutionBp > 0
          ? (color: kRaise, badge: 'RAISE', sub: 'EQUITY')
          : (color: kAccent, badge: 'LOAN', sub: 'DEBT');
    case CardType.consumable:
      // Mockup S5 PLAY tickets ride .t-addon GREEN — and blue is a
      // budget (docs/07): badges never spend it.
      return (color: kGain, badge: 'PLAY', sub: 'HELD');
    case CardType.partner:
      // The hand's partner ticket (round 11): white phosphor badge —
      // blue is a budget, green is the addon's (docs/07).
      return (
        color: kFg,
        badge: 'PARTNER',
        sub: card.sector == null ? 'ENGINE' : sectorToJson(card.sector!),
      );
    case CardType.event:
      return (color: kDim, badge: card.type.name.toUpperCase(), sub: '');
  }
}
