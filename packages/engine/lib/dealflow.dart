/// The DEAL-FLOW layer — hand/shop draws, event-card application, and the
/// card -> action glue (doc 03 §3.1 steps 1 and 3; doc 02 §1 hand /
/// shopOffers / plays; doc 04 §0 type semantics).
///
/// =========================================================================
/// THE DRAW-ORDER CONTRACT, EXTENDED (authoritative for the deal-flow
/// draws; operate.dart's header composes it into the per-OPERATE stream.
/// Golden-tested; reordering, adding, or removing ANY draw is
/// STREAM-BREAKING and requires a new golden replay file + a schemaVersion
/// bump per docs/03 §6):
///
///   THE HAND ROUTINE ([drawHand] — doc 03 §3.1 step 1, "Deal Flow draw"):
///     draw 1: nextInt(3)            — hand size = 3 + draw (3..5, §Q3),
///             then clamped to the pool size (the size draw ALWAYS
///             happens, even over a small pool — uniform contract)
///     draws 2..1+size: nextInt(remaining pool size) — each draw indexes
///             the REMAINING pool, in pool order, and removes the dealt
///             card: WITHOUT REPLACEMENT, so a hand can never hold
///             duplicates. Total draws = 1 + size.
///     THE EXIT-OFFER DRAWS (v5, since schemaVersion 5; only when
///     `ventures` is non-empty — ZERO draws otherwise, and the offer
///     clears):
///       draw 2+size: nextInt(ventures.length) — picks the offered
///             venture by `ventures` LIST ORDER (replay-locked).
///       draw 3+size: u = nextInt(301) — the offer multiple, by the EXACT
///             integer formula (documented per the work order):
///               offerMilli = (live x (900 + u)) ~/ 1000
///             where `live` is the picked venture's multipleMilli — a
///             0.90x..1.20x band around the live multiple in permille
///             steps, floored at the 1000-milli live-venture floor.
///             *** TUNING DIAL — the band shape is an engine decision (no
///             doc pins offer pricing); the resolver still takes
///             min(offer, live), so an above-live offer exits AT live. ***
///     Total hand-routine draws = 1 + size + (2 if ventures exist).
///     Pool ([handPool]) — THE v10 POOL CONTRACT (R20b widened the SOURCE):
///             cards from the FULL content with type in
///             {venture, addon, partner} that pass [cardInUnlockedPool] —
///             `id ∈ run.unlockedCardIds AND tierGate <= tier AND
///             (sector == null OR sector ∈ run.unlockedSectors)` — IN
///             CONTENT FILE ORDER (the pool order is part of this contract).
///             *** v9->v10 STREAM MOVE: the source was `verticalSlice`;
///             it is now `content.cards` ∩ the per-run FROZEN unlocked
///             predicate, so the 14 held-out cards draw once unlocked AND
///             the pool that feeds nextInt grows — every no-replacement
///             index moves. Cursor MATH is unchanged (still 1 + size, the
///             same draw STRUCTURE); only the pool SIZE feeding nextInt
///             moved -> golden v10 + schemaVersion 10. *** PARTNERS
///             RE-INCLUDED (round 10). THE DEAD-DRAW FILTER (v5): venture-
///             type cards are EXCLUDED while `ventures.length >=
///             slotsMax(tier)`. Pool composition is a function of (content,
///             frozen unlocked set, frozen unlocked sectors, tier,
///             slots-full): all replay-stable inputs.
///     The new hand REPLACES the old wholesale: unplayed cards expire at
///     the next draw (doc 02 §2 "draw a fresh hand") — and the exit offer
///     expires/renews with the hand (one per round, doc 02 §3.7's "an
///     exit offer card is present").
///
///   THE SHOP ROUTINE ([drawShop] — doc 02 §2 SHOP):
///     draws 1..kShopOfferCount: nextInt(remaining pool size) — the same
///             shrinking-pool no-replacement walk. NO size draw: the
///             offer count is the fixed [kShopOfferCount].
///     Pool ([shopPool]): FULL content with type in {financing, consumable}
///             that pass [cardInUnlockedPool], in content file order (doc 04
///             §0: financing + PLAYS are the SHOP counter; v10 widened the
///             source from verticalSlice to the unlocked predicate).
///
///   THE EVENT ROLL (runOperate step 5 — see operate.dart; the helpers
///   here are [eventPool] + [applyEventCard]):
///     draw 1: nextInt(100)          — fires when < [kEventChancePct]
///     draw 2 (only when fired AND the pool is non-empty):
///             nextInt(event pool size) — picks the card by pool index.
///     Pool ([eventPool]): FULL content events that pass
///             [cardInUnlockedPool], in content file order (v10 widened).
///
///   WHO RUNS WHAT (the timing contract):
///     - runOperate runs the HAND routine FIRST, before the market roll
///       (doc 03 §3.1 lists Deal Flow as step 1), and the EVENT roll at
///       doc 01 §6.1's step 5 (after decay, before interest). Doc 02 §2
///       words the fresh-hand draw as part of the DEADLINE_CHECK advance;
///       the draw lives in OPERATE per doc 03 — same effective timing
///       (advance -> OPERATE -> the hand is fresh before ACT), and it
///       keeps runDeadlineCheck structurally draw-free.
///     - endTurn (act -> shop) runs the SHOP routine (round.dart).
///     - Reroll re-runs the CURRENT PHASE's routine (doc 02 §3.8: hand in
///       ACT — including a fresh SIZE draw — offers in SHOP); its cursor
///       position is fully determined by when the player rerolls
///       (doc 03 §3.1 step 4).
/// =========================================================================
///
/// TUNING DIALS (no canon integers exist for these; logged in
/// .claude/STATE.md — change HERE and version a new golden):
///   - [kHandSizeMin]/[kHandSizeSpan]: doc 02 §Q3 fixes the 3-5 RANGE; the
///     uniform 3 + nextInt(3) DISTRIBUTION is this engine's choice.
///   - [kShopOfferCount] = 3: no doc pins an offer count.
///   - [kEventChancePct] = 25: doc 01 §6.1 fixes WHERE events resolve,
///     no doc fixes HOW OFTEN one fires.
///
/// All integer fixed-point; pure dart:core + sibling engine libraries.
library;

import 'actions.dart';
import 'content.dart';
import 'model.dart';
import 'resolver.dart';
import 'rng.dart';

// --- Tuning dials (see the library header; NOT canon) ---

/// Minimum hand size (doc 02 §Q3: "3-5 hand cards").
const int kHandSizeMin = 3;

/// Width of the one uniform hand-size draw: size = 3 + nextInt(3) -> 3..5.
/// *** TUNING DIAL — the distribution shape is not canon. ***
const int kHandSizeSpan = 3;

/// Offers dealt to the SHOP counter per round.
/// *** TUNING DIAL — no doc pins an offer count. ***
const int kShopOfferCount = 3;

/// P(an event card fires this OPERATE) = 25 of 100.
/// *** TUNING DIAL — NOT CANON. *** Doc 01 §6.1 step 5 / economy-model
/// roundOrder fix WHERE events resolve; no doc fixes the per-round
/// probability. Logged in .claude/STATE.md; changing this moves the
/// stream (new golden + schemaVersion bump).
const int kEventChancePct = 25;

/// The canonical dividend-recap fraction in basis points: 0.16 -> 1600.
/// Source: economy-model.json constants.recapPct = 0.16 (doc 01 §7.7's
/// `recapPct x EV` pull; parsed as EconomyConstants.recapPctBp; also
/// tuningKnobs "primary greed-death dial alongside crunch").
/// *** R12 TUNE: 0.30 -> 0.16 *** — the named greed-death dial, turned
/// down per the full-model harness: at 0.30 one pull lands ~2.4x EBITDA
/// of debt at a stroke (EV ~ 8x E), so the §11.2 greedy oscillates AT its
/// 5.8x line and bankrupted 22-30% (band [8,12]%); at 0.16 the chunk is
/// ~1.3x E and greed dies in band (11% measured) while the pull still
/// banks real money. The CANON (resolve-time trunc(EV x recapPct), R12)
/// is untouched — only the fraction moved.
/// *** R20b RE-TUNE: 0.16 -> 0.20 *** — the draw-pool keystone widened the
/// SHOP pool from the 6-card slice consumable set to the full content, so
/// PLY_DIVIDEND_RECAP / PLY_BRIDGE_LOAN appear LESS often per counter (pool
/// dilution). With the slice pool greedy recapped to its 5.8x line and
/// bankrupted 11%; with the full pool it can't accumulate debt as fast and
/// bankruptcy fell to 5.2% (below the [8,12]% band — greed stopped being
/// fatal). Turning the per-pull chunk back up (0.16 -> 0.20, still well
/// under the R12-retired 0.30) restores greed's lethality in the wider pool
/// (re-sweep: greedy 9.x% in band) while the prudent floor — which recaps
/// only to 3.0x behind a max-crunch buffer — stays at 0.0% bankruptcy. The
/// seed-42 golden plays no recap, so golden v10 is unmoved.
const int kRecapPctBp = 2000;

/// PRT_COO_FIXED's recurring fixed salary as a fraction of the per-round
/// EBITDA it brings, basis points (R17). 0.60 -> 6000: the COO earns +$450k
/// EBITDA but bills a fixed ~$270k/round salary, so the NET organic gain is
/// ~$180k/round while earnings are healthy — but the salary is FIXED, so a
/// crash that craters EBITDA leaves the salary draining cash (operating
/// leverage, doc 04 §1). *** TUNING DIAL — no canon pins the salary ratio;
/// the v1 card schema has no explicit fixed-cost face so the glue derives
/// it id-keyed. ***
const int kCooFixedCostBp = 6000;

/// PLY_EARN_OUT's scheduled drag as a PCT of the acquired venture's per-round
/// EBITDA, basis points (R20b). 0.25 -> 2500: the earn-out acquires +$500k
/// EBITDA for $0 down, then pays the seller 25% of that venture's live
/// earnings each round for [kEarnOutRounds] rounds — a deferred cash drag
/// that scales with how well the acquisition does (doc 02 §3.6 PCT_EBITDA).
/// *** TUNING DIAL — no canon pins the earn-out terms; the v1 card schema
/// has no PCT/rounds face, so the glue derives them id-keyed (the same
/// honest pattern as recap/secondary/COO). ***
const int kEarnOutPctBp = 2500;

/// PLY_EARN_OUT's scheduled-drag length in rounds (R20b). 4 rounds: the
/// bill stretches across most of a tier's deadline, so "buy now, sweat
/// later" bites for a while. *** TUNING DIAL — no canon. ***
const int kEarnOutRounds = 4;

// --- Tier slots (doc 02 §3 PLAYS/SLOTS table; here since v5 for the
// dead-draw pool filter — apply.dart re-exports it) ---

/// Max concurrent ventures (SLOTS) per tier: T1 1, T2 2, T3 2 (deliberately
/// stays at 2 so the exit fork bites), T4 3, T5/endless cap 4.
/// Source: doc 02 §3 PLAYS/SLOTS table (`slotsMax`).
int slotsMax(int tier) {
  switch (tier) {
    case 1:
      return 1;
    case 2:
    case 3:
      return 2;
    case 4:
      return 3;
    case 5:
      return 4;
    default:
      throw ArgumentError.value(tier, 'tier', 'must be 1..5');
  }
}

// --- The exit-offer band (v5; library header = the formula contract) ---

/// Width of the exit-offer multiple draw: u = nextInt(301).
/// *** TUNING DIAL — engine decision, no doc pins offer pricing. ***
const int kExitOfferBandDraws = 301;

/// Permille floor of the band: offer = live x (900 + u) / 1000.
const int kExitOfferBandFloorPermille = 900;

// --- The unlocked-pool predicate (the v10 POOL CONTRACT — library header) ---

/// THE POOL PREDICATE (schemaVersion 10; R20b): is [card] in this run's
/// legal draw pool given its FROZEN-at-init [unlockedCardIds] /
/// [unlockedSectors] and the live [tier]? Pool membership is the
/// INTERSECTION of the cross-run unlock set and the in-run gates (GDD §Q7):
///   1. `card.id ∈ unlockedCardIds` — the per-run frozen unlock snapshot
///      (`baseCurriculum ∪ meta.unlockedCards`, taken at initRun); a card
///      the run never unlocked is never dealt, even at a high tier.
///   2. `card.tierGate <= tier` — the IN-RUN curriculum gate (a gate-2 card
///      stays out of T1 even when unlocked; unlock order == curriculum
///      order, so this rarely bites, but it keeps the early curriculum
///      clean).
///   3. `card.sector == null OR card.sector ∈ unlockedSectors` — a
///      sectored venture/addon/event in a not-yet-unlocked sector
///      (CONSUMER/MEDIA pre-beat-game) is excluded; sector-NULL cards
///      (partners/financing/most plays) are always sector-legal.
/// Type/slot rules are applied by the per-pool helpers below (they own the
/// dead-draw filter). All three inputs are replay-stable, so the pool is a
/// pure function of (content, frozen unlock set, tier).
bool cardInUnlockedPool(
  Card card,
  int tier,
  Set<String> unlockedCardIds,
  Set<Sector> unlockedSectors,
) =>
    unlockedCardIds.contains(card.id) &&
    card.tierGate <= tier &&
    (card.sector == null || unlockedSectors.contains(card.sector));

/// The run's full unlocked card-id set, taken from [meta] at initRun
/// (the per-run FROZEN snapshot source): the base curriculum ALWAYS-on core
/// (doc 04 §3's vertical slice, [kDefaultUnlockedCardIds]) UNIONED with the
/// meta's cross-run unlocks (the §Q7 ladder's gate-2/3/4 decks). Returned in
/// CONTENT FILE ORDER (the pool order is part of the replay contract), so a
/// run's pool is deterministic regardless of how the sets were built. Only
/// ids the content DB actually knows are kept (a meta unlock id with no card
/// is silently dropped — forward-compat).
List<String> runUnlockedCardIds(MetaState meta, ContentDb content) {
  final unlocked = <String>{
    ...kDefaultUnlockedCardIds,
    ...meta.unlockedCards,
  };
  return [
    for (final c in content.cards)
      if (unlocked.contains(c.id)) c.id,
  ];
}

// --- Pools (content file order = the replay contract since v10) ---

/// The ACT-card hand pool (the v10 POOL CONTRACT — library header): the full
/// content's ventures + addons + partners that pass [cardInUnlockedPool] for
/// this run's frozen [unlockedCardIds] / [unlockedSectors] and [tier], in
/// CONTENT FILE ORDER; venture-type cards EXCLUDED when [slotsFull] (the
/// dead-draw filter — a venture ticket cannot resolve while every slot is
/// taken). v10 widened the SOURCE from `content.verticalSlice` to
/// `content.cards` ∩ the unlocked predicate, so the 14 held-out cards now
/// draw once unlocked.
List<Card> handPool(
  ContentDb content,
  int tier, {
  required bool slotsFull,
  Set<String> unlockedCardIds = kDefaultUnlockedCardIdSet,
  Set<Sector> unlockedSectors = kDefaultUnlockedSectorSet,
}) =>
    [
      for (final c in content.cards)
        if ((c.type == CardType.venture && !slotsFull ||
                c.type == CardType.addon ||
                c.type == CardType.partner) &&
            cardInUnlockedPool(c, tier, unlockedCardIds, unlockedSectors))
          c,
    ];

/// The SHOP pool: the full content's financing + consumables that pass the
/// unlocked predicate, in content file order (doc 04 §0; v10 widened).
List<Card> shopPool(
  ContentDb content,
  int tier, {
  Set<String> unlockedCardIds = kDefaultUnlockedCardIdSet,
  Set<Sector> unlockedSectors = kDefaultUnlockedSectorSet,
}) =>
    [
      for (final c in content.cards)
        if ((c.type == CardType.financing || c.type == CardType.consumable) &&
            cardInUnlockedPool(c, tier, unlockedCardIds, unlockedSectors))
          c,
    ];

/// The event pool: the full content's events that pass the unlocked
/// predicate, in content file order (doc 04 §0: events auto-resolve in
/// OPERATE; v10 widened).
List<Card> eventPool(
  ContentDb content,
  int tier, {
  Set<String> unlockedCardIds = kDefaultUnlockedCardIdSet,
  Set<Sector> unlockedSectors = kDefaultUnlockedSectorSet,
}) =>
    [
      for (final c in content.cards)
        if (c.type == CardType.event &&
            cardInUnlockedPool(c, tier, unlockedCardIds, unlockedSectors))
          c,
    ];

// --- The shared shrinking-pool draw (the no-replacement walk) ---

/// Deals [count] card ids from [pool] WITHOUT replacement: each draw is
/// `nextInt(remaining.length)` indexing the remaining pool in pool order,
/// and the dealt card is removed. [count] is clamped to the pool size.
/// Consumes exactly `min(count, pool.length)` draws.
List<String> _dealWithoutReplacement(
    List<Card> pool, int count, SplitMix64Rng rng) {
  final remaining = [...pool];
  if (count > remaining.length) count = remaining.length;
  return [
    for (var i = 0; i < count; i++)
      remaining.removeAt(rng.nextInt(remaining.length)).id,
  ];
}

// --- The two named draw functions (doc 02 §2 "the named draw functions") ---

/// Runs the HAND routine (library header — the v5 contract): one size
/// draw, the no-replacement walk over [handPool] (dead-draw-filtered),
/// then the EXIT-OFFER pair when ventures exist. Returns [state] with
/// `hand` AND `exitOffer` REPLACED wholesale and `rngCursor` reconciled.
/// Phase-agnostic by design: the steps that own the timing (runOperate,
/// an ACT Reroll) gate the phase; this is the routine they share.
GameState drawHand(GameState state, SplitMix64Rng rng, ContentDb content) {
  final size = kHandSizeMin + rng.nextInt(kHandSizeSpan);
  final pool = handPool(content, state.tier,
      slotsFull: state.ventures.length >= slotsMax(state.tier),
      unlockedCardIds: state.unlockedCardIds.toSet(),
      unlockedSectors: state.unlockedSectors.toSet());
  final hand = _dealWithoutReplacement(pool, size, rng);

  // The exit-offer pair (library header): venture pick + band multiple.
  ExitOffer? offer;
  if (state.ventures.isNotEmpty) {
    final v = state.ventures[rng.nextInt(state.ventures.length)];
    final u = rng.nextInt(kExitOfferBandDraws);
    var offerMilli =
        (v.multipleMilli * (kExitOfferBandFloorPermille + u)) ~/ milliScale;
    if (offerMilli < multipleFloorMilli) offerMilli = multipleFloorMilli;
    offer = ExitOffer(ventureId: v.id, offerMultipleMilli: offerMilli);
  }

  return state.copyWith(
    hand: hand,
    exitOffer: offer,
    clearExitOffer: offer == null,
    rngCursor: rng.cursor,
  );
}

/// Maps the state's pending [GameState.exitOffer] onto the [ExitVenture]
/// action that resolves it (the one entry point the UI's EXIT OFFER ticket
/// needs): the live side of the `min(offer, live)` fork is the offered
/// venture's CURRENT multipleMilli — the engine's live mark (drifted by
/// the market each OPERATE; doc 01 §7.3's per-venture live multiple).
/// Returns null when no offer is pending or its venture has left play
/// (a stale ticket maps to nothing; the next hand draw renews it).
ExitVenture? exitOfferAction(GameState state) {
  final offer = state.exitOffer;
  if (offer == null) return null;
  final idx = state.ventures.indexWhere((v) => v.id == offer.ventureId);
  if (idx < 0) return null;
  return ExitVenture(
    ventureId: offer.ventureId,
    offerMultipleMilli: offer.offerMultipleMilli,
    liveMarketMultipleMilli: state.ventures[idx].multipleMilli,
  );
}

/// Runs the SHOP routine (library header): [kShopOfferCount] draws over
/// [shopPool], no size draw. Returns [state] with `shopOffers` REPLACED
/// wholesale and `rngCursor` reconciled. Phase-agnostic (endTurn and a
/// SHOP Reroll own the timing).
GameState drawShop(GameState state, SplitMix64Rng rng, ContentDb content) {
  final offers = _dealWithoutReplacement(
      shopPool(content, state.tier,
          unlockedCardIds: state.unlockedCardIds.toSet(),
          unlockedSectors: state.unlockedSectors.toSet()),
      kShopOfferCount,
      rng);
  return state.copyWith(shopOffers: offers, rngCursor: rng.cursor);
}

// --- Event-card application (runOperate step 5's delta engine) ---

/// Applies one event [card]'s deltas (doc 01 §6.1 step 5: "resolve event
/// cards as deltas"), returning the new ventures list + cash. Draw-free —
/// the roll/pick draws live in runOperate.
///
/// INTERPRETATION (documented per the work order; doc 04 events carry a
/// sector or null):
///   - The MATCHING SET is every venture of the card's sector; a
///     sector-NULL event is market-wide weather and matches EVERY venture
///     (EVT_CREDIT_CRUNCH compresses all multiples — reading sector-null
///     as cash-only would make the crunch a no-op).
///   - Per-venture delta keys (ebitda/multiple/netDebt/own) apply to EACH
///     venture in the matching set, clamped per economy-model.json
///     resolverInputs.clamps (ebitda >= 0; multiple >= 1000 milli; own in
///     0..10000 bp; netDebt unclamped).
///   - The `cash` delta is GLOBAL: applied exactly once, unclamped, even
///     with zero matching ventures. A (post-slice) negative-cash event can
///     therefore push cash below zero mid-OPERATE; F6 still only fires at
///     step 6, after interest — consistent with doc 01 §6.1's ordering.
///   - `roundsNeglected` is untouched: an event is market weather, not a
///     targeting Act (doc 02 §2 ACT resets are player-action-only).
({List<Venture> ventures, int cashCents}) applyEventCard({
  required List<Venture> ventures,
  required int cashCents,
  required Card card,
}) {
  final next = <Venture>[];
  for (final v in ventures) {
    if (card.sector != null && v.sector != card.sector) {
      next.add(v);
      continue;
    }
    var ebitda = v.ebitdaCents + (card.deltas['ebitda'] ?? 0);
    if (ebitda < 0) ebitda = 0; // clamp: ebitda >= 0
    var multiple = v.multipleMilli + (card.deltas['multiple'] ?? 0);
    if (multiple < multipleFloorMilli) multiple = multipleFloorMilli;
    var own = v.ownershipBp + (card.deltas['own'] ?? 0);
    if (own < 0) own = 0;
    if (own > bpScale) own = bpScale;
    next.add(v.copyWith(
      ebitdaCents: ebitda,
      multipleMilli: multiple,
      netDebtCents: v.netDebtCents + (card.deltas['netDebt'] ?? 0),
      ownershipBp: own,
    ));
  }
  return (ventures: next, cashCents: cashCents + (card.deltas['cash'] ?? 0));
}

// --- Held-plays cap (doc 02 §3 playsHeldMax) ---

/// Max held consumables per tier: T1-T3 2, T4+ 3.
/// Source: doc 02 §3 `playsHeldMax` {1:2, 2:2, 3:2, 4:3, 5:3} (GDD §Q2:
/// "scales toward 3 by T4").
int playsHeldMax(int tier) {
  switch (tier) {
    case 1:
    case 2:
    case 3:
      return 2;
    case 4:
    case 5:
      return 3;
    default:
      throw ArgumentError.value(tier, 'tier', 'must be 1..5');
  }
}

// --- The card -> action glue (doc 03 §4.2/§5: faces map to raw payloads) ---

/// Maps a [card]'s faces onto the existing Action payload that resolves it
/// (doc 03 §4.1's closed union; the engine stays card-schema-agnostic).
/// [targetVentureId] is: the NEW venture's id for a venture card (the
/// engine does not mint ids), the platform for an addon, the target for
/// financing, and the (nullable) target for a consumable.
///
/// Per-type mapping, with the documented v1 decisions:
///   - venture -> [StartVenture]: price/debt from the cost block (cost.cash
///     mirrors -deltas.cash for purchase cards, doc 04 §0), face EBITDA +
///     multiple from the deltas. Ownership is the resolver's hard 10000.
///   - addon -> [AcquireAddOn]: the v1 card schema carries NO buy multiple,
///     so the glue derives the IMPLIED one — m_buy = trunc(cost.cash x
///     1000 / faceEbitda) — and the resolver's addonPrice recomputes
///     trunc(ebitda x m_buy / 1000), which can land a sub-dollar sliver
///     UNDER the face when the division is inexact (ADD_SW_MICRO: 499860
///     vs the 500000 face). The truncation goes to the player; the implied
///     multiple also feeds the render-only arbitrage flash. Any
///     illustrative `multiple` delta on the card (the -640 drag) is
///     IGNORED: the resolver computes the real live x0.92 drag
///     (doc 03 §4.2; doc 04 §4).
///   - financing -> dispatch by SHAPE: a dilution face (cost.dilution > 0)
///     is an equity raise -> [RaiseEquity] (raise = deltas.cash; the
///     engine's F5 recomputes the real ownership cut — the face dilution
///     is nominal, doc 04 §0). Anything else is a debt-side instrument ->
///     [TakeDebt] (proceeds = deltas.cash, face = deltas.netDebt; both may
///     be NEGATIVE — FIN_REFI pays a fee and retires debt).
///     Growth riders (doc 02 §3.2 POST "apply card defaults") are LIVE
///     since round 10: the raise card's ebitda/multiple faces map onto
///     RaiseEquity's rider channel and land after the F5 dilution.
///   - consumable -> [PlayConsumable] with the card's deltas, PURCHASE-
///     MIRROR-STRIPPED: doc 04 §0 has cost.cash mirror -deltas.cash for
///     purchase-priced cards, and the SHOP buy (buyShopOffer) already
///     charged it — so a deltas.cash that exactly equals -cost.cash (with
///     cost.cash > 0) is dropped, never charged twice. PLY_HOT_WINDOW /
///     PLY_MARKET_READ map their market-flag effects via the action's
///     armsHotWindow / readsMarket bools (id-keyed; live since round 10).
///   - partner -> [UnsupportedError]: the v1 exclusion (library header).
///   - event -> [ArgumentError]: events auto-resolve in OPERATE, never
///     through a player action (doc 04 §0).
Action actionForCard(Card card, {String? targetVentureId}) {
  switch (card.type) {
    case CardType.venture:
      return StartVenture(
        ventureId: _requireTarget(card, targetVentureId, 'the new venture id'),
        sector: card.sector!,
        ebitdaCents: card.deltas['ebitda']!,
        multipleMilli: card.deltas['multiple']!,
        priceCents: card.cost.cashCents,
        faceDebtCents: card.cost.debtCents,
      );
    case CardType.addon:
      final ebitda = card.deltas['ebitda']!;
      if (ebitda <= 0) {
        throw ArgumentError.value(ebitda, 'card.deltas[ebitda]',
            'addon ${card.id} needs a positive face EBITDA to imply m_buy');
      }
      return AcquireAddOn(
        targetVentureId:
            _requireTarget(card, targetVentureId, 'the platform id'),
        addonSector: card.sector!,
        addonEbitdaCents: ebitda,
        // m_buy = trunc(price x 1000 / ebitda) — ONE division, last.
        addonBuyMultipleMilli: (card.cost.cashCents * milliScale) ~/ ebitda,
        addonFaceDebtCents: card.cost.debtCents,
      );
    case CardType.financing:
      final target = _requireTarget(card, targetVentureId, 'the target id');
      if (card.cost.dilutionBp > 0) {
        // Growth riders (doc 02 §3.2 POST; live since round 10): the raise
        // card's ebitda/multiple faces ride along — FIN_SEED_RAISE lands
        // +200k EBITDA / +1000 milli alongside the F5 dilution.
        return RaiseEquity(
          ventureId: target,
          raiseCents: card.deltas['cash'] ?? 0,
          ebitdaDeltaCents: card.deltas['ebitda'] ?? 0,
          multipleDeltaMilli: card.deltas['multiple'] ?? 0,
        );
      }
      return TakeDebt(
        ventureId: target,
        proceedsCents: card.deltas['cash'] ?? 0,
        faceDebtCents: card.deltas['netDebt'] ?? 0,
      );
    case CardType.consumable:
      final deltas = Map<String, int>.from(card.deltas);
      final cash = deltas['cash'];
      if (cash != null &&
          card.cost.cashCents > 0 &&
          cash == -card.cost.cashCents) {
        deltas.remove('cash'); // the purchase mirror — already paid at buy
      }
      // THE CANONICAL RECAP (doc 01 §7.7; economy formulas.dividendRecap;
      // R12): PLY_DIVIDEND_RECAP's JSON faces (+$30k cash/+$30k debt) are
      // ILLUSTRATIVE — the doc's formula is `trunc(EV x recapPct)` at
      // resolve time, which the fixed face neither scales with nor
      // matches. The glue STRIPS both faces (like the addon's
      // illustrative multiple delta) and routes the pull through
      // PlayConsumable.recapBp = [kRecapPctBp] (economy
      // constants.recapPct; apply.dart computes against the live EV).
      final isRecap = card.id == 'PLY_DIVIDEND_RECAP';
      if (isRecap) {
        deltas.remove('cash');
        deltas.remove('netDebt');
      }
      // THE SECONDARY SALE (doc 02 §3.6; schemaVersion 9 — audit L3):
      // PLY_SECONDARY_SALE's JSON faces are ILLUSTRATIVE — `cash: 0` was the
      // $0 proceeds PLACEHOLDER and `own: -Δbp` the slice to sell. The doc's
      // formula computes proceeds from the live equity at RESOLVE time, so
      // (exactly like the recap) the glue STRIPS both faces and routes the
      // ownership MAGNITUDE through PlayConsumable.secondaryBp; apply
      // computes `proceeds = trunc(equity x secondaryBp / 10000)` and applies
      // the ownership cut itself. The magnitude is the `own` face's absolute
      // value (the card sells, so it is negative on the card).
      final isSecondary = card.id == 'PLY_SECONDARY_SALE';
      var secondaryBp = 0;
      if (isSecondary) {
        final ownFace = deltas['own'] ?? 0;
        secondaryBp = ownFace < 0 ? -ownFace : ownFace;
        deltas.remove('own');
        deltas.remove('cash');
      }
      // SPIN_OFF (doc 02 §3.6; R20b): the whole-venture form (no add-on
      // ledger in v1) — split the target back out at its live mark, bank
      // the stake, free the slot. The card's 300k fee rides through
      // deltas.cash (no purchase mirror to strip — cost.cash is the play's
      // own fee, not a -deltas.cash mirror). The resolver computes proceeds
      // from the live equity at resolve time.
      final isSpinOff = card.id == 'PLY_SPIN_OFF';
      // EARN_OUT (doc 02 §3.6; R20b): the card's `ebitda` face (the acquired
      // earnings) lands NOW via deltas; the glue derives the scheduled drag
      // terms id-keyed (the v1 schema has no PCT/rounds face — same honest
      // pattern as recap/secondary/COO).
      final isEarnOut = card.id == 'PLY_EARN_OUT';
      // The market-flag/recap/secondary/spin-off/earn-out plays are keyed BY
      // CARD ID (documented glue decision: the v1 card schema carries no
      // consumableKind field, so the id is the only honest discriminator;
      // when content lands the kind, key off it instead). Live since round
      // 10 — the v1 "pure cost" gap is closed; R20b adds spin-off + earn-out.
      return PlayConsumable(
        playId: card.id,
        deltas: deltas,
        targetVentureId: targetVentureId,
        armsHotWindow: card.id == 'PLY_HOT_WINDOW',
        readsMarket: card.id == 'PLY_MARKET_READ',
        recapBp: isRecap ? kRecapPctBp : 0,
        secondaryBp: secondaryBp,
        spinsOff: isSpinOff,
        earnOutPctBp: isEarnOut ? kEarnOutPctBp : 0,
        earnOutRounds: isEarnOut ? kEarnOutRounds : 0,
      );
    case CardType.partner:
      // The PartnerEngine layer (schemaVersion 5): the card's `ebitda`
      // delta is the engine's PER-ROUND accrual (doc 04 §1 "+150k/rd"),
      // its `multiple` delta (PRT_GROWTH_HACKER) a one-time story bump,
      // and its `cash` delta the purchase mirror of cost.cash — IGNORED
      // here because the resolver charges cost.cash itself (nothing
      // charges twice).
      //
      // PRT_COO_FIXED — OPERATING LEVERAGE (doc 04 §1; R17): the COO is a
      // big +EBITDA engine that carries a RECURRING FIXED SALARY (a
      // ScheduledCost in HirePartner, fired in OPERATE step 3c). The v1
      // card SCHEMA carries no explicit fixed-cost face, so the glue
      // DERIVES it id-keyed (the same honest pattern as recap/secondary):
      // the recurring salary = [kCooFixedCostBp] of the per-round EBITDA the
      // COO brings — glorious when earnings are fat, lethal when thin (it
      // can push cash negative mid-OPERATE; F6 still verdicts at step 6,
      // already pinned). All other partners map fixedCostCents 0.
      final perRoundEbitda = card.deltas['ebitda'] ?? 0;
      final fixedCostCents = card.id == 'PRT_COO_FIXED'
          ? (perRoundEbitda * kCooFixedCostBp) ~/ 10000
          : 0;
      return HirePartner(
        ventureId:
            _requireTarget(card, targetVentureId, 'the venture hiring'),
        defId: card.id,
        costCents: card.cost.cashCents,
        perRoundEbitdaCents: perRoundEbitda,
        multipleDeltaMilli: card.deltas['multiple'] ?? 0,
        fixedCostCents: fixedCostCents,
      );
    case CardType.event:
      throw ArgumentError.value(card.id, 'card',
          'event cards auto-resolve in OPERATE and are never player-played');
  }
}

String _requireTarget(Card card, String? targetVentureId, String what) {
  if (targetVentureId == null) {
    throw ArgumentError.value(null, 'targetVentureId',
        '${card.type.name} card ${card.id} requires $what');
  }
  return targetVentureId;
}
