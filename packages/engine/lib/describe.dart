/// describeAction — turns a logged player action into the autopsy's human
/// "THE ROUND IT BROKE" line (doc 02 §Q5; the S8 autopsy row). Pure display
/// formatting via the money.dart helpers — it REPLACES the raw cents leak
/// R9 flagged (the S8 round-line printed the engine actionLog summary
/// verbatim: `BuyShopOffer PLY_MARKET_READ: cost 100000` — milli/cents
/// straight to the player). Every number here goes through formatMoney /
/// formatMultiple, never a raw integer.
///
/// Two entry points:
///   - [describeAction]: the core — a typed [Action] + its round -> a clean
///     sentence. Uses the action's own raw magnitudes (the reliable source),
///     not a parsed summary string.
///   - [describeRunStep]: the step-level wrapper for the replayable journal
///     (serialize.dart) — dispatches a [RunStep] (player apply / playCard /
///     buyShop, or a system OPERATE/END_TURN/DEADLINE_CHECK) to a line,
///     looking card names up in the [ContentDb] when given.
///
/// Pure and dependency-free except for sibling engine libraries.
library;

import 'actions.dart';
import 'content.dart';
import 'model.dart';
import 'money.dart';
import 'serialize.dart';

/// A human, money-formatted one-line description of [action] taken in
/// [round] (doc 02 §Q5 autopsy phrasing). [ventureName] (the venture's
/// [Venture.displayName]) is woven in when the action targets one and the
/// caller can supply it; otherwise the target id is used.
///
/// The lines are written for the autopsy's "THE ROUND IT BROKE" row — the
/// decisive move — so they read as a consequence ("took on $500k of
/// leverage", "exited at 6.0x for $1.2M"), not a debug dump.
String describeAction(Action action, {required int round, String? ventureName}) {
  final r = 'Round $round: ';
  String who(String id) => ventureName ?? id;
  switch (action) {
    case StartVenture():
      return '${r}founded ${who(action.ventureId)} '
          '(${sectorToJson(action.sector)}) for '
          '${formatMoney(action.priceCents)}';
    case RaiseEquity():
      return '${r}raised ${formatMoney(action.raiseCents)} of equity into '
          '${who(action.ventureId)} (diluted your stake)';
    case TakeDebt():
      return '${r}took on ${formatMoney(action.faceDebtCents)} of leverage '
          '(${formatMoney(action.proceedsCents)} cash now, interest forever)';
    case AcquireAddOn():
      return '${r}bolted a ${sectorToJson(action.addonSector)} add-on onto '
          '${who(action.targetVentureId)} at '
          '${formatMultiple(action.addonBuyMultipleMilli)}';
    case DividendRecap():
      return '${r}pulled a dividend recap out of ${who(action.ventureId)} '
          '(cash now, debt forever)';
    case ExitVenture():
      return '${r}exited ${who(action.ventureId)} at '
          '${formatMultiple(action.offerMultipleMilli)}';
    case HireCEO():
      return '${r}hired a CEO for ${who(action.ventureId)} '
          '(${formatMoney(action.costCents)}; went passive)';
    case SellPlay():
      return '${r}sold a held play for '
          '${formatMoney(truncDiv(action.purchasePriceCents, 2))}';
    case Reroll():
      return '${r}paid ${formatMoney(action.costCents)} to reroll the deals';
    case PlayConsumable():
      if (action.recapBp > 0) {
        return '${r}played a dividend recap';
      }
      if (action.secondaryBp > 0) {
        return '${r}sold a secondary stake';
      }
      if (action.armsHotWindow) return '${r}armed a hot exit window';
      if (action.readsMarket) return '${r}read the market';
      return '${r}played a consumable';
    case ReinvestBaseline():
      return '${r}reinvested ${formatMoney(action.amountCents)} into '
          '${who(action.ventureId)}';
    case HirePartner():
      return '${r}hired an operating partner for ${who(action.ventureId)} '
          '(${formatMoney(action.costCents)})';
  }
}

/// A human one-line description of a replayable [step] taken in [round]
/// (the autopsy reads the typed journal). Player steps delegate to
/// [describeAction]; [content], when given, resolves a [PlayCardStep] /
/// [BuyShopStep] card id to its flavor name. System steps get a phase line
/// (rarely the decisive move, but complete for a full trail).
///
/// [ventures] (the current holdings) lets the line name a targeted venture by
/// its [Venture.displayName] instead of its raw id.
String describeRunStep(
  RunStep step, {
  required int round,
  ContentDb? content,
  List<Venture> ventures = const [],
}) {
  String? nameFor(String? ventureId) {
    if (ventureId == null) return null;
    for (final v in ventures) {
      if (v.id == ventureId) return v.displayName;
    }
    return null;
  }

  switch (step) {
    case OperateStep():
      return 'Round $round: a quarter passed (operations + market)';
    case EndTurnStep():
      return 'Round $round: closed the books for the round';
    case DeadlineCheckStep():
      return 'Round $round: faced the deadline';
    case ApplyStep(:final action):
      final vId = _actionVentureId(action);
      return describeAction(action, round: round, ventureName: nameFor(vId));
    case PlayCardStep(:final cardId, :final targetVentureId):
      final cardName = content != null ? content.byId(cardId).name : cardId;
      final target = nameFor(targetVentureId);
      final onto = target == null ? '' : ' onto $target';
      return 'Round $round: played $cardName$onto';
    case BuyShopStep(:final cardId):
      final cardName = content != null ? content.byId(cardId).name : cardId;
      return 'Round $round: bought $cardName off the counter';
  }
}

/// The venture an [action] targets, or null for context-free ones — used to
/// resolve a display name for the autopsy line.
String? _actionVentureId(Action action) {
  switch (action) {
    case StartVenture():
      return action.ventureId;
    case RaiseEquity():
      return action.ventureId;
    case TakeDebt():
      return action.ventureId;
    case AcquireAddOn():
      return action.targetVentureId;
    case DividendRecap():
      return action.ventureId;
    case ExitVenture():
      return action.ventureId;
    case HireCEO():
      return action.ventureId;
    case ReinvestBaseline():
      return action.ventureId;
    case HirePartner():
      return action.ventureId;
    case PlayConsumable():
      return action.targetVentureId;
    case SellPlay():
    case Reroll():
      return null;
  }
}
