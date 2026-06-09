/// The resolver entry point: `apply(state, action, rng, content) ->
/// ApplyResult`, plus the deal-flow player entry points [buyShopOffer]
/// (the SHOP counter) and [playCard] (play a card from hand/offers by id).
///
/// Doc 03 §4: the resolver is a pure function over the immutable model — same
/// inputs, same output; no I/O, no clock, no float. It dispatches over the
/// closed `Action` union (doc 03 §4.1) and returns the next state plus a small
/// list of [GameEvent]s for the UI to animate (doc 02 §1 GameEvent, trimmed
/// here to what the engine needs now; it grows as actions land).
///
/// Precondition failure (doc 02 §3 notation: PRE) means NO state change — the
/// returned state is the input state — plus a single ACTION_REJECTED event
/// carrying a snake_case reason key. The phase and plays gates (doc 02 §3
/// PRE columns) run FIRST, in [apply], before any action-specific PRE.
/// Postconditions (POST) mutate only the five §7 inputs
/// `{ebitda, multiple, netDebt, own, cash}` plus whitelisted bookkeeping
/// (actionLog, venture add/remove, the play-counter decrement, the
/// hand/shopOffers/playsHeld list consumption, and the doc 02 §2 ACT rule:
/// any action TARGETING a venture resets that venture's `roundsNeglected`
/// to 0 — wired into every targeting branch below; OPERATE increments it).
///
/// `content` (the loaded card database) is threaded through [apply] for the
/// actions that consume it — today ONLY Reroll's redraw; every other action
/// ignores it (its payload already carries the raw magnitudes, mapped
/// upstream by dealflow.actionForCard).
///
/// Pure and dependency-free except for sibling engine libraries (only
/// `dart:core`).
library;

import 'actions.dart';
import 'content.dart';
import 'dealflow.dart';
import 'model.dart';
import 'resolver.dart';
import 'rng.dart';

export 'dealflow.dart' show slotsMax;

/// The UI event contract returned from [apply], never persisted (doc 02 §1
/// GameEventType, trimmed to the variants the engine emits today).
enum GameEventType {
  /// BUY_ADDON committed; carries the realized accretion (RENDER-ONLY).
  multipleArbitrage,

  /// RAISE (later DOWN_ROUND) cut ownership; carries the signed bp delta.
  dilution,

  /// EXIT paid out; carries the realized proceeds in cents.
  exitRealized,

  /// A PRE failed; carries a reason key. The state did not change.
  actionRejected,

  /// OPERATE step 6 charged interest; carries the bill in cents (> 0;
  /// a zero-debt round emits nothing).
  interestCharged,

  /// OPERATE step 4 decayed a neglected venture; carries the SIGNED ebitda
  /// delta in cents (<= 0) and the venture id.
  neglectDecay,

  /// The market weather actually turned at a state boundary (engine
  /// extension for the doc 02 §1 HOT/COLD banner; a same-temp redraw emits
  /// nothing). Carries the new duration in rounds and a
  /// `market_now_<temp>` reason key.
  marketStateChanged,

  /// F6 fired: cash went below zero after the OPERATE interest charge.
  /// Carries the (negative) post-charge cash. The run is over.
  bankruptcy,

  /// DEADLINE_CHECK cleared the tier bar (doc 02 §2); carries the
  /// bar-clearing net worth in cents. The reseed that follows is visible in
  /// the action log, not as a separate event.
  tierCleared,

  /// DEADLINE_CHECK cleared an ENDLESS ante's rising survival bar (T5;
  /// doc 01 §5 escalating modifiers, audit L1); carries the net worth in
  /// cents. The next ante's bar is higher. Endless never WINS (no won
  /// event), it only continues until it fails out (missedDeadline). Events
  /// are UI-only and never persisted, so appending this member is
  /// replay-safe.
  endlessAnteCleared,

  /// DEADLINE_CHECK ran out of rounds with the bar uncleared (doc 02 §2);
  /// carries the final net worth in cents. The run is over.
  missedDeadline,

  /// DEADLINE_CHECK cleared the T4 $1B bar — the win (doc 02 §2: clearing
  /// TIER_BAR[4] IS the win); carries the final net worth in cents. The run
  /// is over (victorious).
  won,

  /// OPERATE step 5 fired an event card and auto-resolved its deltas
  /// (doc 01 §6.1 step 5; doc 04 events). Carries the card id as the
  /// reason key — the UI looks the face up in content. Engine extension
  /// like [marketStateChanged] (doc 02 §1 has no event-fired variant;
  /// SCHEDULED_EFFECT_FIRED is the deferred-effect channel, not this).
  eventResolved,

  /// OPERATE step 3c fired a [ScheduledCost] entry (doc 02 §1
  /// SCHEDULED_EFFECT_FIRED; §2 scheduled-effects step). Carries the
  /// signed cash delta and the venture the entry's lifetime is tied to
  /// (null = run-level).
  scheduledEffectFired,

  /// PLAY_CONSUMABLE armed the hot window (doc 02 §1 HOT_WINDOW_ARMED);
  /// carries the flat-round expiry as the amount.
  hotWindowArmed,

  /// An EXIT fired the armed hot window (doc 02 §1 HOT_WINDOW_FIRED);
  /// carries the forced hot multiple in milli-units.
  hotWindowFired,

  /// OPERATE step 1 expired an unconsumed hot window (doc 02 §1
  /// HOT_WINDOW_EXPIRED).
  hotWindowExpired,

  /// PLAY_CONSUMABLE revealed next round's direction (doc 02 §1
  /// MARKET_READ_REVEALED); the reason carries `market_read_<temp>`.
  marketReadRevealed,

  /// PLAY_CONSUMABLE resolved a CANONICAL dividend recap (doc 01 §7.7;
  /// R12): carries the realized pull in cents (`trunc(EV x recapBp /
  /// 10000)` — banked to cash AND landed as new debt on the carried
  /// venture id). Events are UI-only and never persisted, so appending
  /// this member is replay-safe.
  dividendRecap,

  /// PLAY_CONSUMABLE resolved a SECONDARY SALE (doc 02 §3.6; schemaVersion
  /// 9): sold Δownership at the live mark. Carries the realized proceeds in
  /// cents (`trunc(equity x secondaryBp / 10000)` — banked to cash; the
  /// target's ownership dropped by the sold bp) and the venture id. The
  /// meta layer folds the amount into reputation as a secondary
  /// (RunOutcomes.withSecondary). UI-only, never persisted — replay-safe.
  secondarySale,
}

/// A minimal immutable UI event (doc 02 §1 GameEvent, trimmed: type +
/// headline amount + optional venture id + optional reason key).
class GameEvent {
  const GameEvent({
    required this.type,
    this.amount = 0,
    this.ventureId,
    this.reason,
  });

  /// What happened.
  final GameEventType type;

  /// Headline number (cents/milli/bp depending on [type]); 0 when not
  /// applicable. For [GameEventType.multipleArbitrage] this is the
  /// RENDER-ONLY accretion flash in cents — written to NO state field.
  final int amount;

  /// The venture the event concerns, when there is one.
  final String? ventureId;

  /// Snake_case phrasing key (rejections, autopsy flavor), when there is one.
  final String? reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameEvent &&
        other.type == type &&
        other.amount == amount &&
        other.ventureId == ventureId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(type, amount, ventureId, reason);

  @override
  String toString() => 'GameEvent(type: $type, amount: $amount, '
      'ventureId: $ventureId, reason: $reason)';
}

/// The result of [apply]: the next immutable state plus the events the action
/// produced (unmodifiable).
class ApplyResult {
  /// Builds an [ApplyResult]; [events] is copied into an unmodifiable list.
  ApplyResult({required this.state, required List<GameEvent> events})
      : events = List.unmodifiable(events);

  /// The state after the action (identical to the input state on rejection).
  final GameState state;

  /// What happened, for the UI to animate. Never persisted.
  final List<GameEvent> events;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApplyResult &&
        other.state == state &&
        _listEquals(other.events, events);
  }

  @override
  int get hashCode => Object.hash(state, Object.hashAll(events));

  @override
  String toString() => 'ApplyResult(state: $state, events: $events)';
}

// slotsMax moved to dealflow.dart at schemaVersion 5 (the v5 hand-pool
// filter needs it); re-exported below so existing imports keep working.

/// True when [action] consumes one of the round's PLAYS on success.
/// Source: the doc 02 §3 action/economy matrix — REROLL, PLAY_CONSUMABLE
/// (a held resource, §Q2), and sell-a-play are throughput-FREE; every other
/// Act costs exactly 1 play. DividendRecap rides the costing side here
/// because the engine models it as a standalone action (doc 02 files it
/// under consumables; when it arrives via PlayConsumable deltas it is free
/// like any play — both paths exist by design).
bool _costsPlay(Action action) =>
    action is! Reroll && action is! PlayConsumable && action is! SellPlay;

/// Applies [action] to [state], returning the next state plus UI events.
///
/// Doc 02 §3 PREs, gated IN ORDER before any action-specific check:
///  1. PHASE — every action requires `phase == act`, except REROLL which is
///     legal in act OR shop (doc 02 §3.8). Failure rejects with
///     `wrong_phase` (actions REJECT through the event channel; the phase
///     STEP functions — runOperate/endTurn/runDeadlineCheck — throw
///     StateError instead: a step from the wrong phase is a caller bug,
///     an action is player input).
///  2. PLAYS — play-costing actions (see [_costsPlay]) require
///     `playsRemaining >= 1`; failure rejects with `no_plays_remaining`.
/// On SUCCESS a play-costing action then decrements `playsRemaining` by 1
/// ("costs 1 play"); rejections never spend the play.
///
/// [rng] is the run's deterministic stream; actions that draw (today ONLY
/// Reroll, whose redraw re-runs the current phase's deal-flow routine)
/// advance its cursor and reconcile `state.rngCursor`. [content] feeds the
/// redraw; non-card actions ignore it.
ApplyResult apply(
    GameState state, Action action, SplitMix64Rng rng, ContentDb content) {
  final phaseOk = action is Reroll
      ? state.phase == PhaseId.act || state.phase == PhaseId.shop
      : state.phase == PhaseId.act;
  if (!phaseOk) return _reject(state, 'wrong_phase');
  if (_costsPlay(action) && state.playsRemaining < 1) {
    return _reject(state, 'no_plays_remaining');
  }

  final result = _dispatch(state, action, rng, content);
  if (!_costsPlay(action) ||
      result.events.any((e) => e.type == GameEventType.actionRejected)) {
    return result;
  }
  return ApplyResult(
    state: result.state
        .copyWith(playsRemaining: result.state.playsRemaining - 1),
    events: result.events,
  );
}

/// The per-variant dispatch (doc 03 §4.1's closed union), after the gates.
/// Only Reroll consumes [rng]/[content].
ApplyResult _dispatch(
    GameState state, Action action, SplitMix64Rng rng, ContentDb content) {
  switch (action) {
    case AcquireAddOn():
      return _acquireAddOn(state, action);
    case StartVenture():
      return _startVenture(state, action);
    case RaiseEquity():
      return _raiseEquity(state, action);
    case TakeDebt():
      return _takeDebt(state, action);
    case DividendRecap():
      return _dividendRecap(state, action);
    case ExitVenture():
      return _exitVenture(state, action);
    case HireCEO():
      return _hireCEO(state, action);
    case HirePartner():
      return _hirePartner(state, action);
    case SellPlay():
      return _sellPlay(state, action);
    case Reroll():
      return _reroll(state, action, rng, content);
    case PlayConsumable():
      return _playConsumable(state, action);
    case ReinvestBaseline():
      return _reinvestBaseline(state, action);
  }
}

/// Rejection: NO state change, one ACTION_REJECTED event with a reason key
/// (doc 02 §3 PRE notation).
ApplyResult _reject(GameState state, String reason) => ApplyResult(
      state: state,
      events: [GameEvent(type: GameEventType.actionRejected, reason: reason)],
    );

/// BUY_ADDON — the signature multiple-arbitrage merge (doc 02 §3.4; doc 03
/// §4.2: resolver-COMPUTED from live platform state, never card deltas).
///
/// PRE: the target platform exists; `cash >= price` where
/// `price = trunc(addonEbitda * m_buy / 1000)` (economy-model.json
/// `addonPrice`). Else reject, no mutation.
///
/// POST: `cash -= price`; `netDebt += faceDebt`. Same-sector: EBITDA absorbs
/// the add-on plus +20% synergy at an unchanged multiple
/// (economy-model.json `synergySameSector`). Cross-sector: raw EBITDA, zero
/// synergy, and the live platform multiple drags by x0.92 per add-on,
/// stacking 0.92^n (economy-model.json `congDrag`) — may be net-dilutive,
/// which is legal and intended. The dragged multiple is clamped at the
/// 1000-milli (1.0x) live-venture floor (economy-model.json
/// resolverInputs.clamps; reachable because drift floors at exactly 1000).
///
/// Emits MULTIPLE_ARBITRAGE whose amount is the RENDER-ONLY accretion flash
/// `trunc(addonEbitda * (m_platform - m_buy) / 1000)` (economy-model.json
/// `arbitrageFlash`), written to NO state field. Design decision (the docs
/// leave `m_platform` open for the cross-sector case): the flash uses the
/// PRE-merge live platform multiple — the multiple the absorbed earnings
/// bolt in at per doc 03 §4.2; the drag is a separate, visible consequence.
ApplyResult _acquireAddOn(GameState state, AcquireAddOn a) {
  final idx = state.ventures.indexWhere((v) => v.id == a.targetVentureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  final platform = state.ventures[idx];

  // price = trunc(addon.ebitda * m_buy / 1000) — same F1 shape as EV.
  final price = enterpriseValue(a.addonEbitdaCents, a.addonBuyMultipleMilli);
  if (state.cashCents < price) return _reject(state, 'insufficient_cash');

  final sameSector = a.addonSector == platform.sector;
  // Cross-sector drag, clamped at the live-venture multiple floor
  // (economy-model.json resolverInputs.clamps: multiple >= 1000).
  final dragged = absorbCrossSectorMultiple(platform.multipleMilli);
  final draggedClamped =
      dragged < multipleFloorMilli ? multipleFloorMilli : dragged;
  final merged = platform.copyWith(
    ebitdaCents: sameSector
        ? absorbSameSector(
            platformEbitda: platform.ebitdaCents,
            addonEbitda: a.addonEbitdaCents,
          )
        : platform.ebitdaCents + a.addonEbitdaCents, // zero synergy
    multipleMilli: sameSector
        ? platform.multipleMilli // unchanged
        : draggedClamped,
    netDebtCents: platform.netDebtCents + a.addonFaceDebtCents,
    roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
  );

  // RENDER-ONLY flash; emitted on the event, written to NO field.
  final accretion = arbitrageAccretion(
      a.addonEbitdaCents, platform.multipleMilli, a.addonBuyMultipleMilli);

  final ventures = [...state.ventures];
  ventures[idx] = merged;
  final next = state.copyWith(
    ventures: ventures,
    cashCents: state.cashCents - price,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'AcquireAddOn ${sameSector ? 'same' : 'cross'}-sector '
            'onto ${platform.id}: price $price, '
            'ebitda +${merged.ebitdaCents - platform.ebitdaCents}, '
            'netDebt +${a.addonFaceDebtCents}',
      ),
    ],
  );
  return ApplyResult(state: next, events: [
    GameEvent(
      type: GameEventType.multipleArbitrage,
      amount: accretion,
      ventureId: platform.id,
    ),
  ]);
}

/// RAISE — equity raise: grow the pie, cut your slice (doc 02 §3.2; F5).
///
/// PRE: the venture exists; its equity is strictly positive — you cannot
/// price a raise into an over-levered venture with non-positive equity
/// (reason `raise_blocked_negative_equity`; use TAKE_DEBT or EXIT instead).
/// Else reject, no mutation.
///
/// POST: `cash += raise` (facePrice is NEW MONEY for a RAISE per the doc 02
/// §1 sign convention; v1 routes raise cash to pocket). Ownership dilutes
/// per F5 with preMoney = the venture's CURRENT equity:
/// `newOwn = trunc(oldOwn * preMoney / (preMoney + raise))`
/// (economy-model.json formulas.F5_dilution). Emits DILUTION whose amount is
/// the signed ownership delta in bp (<= 0).
///
/// GROWTH RIDERS (doc 02 §3.2 POST "apply card defaults"; live since round
/// 10 — the v1 gap closed): the card's ebitda/multiple deltas land on the
/// venture AFTER the dilution math. ORDER DECISION (documented): the new
/// money prices the company AS-IS — preMoney is the pre-rider equity, so
/// the riders are what the raise BUYS, not what it is priced on (pricing
/// post-rider would let the founder mark up their own round). The multiple
/// rider floors at the 1000-milli live-venture floor; the ebitda rider
/// floors at 0 (economy resolverInputs.clamps).
ApplyResult _raiseEquity(GameState state, RaiseEquity a) {
  final idx = state.ventures.indexWhere((v) => v.id == a.ventureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  final v = state.ventures[idx];
  final preMoney = equityValueOf(v);
  if (preMoney <= 0) return _reject(state, 'raise_blocked_negative_equity');

  final newOwn = diluteOwnership(v.ownershipBp, preMoney, a.raiseCents);
  var ebitda = v.ebitdaCents + a.ebitdaDeltaCents;
  if (ebitda < 0) ebitda = 0; // clamp: ebitda >= 0
  var multiple = v.multipleMilli + a.multipleDeltaMilli;
  if (multiple < multipleFloorMilli) multiple = multipleFloorMilli;
  final ventures = [...state.ventures];
  ventures[idx] = v.copyWith(
    ownershipBp: newOwn,
    ebitdaCents: ebitda,
    multipleMilli: multiple,
    roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
  );
  final next = state.copyWith(
    ventures: ventures,
    cashCents: state.cashCents + a.raiseCents,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'RaiseEquity ${v.id}: raise ${a.raiseCents}, '
            'own ${v.ownershipBp} -> $newOwn'
            '${a.ebitdaDeltaCents != 0 ? ', ebitda +${a.ebitdaDeltaCents}' : ''}'
            '${a.multipleDeltaMilli != 0 ? ', multiple +${a.multipleDeltaMilli}' : ''}',
      ),
    ],
  );
  return ApplyResult(state: next, events: [
    GameEvent(
      type: GameEventType.dilution,
      amount: newOwn - v.ownershipBp,
      ventureId: v.id,
    ),
  ]);
}

/// TAKE_DEBT — leverage: cash now, a recurring bill forever (doc 02 §3.3).
///
/// PRE: the venture exists. The doc 02 §3.3 COLD-market gate
/// (`market.temp !== 'COLD'` OR a COLD-priced card variant) is DEFERRED to
/// the market layer — the engine has no MarketState yet; until it lands the
/// layer above must not issue TakeDebt in a crunch.
///
/// POST: `cash += proceeds` (facePrice is PROCEEDS for TAKE_DEBT, doc 02 §1
/// sign convention); `netDebt += faceDebt`. No interest is charged here;
/// interest is the per-OPERATE F4 charge (the OPERATE loop lands later).
/// Over-levering is ALLOWED — death is via interest, telegraphed.
ApplyResult _takeDebt(GameState state, TakeDebt a) {
  final idx = state.ventures.indexWhere((v) => v.id == a.ventureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  final v = state.ventures[idx];

  final ventures = [...state.ventures];
  ventures[idx] = v.copyWith(
    netDebtCents: v.netDebtCents + a.faceDebtCents,
    roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
  );
  final next = state.copyWith(
    ventures: ventures,
    cashCents: state.cashCents + a.proceedsCents,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'TakeDebt ${v.id}: proceeds ${a.proceedsCents}, '
            'faceDebt ${a.faceDebtCents}',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

/// DIVIDEND_RECAP — pull cash out against EV; greed, can be fatal
/// (doc 02 §3.6 DIVIDEND_RECAP; economy-model.json formulas.dividendRecap,
/// the classic F6 setup).
///
/// PRE: `tier >= 2` (reason `recap_tier_gated`, checked first); the venture
/// exists. Else reject, no mutation.
///
/// POST: `pull = trunc(EV * recapPctBp / 10000)` (recapPctBp arrives from
/// the content layer; canon value economy-model.json constants.recapPct
/// = 0.16 -> 1600 bp after the R12 tune from 0.30); `cash += pull`;
/// `netDebt += pull`.
ApplyResult _dividendRecap(GameState state, DividendRecap a) {
  if (state.tier < 2) return _reject(state, 'recap_tier_gated');
  final idx = state.ventures.indexWhere((v) => v.id == a.ventureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  final v = state.ventures[idx];

  // pull = trunc(EV * recapPctBp / 10000) — the §0.7 mulBp shape.
  final pull = (enterpriseValueOf(v) * a.recapPctBp) ~/ bpScale;
  final ventures = [...state.ventures];
  ventures[idx] = v.copyWith(
    netDebtCents: v.netDebtCents + pull,
    roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
  );
  final next = state.copyWith(
    ventures: ventures,
    cashCents: state.cashCents + pull,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'DividendRecap ${v.id}: pull $pull '
            'at ${a.recapPctBp} bp of EV',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

/// REROLL — banker fee: recover a bad hand at a price (doc 02 §3.8).
///
/// PRE: `cash >= cost` (reason `insufficient_cash`). The scaling
/// `rerollCost(rerollsUsed)` formula (doc 02 §4) is content/SHOP-layer; the
/// engine charges exactly the cost it is handed.
///
/// POST: `cash -= cost`; `rerollsUsed += 1` (bookkeeping; DEADLINE_CHECK
/// resets it each round); the CURRENT PHASE's deck is REDRAWN — the real
/// redraw the Phase-1 note promised, live since schemaVersion 4:
///   - in ACT: `hand` re-runs the full hand routine (a fresh SIZE draw,
///     then the no-replacement walk — dealflow.dart's contract);
///   - in SHOP: `shopOffers` re-runs the shop routine (kShopOfferCount
///     draws).
/// The redraw advances the RNG cursor (its position is fully determined by
/// WHEN the player rerolls — doc 03 §3.1 step 4) and `rngCursor` is
/// reconciled. Golden-covered; any change here is stream-breaking.
ApplyResult _reroll(
    GameState state, Reroll a, SplitMix64Rng rng, ContentDb content) {
  if (state.cashCents < a.costCents) {
    return _reject(state, 'insufficient_cash');
  }

  final charged = state.copyWith(
    cashCents: state.cashCents - a.costCents,
    rerollsUsed: state.rerollsUsed + 1,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'Reroll: fee ${a.costCents} '
            '(reroll #${state.rerollsUsed + 1} this round)',
      ),
    ],
  );
  // The phase gate in apply() guarantees act|shop here.
  final next = state.phase == PhaseId.act
      ? drawHand(charged, rng, content)
      : drawShop(charged, rng, content);
  return ApplyResult(state: next, events: const []);
}

/// The HOT exit multiple as a fraction of the live multiple: x135/100.
///
/// Doc 01 §7.6 forces a hot-window exit to `sectorHotMultiple` without
/// pinning its number; the canon HOT repricing factor is driftBubble 1.35
/// (doc 01 §7.3 / economy-model.json curves.driftModel.driftBubble), so
/// the engine reads hot = live x 1.35 -> 135/100 in integer form.
/// *** TUNING DIAL — the 1.35 reuse is an engine decision, logged in
/// .claude/STATE.md; economy-affecting if changed (golden-pinned). ***
const int hotExitMulNum = 135;

/// Denominator for [hotExitMulNum].
const int hotExitMulDen = 100;

/// EXIT — acquisition / IPO: convert paper to real, frees a SLOT
/// (doc 02 §3.7; economy-model.json formulas.exit / exitMultiple).
///
/// PRE: the venture exists; `cash + proceeds >= 0` (doc 02 §2 ACT rule: no
/// action may push cash below zero mid-Act — a deep-negative-equity exit is
/// a cash OUTFLOW; reason `exit_would_bankrupt`; bankruptcy only ever
/// happens via interest in OPERATE, the telegraphed death).
///
/// POST (economy-model.json formulas.exitMultiple, LIVE since round 10):
/// `exitMultiple = hotWindowArmed ? trunc(live x 135/100)
///                                : min(offer, live)`
/// — the doc 01 §7.6 hot override; on a fired window the armed flag and
/// its expiry are CLEARED (emit HOT_WINDOW_FIRED, doc 02 §3.7) — the
/// one-window lifetime's consumption path. liveMarketMultipleMilli remains
/// the action's payload carrier; the exit-offer ticket layer
/// (dealflow.exitOfferAction) fills it with the venture's own live
/// multiple.
/// `evAtExit = trunc(ebitda * exitMultiple / 1000)`;
/// `proceeds = trunc((evAtExit - netDebt) * own / 10000)` (divisions LAST,
/// truncating toward zero — a negative-equity fire-sale is legal);
/// `cash += proceeds`; the venture is REMOVED (frees its SLOT); a pending
/// EXIT OFFER on the exited venture is CLEARED (the ticket died with the
/// company — §7 deck-like bookkeeping scoped to ExitVenture; an offer on
/// a DIFFERENT venture survives). Emits EXIT_REALIZED carrying the
/// proceeds. The doc 02 §3.7 CLEAN_EXIT / reputation bookkeeping is
/// meta-layer and lands with it.
ApplyResult _exitVenture(GameState state, ExitVenture a) {
  final idx = state.ventures.indexWhere((v) => v.id == a.ventureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  final v = state.ventures[idx];

  final hot = state.market.hotWindowArmed;
  final exitMultiple = hot
      ? (a.liveMarketMultipleMilli * hotExitMulNum) ~/ hotExitMulDen
      : (a.offerMultipleMilli < a.liveMarketMultipleMilli
          ? a.offerMultipleMilli
          : a.liveMarketMultipleMilli);
  final evAtExit = enterpriseValue(v.ebitdaCents, exitMultiple);
  final proceeds = ((evAtExit - v.netDebtCents) * v.ownershipBp) ~/ bpScale;
  if (state.cashCents + proceeds < 0) {
    return _reject(state, 'exit_would_bankrupt');
  }

  final next = state.copyWith(
    ventures: [...state.ventures]..removeAt(idx),
    cashCents: state.cashCents + proceeds,
    clearExitOffer: state.exitOffer?.ventureId == a.ventureId,
    market: hot
        ? state.market
            .copyWith(hotWindowArmed: false, hotWindowExpiresRound: -1)
        : state.market,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'ExitVenture ${v.id}: exitMultiple $exitMultiple '
            '(offer ${a.offerMultipleMilli}, live ${a.liveMarketMultipleMilli}'
            '${hot ? ', HOT WINDOW x$hotExitMulNum/$hotExitMulDen' : ''}), '
            'proceeds $proceeds',
      ),
    ],
  );
  return ApplyResult(state: next, events: [
    if (hot)
      GameEvent(
        type: GameEventType.hotWindowFired,
        amount: exitMultiple,
        ventureId: v.id,
      ),
    GameEvent(
      type: GameEventType.exitRealized,
      amount: proceeds,
      ventureId: v.id,
    ),
  ]);
}

/// HIRE_CEO — delegation: convert a venture to passive at an agency cost
/// (doc 02 §3.10).
///
/// PRE (in order): the venture exists; it is not already passive (reason
/// `already_passive`); `cash >= cost` (reason `insufficient_cash`). Else
/// reject, no mutation.
///
/// POST: `cash -= cost`; `venture.passive = true` (whitelisted §7
/// bookkeeping). The passive consequences — reduced neglect decay and the
/// dampened CASH_YIELD_BP_PASSIVE — resolve in OPERATE, which lands with
/// the round loop.
ApplyResult _hireCEO(GameState state, HireCEO a) {
  final idx = state.ventures.indexWhere((v) => v.id == a.ventureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  final v = state.ventures[idx];
  if (v.passive) return _reject(state, 'already_passive');
  if (state.cashCents < a.costCents) {
    return _reject(state, 'insufficient_cash');
  }

  final ventures = [...state.ventures];
  ventures[idx] = v.copyWith(
    passive: true,
    roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
  );
  final next = state.copyWith(
    ventures: ventures,
    cashCents: state.cashCents - a.costCents,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'HireCEO ${v.id}: cost ${a.costCents}, now passive',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

/// HIRE_PARTNER — attach an operating-partner engine to a venture; the
/// permanent-engine / Jokers layer (doc 02 §3.5).
///
/// PRE (in order): the venture exists; `cash >= cost` (facePrice is a COST
/// for type `partner`, doc 02 §1 sign convention). Else reject, no
/// mutation.
///
/// POST: `cash -= cost`; push `PartnerEngine{defId, perRoundEbitda}` onto
/// the venture's `partners` (whitelisted §7 structural membership, doc 02
/// §7 `partners[]`); apply the one-time [HirePartner.multipleDeltaMilli]
/// story bump (floored at the 1000-milli live-venture floor); if the
/// variant carries a fixed cost, register a RECURRING [ScheduledCost] of
/// `-fixedCost` tied to the venture (doc 02 §3.5 PARTNER_FIXED_COST: "all
/// deferred/recurring money flows through ONE channel" — it lands in
/// OPERATE step 3c, never here). The per-round +EBITDA accrues in OPERATE
/// step 3a (model.dart PartnerEngine documents the accrual decision);
/// nothing economic beyond the price moves at hire time.
ApplyResult _hirePartner(GameState state, HirePartner a) {
  final idx = state.ventures.indexWhere((v) => v.id == a.ventureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  final v = state.ventures[idx];
  if (state.cashCents < a.costCents) {
    return _reject(state, 'insufficient_cash');
  }

  var multiple = v.multipleMilli + a.multipleDeltaMilli;
  if (multiple < multipleFloorMilli) multiple = multipleFloorMilli;
  final ventures = [...state.ventures];
  ventures[idx] = v.copyWith(
    multipleMilli: multiple,
    partners: [
      ...v.partners,
      PartnerEngine(
          defId: a.defId, perRoundEbitdaCents: a.perRoundEbitdaCents),
    ],
    roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
  );
  final next = state.copyWith(
    ventures: ventures,
    cashCents: state.cashCents - a.costCents,
    scheduled: a.fixedCostCents > 0
        ? [
            ...state.scheduled,
            ScheduledCost(
              ventureId: v.id,
              cashDeltaCents: -a.fixedCostCents,
              recurring: true,
            ),
          ]
        : state.scheduled,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'HirePartner ${a.defId} onto ${v.id}: cost ${a.costCents}, '
            '+${a.perRoundEbitdaCents}/rd'
            '${a.fixedCostCents > 0 ? ', fixed -${a.fixedCostCents}/rd' : ''}',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

/// Sell-a-play — liquidate a held consumable for ~50% of purchase price;
/// the liquidity lesson (doc 02 §3.6 sell-a-play; doc 03 §4.1 SellPlay).
///
/// PRE (live since the deal-flow layer): `playId` is in `playsHeld`
/// (reason `play_not_held` — the inventory the buy pushed onto). Else
/// reject, no mutation.
///
/// POST: `cash += trunc(price / 2)`; the play is REMOVED from `playsHeld`
/// (first occurrence — the same id can be held twice across rounds; one
/// sale consumes one copy).
ApplyResult _sellPlay(GameState state, SellPlay a) {
  if (!state.playsHeld.contains(a.playId)) {
    return _reject(state, 'play_not_held');
  }
  final proceeds = a.purchasePriceCents ~/ 2; // trunc(price / 2), doc 02 §3.6
  final next = state.copyWith(
    cashCents: state.cashCents + proceeds,
    playsHeld: _removeFirst(state.playsHeld, a.playId),
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'SellPlay ${a.playId}: bought ${a.purchasePriceCents}, '
            'sold for $proceeds',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

/// [list] minus the FIRST occurrence of [id] (held inventories may carry
/// the same card id twice; one consumption removes one copy).
List<String> _removeFirst(List<String> list, String id) {
  final out = [...list];
  out.remove(id); // List.remove removes the first match only
  return out;
}

/// The four per-venture delta keys; `cash` is the fifth, global key.
const Set<String> _perVentureKeys = {'ebitda', 'multiple', 'netDebt', 'own'};

/// PLAY_CONSUMABLE — a one-shot PLAY's deltas over the five §7 inputs
/// (doc 02 §3.6; doc 03 §5 Deltas shape, mapped from the card upstream by
/// dealflow.actionForCard).
///
/// PRE (in order): `playId` is in `playsHeld` — the held inventory the
/// SHOP buy pushed onto (reason `play_not_held`; FIRST because you cannot
/// play what you do not hold); every delta key is one of the five mutable
/// inputs (`kMutableInputs`; ownership wire key is `own` — LOCKED; reason
/// `invalid_deltas`); any per-venture key requires a target venture that
/// exists (reason `venture_not_found`); the resulting cash is >= 0 (doc 02
/// §2 ACT rule; reason `insufficient_cash`).
///
/// POST: additive deltas, with the RESULT clamped per economy-model.json
/// resolverInputs.clamps: ebitda floor 0; multiple floor 1000 milli (the
/// live-venture floor); own clamped to 0..10000 bp; netDebt unclamped
/// (negative = net cash, legal); cash never clamped (the PRE keeps it
/// non-negative). The play is REMOVED from `playsHeld` (first occurrence).
/// The engine trusts the payload deltas (Phase-1 audit: the content layer
/// guarantees magnitudes); membership is checked by ID only.
///
/// MARKET FLAGS (doc 02 §3.6 HOT_WINDOW / MARKET_READ, live since round
/// 10 — both plays were pure costs in v1):
///   - `armsHotWindow`: `market.hotWindowArmed = true`,
///     `hotWindowExpiresRound = flatRound + 1` (the one-window lifetime,
///     §Q2); emit HOT_WINDOW_ARMED. No economic delta until exit.
///   - `readsMarket`: `market.marketReadHint = marketReadDirection(...)`
///     (model.dart documents exactly what is honestly knowable),
///     `marketReadExpiresRound = flatRound + 1` (one-round lifetime); emit
///     MARKET_READ_REVEALED with `market_read_<temp>`. Direction only.
/// Both writes are §7 CONSUMABLE-FLAG bookkeeping scoped to this action
/// (the invariant test whitelists exactly these paths for it); expiry is
/// OPERATE step 1's job.
ApplyResult _playConsumable(GameState state, PlayConsumable a) {
  if (!state.playsHeld.contains(a.playId)) {
    return _reject(state, 'play_not_held');
  }
  if (!a.deltas.keys.every(kMutableInputs.contains)) {
    return _reject(state, 'invalid_deltas');
  }
  final targetsVenture = a.deltas.keys.any(_perVentureKeys.contains) ||
      a.recapBp > 0 ||
      a.secondaryBp > 0 ||
      a.spinsOff ||
      a.earnOutPctBp > 0;
  var idx = -1;
  if (targetsVenture) {
    final targetId = a.targetVentureId;
    if (targetId == null) return _reject(state, 'venture_not_found');
    idx = state.ventures.indexWhere((v) => v.id == targetId);
    if (idx < 0) return _reject(state, 'venture_not_found');
  }

  // SPIN_OFF (doc 02 §3.6; R20b — the whole-venture form): split the target
  // back out at its CURRENT live mark, bank the equity stake, FREE THE SLOT.
  // Structural, like a partial exit but at the live multiple with no offer
  // haircut/hot-window (it LOCKS the value at the current mark). The card's
  // fee rides through deltas.cash; the proceeds are computed at resolve time
  // from the live equity. PRE: cash after the fee + proceeds stays >= 0
  // (doc 02 §2 ACT rule); a spin-off only ever ADDS cash (proceeds >= 0
  // floored), so the only way it bankrupts is the fee — checked via newCash
  // below. Returns early because it removes the venture (the general
  // venture-delta path below assumes the venture stays).
  if (a.spinsOff) {
    final v = state.ventures[idx];
    final equity = equityValueOf(v);
    final proceeds = equity <= 0 ? 0 : (equity * v.ownershipBp) ~/ bpScale;
    final feeCash = a.deltas['cash'] ?? 0; // the play's own fee (negative)
    final newCashSpin = state.cashCents + feeCash + proceeds;
    if (newCashSpin < 0) return _reject(state, 'insufficient_cash');
    final next = state.copyWith(
      ventures: [...state.ventures]..removeAt(idx),
      cashCents: newCashSpin,
      clearExitOffer: state.exitOffer?.ventureId == v.id,
      playsHeld: _removeFirst(state.playsHeld, a.playId),
      actionLog: [
        ...state.actionLog,
        LoggedAction(
          round: state.round,
          summary: 'SpinOff ${v.id} (${a.playId}): live mark '
              '${v.multipleMilli}, proceeds $proceeds, fee ${-feeCash}, '
              'slot freed',
        ),
      ],
    );
    return ApplyResult(state: next, events: [
      GameEvent(
        type: GameEventType.exitRealized,
        amount: proceeds,
        ventureId: v.id,
      ),
    ]);
  }

  // The CANONICAL dividend recap (doc 01 §7.7; economy
  // formulas.dividendRecap; R12): `pull = trunc(EV x recapBp / 10000)`
  // computed at RESOLVE TIME against the target's live EV — `cash += pull;
  // netDebt += pull` on the target. Both sides of the pull are real state
  // mutations through the five inputs; the card's illustrative fixed faces
  // were stripped upstream (actionForCard). 0 when not a recap.
  var recapPull = 0;
  if (a.recapBp > 0) {
    recapPull =
        (enterpriseValueOf(state.ventures[idx]) * a.recapBp) ~/ bpScale;
    if (recapPull < 0) recapPull = 0; // a worthless EV pulls nothing
  }

  // The SECONDARY SALE (doc 02 §3.6 SECONDARY_SALE; schemaVersion 9): sell
  // `secondaryBp` of the stake AT THE LIVE MARK — `proceeds = trunc(equity x
  // secondaryBp / 10000)` against the target's PRE-sale equity; `cash +=
  // proceeds`, `ownership -= secondaryBp` (carried below). The ownership
  // magnitude is clamped to what the player actually holds (can't sell more
  // than 100% of the stake); a non-positive equity sells for nothing (a
  // fire-sale of paper, the prudent-vs-greedy lesson). 0 when not a secondary.
  var secondaryProceeds = 0;
  var secondaryBp = 0;
  if (a.secondaryBp > 0) {
    final v = state.ventures[idx];
    secondaryBp = a.secondaryBp > v.ownershipBp ? v.ownershipBp : a.secondaryBp;
    final equity = equityValueOf(v);
    secondaryProceeds = equity <= 0 ? 0 : (equity * secondaryBp) ~/ bpScale;
  }

  final newCash = state.cashCents +
      (a.deltas['cash'] ?? 0) +
      recapPull +
      secondaryProceeds;
  if (newCash < 0) return _reject(state, 'insufficient_cash');

  var ventures = state.ventures;
  if (idx >= 0) {
    final v = state.ventures[idx];
    var ebitda = v.ebitdaCents + (a.deltas['ebitda'] ?? 0);
    if (ebitda < 0) ebitda = 0; // clamp: ebitda >= 0
    var multiple = v.multipleMilli + (a.deltas['multiple'] ?? 0);
    if (multiple < multipleFloorMilli) multiple = multipleFloorMilli;
    // own delta from the card, MINUS the secondary-sale slice sold above
    // (clamped to the held stake, so own never goes negative from it).
    var own = v.ownershipBp + (a.deltas['own'] ?? 0) - secondaryBp;
    if (own < 0) own = 0;
    if (own > bpScale) own = bpScale;
    final list = [...state.ventures];
    list[idx] = v.copyWith(
      ebitdaCents: ebitda,
      multipleMilli: multiple,
      // unclamped; the recap pull lands as new debt on the target
      netDebtCents: v.netDebtCents + (a.deltas['netDebt'] ?? 0) + recapPull,
      ownershipBp: own,
      roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
    );
    ventures = list;
  }

  // The consumable market flags (doc comment above) — draw-free.
  var market = state.market;
  final events = <GameEvent>[];
  final expires = flatRoundOf(state) + 1;
  if (a.armsHotWindow) {
    market = market.copyWith(
        hotWindowArmed: true, hotWindowExpiresRound: expires);
    events.add(GameEvent(
        type: GameEventType.hotWindowArmed, amount: expires));
  }
  if (a.readsMarket) {
    final hint = marketReadDirection(market);
    market = market.copyWith(
        marketReadHint: hint, marketReadExpiresRound: expires);
    events.add(GameEvent(
        type: GameEventType.marketReadRevealed,
        reason: 'market_read_${hint.name}'));
  }
  if (recapPull > 0) {
    events.add(GameEvent(
      type: GameEventType.dividendRecap,
      amount: recapPull,
      ventureId: a.targetVentureId,
    ));
  }
  if (a.secondaryBp > 0) {
    // Emit even on a $0 fire-sale of paper (proceeds 0) — the ownership
    // still moved; the amount carries the realized proceeds the meta layer
    // folds into reputation (RunOutcomes.withSecondary).
    events.add(GameEvent(
      type: GameEventType.secondarySale,
      amount: secondaryProceeds,
      ventureId: a.targetVentureId,
    ));
  }

  // EARN_OUT (doc 02 §3.6; R20b): the acquired +EBITDA landed via the deltas
  // path above (no cash/debt/dilution upfront); register a non-recurring
  // PCT_EBITDA countdown ScheduledCost on the target — each OPERATE pays
  // -trunc(target.ebitda x earnOutPctBp / 10000) for earnOutRounds rounds
  // (the seller paid out of future earnings, operate.dart step 3c). "Buy
  // now, sweat later." The §7 invariant whitelists scheduled[] membership
  // for the consumable that registers it (like HIRE_PARTNER's fixed cost).
  var scheduled = state.scheduled;
  if (a.earnOutPctBp > 0 && a.earnOutRounds > 0) {
    scheduled = [
      ...state.scheduled,
      ScheduledCost(
        ventureId: a.targetVentureId,
        cashDeltaCents: 0, // PCT basis: charge is computed from live ebitda
        recurring: true, // a countdown is recurring-until-zero
        roundsLeft: a.earnOutRounds,
        pctEbitdaBp: a.earnOutPctBp,
      ),
    ];
  }

  final next = state.copyWith(
    ventures: ventures,
    cashCents: newCash,
    market: market,
    scheduled: scheduled,
    playsHeld: _removeFirst(state.playsHeld, a.playId),
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'PlayConsumable ${a.playId}'
            '${idx >= 0 ? ' on ${a.targetVentureId}' : ''}: ${a.deltas}'
            '${a.armsHotWindow ? ' +hotWindow' : ''}'
            '${a.readsMarket ? ' +marketRead' : ''}'
            '${recapPull > 0 ? ' recap $recapPull' : ''}'
            '${a.secondaryBp > 0 ? ' secondary $secondaryBp bp -> $secondaryProceeds' : ''}',
      ),
    ],
  );
  return ApplyResult(state: next, events: events);
}

/// REINVEST — the always-available baseline: brute-force EBITDA growth at
/// decaying efficiency (doc 02 §3.9; no hand unwinnable, §Q3).
///
/// PRE: the venture exists; `cash >= amount` (reason `insufficient_cash`).
/// Else reject, no mutation.
///
/// POST: `cash -= amount`;
/// `ebitda += trunc(amount * reinvestEfficiencyBp(round, tier) / 10000)`.
///
/// NOTE (doc deviation, documented): doc 02 §3.9 describes a per-venture
/// `reinvestCount`-based decay curve; data/economy-model.json
/// curves.reinvestDecay (authoritative per CLAUDE.md) decays by
/// round-in-tier progress over the tier's deadline instead. This follows
/// the JSON — see [reinvestEfficiencyBp].
ApplyResult _reinvestBaseline(GameState state, ReinvestBaseline a) {
  final idx = state.ventures.indexWhere((v) => v.id == a.ventureId);
  if (idx < 0) return _reject(state, 'venture_not_found');
  if (state.cashCents < a.amountCents) {
    return _reject(state, 'insufficient_cash');
  }
  final v = state.ventures[idx];

  final effBp = reinvestEfficiencyBp(round: state.round, tier: state.tier);
  // gain = trunc(amount * effBp / 10000) — the §0.7 mulBp shape.
  final gain = (a.amountCents * effBp) ~/ bpScale;
  final ventures = [...state.ventures];
  ventures[idx] = v.copyWith(
    ebitdaCents: v.ebitdaCents + gain,
    roundsNeglected: 0, // targeting resets neglect (doc 02 §2 ACT)
  );
  final next = state.copyWith(
    ventures: ventures,
    cashCents: state.cashCents - a.amountCents,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'ReinvestBaseline ${v.id}: amount ${a.amountCents} '
            'at $effBp bp -> ebitda +$gain',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

/// START_VENTURE — begin a new company; consumes a SLOT (doc 02 §3.1).
///
/// PRE: `ventures.length < slotsMax(tier)`; `cash >= price`. Else reject,
/// no mutation. (Phase/playsRemaining PREs land with the round loop.)
///
/// POST: `cash -= price`; create the venture at 100% ownership (10000 bp)
/// with the face debt as its opening netDebt. The face multiple is used
/// AS-SHOWN — content guarantees it is in SECTOR_BAND; never clamped here.
ApplyResult _startVenture(GameState state, StartVenture a) {
  if (state.ventures.length >= slotsMax(state.tier)) {
    return _reject(state, 'slots_full');
  }
  if (state.cashCents < a.priceCents) {
    return _reject(state, 'insufficient_cash');
  }

  final next = state.copyWith(
    ventures: [
      ...state.ventures,
      Venture(
        id: a.ventureId,
        sector: a.sector,
        ebitdaCents: a.ebitdaCents,
        multipleMilli: a.multipleMilli,
        netDebtCents: a.faceDebtCents,
        ownershipBp: 10000, // founding = 100% ownership (doc 02 §3.1)
        roundsNeglected: 0, // born attended (doc 02 §3.1 POST)
      ),
    ],
    cashCents: state.cashCents - a.priceCents,
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'StartVenture ${a.ventureId} (${sectorToJson(a.sector)}): '
            'price ${a.priceCents}, ebitda ${a.ebitdaCents}, '
            'multiple ${a.multipleMilli}, faceDebt ${a.faceDebtCents}',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

// ---------------------------------------------------------------------------
// Deal-flow player entry points (doc 02 §2 SHOP; doc 04 §0 type semantics)
// ---------------------------------------------------------------------------

/// SHOP buy — take a CONSUMABLE off the counter into the held inventory
/// (doc 02 §2 SHOP: "buying a consumable adds it to plays[]"; cash only,
/// never a PLAY). Player input, so failures REJECT (events), never throw.
///
/// PRE (in order): `phase == shop` (reason `wrong_phase` — SHOP is the
/// between-round counter); `cardId` is on the counter (reason
/// `offer_not_in_shop`); the offer is a CONSUMABLE (reason
/// `offer_not_buyable` — financing offers are not bought-and-held: they
/// EXERCISE as RaiseEquity/TakeDebt actions via [playCard], see its doc);
/// `playsHeld.length < playsHeldMax(tier)` (reason `plays_full`, doc 02
/// §2); `cash >= cost.cash` (reason `insufficient_cash`).
///
/// POST: `cash -= cost.cash` (the cost block's cash face — its deltas
/// mirror, when one exists, is stripped at PLAY time by actionForCard so
/// nothing charges twice); `playsHeld += [cardId]`; the offer is REMOVED
/// from `shopOffers` (taken off the counter); logged. Draw-free.
ApplyResult buyShopOffer(GameState state, String cardId, ContentDb content) {
  if (state.phase != PhaseId.shop) return _reject(state, 'wrong_phase');
  if (!state.shopOffers.contains(cardId)) {
    return _reject(state, 'offer_not_in_shop');
  }
  final card = content.byId(cardId);
  if (card.type != CardType.consumable) {
    return _reject(state, 'offer_not_buyable');
  }
  if (state.playsHeld.length >= playsHeldMax(state.tier)) {
    return _reject(state, 'plays_full');
  }
  if (state.cashCents < card.cost.cashCents) {
    return _reject(state, 'insufficient_cash');
  }

  final next = state.copyWith(
    cashCents: state.cashCents - card.cost.cashCents,
    playsHeld: [...state.playsHeld, cardId],
    shopOffers: _removeFirst(state.shopOffers, cardId),
    actionLog: [
      ...state.actionLog,
      LoggedAction(
        round: state.round,
        summary: 'BuyShopOffer $cardId: cost ${card.cost.cashCents}, '
            'held ${state.playsHeld.length + 1}/${playsHeldMax(state.tier)}',
      ),
    ],
  );
  return ApplyResult(state: next, events: const []);
}

/// Plays a card BY ID from the deck that owns its type, mapping it through
/// dealflow.actionForCard and resolving via [apply] — the one entry point
/// the UI needs for card play. Membership gates by type (doc 04 §0's
/// canonical path per card type):
///   - venture/addon/partner (ACT cards): `cardId` must be in `hand`
///     (reason `card_not_in_hand`); consumed (removed) on success.
///   - financing: `cardId` must be in `shopOffers` (reason
///     `offer_not_in_shop` — engine decision, documented: doc 04 §0 sells
///     financing "in SHOP for cash, no PLAY", but RaiseEquity/TakeDebt are
///     LOCKED as act-phase play-costing actions since round 2, so a
///     financing offer is EXERCISED from the offer row during ACT — it
///     persists on the counter until the next endTurn redraws the shop —
///     and is consumed on success. Revisit if the plays matrix is ever
///     re-derived).
///   - consumable: delegates straight to [apply]'s PlayConsumable, whose
///     own `play_not_held` gate + playsHeld removal own the inventory (no
///     double bookkeeping here).
///   - event: actionForCard throws (caller bug — events are never
///     player-played; they auto-resolve in OPERATE).
///
/// [targetVentureId] is forwarded to actionForCard (the new venture id /
/// platform / target; nullable only for context-free consumables). All of
/// apply()'s gates (phase, plays cost, action PREs) run unchanged
/// underneath — a financing exercise still costs a play, a hand addon
/// still pays the resolver-computed price.
ApplyResult playCard(
  GameState state,
  String cardId,
  SplitMix64Rng rng,
  ContentDb content, {
  String? targetVentureId,
}) {
  final card = content.byId(cardId);
  switch (card.type) {
    case CardType.venture:
    case CardType.addon:
    case CardType.partner: // ACT cards, dealt to the hand (doc 04 §0)
      if (!state.hand.contains(cardId)) {
        return _reject(state, 'card_not_in_hand');
      }
    case CardType.financing:
      if (!state.shopOffers.contains(cardId)) {
        return _reject(state, 'offer_not_in_shop');
      }
    case CardType.consumable:
      break; // PlayConsumable's play_not_held gate owns membership
    case CardType.event:
      // actionForCard refuses these loudly below (caller bug, not input).
      break;
  }

  final action = actionForCard(card, targetVentureId: targetVentureId);
  final result = apply(state, action, rng, content);
  if (result.events.any((e) => e.type == GameEventType.actionRejected)) {
    return result;
  }
  // Success: consume the card from the deck that held it (consumables were
  // already consumed from playsHeld inside apply).
  final consumed = switch (card.type) {
    CardType.venture ||
    CardType.addon ||
    CardType.partner =>
      result.state.copyWith(hand: _removeFirst(result.state.hand, cardId)),
    CardType.financing => result.state.copyWith(
        shopOffers: _removeFirst(result.state.shopOffers, cardId)),
    _ => result.state,
  };
  return ApplyResult(state: consumed, events: result.events);
}

/// Element-by-element list equality (the package avoids a `collection`
/// dependency, so this small helper stands in for `listEquals`).
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
