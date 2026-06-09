/// Immutable game-state model and the §7 derived net-worth getter.
///
/// LOCKED fixed-point conventions (mirrored from money.dart / economy-model.json):
/// - Money is integer **cents**. No `double` anywhere in this package.
/// - `multipleMilli` = multiple x1000 (14x is `14000`).
/// - `ownershipBp` = ownership x10000 (100% is `10000`, 80% is `8000`).
/// - Integer division truncates toward zero (Dart `~/`).
///
/// Design choices (documented per task):
/// - Value equality is implemented manually (`==`/`hashCode`) rather than via a
///   codegen package, keeping the package dependency-free. `GameState` compares
///   its `ventures` list element-by-element so two states built from equal
///   inputs are equal (required by the resolver and save layers).
/// - `netWorthCents` is a getter only. There is no field and no setter; net
///   worth is always recomputed from the five resolver inputs + cash, so it can
///   never drift out of sync with the venture data.
///
/// Pure and dependency-free except for the sibling money helpers (only
/// `dart:core` transitively) — [netWorthCents] uses [satMul] for its
/// saturating products (audit 2026-06-09 M3).
library;

import 'money.dart' show satMul;

/// The engine's CURRENT save/replay schema version.
///
/// History (docs/03 §6: any change to the RNG draw order or the state schema
/// is a HARD bump — in-progress runs from older versions are abandoned, never
/// migrated, because a migration cannot un-break a moved stream):
///   1 -> Phase 1: the action layer; all 11 actions draw 0
///        (golden: test/golden/replay_seed42_v1.txt, RETIRED).
///   2 -> Phase 3 round 1: MarketState + the OPERATE step — the first real
///        RNG draws (golden: test/golden/replay_seed42_v2.txt, RETIRED).
///   3 -> Phase 3 round 2: the round machine (DEADLINE_CHECK, tier
///        clear/reseed, win/death, strict phase gates) added
///        netWorthAtTierEntry / netWorthLastRound / won / death to the
///        state and to the flatten() serialization. FIELD ADDITIONS ONLY:
///        the RNG draw-order contract is byte-identical to v2 — the bump is
///        for the widened flatten paths, not a moved stream
///        (golden: test/golden/replay_seed42_v3.txt, RETIRED).
///   4 -> Phase 3 round 4: the DEAL-FLOW layer — a MOVED STREAM, the
///        second pre-declared stream-breaking bump (apply.dart's Reroll
///        note). runOperate now opens with the hand draw (doc 03 §3.1
///        step 1) and rolls event cards at doc 01 §6.1's step 5; endTurn
///        draws the shop offers; Reroll REALLY redraws. hand / shopOffers
///        / playsHeld joined the state and flatten()
///        (golden: test/golden/replay_seed42_v4.txt, RETIRED).
///   5 -> Phase 3 round 10: GAMEPLAY COMPLETENESS — the third pre-declared
///        stream-breaking bump. The hand routine gained the per-round
///        EXIT-OFFER draws (venture pick + offer multiple) and the v5 pool
///        contract (partners RE-INCLUDED; venture cards excluded while the
///        tier's slots are full — the T1 dead-draw fix). Venture.partners,
///        GameState.scheduled/exitOffer, and the MarketState consumable
///        flags joined the state and flatten()
///        (golden: test/golden/replay_seed42_v5.txt, RETIRED).
///   6 -> Phase 5 / R12 balance round: ORGANIC GROWTH (doc 01 §3.2 /
///        §6.1 step 3) — economy constants.organicGrowthDefault (0.10,
///        parsed since Phase 2) finally APPLIED at OPERATE step 3a to
///        PARTNERED ventures, and initRun attaches the FOUNDING OPERATOR
///        (a 0-face PartnerEngine) to the seed venture. The RNG draw
///        order is UNCHANGED from v5 — the bump is for the moved VALUES
///        (every partnered venture's EBITDA path compounds differently,
///        so v5 saves/replays land different states) and the widened
///        initRun flatten (the seed venture now emits partner paths).
///        CONSOLIDATED into the same bump (v6 never shipped outside the
///        R12 round): the CANONICAL dividend recap — PLY_DIVIDEND_RECAP
///        resolves doc 01 §7.7's `trunc(EV x recapPct)` at play time via
///        PlayConsumable.recapBp instead of charging the card's
///        illustrative $30k faces
///        (golden: test/golden/replay_seed42_v6.txt, RETIRED).
///   7 -> Phase 5 / R12 balance round, the TUNING PASS (doc 01 §8 knob
///        order, measured by tool/sim.dart's full-model Monte-Carlo
///        against §11's bands): organicGrowthDefault 0.10 -> 0.20,
///        interestMax 0.14 -> 0.12, crunch rateMul 1.8 -> 1.3, crunch
///        entry probability 0.18 -> 0.12, recapPct 0.30 -> 0.16,
///        carrySeedFrac 0.24 -> 0.37, deadlineRounds [8,8,9,10] ->
///        [9,10,9,10]. The RNG draw order is UNCHANGED from v5/v6 — the
///        bump is for the moved VALUES (every EBITDA path and live-rate
///        draw lands differently, so v6 saves/replays land different
///        states). Why each dial moved is documented AT the dial
///        (operate/resolver/round/dealflow.dart) and in .claude/STATE.md
///        (golden: test/golden/replay_seed42_v7.txt, RETIRED).
///   8 -> Phase 4 / R13 save-persistence round: the PERSISTED CONTRACT
///        change. The run save (docs/06) is the minimal reproducible
///        record `{seed, cursor, startConfig:{runId, backgroundId},
///        actionLog}` replayed through the engine — so the actionLog's
///        on-disk shape (the typed, replayable RunStep journal in
///        serialize.dart) and the new startConfig.backgroundId (§Q7
///        founder backgrounds, meta.dart) are now part of the on-disk
///        contract. Also additive to the state itself: every venture
///        gained a deterministic [Venture.displayName] (R9/R11's "V1 vs
///        NIMBUS" flag), which flatten() serializes — so the golden's
///        path SET grew by one venture.displayName line per venture. The
///        RNG DRAW ORDER IS UNCHANGED from v7 (cursor still 28; nothing
///        in serialize/migrate/meta/describe touches the stream) — the
///        bump is for the persisted-contract change + the widened flatten,
///        not a moved stream, so a v7 save is abandoned (docs/06 §3
///        STREAM-BREAKING table) rather than mis-replayed only because the
///        actionLog format moved underneath it
///        (golden: test/golden/replay_seed42_v8.txt, RETIRED).
///   9 -> Phase 6 / R15 engine round (audit 2026-06-09): three changes
///        fold into ONE bump. (a) GameState gained [backgroundId] — the
///        founder background is now carried on the run state (was only in
///        the save's startConfig), so the round layer can honor the
///        DEALMAKER +1-play grant; flatten() serializes it (the golden's
///        path set grows by one `backgroundId` line). (b) PLY_SECONDARY_
///        SALE got its real resolver: [PlayConsumable.secondaryBp] sells
///        Δownership at the live equity mark (doc 02 §3.6) — a new action
///        field, part of the persisted journal. (c) T5 endless now
///        ESCALATES (round.dart endlessSurvivalBarCents — a rising survival
///        bar per ante) instead of always-advancing forever. The RNG
///        DRAW ORDER IS UNCHANGED from v8 (cursor still 28; the seed-42
///        Bootstrapper script touches none of these new paths beyond the
///        additive backgroundId field) — the bump is for the widened
///        state/flatten + the persisted-journal action shape + the moved
///        endless behavior, so a v8 save is abandoned (docs/06 §3) rather
///        than mis-replayed
///        (golden: test/golden/replay_seed42_v9.txt, RETIRED).
///  10 -> Phase 6 / R20b DRAW-POOL KEYSTONE: the full unlocked card set
///        finally enters PLAY. R17 authored the 33-card set + the §Q7 meta
///        unlock ladder, but the draw pools (dealflow.dart
///        handPool/shopPool/eventPool) still keyed off `content.verticalSlice`
///        — the 14 held-out cards were unlock-tracked but NEVER DRAWN. This
///        round threads a per-run FROZEN [GameState.unlockedCardIds] /
///        [GameState.unlockedSectors] snapshot (taken from MetaState at
///        initRun, so a run's legal pool is fixed at start and replay-stable;
///        GDD §Q7: unlocks are cross-run meta, tier-gating is in-run — the
///        pool is the INTERSECTION), and the three draw pools now select from
///        the FULL content (`content.cards`) by the predicate `id ∈
///        unlockedCardIds AND tierGate <= tier AND (sector == null OR sector
///        ∈ unlockedSectors) AND type/slot rules`. A default/new-player meta
///        unlocks exactly the base curriculum (doc 04 §3's 19-card slice), so
///        a fresh run still plays like the v9 slice at T1 — but the pool that
///        FEEDS nextInt now grows with the unlock set, which MOVES THE STREAM
///        (a wider pool changes every no-replacement draw index). Also: the
///        PLY_SPIN_OFF (slot-free partial-exit) and PLY_EARN_OUT (scheduled
///        PCT-of-EBITDA drag over N rounds) resolvers landed real (doc 02
///        §3.6), widening [ScheduledCost] with a roundsLeft countdown + a
///        PCT_EBITDA basis. The persisted contract widened too: the save's
///        startConfig now carries unlockedCardIds/unlockedSectors (so replay
///        reproduces the frozen pool). STREAM-BREAKING — a v9 save is
///        abandoned (docs/06 §3), not migrated
///        (golden: test/golden/replay_seed42_v10.txt).
const int engineSchemaVersion = 10;

/// The investable sectors (verified against data/cards.json).
///
/// The base FOUR (software/retail/services/industrial) ship in v1; CONSUMER
/// and MEDIA are the two POST-LAUNCH sectors (GDD §8 Q6 / doc 04), gated
/// behind beating the game (meta.dart [kPostLaunchSectors]). They are
/// APPENDED to the enum so the existing `.index` values are unchanged — the
/// flatten/golden replay contract (which serializes `.index`) is preserved.
///
/// Content JSON uses UPPERCASE spellings (`SOFTWARE`, `RETAIL`, ...); use
/// [sectorFromJson] / [sectorToJson] to cross that boundary.
enum Sector { software, retail, services, industrial, consumer, media }

/// Parses a content-JSON sector spelling (uppercase) into a [Sector].
///
/// Throws [ArgumentError] on an unrecognised spelling so malformed content
/// fails loudly at load time rather than silently defaulting.
Sector sectorFromJson(String json) {
  switch (json) {
    case 'SOFTWARE':
      return Sector.software;
    case 'RETAIL':
      return Sector.retail;
    case 'SERVICES':
      return Sector.services;
    case 'INDUSTRIAL':
      return Sector.industrial;
    case 'CONSUMER':
      return Sector.consumer;
    case 'MEDIA':
      return Sector.media;
    default:
      throw ArgumentError.value(json, 'json', 'Unknown sector spelling');
  }
}

/// Serialises a [Sector] back to its content-JSON uppercase spelling.
String sectorToJson(Sector sector) {
  switch (sector) {
    case Sector.software:
      return 'SOFTWARE';
    case Sector.retail:
      return 'RETAIL';
    case Sector.services:
      return 'SERVICES';
    case Sector.industrial:
      return 'INDUSTRIAL';
    case Sector.consumer:
      return 'CONSUMER';
    case Sector.media:
      return 'MEDIA';
  }
}

/// The single global market temperature (doc 02 §1 MarketTemp).
///
/// Maps onto economy-model.json curves.driftModel.states:
///   `cold` = "crunch" (multiples compress, rates spike, financing gated),
///   `neutral` = "normal",
///   `hot` = "bubble" (everything reprices up; sell, don't buy).
///
/// DECLARATION ORDER IS PART OF THE REPLAY CONTRACT: the golden replay file
/// serializes the temp as its `.index` (cold=0, neutral=1, hot=2). Never
/// reorder or insert members — that is a schemaVersion bump.
enum MarketTemp { cold, neutral, hot }

/// The core-loop phase (doc 02 §1 PhaseId / §2 state machine).
///
/// DECLARATION ORDER IS PART OF THE REPLAY CONTRACT (serialized as `.index`):
/// operate=0, act=1, shop=2, deadlineCheck=3, runOver=4. Never reorder.
enum PhaseId { operate, act, shop, deadlineCheck, runOver }

/// Why a run ended (doc 02 §1 DeathCause): F6 liquidity death or the
/// growth-rate death. A WIN is not a death — a victorious run carries
/// `won == true` with [GameState.death] still null.
///
/// DECLARATION ORDER IS PART OF THE REPLAY CONTRACT (the golden flatten()
/// serializes a dead run's cause as `.index`, -1 while alive):
/// bankruptcy=0, missedDeadline=1. Never reorder or insert members.
enum DeathCause { bankruptcy, missedDeadline }

/// The single global market banner (doc 02 §1 MarketState — including the
/// hotWindow/marketRead consumable flags since the round-10 layer).
///
/// Design decision (doc 01 §7.3, documented per the work order): per-sector
/// drift is NOT stored here. Doc 01 §7.3 defines drift as PER-VENTURE jitter
/// — `driftFactor = stateFactor * (1 + sectorVol * tri)` with `tri` drawn
/// fresh per venture per OPERATE — so a stored per-sector map would be a
/// stale duplicate of two RNG draws. Drift is computed at apply time in
/// `runOperate` (operate.dart) and exists in state only as its effect on
/// each venture's stored `multipleMilli`.
///
/// All fields are replay-relevant (they steer future draws and charges) and
/// are therefore serialized by the golden-replay flatten() walker.
class MarketState {
  const MarketState({
    required this.temp,
    required this.roundsInState,
    required this.stateDurationRounds,
    required this.liveRateBp,
    this.hotWindowArmed = false,
    this.hotWindowExpiresRound = -1,
    this.marketReadHint,
    this.marketReadExpiresRound = -1,
  });

  /// Current market weather (sticky; doc 01 §7.3).
  final MarketTemp temp;

  /// OPERATEs this state has governed so far, INCLUDING the round it was
  /// drawn in (a fresh state starts at 1). When this reaches
  /// [stateDurationRounds] the next OPERATE draws a transition.
  final int roundsInState;

  /// How long this state lasts, in rounds (one bounded 2..3 draw,
  /// economy-model.json curves.driftModel.stateDurationRounds).
  final int stateDurationRounds;

  /// The live per-round interest rate in basis points, drawn each OPERATE
  /// inside the economy-model interestBand and scaled by the state's
  /// rateMul. 0 means "not yet drawn" (a fresh run before its first
  /// OPERATE); interest is only ever charged AFTER the round's draw.
  final int liveRateBp;

  /// HOT_WINDOW armed (doc 02 §1): the NEXT exit uses the HOT multiple
  /// (live x135/100, apply.dart) instead of `min(offer, live)`. Set by
  /// playing PLY_HOT_WINDOW; cleared when an EXIT fires it OR by the
  /// OPERATE step-1 expiry. CONSUMABLE BOOKKEEPING, never itself money —
  /// but replay-relevant (it steers a future exit), so flatten()
  /// serializes it (disarmed contributes no path).
  final bool hotWindowArmed;

  /// Absolute flat-round counter (`tier x 100 + round`, [flatRoundOf] —
  /// doc 02 §3.6's flatRound) past which the armed window auto-expires at
  /// OPERATE step 1 (doc 02 §2: "no flag persists silently"). -1 =
  /// disarmed (the doc's null, kept int for the flatten contract).
  final int hotWindowExpiresRound;

  /// MARKET_READ's revealed next-round direction (doc 02 §1; doc 01 §7.3:
  /// "direction only, never magnitude"); null = no read active. Set by
  /// playing PLY_MARKET_READ ([marketReadDirection] documents exactly what
  /// is honestly knowable); cleared by the OPERATE step-1 expiry.
  final MarketTemp? marketReadHint;

  /// Flat-round expiry for [marketReadHint] (one-round lifetime,
  /// doc 02 §3.6); -1 = no read active.
  final int marketReadExpiresRound;

  /// Returns a copy with the named fields replaced; all others preserved.
  /// [marketReadHint] is keep-on-null; pass [clearMarketReadHint] to null
  /// it (the OPERATE step-1 expiry path).
  MarketState copyWith({
    MarketTemp? temp,
    int? roundsInState,
    int? stateDurationRounds,
    int? liveRateBp,
    bool? hotWindowArmed,
    int? hotWindowExpiresRound,
    MarketTemp? marketReadHint,
    bool clearMarketReadHint = false,
    int? marketReadExpiresRound,
  }) {
    return MarketState(
      temp: temp ?? this.temp,
      roundsInState: roundsInState ?? this.roundsInState,
      stateDurationRounds: stateDurationRounds ?? this.stateDurationRounds,
      liveRateBp: liveRateBp ?? this.liveRateBp,
      hotWindowArmed: hotWindowArmed ?? this.hotWindowArmed,
      hotWindowExpiresRound:
          hotWindowExpiresRound ?? this.hotWindowExpiresRound,
      marketReadHint:
          clearMarketReadHint ? null : (marketReadHint ?? this.marketReadHint),
      marketReadExpiresRound:
          marketReadExpiresRound ?? this.marketReadExpiresRound,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MarketState &&
        other.temp == temp &&
        other.roundsInState == roundsInState &&
        other.stateDurationRounds == stateDurationRounds &&
        other.liveRateBp == liveRateBp &&
        other.hotWindowArmed == hotWindowArmed &&
        other.hotWindowExpiresRound == hotWindowExpiresRound &&
        other.marketReadHint == marketReadHint &&
        other.marketReadExpiresRound == marketReadExpiresRound;
  }

  @override
  int get hashCode => Object.hash(
        temp,
        roundsInState,
        stateDurationRounds,
        liveRateBp,
        hotWindowArmed,
        hotWindowExpiresRound,
        marketReadHint,
        marketReadExpiresRound,
      );

  @override
  String toString() => 'MarketState(temp: $temp, '
      'roundsInState: $roundsInState/$stateDurationRounds, '
      'liveRateBp: $liveRateBp, hotWindowArmed: $hotWindowArmed'
      '${hotWindowArmed ? ' (expires $hotWindowExpiresRound)' : ''}, '
      'marketReadHint: $marketReadHint)';
}

/// The round's EXIT OFFER ticket (doc 02 §3.7 "an exit offer card is
/// present"; the round-10 work order): one offer per hand draw whenever
/// ventures exist — WHICH venture and at WHAT multiple are stream draws
/// (dealflow.dart's v5 hand-routine contract documents the exact integer
/// formula). The UI renders it as an EXIT OFFER ticket; it resolves
/// through the existing ExitVenture action (dealflow.exitOfferAction maps
/// it), where `min(offer, live)` / the hot-window override apply as ever.
/// Replaced wholesale by every hand draw (it expires with the hand);
/// cleared by an EXIT of its venture. Value type; REPLAY-RELEVANT, so
/// flatten() serializes it (no offer contributes no paths).
class ExitOffer {
  const ExitOffer({required this.ventureId, required this.offerMultipleMilli});

  /// The venture the buyer wants (always one of `ventures` at draw time;
  /// an exit of that venture clears the offer).
  final String ventureId;

  /// The offered exit multiple in milli-units (the band formula lives in
  /// dealflow.dart; the resolver still takes `min(offer, live)`).
  final int offerMultipleMilli;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExitOffer &&
        other.ventureId == ventureId &&
        other.offerMultipleMilli == offerMultipleMilli;
  }

  @override
  int get hashCode => Object.hash(ventureId, offerMultipleMilli);

  @override
  String toString() =>
      'ExitOffer(ventureId: $ventureId, multiple: $offerMultipleMilli)';
}

/// The doc 02 §3.6 `flatRound(run)` counter: a monotonically increasing
/// round counter across tiers (`tier x 100 + round` — the doc's own
/// example formula), used ONLY to date the one-window consumable-flag
/// expiries. Bookkeeping, never economy; monotone because no tier reaches
/// 100 rounds (deadlines top out at 12).
int flatRoundOf(GameState s) => s.tier * 100 + s.round;

/// What MARKET_READ can HONESTLY reveal about the NEXT round's direction
/// (documented per the work order — derived deterministically, consuming
/// and peeking NO draws):
///   - MID-STATE (`roundsInState < stateDurationRounds`): the next OPERATE
///     cannot transition (operate.dart's machine only rolls at a
///     boundary), so next round's temp IS the current temp — a certainty,
///     genuinely revealed.
///   - AT A BOUNDARY: the transition draw has not happened yet, and
///     reading it early would either consume stream draws (moving every
///     subsequent draw — stream-breaking) or peek without consuming
///     (breaking the f(seed, cursor) replay discipline). The hint is
///     therefore the MODAL outcome — NEUTRAL, 64 of 100 per the
///     transitionAtBoundary table — a best forecast, not a peek. This is
///     the honest limit of what is knowable at play time; doc 01 §7.3's
///     "reveals next round's direction only" is satisfied exactly in the
///     mid-state case and approximated by the mode at a boundary.
MarketTemp marketReadDirection(MarketState market) =>
    market.roundsInState >= market.stateDurationRounds
        ? MarketTemp.neutral
        : market.temp;

/// The default market a freshly-constructed state carries: a known NEUTRAL
/// opening that has governed 1 round of a 2-round duration, so the first
/// OPERATE ticks (no transition draws) and the second hits the boundary.
/// liveRateBp 0 = "not yet drawn" (see [MarketState.liveRateBp]). Engine
/// decision, documented here; the run-init layer may seed differently later.
const MarketState kOpeningMarket = MarketState(
  temp: MarketTemp.neutral,
  roundsInState: 1,
  stateDurationRounds: 2,
  liveRateBp: 0,
);

/// An operating-partner engine attached to a venture (doc 02 §1
/// PartnerEngine — the permanent-engine / Jokers layer, §3.5), trimmed to
/// the v1 slice's needs: the content archetype id plus the one per-round
/// delta the slice partners carry (+EBITDA). Doc 02's full `perRound:
/// Deltas` shape widens this when a partner card needs another key; the
/// fixed-cost variant flows through [ScheduledCost], never here (doc 02
/// §3.5: "all deferred/recurring money flows through ONE channel").
///
/// Engine decision (documented; diverges from doc 02's ventureCashYield
/// PSEUDOCODE, reconciled against its own §3.5 PROSE): the per-round
/// +EBITDA ACCRUES onto the venture's stored ebitda each OPERATE (the
/// "organic compounder ... permanent +EBITDA engine every round"), rather
/// than being a non-accruing yield-base bonus — and the cash yield then
/// converts the accrued earnings too. See operate.dart step 3a.
///
/// Value type; replay-relevant (it drives every future OPERATE's EBITDA),
/// so flatten() serializes each engine as indexed per-venture paths.
class PartnerEngine {
  const PartnerEngine({required this.defId, required this.perRoundEbitdaCents});

  /// Content-DB archetype id (e.g. `PRT_SALES_LEAD`).
  final String defId;

  /// EBITDA this engine adds to its venture each OPERATE, in cents.
  final int perRoundEbitdaCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PartnerEngine &&
        other.defId == defId &&
        other.perRoundEbitdaCents == perRoundEbitdaCents;
  }

  @override
  int get hashCode => Object.hash(defId, perRoundEbitdaCents);

  @override
  String toString() =>
      'PartnerEngine(defId: $defId, perRoundEbitda: $perRoundEbitdaCents)';
}

/// A scheduled (deferred/recurring) cash delta — the engine's slice of
/// doc 02 §1 ScheduledEffect ("the later bill machinery"). Resolved in
/// OPERATE alongside the yield step — see operate.dart step 3c for the
/// documented position vs doc 01 §6.1.
///
/// TWO BASES (schemaVersion 10 — R20b widened this from the v5 fixed-only
/// shape so PLY_EARN_OUT could land its real scheduled drag, doc 02 §3.6):
///   - FIXED ([pctEbitdaBp] == 0): the entry charges [cashDeltaCents] flat
///     each time it fires (a partner fixed cost is negative). This is the v5
///     shape — every existing entry keeps it.
///   - PCT_EBITDA ([pctEbitdaBp] > 0): the entry charges
///     `-trunc(target.ebitda x pctEbitdaBp / 10000)` each fire — a drag that
///     scales with the acquired venture's live earnings (doc 02 §3.6
///     EARN_OUT "pay the seller out of future earnings"). [cashDeltaCents]
///     is ignored for this basis (kept 0). The target is [ventureId].
///
/// LIFETIME — [roundsLeft] (schemaVersion 10):
///   - `< 0` (the sentinel, the v5 default): lives until its [ventureId]
///     leaves play (a partner fixed cost — fires every OPERATE forever while
///     the partner exists). [recurring] must be true with this.
///   - `> 0`: a COUNTDOWN — fires this many more OPERATEs, decrementing each
///     fire, then is removed (an EARN_OUT pays out over exactly N rounds).
///
/// [ventureId] does not target the cash (cash is global); it ties the
/// entry's LIFETIME to a venture: when that venture leaves play, the entry
/// is dropped at the next OPERATE without firing (doc 02 §2 step 5:
/// "recurring entries persist while the partner exists"). null = run-level
/// (only legal for a FIXED, finite-or-once entry — a PCT_EBITDA entry needs
/// a target to read earnings from).
///
/// Value type; replay-relevant, so flatten() serializes each entry.
class ScheduledCost {
  const ScheduledCost({
    required this.ventureId,
    required this.cashDeltaCents,
    required this.recurring,
    this.roundsLeft = -1,
    this.pctEbitdaBp = 0,
  });

  /// The venture this entry's lifetime is tied to (and, for a PCT_EBITDA
  /// basis, the earnings it reads); null = run-level.
  final String? ventureId;

  /// The signed FIXED cash delta in cents applied each fire (a partner fixed
  /// cost is negative). Ignored when [pctEbitdaBp] > 0.
  final int cashDeltaCents;

  /// True = fires every OPERATE while alive (a partner fixed cost, with
  /// [roundsLeft] < 0); false = fires once and is removed. A countdown
  /// ([roundsLeft] > 0) is recurring-until-zero — it carries recurring=true.
  final bool recurring;

  /// Remaining fires: `< 0` = until the [ventureId] leaves play (the v5
  /// sentinel); `> 0` = a countdown decremented each fire (EARN_OUT).
  final int roundsLeft;

  /// PCT-of-target-EBITDA basis in basis points: 0 = FIXED-cash basis
  /// (charge [cashDeltaCents]); > 0 = charge `-trunc(target.ebitda x this /
  /// 10000)` each fire (EARN_OUT, doc 02 §3.6 PCT_EBITDA).
  final int pctEbitdaBp;

  /// Returns a copy with [roundsLeft] replaced (the OPERATE countdown
  /// decrement); all other fields preserved.
  ScheduledCost copyWith({int? roundsLeft}) => ScheduledCost(
        ventureId: ventureId,
        cashDeltaCents: cashDeltaCents,
        recurring: recurring,
        roundsLeft: roundsLeft ?? this.roundsLeft,
        pctEbitdaBp: pctEbitdaBp,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScheduledCost &&
        other.ventureId == ventureId &&
        other.cashDeltaCents == cashDeltaCents &&
        other.recurring == recurring &&
        other.roundsLeft == roundsLeft &&
        other.pctEbitdaBp == pctEbitdaBp;
  }

  @override
  int get hashCode =>
      Object.hash(ventureId, cashDeltaCents, recurring, roundsLeft,
          pctEbitdaBp);

  @override
  String toString() => 'ScheduledCost(ventureId: $ventureId, '
      'cashDelta: $cashDeltaCents, recurring: $recurring, '
      'roundsLeft: $roundsLeft, pctEbitdaBp: $pctEbitdaBp)';
}

/// A deterministic, RNG-FREE flavor name for a venture, seeded from its
/// stable [id] and [sector] (the round-13 venture-display-name layer; R9/R11
/// flagged "V1 vs the mockup's NIMBUS"). Pure: same id+sector ALWAYS yields
/// the same name, so it is replay-stable and golden-pinnable without storing
/// a name on the value type or threading card faces through the action layer
/// (the work order sanctions exactly this "deterministic name function
/// seeded from the venture id + sector" option).
///
/// The pool is per-sector flavor (mockup vocabulary — NIMBUS et al.); the
/// index is a stable, overflow-free code-unit-sum hash of the id (NO
/// `dart:math`, NO `Random` — the purity guard bans both). The canonical
/// seed venture [kSeedVentureId] = `v1` (SOFTWARE) pins deterministically to
/// QUANTA (`('v'+'1') % 5 == 2`). Adding/reordering a pool entry is a
/// display change that moves the golden (flatten serializes the name), so the
/// pools are FROZEN like any golden-pinned table.
String ventureDisplayName(String id, Sector sector) {
  const pools = <Sector, List<String>>{
    Sector.software: ['NIMBUS', 'BYTEFORGE', 'QUANTA', 'HELIX', 'PIXELDYNE'],
    Sector.services: ['MERIDIAN', 'KEYSTONE', 'PROXIMA', 'VANGUARD', 'ATLAS'],
    Sector.retail: ['BAZAAR', 'CARTWHEEL', 'EMPORIA', 'TRENCH', 'KIOSK CO'],
    Sector.industrial: ['IRONWORKS', 'FORGEX', 'TITANCAST', 'BEDROCK', 'MILLHAUS'],
    Sector.consumer: ['LUXE', 'EVERGLOW', 'PANTRY', 'VELVET', 'HEARTH'],
    Sector.media: ['SIGNAL', 'NOVA', 'BROADCAST', 'LUMEN', 'ORACLE'],
  };
  final pool = pools[sector]!;
  var sum = 0;
  for (var i = 0; i < id.length; i++) {
    sum += id.codeUnitAt(i);
  }
  return pool[sum % pool.length];
}

/// An immutable per-venture record of the five resolver inputs that feed the
/// net-worth formula (plus its identity and sector).
///
/// All fields are `final`; mutation happens by producing a new instance via
/// [copyWith]. Value equality is required so the resolver and save layers can
/// compare states.
class Venture {
  const Venture({
    required this.id,
    required this.sector,
    required this.ebitdaCents,
    required this.multipleMilli,
    required this.netDebtCents,
    required this.ownershipBp,
    this.passive = false,
    this.roundsNeglected = 0,
    this.partners = const [],
  });

  /// Stable identifier for this venture (slot/content id).
  final String id;

  /// Which sector this venture belongs to.
  final Sector sector;

  /// EBITDA in integer cents (clamped `>= 0` elsewhere; not enforced here).
  final int ebitdaCents;

  /// Valuation multiple in milli-units (x1000).
  final int multipleMilli;

  /// Net debt in integer cents (may exceed EV, i.e. negative equity is legal).
  final int netDebtCents;

  /// Ownership in basis points (x10000), in the range `0..10000`.
  final int ownershipBp;

  /// True after HIRE_CEO converted this venture to passive (doc 02 §3.10).
  ///
  /// Whitelisted §7 BOOKKEEPING, not a sixth economic input: it selects which
  /// curves apply elsewhere (reduced neglect decay, dampened cash yield in
  /// OPERATE) and is never itself money.
  final bool passive;

  /// Rounds since this venture last received a targeting Act (doc 02 §1).
  ///
  /// Whitelisted §7 BOOKKEEPING (it is a counter, never money) but
  /// REPLAY-RELEVANT: it drives the OPERATE neglect-decay deltas, so the
  /// golden-replay flatten() walker serializes it. Incremented for every
  /// venture at the end of OPERATE step 4; reset to 0 by any apply() action
  /// that targets this venture (doc 02 §2 ACT).
  final int roundsNeglected;

  /// Operating-partner engines hired onto this venture (doc 02 §1
  /// `partners`; §3.5 HIRE_PARTNER pushes here). Direct-assigned (not
  /// wrapped unmodifiable) so `const Venture(...)` stays const; the engine
  /// only ever builds fresh lists — callers must too. Structural-membership
  /// whitelisted under §7 (doc 02 §7: `partners[]` membership) and
  /// REPLAY-RELEVANT (drives every future OPERATE's EBITDA accrual), so
  /// flatten() serializes each engine. LIST ORDER IS PART OF THE REPLAY
  /// CONTRACT.
  final List<PartnerEngine> partners;

  /// The deterministic flavor name for the UI/autopsy (R13; see
  /// [ventureDisplayName]). A GETTER, not a stored field, so it adds nothing
  /// to the constructor / equality / hashCode and can never drift from
  /// id+sector — it is purely derived, exactly like [GameState.netWorthCents].
  /// REPLAY-RELEVANT only in the trivial sense that it is a stable function
  /// of replay-relevant inputs; flatten() serializes it so the golden pins
  /// the naming table (and the §7 invariant whitelists it as the bookkeeping
  /// string it is — never economy).
  String get displayName => ventureDisplayName(id, sector);

  /// Returns a copy with the named fields replaced; all others preserved.
  Venture copyWith({
    String? id,
    Sector? sector,
    int? ebitdaCents,
    int? multipleMilli,
    int? netDebtCents,
    int? ownershipBp,
    bool? passive,
    int? roundsNeglected,
    List<PartnerEngine>? partners,
  }) {
    return Venture(
      id: id ?? this.id,
      sector: sector ?? this.sector,
      ebitdaCents: ebitdaCents ?? this.ebitdaCents,
      multipleMilli: multipleMilli ?? this.multipleMilli,
      netDebtCents: netDebtCents ?? this.netDebtCents,
      ownershipBp: ownershipBp ?? this.ownershipBp,
      passive: passive ?? this.passive,
      roundsNeglected: roundsNeglected ?? this.roundsNeglected,
      partners: partners ?? this.partners,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Venture &&
        other.id == id &&
        other.sector == sector &&
        other.ebitdaCents == ebitdaCents &&
        other.multipleMilli == multipleMilli &&
        other.netDebtCents == netDebtCents &&
        other.ownershipBp == ownershipBp &&
        other.passive == passive &&
        other.roundsNeglected == roundsNeglected &&
        _listEquals(other.partners, partners);
  }

  @override
  int get hashCode => Object.hash(
        id,
        sector,
        ebitdaCents,
        multipleMilli,
        netDebtCents,
        ownershipBp,
        passive,
        roundsNeglected,
        Object.hashAll(partners),
      );

  @override
  String toString() => 'Venture(id: $id, sector: $sector, '
      'ebitda: $ebitdaCents, multiple: $multipleMilli, '
      'netDebt: $netDebtCents, ownership: $ownershipBp, passive: $passive, '
      'roundsNeglected: $roundsNeglected, partners: $partners)';
}

/// A minimal immutable record of something that happened, enough to later
/// render an "autopsy". Shape is intentionally small and excluded from the §7
/// invariant; it will grow as the action/resolver layers land.
class LoggedAction {
  const LoggedAction({required this.round, required this.summary});

  /// The round in which this action occurred.
  final int round;

  /// Human-readable summary of what happened.
  final String summary;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoggedAction &&
        other.round == round &&
        other.summary == summary;
  }

  @override
  int get hashCode => Object.hash(round, summary);

  @override
  String toString() => 'LoggedAction(round: $round, summary: $summary)';
}

/// The immutable game state: the venture slots, the single global cash pool,
/// and bookkeeping fields. Net worth is derived, never stored.
class GameState {
  /// Builds a [GameState]. The [ventures] list is copied into an unmodifiable
  /// list so the slots cannot be mutated in place after construction.
  GameState({
    required List<Venture> ventures,
    required this.cashCents,
    this.rngCursor = 0,
    List<LoggedAction> actionLog = const [],
    this.round = 0,
    this.tier = 1,
    this.schemaVersion = engineSchemaVersion,
    this.rerollsUsed = 0,
    this.market = kOpeningMarket,
    this.phase = PhaseId.act,
    this.playsRemaining = 0,
    this.netWorthAtTierEntry = 0,
    this.netWorthLastRound = 0,
    this.won = false,
    this.death,
    List<String> hand = const [],
    List<String> shopOffers = const [],
    List<String> playsHeld = const [],
    List<ScheduledCost> scheduled = const [],
    this.exitOffer,
    this.backgroundId = kBootstrapperBackgroundId,
    List<String> unlockedCardIds = kDefaultUnlockedCardIds,
    List<Sector> unlockedSectors = kDefaultUnlockedSectors,
  })  : ventures = List.unmodifiable(ventures),
        actionLog = List.unmodifiable(actionLog),
        hand = List.unmodifiable(hand),
        shopOffers = List.unmodifiable(shopOffers),
        playsHeld = List.unmodifiable(playsHeld),
        scheduled = List.unmodifiable(scheduled),
        unlockedCardIds = List.unmodifiable(unlockedCardIds),
        unlockedSectors = List.unmodifiable(unlockedSectors);

  /// The venture SLOTS (1..4). Unmodifiable.
  final List<Venture> ventures;

  /// The ONLY global money quantity, in integer cents. May be negative
  /// (bankruptcy is detected elsewhere; not clamped here).
  final int cashCents;

  // --- Bookkeeping (explicitly NOT gameplay fields) ---

  /// Deterministic RNG cursor position.
  final int rngCursor;

  /// Ordered log of past actions, for the run autopsy. Unmodifiable.
  final List<LoggedAction> actionLog;

  /// Current round number.
  final int round;

  /// Current tier.
  final int tier;

  /// Save-format schema version.
  final int schemaVersion;

  /// Banker-fee rerolls taken this round (doc 02 §3.8; the cost scales off
  /// this upstream). Bookkeeping, not an economic input; DEADLINE_CHECK
  /// resets it to 0 on every round/tier advance (doc 02 §2).
  final int rerollsUsed;

  /// The single global market banner (doc 02 §1). Owned by the OPERATE step;
  /// REPLAY-RELEVANT bookkeeping (its temp/duration/rate steer future draws
  /// and the interest charge), so flatten() serializes every field.
  final MarketState market;

  /// The core-loop phase (doc 02 §2). Defaults to [PhaseId.act] because
  /// every state built directly today is a mid-ACT fixture; the run-init
  /// layer will seed real runs explicitly. Bookkeeping, not an economic
  /// input. The STRICT machine is enforced since the round layer:
  /// `runOperate` requires operate, actions require act (Reroll: act or
  /// shop), `endTurn` requires act, `runDeadlineCheck` requires shop.
  final PhaseId phase;

  /// Throughput left this round (doc 02 §1). Granted by OPERATE as
  /// playsPerRound(tier); every play-costing Act decrements it by 1 on
  /// success (doc 02 §3 matrix — REROLL/PLAY_CONSUMABLE/sell-a-play are
  /// free); DEADLINE_CHECK re-stages it on round/tier advance. Bookkeeping
  /// (doc 02 §5.2.1 whitelists play counters), never money.
  final int playsRemaining;

  /// Mark-to-market net worth in cents captured when the current tier began
  /// (doc 02 §1 RunState baselines). On a DEADLINE_CHECK tier advance this
  /// is the PRE-reseed, bar-clearing net worth — doc 01 §6 keys its
  /// 10x-per-tier growth table off the cleared bar, so the reseed haircut
  /// reads as round-1 pressure, not a moved baseline. WRITE-ONCE-PER-EVENT
  /// SNAPSHOT: one of the two exact names doc 02 §5.1 whitelists
  /// (SCORE_SNAPSHOT_WHITELIST); never read by any card/action/event
  /// resolution path — only the derived ForwardMeters read it.
  final int netWorthAtTierEntry;

  /// Net worth in cents snapshotted at the END of the most recent OPERATE
  /// (doc 02 §2 step 9), for the per-round growth read. Taken on the
  /// bankrupt branch too, so the autopsy can quote it. Same write-once
  /// whitelist rules as [netWorthAtTierEntry] (doc 02 §5.1).
  final int netWorthLastRound;

  /// True once DEADLINE_CHECK cleared the T4 bar (doc 02 §2: TIER_BAR[4]
  /// IS the $1B win bar — there is no separate billion check). Never set in
  /// T5 endless. Bookkeeping.
  final bool won;

  /// Why the run ended; null while the run is alive (and on a win).
  /// TERMINAL: once set it is never cleared — [copyWith] treats a null
  /// argument as "keep" (no engine path ever needs to un-die a run).
  final DeathCause? death;

  // --- The three deal-flow lists (doc 02 §1 RunState) ---
  //
  // DESIGN DECISION (documented per the work order): these hold card IDS
  // (strings), never card objects — the engine REFERENCES content by id and
  // the faces live in ContentDb. That keeps the flatten()/golden
  // serialization compact (one string per slot) and keeps content
  // authoritative: a card's economics can never fork from its id inside a
  // save. All three are REPLAY-RELEVANT bookkeeping (they steer which
  // actions are legal and are golden-pinned as indexed flatten paths
  // hand.0, hand.1, ...); LIST ORDER IS PART OF THE REPLAY CONTRACT.

  /// The deal-flow hand drawn this round (doc 02 §1 `hand`; §Q3 3-5 cards).
  /// Drawn wholesale by OPERATE (doc 03 §3.1 step 1) and by an ACT Reroll;
  /// consumed (removed) by playing a hand card. Unplayed cards expire at
  /// the next draw — the list is REPLACED, never appended.
  final List<String> hand;

  /// The SHOP counter this round (doc 02 §1 `shopOffers`): financing +
  /// consumable offers. Drawn wholesale at endTurn (act -> shop) and by a
  /// SHOP Reroll; consumed by buying a consumable or exercising a
  /// financing offer.
  final List<String> shopOffers;

  /// Held consumable inventory (doc 02 §1 `plays`), capped at
  /// playsHeldMax(tier). Pushed by a SHOP buy; consumed (removed) by
  /// PlayConsumable / SellPlay.
  final List<String> playsHeld;

  /// Deferred/recurring cash deltas (doc 02 §1 `scheduled`, the engine's
  /// minimal slice — see [ScheduledCost]). Pushed by HIRE_PARTNER's
  /// fixed-cost variant (doc 02 §3.5); resolved (and pruned) by OPERATE
  /// step 3c. REPLAY-RELEVANT bookkeeping (each entry is a future cash
  /// charge), so flatten() serializes every entry; LIST ORDER IS PART OF
  /// THE REPLAY CONTRACT. Unmodifiable.
  final List<ScheduledCost> scheduled;

  /// The round's EXIT OFFER ticket (see [ExitOffer]); null = none (no
  /// ventures at the last hand draw, or the offer's venture was exited).
  /// Written by the hand routine (OPERATE step 0 / an ACT Reroll) and
  /// cleared by an EXIT of its venture — §7 deck-like bookkeeping, scoped
  /// exactly like the hand.
  final ExitOffer? exitOffer;

  /// The §Q7 FOUNDER BACKGROUND this run was started with (meta.dart
  /// [kFounderBackgrounds]; defaults to [kBootstrapperBackgroundId]). The
  /// run save has always recorded it in `startConfig.backgroundId`; carrying
  /// it on the state too (schemaVersion 9) lets the ROUND LAYER honor a
  /// background's per-round perk that init can't stage — specifically the
  /// DEALMAKER's +1 play (runOperate / runDeadlineCheck grant
  /// `playsPerRound(tier)` and need to see the background to add the +1).
  /// REPLAY-RELEVANT bookkeeping (it steers the plays grant every round), so
  /// flatten() serializes it; it is access/setup state, never economy, so it
  /// is OUTSIDE the §7 five-input invariant (like the deck lists). initRun
  /// seats it; copyWith preserves it; no action ever changes it mid-run.
  final String backgroundId;

  /// The run's FROZEN-AT-INIT unlocked card ids (schemaVersion 10 —
  /// R20b draw-pool keystone). A per-run snapshot taken from MetaState at
  /// [initRun] time (`baseCurriculumCardIds ∪ meta.unlockedCards`), so the
  /// run's legal draw pool is FIXED at start and replay-stable even though
  /// meta unlocks are cross-run progression (GDD §Q7: unlocks are cross-run
  /// meta, but a single run plays one fixed pool). The deal-flow draw
  /// functions (dealflow.dart handPool/shopPool/eventPool) intersect THIS
  /// set with the in-run `tierGate <= tier` + `sector ∈ unlockedSectors`
  /// gates (doc 04 §0). REPLAY-RELEVANT bookkeeping (it steers every draw),
  /// so flatten() serializes it (sorted, indexed) and the run save's
  /// startConfig carries it (so replayRun reproduces the same pool). Access
  /// state, never economy — OUTSIDE the §7 five-input invariant (like the
  /// deck lists / backgroundId). initRun seats it; copyWith preserves it; no
  /// action ever changes it mid-run.
  final List<String> unlockedCardIds;

  /// The run's FROZEN-AT-INIT unlocked sectors (schemaVersion 10). A per-run
  /// snapshot of MetaState.unlockedSectors at [initRun] time (the base 4,
  /// plus CONSUMER/MEDIA once the game has been beaten). A card whose
  /// `sector` is not in this set is excluded from every draw pool (a
  /// sector-NULL card — partners/financing/most plays — is always sector-
  /// legal). REPLAY-RELEVANT (steers the pool), serialized by flatten() (by
  /// enum `.index`, sorted) + carried in the save's startConfig. Access
  /// state, never economy.
  final List<Sector> unlockedSectors;

  /// DERIVED §7 canonical net worth in integer cents. Getter only — there is
  /// no field and no setter, so it can never be set independently of the
  /// venture data.
  ///
  /// Per venture the basis-point / milli divisions happen LAST, in exactly this
  /// order (canonical; match precisely so a later port stays byte-identical):
  /// ```
  /// ev      = (ebitdaCents * multipleMilli) ~/ 1000;  // enterprise value
  /// equity  = ev - netDebtCents;                       // may be negative
  /// mine    = (equity * ownershipBp) ~/ 10000;         // truncate LAST
  /// ```
  /// Net worth is `sum(mine) + cashCents`.
  ///
  /// The two multiplies route through [satMul] (audit 2026-06-09 M3): a
  /// marathon T5-endless run compounds without a deadline, so the raw
  /// `ebitda * multiple` / `equity * ownership` products are theoretically
  /// unbounded; saturating at ▒[kMaxCents] keeps a huge net worth from
  /// silently WRAPPING to a negative (a false bankruptcy). The cap is four
  /// orders of magnitude above the $1B win bar, so this changes NO in-range
  /// value (the golden replay is byte-unmoved).
  int get netWorthCents {
    var sum = 0;
    for (final v in ventures) {
      final ev = satMul(v.ebitdaCents, v.multipleMilli) ~/ 1000;
      final equity = ev - v.netDebtCents;
      final mine = satMul(equity, v.ownershipBp) ~/ 10000;
      sum += mine;
    }
    return sum + cashCents;
  }

  /// Returns a copy with the named fields replaced; all others preserved.
  ///
  /// [death] is keep-on-null: passing null (or omitting it) preserves the
  /// existing cause — death is terminal, never cleared (see [death]).
  /// [exitOffer] is keep-on-null too; pass [clearExitOffer] to null it
  /// (a venture-less hand draw / an exit of the offered venture).
  GameState copyWith({
    List<Venture>? ventures,
    int? cashCents,
    int? rngCursor,
    List<LoggedAction>? actionLog,
    int? round,
    int? tier,
    int? schemaVersion,
    int? rerollsUsed,
    MarketState? market,
    PhaseId? phase,
    int? playsRemaining,
    int? netWorthAtTierEntry,
    int? netWorthLastRound,
    bool? won,
    DeathCause? death,
    List<String>? hand,
    List<String>? shopOffers,
    List<String>? playsHeld,
    List<ScheduledCost>? scheduled,
    ExitOffer? exitOffer,
    bool clearExitOffer = false,
    String? backgroundId,
    List<String>? unlockedCardIds,
    List<Sector>? unlockedSectors,
  }) {
    return GameState(
      ventures: ventures ?? this.ventures,
      cashCents: cashCents ?? this.cashCents,
      rngCursor: rngCursor ?? this.rngCursor,
      actionLog: actionLog ?? this.actionLog,
      round: round ?? this.round,
      tier: tier ?? this.tier,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      rerollsUsed: rerollsUsed ?? this.rerollsUsed,
      market: market ?? this.market,
      phase: phase ?? this.phase,
      playsRemaining: playsRemaining ?? this.playsRemaining,
      netWorthAtTierEntry: netWorthAtTierEntry ?? this.netWorthAtTierEntry,
      netWorthLastRound: netWorthLastRound ?? this.netWorthLastRound,
      won: won ?? this.won,
      death: death ?? this.death,
      hand: hand ?? this.hand,
      shopOffers: shopOffers ?? this.shopOffers,
      playsHeld: playsHeld ?? this.playsHeld,
      scheduled: scheduled ?? this.scheduled,
      exitOffer: clearExitOffer ? null : (exitOffer ?? this.exitOffer),
      backgroundId: backgroundId ?? this.backgroundId,
      unlockedCardIds: unlockedCardIds ?? this.unlockedCardIds,
      unlockedSectors: unlockedSectors ?? this.unlockedSectors,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameState &&
        _listEquals(other.ventures, ventures) &&
        other.cashCents == cashCents &&
        other.rngCursor == rngCursor &&
        _listEquals(other.actionLog, actionLog) &&
        other.round == round &&
        other.tier == tier &&
        other.schemaVersion == schemaVersion &&
        other.rerollsUsed == rerollsUsed &&
        other.market == market &&
        other.phase == phase &&
        other.playsRemaining == playsRemaining &&
        other.netWorthAtTierEntry == netWorthAtTierEntry &&
        other.netWorthLastRound == netWorthLastRound &&
        other.won == won &&
        other.death == death &&
        _listEquals(other.hand, hand) &&
        _listEquals(other.shopOffers, shopOffers) &&
        _listEquals(other.playsHeld, playsHeld) &&
        _listEquals(other.scheduled, scheduled) &&
        other.exitOffer == exitOffer &&
        other.backgroundId == backgroundId &&
        _listEquals(other.unlockedCardIds, unlockedCardIds) &&
        _listEquals(other.unlockedSectors, unlockedSectors);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(ventures),
        cashCents,
        rngCursor,
        Object.hashAll(actionLog),
        round,
        tier,
        schemaVersion,
        rerollsUsed,
        market,
        phase,
        playsRemaining,
        netWorthAtTierEntry,
        netWorthLastRound,
        won,
        death,
        Object.hashAll(hand),
        Object.hashAll(shopOffers),
        Object.hashAll(playsHeld),
        Object.hashAll(scheduled),
        // exitOffer + backgroundId + the two frozen unlock lists combined
        // into one slot — Object.hash takes at most 20 positional args and
        // the other 19 are already used.
        Object.hash(exitOffer, backgroundId,
            Object.hashAll(unlockedCardIds), Object.hashAll(unlockedSectors)),
      );

  @override
  String toString() => 'GameState(ventures: $ventures, cash: $cashCents, '
      'rngCursor: $rngCursor, round: $round, tier: $tier, '
      'schemaVersion: $schemaVersion, rerollsUsed: $rerollsUsed, '
      'market: $market, phase: $phase, playsRemaining: $playsRemaining, '
      'netWorthAtTierEntry: $netWorthAtTierEntry, '
      'netWorthLastRound: $netWorthLastRound, won: $won, death: $death, '
      'hand: $hand, shopOffers: $shopOffers, playsHeld: $playsHeld, '
      'scheduled: $scheduled, exitOffer: $exitOffer, '
      'backgroundId: $backgroundId, unlockedCardIds: $unlockedCardIds, '
      'unlockedSectors: $unlockedSectors, actionLog: $actionLog)';
}

/// The durable, across-runs META STATE (doc 02 §1 MetaState; GDD §Q7
/// "horizontal only — access, never advantage"). Persisted whole to
/// `meta.json` (docs/06 §2.3), physically separate from the run save so a
/// corrupt mid-run file can never take meta-progression down with it.
///
/// Immutable value type with manual `==`/`hashCode` (dependency-free, like
/// the rest of the package). Lists are copied unmodifiable. NOTHING here is
/// economy — it is unlock/access state plus local-only stats — so MetaState
/// is OUTSIDE the §7 invariant (which guards the run's five economic inputs);
/// it is never part of a GameState and never flattened into the run golden.
/// All mutation is through [meta.dart]'s pure settleRun and unlock helpers.
class MetaState {
  /// Builds a [MetaState]; the five collection fields are copied into
  /// unmodifiable views.
  MetaState({
    this.schemaVersion = engineSchemaVersion,
    this.reputation = 0,
    this.metaLevel = 0,
    this.furthestTierReached = 1, // int (doc 02's Tier 1..5 is a TS alias)
    List<String> unlockedCards = const [],
    List<Sector> unlockedSectors = const [
      Sector.software,
      Sector.services,
      Sector.retail,
      Sector.industrial,
    ],
    List<String> unlockedBackgrounds = const [kBootstrapperBackgroundId],
    List<String> hardModes = const [],
    this.cosmetics = const MetaCosmetics(),
    this.lastDeathCause,
    this.runsPlayed = 0,
    this.cleanExits = 0,
    this.lastSettledRunId,
  })  : unlockedCards = List.unmodifiable(unlockedCards),
        unlockedSectors = List.unmodifiable(unlockedSectors),
        unlockedBackgrounds = List.unmodifiable(unlockedBackgrounds),
        hardModes = List.unmodifiable(hardModes);

  /// On-disk meta schema version (doc 02 §1; the authoritative version for
  /// `meta.json` per docs/06 §2 — the union `SaveFile.schemaVersion` is not
  /// persisted). Migrated additively forward (migrate.dart).
  final int schemaVersion;

  /// Track Record total — REALIZED outcomes only (doc 02 §2; never paper net
  /// worth, never the net worth at death). Settled at RUN_OVER by settleRun.
  final int reputation;

  /// Derived tier of [reputation] that gates unlocks (doc 02 §1). Computed
  /// from reputation by meta.dart's metaLevelFor; stored so the UI reads it
  /// cheaply, recomputed on every settle.
  final int metaLevel;

  /// Furthest tier ever reached — consolation progress even on losses
  /// (doc 02 §1; bumped via max() at RUN_OVER). `int` (1..5); doc 02's
  /// `Tier` is a TypeScript union alias, the engine has always used int.
  final int furthestTierReached;

  /// Archetype/variant defIds available to the deal-flow pool (doc 02 §1).
  final List<String> unlockedCards;

  /// Unlocked sectors (doc 02 §1): the base 4 are always present; CONSUMER /
  /// MEDIA unlock here in a later content drop.
  final List<Sector> unlockedSectors;

  /// Unlocked founder backgrounds (doc 02 §1 / §Q7; each = a difficulty
  /// mode feeding initRun). [kBootstrapperBackgroundId] is always present.
  final List<String> unlockedBackgrounds;

  /// Unlocked hard-mode ids (doc 02 §1).
  final List<String> hardModes;

  /// Cosmetic title ladder + active title + icon skins (doc 02 §1).
  final MetaCosmetics cosmetics;

  /// The opposite-death callback driver (doc 02 §1 §Q5): the cause of the
  /// most recent death, or null on a win / first launch.
  final DeathCause? lastDeathCause;

  /// Lifetime runs completed (doc 02 §1; ++ at every RUN_OVER).
  final int runsPlayed;

  /// Count of CLEAN exits banked across all runs (doc 02 §3.7; the realized
  /// outcomes that fed reputation).
  final int cleanExits;

  /// The idempotency guard for RUN_OVER settlement (docs/06 §5.1): the
  /// runId of the most recently settled run, written inside the same atomic
  /// meta write as the settlement. On boot, a `run.json` whose runId equals
  /// this was already settled and is discarded (no double reputation). null
  /// = nothing settled yet.
  final String? lastSettledRunId;

  /// Returns a copy with the named fields replaced; all others preserved.
  /// [lastDeathCause] and [lastSettledRunId] are keep-on-null — pass the
  /// dedicated `clear...` flags to null them (a win clears neither; both are
  /// only ever advanced, never reset, by settleRun).
  MetaState copyWith({
    int? schemaVersion,
    int? reputation,
    int? metaLevel,
    int? furthestTierReached,
    List<String>? unlockedCards,
    List<Sector>? unlockedSectors,
    List<String>? unlockedBackgrounds,
    List<String>? hardModes,
    MetaCosmetics? cosmetics,
    DeathCause? lastDeathCause,
    bool clearLastDeathCause = false,
    int? runsPlayed,
    int? cleanExits,
    String? lastSettledRunId,
  }) {
    return MetaState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      reputation: reputation ?? this.reputation,
      metaLevel: metaLevel ?? this.metaLevel,
      furthestTierReached: furthestTierReached ?? this.furthestTierReached,
      unlockedCards: unlockedCards ?? this.unlockedCards,
      unlockedSectors: unlockedSectors ?? this.unlockedSectors,
      unlockedBackgrounds: unlockedBackgrounds ?? this.unlockedBackgrounds,
      hardModes: hardModes ?? this.hardModes,
      cosmetics: cosmetics ?? this.cosmetics,
      lastDeathCause:
          clearLastDeathCause ? null : (lastDeathCause ?? this.lastDeathCause),
      runsPlayed: runsPlayed ?? this.runsPlayed,
      cleanExits: cleanExits ?? this.cleanExits,
      lastSettledRunId: lastSettledRunId ?? this.lastSettledRunId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MetaState &&
        other.schemaVersion == schemaVersion &&
        other.reputation == reputation &&
        other.metaLevel == metaLevel &&
        other.furthestTierReached == furthestTierReached &&
        _listEquals(other.unlockedCards, unlockedCards) &&
        _listEquals(other.unlockedSectors, unlockedSectors) &&
        _listEquals(other.unlockedBackgrounds, unlockedBackgrounds) &&
        _listEquals(other.hardModes, hardModes) &&
        other.cosmetics == cosmetics &&
        other.lastDeathCause == lastDeathCause &&
        other.runsPlayed == runsPlayed &&
        other.cleanExits == cleanExits &&
        other.lastSettledRunId == lastSettledRunId;
  }

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        reputation,
        metaLevel,
        furthestTierReached,
        Object.hashAll(unlockedCards),
        Object.hashAll(unlockedSectors),
        Object.hashAll(unlockedBackgrounds),
        Object.hashAll(hardModes),
        cosmetics,
        lastDeathCause,
        runsPlayed,
        cleanExits,
        lastSettledRunId,
      );

  @override
  String toString() => 'MetaState(schemaVersion: $schemaVersion, '
      'reputation: $reputation, metaLevel: $metaLevel, '
      'furthestTierReached: $furthestTierReached, '
      'unlockedCards: $unlockedCards, unlockedSectors: $unlockedSectors, '
      'unlockedBackgrounds: $unlockedBackgrounds, hardModes: $hardModes, '
      'cosmetics: $cosmetics, lastDeathCause: $lastDeathCause, '
      'runsPlayed: $runsPlayed, cleanExits: $cleanExits, '
      'lastSettledRunId: $lastSettledRunId)';
}

/// The cosmetics sub-record of [MetaState] (doc 02 §1): the title ladder,
/// the active title, and icon skins. Pure access state (score-chaser
/// flair), never advantage. Immutable value type.
class MetaCosmetics {
  const MetaCosmetics({
    this.titles = const [],
    this.activeTitle,
    this.iconSkins = const [],
  });

  /// The cosmetic title ladder the player has earned.
  final List<String> titles;

  /// The currently displayed title, or null for none.
  final String? activeTitle;

  /// Unlocked icon skins.
  final List<String> iconSkins;

  /// Returns a copy with the named fields replaced. [activeTitle] is
  /// keep-on-null; pass [clearActiveTitle] to null it.
  MetaCosmetics copyWith({
    List<String>? titles,
    String? activeTitle,
    bool clearActiveTitle = false,
    List<String>? iconSkins,
  }) {
    return MetaCosmetics(
      titles: titles ?? this.titles,
      activeTitle: clearActiveTitle ? null : (activeTitle ?? this.activeTitle),
      iconSkins: iconSkins ?? this.iconSkins,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MetaCosmetics &&
        _listEquals(other.titles, titles) &&
        other.activeTitle == activeTitle &&
        _listEquals(other.iconSkins, iconSkins);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(titles),
        activeTitle,
        Object.hashAll(iconSkins),
      );

  @override
  String toString() => 'MetaCosmetics(titles: $titles, '
      'activeTitle: $activeTitle, iconSkins: $iconSkins)';
}

/// The canonical id of the default founder background (doc 02 §Q7): the
/// current $20k / 100%-own / no-credit / SOFTWARE seed — today's exact
/// $56,000 opening, pinned unchanged. meta.dart owns the full background
/// table; this id lives here because [MetaState] defaults its unlock list
/// to it.
const String kBootstrapperBackgroundId = 'BOOTSTRAPPER';

/// The BASE CURRICULUM card ids — the T1 default-unlock set every fresh run
/// begins with (schemaVersion 10; R20b). This is exactly doc 04 §3's 19-card
/// vertical slice: the curriculum core that is ALWAYS in the draw pool
/// regardless of meta progression (GDD §Q7 "unlock order == curriculum
/// order" — the base layer is the always-on starting curriculum, and meta
/// unlocks WIDEN it). The full unlocked set threaded onto a run is
/// `kDefaultUnlockedCardIds ∪ meta.unlockedCards` (dealflow.runUnlockedCardIds),
/// so a default/new-player meta plays exactly today's slice at T1 and the
/// unlock ladder adds the held-out cards as tiers/rep grow.
///
/// FROZEN like the slice itself (content_lint pins data/cards.json's
/// inVerticalSlice flags to this same 19-card set; the two are the same
/// design object — the default-unlock curriculum). The GameState default
/// uses THIS so a directly-built fixture / a Bootstrapper run is the base
/// pool with no meta wiring.
const List<String> kDefaultUnlockedCardIds = [
  // Ventures (4): one starter per base sector.
  'VEN_SW_GARAGE', 'VEN_SVC_AGENCY', 'VEN_RET_KIOSK', 'VEN_IND_WORKSHOP',
  // Add-ons (3): two same-sector (synergy), one cross (drag).
  'ADD_SW_PLUGIN', 'ADD_SW_MICRO', 'ADD_SVC_TEAM',
  // Partner (1).
  'PRT_SALES_LEAD',
  // Financing (2): dilution + leverage.
  'FIN_SEED_RAISE', 'FIN_TERM_LOAN',
  // Events (3).
  'EVT_SECTOR_BUBBLE', 'EVT_CREDIT_CRUNCH', 'EVT_KEY_CLIENT_LOSS',
  // PLAYS (6).
  'PLY_BRIDGE_LOAN', 'PLY_SECONDARY_SALE', 'PLY_DOWN_ROUND',
  'PLY_DIVIDEND_RECAP', 'PLY_HOT_WINDOW', 'PLY_MARKET_READ',
];

/// The BASE unlocked sectors every fresh run begins with (the v1 four;
/// schemaVersion 10). CONSUMER/MEDIA join only once the game has been beaten
/// (meta.kPostLaunchSectors) and are threaded on per-run via initRun. Mirrors
/// MetaState's own unlockedSectors default.
const List<Sector> kDefaultUnlockedSectors = [
  Sector.software,
  Sector.services,
  Sector.retail,
  Sector.industrial,
];

/// [kDefaultUnlockedCardIds] as a const Set — the default for the
/// dealflow pool helpers' membership test (so a unit test / a Bootstrapper
/// run reads the base curriculum pool with no extra wiring).
const Set<String> kDefaultUnlockedCardIdSet = {
  'VEN_SW_GARAGE', 'VEN_SVC_AGENCY', 'VEN_RET_KIOSK', 'VEN_IND_WORKSHOP',
  'ADD_SW_PLUGIN', 'ADD_SW_MICRO', 'ADD_SVC_TEAM',
  'PRT_SALES_LEAD',
  'FIN_SEED_RAISE', 'FIN_TERM_LOAN',
  'EVT_SECTOR_BUBBLE', 'EVT_CREDIT_CRUNCH', 'EVT_KEY_CLIENT_LOSS',
  'PLY_BRIDGE_LOAN', 'PLY_SECONDARY_SALE', 'PLY_DOWN_ROUND',
  'PLY_DIVIDEND_RECAP', 'PLY_HOT_WINDOW', 'PLY_MARKET_READ',
};

/// [kDefaultUnlockedSectors] as a const Set (the pool helper default).
const Set<Sector> kDefaultUnlockedSectorSet = {
  Sector.software,
  Sector.services,
  Sector.retail,
  Sector.industrial,
};

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
