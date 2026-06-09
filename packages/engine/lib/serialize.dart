/// SERIALIZATION + REPLAY — the run save's pure core (docs/06). The app does
/// the file I/O (path_provider, temp-write + rename); THIS file owns the
/// format and the reconstruction:
///
///   - [flatten]: the ONE canonical state walker (docs/06 §2.2 + doc 03 §5).
///     It lives HERE, in the pure engine, so the LOAD PATH (cache
///     reconciliation) and the §7 invariant / golden tests share one
///     implementation — there is no second copy (test/helpers/flatten.dart
///     re-exports this).
///   - [RunStep] (+ its JSON): the typed, REPLAYABLE journal — one entry per
///     engine call that advances the run (OPERATE / END_TURN /
///     DEADLINE_CHECK / a player apply / playCard / buyShopOffer). This is
///     the docs/06 §2.1 `actionLog` on disk: the parallel typed action log
///     the R13 work order sanctioned, carrying enough to re-drive each step
///     (the schemaVersion 7->8 persisted-contract change).
///   - [runSaveToJson] / [runSaveFromJson]: the docs/06 minimal record
///     `{schemaVersion, seed, cursor, startConfig:{runId, backgroundId},
///     actionLog, cache?}` and its reconstruction BY REPLAY (re-feed the
///     journal from the seed; the cache is an optimization, reconciled or
///     discarded per §2.2).
///   - Hand-written toJson/fromJson on the model (NO json_serializable on
///     GameState — the content layer proved hand-written avoids codegen
///     drift, and the rng-stripped cache needs bespoke handling anyway).
///
/// Pure and dependency-free except for `dart:convert` (JSON map<->string is
/// not I/O — no file, clock, RNG, or float) and sibling engine libraries.
library;

import 'dart:convert';

import 'actions.dart';
import 'apply.dart';
import 'content.dart';
import 'init.dart';
import 'model.dart';
import 'operate.dart';
import 'rng.dart';
import 'round.dart';

// ===========================================================================
// flatten() — the canonical state walker (moved here from the test helper per
// docs/06 §2.2: load path + invariant test share ONE implementation)
// ===========================================================================

/// Flattens [s] into sorted-comparable `path -> value` entries, keyed by
/// venture ID so a venture add/remove shows as appeared/disappeared paths,
/// not index shifts. Used by the cache reconciliation here, the §7 invariant
/// test, and the golden replay snapshot — ONE walker, no fork.
///
/// Values are integers OR card-id / display-name strings. Booleans encode
/// 0/1; enums encode their declaration `.index` (model.dart locks the order
/// as part of the replay contract); the nullable death is -1 while alive.
/// New families (partners, scheduled, market flags, exitOffer) emit paths
/// ONLY when set/non-empty — the appeared/disappeared convention. No
/// `double` anywhere.
Map<String, Object> flatten(GameState s) => {
      for (final v in s.ventures) ...{
        'venture.${v.id}.ebitda': v.ebitdaCents,
        'venture.${v.id}.multiple': v.multipleMilli,
        'venture.${v.id}.netDebt': v.netDebtCents,
        'venture.${v.id}.own': v.ownershipBp,
        'venture.${v.id}.passive': v.passive ? 1 : 0,
        // The deterministic display name (schemaVersion 8): a stable string
        // derived from id+sector — bookkeeping, but pinned so the golden
        // freezes the naming table.
        'venture.${v.id}.displayName': v.displayName,
        'venture.${v.id}.roundsNeglected': v.roundsNeglected,
        for (var i = 0; i < v.partners.length; i++) ...{
          'venture.${v.id}.partners.$i.defId': v.partners[i].defId,
          'venture.${v.id}.partners.$i.perRoundEbitda':
              v.partners[i].perRoundEbitdaCents,
        },
      },
      'cash': s.cashCents,
      'rngCursor': s.rngCursor,
      'round': s.round,
      'tier': s.tier,
      'schemaVersion': s.schemaVersion,
      // The founder background carried on the run state (schemaVersion 9 —
      // steers the per-round plays grant, so it is replay-relevant).
      'backgroundId': s.backgroundId,
      // The FROZEN-at-init draw-pool unlock snapshot (schemaVersion 10):
      // replay-relevant (it steers every hand/shop/event draw). Emitted as
      // indexed paths IN ORDER (the lists are already in content/enum order
      // from initRun; the order is part of the pool contract, so it is
      // pinned, not sorted away). A sector serializes as its enum .index
      // (the locked replay convention).
      for (var i = 0; i < s.unlockedCardIds.length; i++)
        'unlockedCardIds.$i': s.unlockedCardIds[i],
      for (var i = 0; i < s.unlockedSectors.length; i++)
        'unlockedSectors.$i': s.unlockedSectors[i].index,
      'rerollsUsed': s.rerollsUsed,
      'phase': s.phase.index,
      'playsRemaining': s.playsRemaining,
      'market.temp': s.market.temp.index,
      'market.roundsInState': s.market.roundsInState,
      'market.stateDurationRounds': s.market.stateDurationRounds,
      'market.liveRateBp': s.market.liveRateBp,
      if (s.market.hotWindowArmed) 'market.hotWindowArmed': 1,
      if (s.market.hotWindowExpiresRound >= 0)
        'market.hotWindowExpiresRound': s.market.hotWindowExpiresRound,
      if (s.market.marketReadHint != null)
        'market.marketReadHint': s.market.marketReadHint!.index,
      if (s.market.marketReadExpiresRound >= 0)
        'market.marketReadExpiresRound': s.market.marketReadExpiresRound,
      'netWorthAtTierEntry': s.netWorthAtTierEntry,
      'netWorthLastRound': s.netWorthLastRound,
      'won': s.won ? 1 : 0,
      'death': s.death == null ? -1 : s.death!.index,
      for (var i = 0; i < s.hand.length; i++) 'hand.$i': s.hand[i],
      for (var i = 0; i < s.shopOffers.length; i++)
        'shopOffers.$i': s.shopOffers[i],
      for (var i = 0; i < s.playsHeld.length; i++)
        'playsHeld.$i': s.playsHeld[i],
      for (var i = 0; i < s.scheduled.length; i++) ...{
        'scheduled.$i.ventureId': s.scheduled[i].ventureId ?? '-',
        'scheduled.$i.cashDelta': s.scheduled[i].cashDeltaCents,
        'scheduled.$i.recurring': s.scheduled[i].recurring ? 1 : 0,
      },
      if (s.exitOffer != null) ...{
        'exitOffer.ventureId': s.exitOffer!.ventureId,
        'exitOffer.multiple': s.exitOffer!.offerMultipleMilli,
      },
      'actionLog.length': s.actionLog.length,
    };

// ===========================================================================
// Small JSON cast helpers (NO `double` — the purity guard bans the word;
// jsonDecode of an integer literal yields an int on the VM, our only target)
// ===========================================================================

/// Reads [json]\[key] as an int, throwing a clear [FormatException] on a
/// missing/non-int value (a torn or foreign save fails loudly at the cast).
int _int(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is int) return v;
  throw FormatException('expected int at "$key", got $v');
}

/// Reads [json]\[key] as a String, throwing on a missing/non-string value.
String _str(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is String) return v;
  throw FormatException('expected String at "$key", got $v');
}

/// Casts a decoded JSON value to a typed object map (the shape codegen would
/// give), throwing on a non-object.
Map<String, Object?> _obj(Object? v, String what) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw FormatException('expected a JSON object for $what, got $v');
}

// ===========================================================================
// Action <-> JSON (the 12-variant closed union, doc 03 §4.1)
// ===========================================================================

/// Serializes an [Action] to a JSON map tagged with a `t` discriminator.
/// Every payload field is an int / String / Map<String,int> — no float.
Map<String, Object?> actionToJson(Action a) {
  switch (a) {
    case StartVenture():
      return {
        't': 'StartVenture',
        'ventureId': a.ventureId,
        'sector': sectorToJson(a.sector),
        'ebitda': a.ebitdaCents,
        'multiple': a.multipleMilli,
        'price': a.priceCents,
        'faceDebt': a.faceDebtCents,
      };
    case RaiseEquity():
      return {
        't': 'RaiseEquity',
        'ventureId': a.ventureId,
        'raise': a.raiseCents,
        'ebitdaDelta': a.ebitdaDeltaCents,
        'multipleDelta': a.multipleDeltaMilli,
      };
    case TakeDebt():
      return {
        't': 'TakeDebt',
        'ventureId': a.ventureId,
        'proceeds': a.proceedsCents,
        'faceDebt': a.faceDebtCents,
      };
    case AcquireAddOn():
      return {
        't': 'AcquireAddOn',
        'targetVentureId': a.targetVentureId,
        'addonSector': sectorToJson(a.addonSector),
        'addonEbitda': a.addonEbitdaCents,
        'addonBuyMultiple': a.addonBuyMultipleMilli,
        'addonFaceDebt': a.addonFaceDebtCents,
      };
    case DividendRecap():
      return {
        't': 'DividendRecap',
        'ventureId': a.ventureId,
        'recapPctBp': a.recapPctBp,
      };
    case ExitVenture():
      return {
        't': 'ExitVenture',
        'ventureId': a.ventureId,
        'offerMultiple': a.offerMultipleMilli,
        'liveMarketMultiple': a.liveMarketMultipleMilli,
      };
    case HireCEO():
      return {'t': 'HireCEO', 'ventureId': a.ventureId, 'cost': a.costCents};
    case SellPlay():
      return {
        't': 'SellPlay',
        'playId': a.playId,
        'purchasePrice': a.purchasePriceCents,
      };
    case Reroll():
      return {'t': 'Reroll', 'cost': a.costCents};
    case PlayConsumable():
      return {
        't': 'PlayConsumable',
        'playId': a.playId,
        'deltas': Map<String, Object?>.from(a.deltas),
        if (a.targetVentureId != null) 'targetVentureId': a.targetVentureId,
        'armsHotWindow': a.armsHotWindow,
        'readsMarket': a.readsMarket,
        'recapBp': a.recapBp,
        'secondaryBp': a.secondaryBp,
        'spinsOff': a.spinsOff,
        'earnOutPctBp': a.earnOutPctBp,
        'earnOutRounds': a.earnOutRounds,
      };
    case ReinvestBaseline():
      return {
        't': 'ReinvestBaseline',
        'ventureId': a.ventureId,
        'amount': a.amountCents,
      };
    case HirePartner():
      return {
        't': 'HirePartner',
        'ventureId': a.ventureId,
        'defId': a.defId,
        'cost': a.costCents,
        'perRoundEbitda': a.perRoundEbitdaCents,
        'multipleDelta': a.multipleDeltaMilli,
        'fixedCost': a.fixedCostCents,
      };
  }
}

/// Reconstructs an [Action] from [actionToJson]'s shape. Throws a
/// [FormatException] on an unknown discriminator (a save from a build with an
/// action this one lacks — caught by the loader as a corrupt/foreign run).
Action actionFromJson(Map<String, Object?> j) {
  final t = _str(j, 't');
  switch (t) {
    case 'StartVenture':
      return StartVenture(
        ventureId: _str(j, 'ventureId'),
        sector: sectorFromJson(_str(j, 'sector')),
        ebitdaCents: _int(j, 'ebitda'),
        multipleMilli: _int(j, 'multiple'),
        priceCents: _int(j, 'price'),
        faceDebtCents: _int(j, 'faceDebt'),
      );
    case 'RaiseEquity':
      return RaiseEquity(
        ventureId: _str(j, 'ventureId'),
        raiseCents: _int(j, 'raise'),
        ebitdaDeltaCents: _int(j, 'ebitdaDelta'),
        multipleDeltaMilli: _int(j, 'multipleDelta'),
      );
    case 'TakeDebt':
      return TakeDebt(
        ventureId: _str(j, 'ventureId'),
        proceedsCents: _int(j, 'proceeds'),
        faceDebtCents: _int(j, 'faceDebt'),
      );
    case 'AcquireAddOn':
      return AcquireAddOn(
        targetVentureId: _str(j, 'targetVentureId'),
        addonSector: sectorFromJson(_str(j, 'addonSector')),
        addonEbitdaCents: _int(j, 'addonEbitda'),
        addonBuyMultipleMilli: _int(j, 'addonBuyMultiple'),
        addonFaceDebtCents: _int(j, 'addonFaceDebt'),
      );
    case 'DividendRecap':
      return DividendRecap(
        ventureId: _str(j, 'ventureId'),
        recapPctBp: _int(j, 'recapPctBp'),
      );
    case 'ExitVenture':
      return ExitVenture(
        ventureId: _str(j, 'ventureId'),
        offerMultipleMilli: _int(j, 'offerMultiple'),
        liveMarketMultipleMilli: _int(j, 'liveMarketMultiple'),
      );
    case 'HireCEO':
      return HireCEO(ventureId: _str(j, 'ventureId'), costCents: _int(j, 'cost'));
    case 'SellPlay':
      return SellPlay(
        playId: _str(j, 'playId'),
        purchasePriceCents: _int(j, 'purchasePrice'),
      );
    case 'Reroll':
      return Reroll(costCents: _int(j, 'cost'));
    case 'PlayConsumable':
      final rawDeltas = _obj(j['deltas'], 'PlayConsumable.deltas');
      return PlayConsumable(
        playId: _str(j, 'playId'),
        deltas: {
          for (final e in rawDeltas.entries) e.key: e.value as int,
        },
        targetVentureId: j['targetVentureId'] as String?,
        armsHotWindow: j['armsHotWindow'] == true,
        readsMarket: j['readsMarket'] == true,
        recapBp: _int(j, 'recapBp'),
        secondaryBp: (j['secondaryBp'] as int?) ?? 0,
        spinsOff: j['spinsOff'] == true,
        earnOutPctBp: (j['earnOutPctBp'] as int?) ?? 0,
        earnOutRounds: (j['earnOutRounds'] as int?) ?? 0,
      );
    case 'ReinvestBaseline':
      return ReinvestBaseline(
        ventureId: _str(j, 'ventureId'),
        amountCents: _int(j, 'amount'),
      );
    case 'HirePartner':
      return HirePartner(
        ventureId: _str(j, 'ventureId'),
        defId: _str(j, 'defId'),
        costCents: _int(j, 'cost'),
        perRoundEbitdaCents: _int(j, 'perRoundEbitda'),
        multipleDeltaMilli: _int(j, 'multipleDelta'),
        fixedCostCents: _int(j, 'fixedCost'),
      );
    default:
      throw FormatException('unknown Action discriminator "$t"');
  }
}

// ===========================================================================
// RunStep — the typed, replayable journal entry (docs/06 §2.1 actionLog)
// ===========================================================================

/// One entry in the replayable run journal: a single engine call that
/// advanced the run (docs/06: the run is `{seed, cursor, startConfig,
/// actionLog}` and the actionLog is replayed). A `sealed` union so the
/// replay dispatch is compiler-checked exhaustive.
///
/// WHY a parallel typed log (not the display LoggedAction list)? The R13
/// work order sanctioned exactly this. The engine's `GameState.actionLog`
/// (LoggedAction) is the DISPLAY/autopsy trail, written only by player
/// applies + the system reseed; it does NOT record the OPERATE / END_TURN /
/// DEADLINE_CHECK phase transitions a replay must re-issue. This RunStep
/// journal records every advancing call so the save is a self-contained,
/// faithfully-replayable record — and replaying it REGENERATES the display
/// LoggedAction list identically (apply/reseed log as they always do), which
/// is exactly what the cache reconciliation's flatten() `actionLog.length`
/// then checks.
sealed class RunStep {
  const RunStep();

  /// JSON with a `s` (step) discriminator.
  Map<String, Object?> toJson();
}

/// Run OPERATE (the round's resolve; draws the hand/market/event).
class OperateStep extends RunStep {
  const OperateStep();
  @override
  Map<String, Object?> toJson() => const {'s': 'operate'};
}

/// Leave ACT for SHOP (deals the shop counter).
class EndTurnStep extends RunStep {
  const EndTurnStep();
  @override
  Map<String, Object?> toJson() => const {'s': 'endTurn'};
}

/// Evaluate the tier bar (advance / clear+reseed / win / death). Draw-free.
class DeadlineCheckStep extends RunStep {
  const DeadlineCheckStep();
  @override
  Map<String, Object?> toJson() => const {'s': 'deadlineCheck'};
}

/// A direct [apply] of a typed [Action] (Reroll, ReinvestBaseline, a
/// hand-built ExitVenture, etc. — anything dispatched straight through
/// apply rather than via a card id).
class ApplyStep extends RunStep {
  const ApplyStep(this.action);
  final Action action;
  @override
  Map<String, Object?> toJson() => {'s': 'apply', 'action': actionToJson(action)};
}

/// A [playCard] by id from the deck that owns its type (hand venture/addon/
/// partner, a SHOP-exercised financing offer, or a held consumable), with an
/// optional target venture.
class PlayCardStep extends RunStep {
  const PlayCardStep(this.cardId, {this.targetVentureId});
  final String cardId;
  final String? targetVentureId;
  @override
  Map<String, Object?> toJson() => {
        's': 'playCard',
        'cardId': cardId,
        if (targetVentureId != null) 'targetVentureId': targetVentureId,
      };
}

/// A [buyShopOffer] — take a consumable off the SHOP counter into inventory.
class BuyShopStep extends RunStep {
  const BuyShopStep(this.cardId);
  final String cardId;
  @override
  Map<String, Object?> toJson() => {'s': 'buyShop', 'cardId': cardId};
}

/// Reconstructs a [RunStep] from [RunStep.toJson]'s shape.
RunStep runStepFromJson(Map<String, Object?> j) {
  final s = _str(j, 's');
  switch (s) {
    case 'operate':
      return const OperateStep();
    case 'endTurn':
      return const EndTurnStep();
    case 'deadlineCheck':
      return const DeadlineCheckStep();
    case 'apply':
      return ApplyStep(actionFromJson(_obj(j['action'], 'ApplyStep.action')));
    case 'playCard':
      return PlayCardStep(_str(j, 'cardId'),
          targetVentureId: j['targetVentureId'] as String?);
    case 'buyShop':
      return BuyShopStep(_str(j, 'cardId'));
    default:
      throw FormatException('unknown RunStep discriminator "$s"');
  }
}

/// Thrown by [replayRun] when a recorded step does NOT reproduce its success
/// path (a rejected apply/playCard/buyShop) — the journal contradicts the
/// engine, which means a corrupt or foreign save. The loader treats this
/// like any corruption: discard the run (docs/06 §5). Never thrown by a
/// faithfully-recorded log on the same engine version.
class ReplayDesyncError extends Error {
  ReplayDesyncError(this.message);
  final String message;
  @override
  String toString() => 'ReplayDesyncError: $message';
}

/// Replays [steps] from the canonical [initRun] opening (posed by
/// [backgroundId]) with a FRESH `SplitMix64Rng(seed)`, returning the
/// reconstructed terminal/resumable [GameState]. This is the docs/06 §3.1
/// "replay is the save format" reconstruction — the SAME engine code path
/// the autopsy and balance harness use, so persistence correctness is free.
///
/// A player-step (apply/playCard/buyShop) that REJECTS throws
/// [ReplayDesyncError] (the journal lied; corrupt save). System steps
/// (operate/endTurn/deadlineCheck) that throw [StateError] (wrong phase)
/// propagate for the same reason. The caller (or [runSaveFromJson]) catches
/// these and abandons the run.
GameState replayRun(
  List<RunStep> steps, {
  required int seed,
  required String backgroundId,
  required EconomyConfig economy,
  required ContentDb content,
  List<String> unlockedCardIds = kDefaultUnlockedCardIds,
  List<Sector> unlockedSectors = kDefaultUnlockedSectors,
}) {
  var state = initRun(
    economy: economy,
    backgroundId: backgroundId,
    unlockedCardIds: unlockedCardIds,
    unlockedSectors: unlockedSectors,
  );
  final rng = SplitMix64Rng(seed);

  void checkClean(ApplyResult r, String label) {
    if (r.events.any((e) => e.type == GameEventType.actionRejected)) {
      final reason = r.events
          .firstWhere((e) => e.type == GameEventType.actionRejected)
          .reason;
      throw ReplayDesyncError('$label rejected on replay ($reason)');
    }
  }

  for (final step in steps) {
    switch (step) {
      case OperateStep():
        state = runOperate(state, rng, content).state;
      case EndTurnStep():
        state = endTurn(state, rng, content);
      case DeadlineCheckStep():
        state = runDeadlineCheck(state).state;
      case ApplyStep(:final action):
        final r = apply(state, action, rng, content);
        checkClean(r, 'apply(${action.runtimeType})');
        state = r.state;
      case PlayCardStep(:final cardId, :final targetVentureId):
        final r = playCard(state, cardId, rng, content,
            targetVentureId: targetVentureId);
        checkClean(r, 'playCard($cardId)');
        state = r.state;
      case BuyShopStep(:final cardId):
        final r = buyShopOffer(state, cardId, content);
        checkClean(r, 'buyShop($cardId)');
        state = r.state;
    }
  }
  return state;
}

// ===========================================================================
// GameState <-> JSON for the derived-state CACHE (docs/06 §2.2)
//
// The cache is a serialized RunState kept ONLY to skip replay on the hot
// path. Two rules keep it from contradicting the canonical record:
//   1. The RNG is STRIPPED on serialize (no rngCursor in the cache JSON);
//      the top-level seed/cursor are the only copies, re-injected on load.
//   2. The cache is tagged with the schema it was written at; a mismatch
//      drops it unread.
// Hand-written (NO json_serializable on GameState) — the rng strip + the
// per-venture/market/scheduled/exitOffer nesting want bespoke handling.
// ===========================================================================

Map<String, Object?> _ventureToJson(Venture v) => {
      'id': v.id,
      'sector': sectorToJson(v.sector),
      'ebitda': v.ebitdaCents,
      'multiple': v.multipleMilli,
      'netDebt': v.netDebtCents,
      'own': v.ownershipBp,
      'passive': v.passive,
      'roundsNeglected': v.roundsNeglected,
      'partners': [
        for (final p in v.partners)
          {'defId': p.defId, 'perRoundEbitda': p.perRoundEbitdaCents},
      ],
    };

Venture _ventureFromJson(Map<String, Object?> j) => Venture(
      id: _str(j, 'id'),
      sector: sectorFromJson(_str(j, 'sector')),
      ebitdaCents: _int(j, 'ebitda'),
      multipleMilli: _int(j, 'multiple'),
      netDebtCents: _int(j, 'netDebt'),
      ownershipBp: _int(j, 'own'),
      passive: j['passive'] == true,
      roundsNeglected: _int(j, 'roundsNeglected'),
      partners: [
        for (final p in (j['partners'] as List? ?? const []))
          PartnerEngine(
            defId: _str(_obj(p, 'partner'), 'defId'),
            perRoundEbitdaCents: _int(_obj(p, 'partner'), 'perRoundEbitda'),
          ),
      ],
    );

Map<String, Object?> _marketToJson(MarketState m) => {
      'temp': m.temp.index,
      'roundsInState': m.roundsInState,
      'stateDurationRounds': m.stateDurationRounds,
      'liveRateBp': m.liveRateBp,
      'hotWindowArmed': m.hotWindowArmed,
      'hotWindowExpiresRound': m.hotWindowExpiresRound,
      if (m.marketReadHint != null) 'marketReadHint': m.marketReadHint!.index,
      'marketReadExpiresRound': m.marketReadExpiresRound,
    };

MarketState _marketFromJson(Map<String, Object?> j) => MarketState(
      temp: MarketTemp.values[_int(j, 'temp')],
      roundsInState: _int(j, 'roundsInState'),
      stateDurationRounds: _int(j, 'stateDurationRounds'),
      liveRateBp: _int(j, 'liveRateBp'),
      hotWindowArmed: j['hotWindowArmed'] == true,
      hotWindowExpiresRound: _int(j, 'hotWindowExpiresRound'),
      marketReadHint: j['marketReadHint'] == null
          ? null
          : MarketTemp.values[j['marketReadHint'] as int],
      marketReadExpiresRound: _int(j, 'marketReadExpiresRound'),
    );

/// Serializes a [GameState] for the cache — RNG STRIPPED (no rngCursor).
/// The display LoggedAction trail IS included (round + summary): the cache is
/// a full RunState snapshot (docs/06 §2.2), so resuming from it preserves the
/// autopsy trail without a replay, and flatten()'s `actionLog.length`
/// reconciles against a replayed state (which regenerates the same count).
Map<String, Object?> gameStateCacheToJson(GameState s) => {
      'actionLog': [
        for (final l in s.actionLog) {'round': l.round, 'summary': l.summary},
      ],
      'ventures': [for (final v in s.ventures) _ventureToJson(v)],
      'cash': s.cashCents,
      'round': s.round,
      'tier': s.tier,
      'schemaVersion': s.schemaVersion,
      'backgroundId': s.backgroundId,
      'rerollsUsed': s.rerollsUsed,
      'market': _marketToJson(s.market),
      'phase': s.phase.index,
      'playsRemaining': s.playsRemaining,
      'netWorthAtTierEntry': s.netWorthAtTierEntry,
      'netWorthLastRound': s.netWorthLastRound,
      'won': s.won,
      'death': s.death?.index,
      'hand': s.hand,
      'shopOffers': s.shopOffers,
      'playsHeld': s.playsHeld,
      'scheduled': [
        for (final c in s.scheduled)
          {
            'ventureId': c.ventureId,
            'cashDelta': c.cashDeltaCents,
            'recurring': c.recurring,
            // schemaVersion 10: the EARN_OUT countdown + PCT_EBITDA basis.
            'roundsLeft': c.roundsLeft,
            'pctEbitdaBp': c.pctEbitdaBp,
          },
      ],
      if (s.exitOffer != null)
        'exitOffer': {
          'ventureId': s.exitOffer!.ventureId,
          'multiple': s.exitOffer!.offerMultipleMilli,
        },
      // The frozen draw-pool unlock snapshot (schemaVersion 10).
      'unlockedCardIds': s.unlockedCardIds,
      'unlockedSectors': [for (final s in s.unlockedSectors) s.index],
    };

/// Reconstructs the cached [GameState], RE-INJECTING [rngCursor] from the
/// top-level (docs/06 §2.2 rule 1: there is exactly one cursor on disk).
GameState gameStateCacheFromJson(Map<String, Object?> j, {required int rngCursor}) {
  final exit = j['exitOffer'];
  final deathIdx = j['death'];
  return GameState(
    actionLog: [
      for (final l in (j['actionLog'] as List? ?? const []))
        LoggedAction(
          round: _int(_obj(l, 'actionLog entry'), 'round'),
          summary: _str(_obj(l, 'actionLog entry'), 'summary'),
        ),
    ],
    ventures: [
      for (final v in (j['ventures'] as List)) _ventureFromJson(_obj(v, 'venture')),
    ],
    cashCents: _int(j, 'cash'),
    rngCursor: rngCursor,
    round: _int(j, 'round'),
    tier: _int(j, 'tier'),
    schemaVersion: _int(j, 'schemaVersion'),
    // Default to Bootstrapper if absent (a pre-9 cache, which is dropped
    // unread on the schema mismatch anyway — defensive parse).
    backgroundId:
        (j['backgroundId'] as String?) ?? kBootstrapperBackgroundId,
    rerollsUsed: _int(j, 'rerollsUsed'),
    market: _marketFromJson(_obj(j['market'], 'market')),
    phase: PhaseId.values[_int(j, 'phase')],
    playsRemaining: _int(j, 'playsRemaining'),
    netWorthAtTierEntry: _int(j, 'netWorthAtTierEntry'),
    netWorthLastRound: _int(j, 'netWorthLastRound'),
    won: j['won'] == true,
    death: deathIdx == null ? null : DeathCause.values[deathIdx as int],
    hand: [for (final c in (j['hand'] as List? ?? const [])) c as String],
    shopOffers: [
      for (final c in (j['shopOffers'] as List? ?? const [])) c as String,
    ],
    playsHeld: [
      for (final c in (j['playsHeld'] as List? ?? const [])) c as String,
    ],
    scheduled: [
      for (final c in (j['scheduled'] as List? ?? const []))
        ScheduledCost(
          ventureId: _obj(c, 'scheduled')['ventureId'] as String?,
          cashDeltaCents: _int(_obj(c, 'scheduled'), 'cashDelta'),
          recurring: _obj(c, 'scheduled')['recurring'] == true,
          // schemaVersion 10 fields; default to the v9 fixed-forever shape
          // (a pre-10 cache is dropped on the schema mismatch anyway).
          roundsLeft: (_obj(c, 'scheduled')['roundsLeft'] as int?) ?? -1,
          pctEbitdaBp: (_obj(c, 'scheduled')['pctEbitdaBp'] as int?) ?? 0,
        ),
    ],
    exitOffer: exit == null
        ? null
        : ExitOffer(
            ventureId: _str(_obj(exit, 'exitOffer'), 'ventureId'),
            offerMultipleMilli: _int(_obj(exit, 'exitOffer'), 'multiple'),
          ),
    // The frozen draw-pool unlock snapshot (schemaVersion 10); default to
    // the base curriculum if absent (a pre-10 cache, dropped on the schema
    // mismatch anyway — defensive parse).
    unlockedCardIds: j['unlockedCardIds'] == null
        ? kDefaultUnlockedCardIds
        : [for (final c in (j['unlockedCardIds'] as List)) c as String],
    unlockedSectors: j['unlockedSectors'] == null
        ? kDefaultUnlockedSectors
        : [
            for (final s in (j['unlockedSectors'] as List))
              Sector.values[s as int]
          ],
  );
}

// ===========================================================================
// The run save: the docs/06 minimal reproducible record + reconstruction
// ===========================================================================

/// Derives the run id from the [seed] (docs/06 §2.1: "the seed derives the
/// run id"; there is no separate run-id entropy). A short, stable,
/// human-readable hex tag — the seed IS the identity, this is the display/
/// guard form. The seed-derived id is authoritative; a denormalized
/// startConfig.runId that disagrees loses to this on load.
String runIdForSeed(int seed) {
  // Lower 32 bits as zero-padded hex (the seed can be negative as a signed
  // 64-bit int; mask to a stable unsigned 32-bit tag). NO float, NO RNG.
  final low = seed & 0xFFFFFFFF;
  final hex = low.toRadixString(16).padLeft(8, '0');
  return 'r_$hex';
}

/// Serializes a run to the docs/06 §2.1 minimal record:
/// `{schemaVersion, seed, cursor, startConfig:{runId, backgroundId},
/// actionLog:[RunStep], cache?:{schemaVersion, state}}`.
///
/// [steps] is the replayable journal (the source of truth). [cursor] is the
/// run's current RNG cursor (= the resumed [GameState.rngCursor]).
/// [cacheState], when given, is serialized rng-stripped as the optional
/// hot-path cache (docs/06 §2.2); omit it to write a journal-only save.
Map<String, Object?> runSaveToJson({
  required int seed,
  required int cursor,
  required String backgroundId,
  required List<RunStep> steps,
  GameState? cacheState,
  List<String> unlockedCardIds = kDefaultUnlockedCardIds,
  List<Sector> unlockedSectors = kDefaultUnlockedSectors,
}) {
  return {
    'schemaVersion': engineSchemaVersion,
    'seed': seed,
    'cursor': cursor,
    'startConfig': {
      'runId': runIdForSeed(seed),
      'backgroundId': backgroundId,
      // The FROZEN draw-pool unlock snapshot (schemaVersion 10): part of the
      // on-disk startConfig so replayRun rebuilds the SAME per-run pool from
      // the seed — the pool that fed every draw the journal recorded.
      'unlockedCardIds': unlockedCardIds,
      'unlockedSectors': [for (final s in unlockedSectors) s.index],
    },
    'actionLog': [for (final s in steps) s.toJson()],
    if (cacheState != null)
      'cache': {
        'schemaVersion': engineSchemaVersion,
        'state': gameStateCacheToJson(cacheState),
      },
  };
}

/// Convenience: [runSaveToJson] encoded to a JSON string (what the app
/// writes to run.json.tmp). `dart:convert` only — no file I/O here.
String runSaveToJsonString({
  required int seed,
  required int cursor,
  required String backgroundId,
  required List<RunStep> steps,
  GameState? cacheState,
  List<String> unlockedCardIds = kDefaultUnlockedCardIds,
  List<Sector> unlockedSectors = kDefaultUnlockedSectors,
}) =>
    jsonEncode(runSaveToJson(
      seed: seed,
      cursor: cursor,
      backgroundId: backgroundId,
      steps: steps,
      cacheState: cacheState,
      unlockedCardIds: unlockedCardIds,
      unlockedSectors: unlockedSectors,
    ));

/// The outcome of loading a run save (docs/06 §2.2): the reconstructed
/// [state] plus whether the cache was trusted ([usedCache]) — the app logs a
/// dev warning when the cache was discarded (replay silently won).
class RunLoadResult {
  const RunLoadResult({
    required this.state,
    required this.seed,
    required this.cursor,
    required this.backgroundId,
    required this.runId,
    required this.steps,
    required this.usedCache,
    this.unlockedCardIds = kDefaultUnlockedCardIds,
    this.unlockedSectors = kDefaultUnlockedSectors,
  });

  /// The reconstructed run state (cache-trusted or freshly replayed).
  final GameState state;

  /// The run stream seed (the only copy on disk).
  final int seed;

  /// The resume cursor (top-level; the only copy on disk).
  final int cursor;

  /// The founder background the run was started with.
  final String backgroundId;

  /// The seed-derived run id (authoritative).
  final String runId;

  /// The replayable journal as loaded (the app keeps appending to it).
  final List<RunStep> steps;

  /// True iff the cache reconciled (flatten-equal + cursor match) and was
  /// trusted; false iff it was absent/stale/divergent and replay was used.
  final bool usedCache;

  /// The run's FROZEN draw-pool unlock snapshot (schemaVersion 10), as
  /// loaded from the save's startConfig (so the app keeps it for re-saves).
  final List<String> unlockedCardIds;
  final List<Sector> unlockedSectors;
}

/// Reconstructs a run from a [runSaveToJson] map BY REPLAY (docs/06 §2.2,
/// §3.1). Assumes the map is already at [engineSchemaVersion] — the loader
/// runs migrate.dart's `migrateRun` FIRST (which throws AbandonRun on a
/// stream-breaking version); a residual schema mismatch here throws
/// [FormatException] (defensive).
///
/// Steps:
///   1. Parse seed/cursor/startConfig/actionLog. The seed-derived runId
///      wins over a denormalized startConfig.runId (docs/06 §2.1).
///   2. REPLAY the journal from the seed (the canonical record).
///   3. Assert the replayed cursor == the top-level cursor (a corruption
///      signal; on mismatch the cache is irrelevant — replay is the truth,
///      but a cursor disagreement means the journal itself is wrong, so we
///      surface it).
///   4. Reconcile the cache IF present and `cache.schemaVersion == top`:
///      re-inject {seed,cursor} into the cached rng, then if
///      `flatten(replayed) == flatten(cached)` trust the cache (resume),
///      else discard it and resume from the replayed state (dev warning via
///      usedCache=false). A stale-schema cache is dropped unread.
///
/// [content]/[economy] feed the replay (initRun + the draw functions).
RunLoadResult runSaveFromJson(
  Map<String, Object?> json, {
  required EconomyConfig economy,
  required ContentDb content,
}) {
  final schema = _int(json, 'schemaVersion');
  if (schema != engineSchemaVersion) {
    throw FormatException(
        'run save schemaVersion $schema != engine $engineSchemaVersion '
        '(migrate first; a stream-breaking version must AbandonRun)');
  }
  final seed = _int(json, 'seed');
  final cursor = _int(json, 'cursor');
  final startConfig = _obj(json['startConfig'], 'startConfig');
  final backgroundId = _str(startConfig, 'backgroundId');
  final runId = runIdForSeed(seed); // seed-derived wins (docs/06 §2.1)
  // The FROZEN draw-pool unlock snapshot (schemaVersion 10): default to the
  // base curriculum if absent (a torn save; the schema check above already
  // guards a real version gap).
  final unlockedCardIds = startConfig['unlockedCardIds'] == null
      ? kDefaultUnlockedCardIds
      : [for (final c in (startConfig['unlockedCardIds'] as List)) c as String];
  final unlockedSectors = startConfig['unlockedSectors'] == null
      ? kDefaultUnlockedSectors
      : [
          for (final s in (startConfig['unlockedSectors'] as List))
            Sector.values[s as int]
        ];

  final rawLog = json['actionLog'];
  if (rawLog is! List) {
    throw const FormatException('run save: actionLog must be a list');
  }
  final steps = [
    for (final e in rawLog) runStepFromJson(_obj(e, 'actionLog entry')),
  ];

  // (2) Replay — the canonical reconstruction.
  final replayed = replayRun(steps,
      seed: seed,
      backgroundId: backgroundId,
      economy: economy,
      content: content,
      unlockedCardIds: unlockedCardIds,
      unlockedSectors: unlockedSectors);

  // (3) Cursor must reconcile to the stream the journal drove.
  if (replayed.rngCursor != cursor) {
    throw FormatException(
        'run save: replay cursor ${replayed.rngCursor} != stored cursor '
        '$cursor (corrupt journal)');
  }

  // (4) Cache reconciliation (optional optimization).
  var usedCache = false;
  var state = replayed;
  final cache = json['cache'];
  if (cache is Map) {
    final cacheObj = _obj(cache, 'cache');
    final cacheSchema = cacheObj['schemaVersion'];
    if (cacheSchema == engineSchemaVersion) {
      final cached =
          gameStateCacheFromJson(_obj(cacheObj['state'], 'cache.state'), rngCursor: cursor);
      // flatten-equality on the economic + replay-relevant paths.
      if (_flattenEquals(flatten(replayed), flatten(cached))) {
        state = cached;
        usedCache = true;
      }
      // else: discard the cache, resume from replayed (usedCache stays false).
    }
    // else: stale-schema cache dropped unread.
  }

  return RunLoadResult(
    state: state,
    seed: seed,
    cursor: cursor,
    backgroundId: backgroundId,
    runId: runId,
    steps: steps,
    usedCache: usedCache,
    unlockedCardIds: unlockedCardIds,
    unlockedSectors: unlockedSectors,
  );
}

/// Convenience: parse a run.json STRING then [runSaveFromJson].
RunLoadResult runSaveFromJsonString(
  String jsonStr, {
  required EconomyConfig economy,
  required ContentDb content,
}) =>
    runSaveFromJson(_obj(jsonDecode(jsonStr), 'run save'),
        economy: economy, content: content);

/// Key-and-value equality over two flatten() maps (the cache reconciliation
/// check; the package avoids a `collection` dependency).
bool _flattenEquals(Map<String, Object> a, Map<String, Object> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

// ===========================================================================
// MetaState <-> JSON (meta.json, serialized WHOLE — docs/06 §2.3)
//
// Enum fields serialize to their canonical NAMES (doc 02 §1 DeathCause
// BANKRUPTCY/MISSED_DEADLINE; Sector via sectorToJson) — not the .index, so
// meta.json is human-readable and a value outside the enum fails the parse
// (caught by the migrate pass). meta.json carries NO RunState — the two
// files are physically separate (docs/06 §2).
// ===========================================================================

/// Serializes [DeathCause] to its canonical JSON name (doc 02 §1).
String deathCauseToJson(DeathCause c) {
  switch (c) {
    case DeathCause.bankruptcy:
      return 'BANKRUPTCY';
    case DeathCause.missedDeadline:
      return 'MISSED_DEADLINE';
  }
}

/// Parses a [DeathCause] JSON name; throws on an unknown spelling.
DeathCause deathCauseFromJson(String s) {
  switch (s) {
    case 'BANKRUPTCY':
      return DeathCause.bankruptcy;
    case 'MISSED_DEADLINE':
      return DeathCause.missedDeadline;
    default:
      throw FormatException('unknown DeathCause "$s"');
  }
}

/// Serializes [MetaState] whole for meta.json (docs/06 §2.3).
Map<String, Object?> metaStateToJson(MetaState m) => {
      'schemaVersion': m.schemaVersion,
      'reputation': m.reputation,
      'metaLevel': m.metaLevel,
      'furthestTierReached': m.furthestTierReached,
      'unlockedCards': m.unlockedCards,
      'unlockedSectors': [for (final s in m.unlockedSectors) sectorToJson(s)],
      'unlockedBackgrounds': m.unlockedBackgrounds,
      'hardModes': m.hardModes,
      'cosmetics': {
        'titles': m.cosmetics.titles,
        'activeTitle': m.cosmetics.activeTitle,
        'iconSkins': m.cosmetics.iconSkins,
      },
      'lastDeathCause':
          m.lastDeathCause == null ? null : deathCauseToJson(m.lastDeathCause!),
      'runsPlayed': m.runsPlayed,
      'cleanExits': m.cleanExits,
      'lastSettledRunId': m.lastSettledRunId,
    };

/// Convenience: [metaStateToJson] encoded to a string (what the app writes
/// to meta.json.tmp).
String metaStateToJsonString(MetaState m) => jsonEncode(metaStateToJson(m));

/// Reconstructs [MetaState] from a CURRENT-shape meta map (run migrate.dart's
/// `migrateMeta` FIRST on an older file). A null/absent optional field falls
/// back to the MetaState default. Enum spellings outside the enum throw.
MetaState metaStateFromJson(Map<String, Object?> j) {
  final cos = j['cosmetics'] is Map
      ? _obj(j['cosmetics'], 'cosmetics')
      : const <String, Object?>{};
  final deathRaw = j['lastDeathCause'];
  return MetaState(
    schemaVersion: _int(j, 'schemaVersion'),
    reputation: _int(j, 'reputation'),
    metaLevel: _int(j, 'metaLevel'),
    furthestTierReached: _int(j, 'furthestTierReached'),
    unlockedCards: [
      for (final c in (j['unlockedCards'] as List? ?? const [])) c as String,
    ],
    unlockedSectors: [
      for (final s in (j['unlockedSectors'] as List? ?? const []))
        sectorFromJson(s as String),
    ],
    unlockedBackgrounds: [
      for (final b in (j['unlockedBackgrounds'] as List? ?? const []))
        b as String,
    ],
    hardModes: [
      for (final h in (j['hardModes'] as List? ?? const [])) h as String,
    ],
    cosmetics: MetaCosmetics(
      titles: [for (final t in (cos['titles'] as List? ?? const [])) t as String],
      activeTitle: cos['activeTitle'] as String?,
      iconSkins: [
        for (final i in (cos['iconSkins'] as List? ?? const [])) i as String,
      ],
    ),
    lastDeathCause:
        deathRaw == null ? null : deathCauseFromJson(deathRaw as String),
    runsPlayed: _int(j, 'runsPlayed'),
    cleanExits: _int(j, 'cleanExits'),
    lastSettledRunId: j['lastSettledRunId'] as String?,
  );
}

/// Convenience: parse a meta.json STRING then [metaStateFromJson].
MetaState metaStateFromJsonString(String jsonStr) =>
    metaStateFromJson(_obj(jsonDecode(jsonStr), 'meta save'));
