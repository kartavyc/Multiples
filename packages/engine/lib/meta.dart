/// META LAYER — the durable, across-runs progression logic (doc 02 §1
/// MetaState, §2 RUN_OVER settlement, §3.7 clean-exit / reputation, §Q7
/// founder backgrounds). Pure: no I/O, no clock, no float, no RNG — exactly
/// like the rest of the engine. The app does the file I/O (docs/06 §6); this
/// file owns the LOGIC (settle, reputation, metaLevel, background opening
/// variants, the double-settle guard).
///
/// What lives here:
///   - [FounderBackground] + [kFounderBackgrounds]: the §Q7 backgrounds, each
///     a startConfig variant feeding initRun (perk + matching constraint).
///   - [RunOutcomes]: the run-local tally of REALIZED outcomes (exits,
///     secondaries, dividends) the caller accumulates AS THEY HAPPEN so the
///     data exists at RUN_OVER without a counterfactual re-sim (doc 02 §2).
///   - [reputationFromOutcomes]: the doc 02 §2 realized-outcomes-only
///     reputation formula (paper net worth NEVER counts).
///   - [metaLevelFor]: the derived reputation tier that gates unlocks.
///   - [settleRun]: the strict doc 02 §2 RUN_OVER sequence with the docs/06
///     §5.1 lastSettledRunId double-settle guard (idempotent).
///
/// Pure and dependency-free except for sibling engine libraries (only
/// `dart:core`).
library;

import 'model.dart';
import 'money.dart';

// ===========================================================================
// §Q7 FOUNDER BACKGROUNDS
// ===========================================================================

/// A founder background (doc 02 §1 backgroundId / §Q7): the run's starting
/// posture. Each is a horizontal variant — a different OPENING and a matching
/// CONSTRAINT, never a flat power boost (GDD §Q7 "access, never advantage").
/// initRun consumes [id] to build the opening; the numeric perk/constraint
/// fields are the dials documented in [kFounderBackgrounds].
///
/// The opening is expressed as DELTAS off the canonical Bootstrapper base
/// (the economy-model.json constants), so the Bootstrapper itself is the
/// all-zero variant and stays byte-identical to today's $56k seed.
class FounderBackground {
  const FounderBackground({
    required this.id,
    required this.label,
    required this.blurb,
    this.startCashDeltaCents = 0,
    this.startOwnershipBpOverride,
    this.extraPlaysPerRound = 0,
    this.grantsFoundingPartner = true,
    this.bonusPartnerEbitdaCents = 0,
  });

  /// Stable id (the persisted startConfig.backgroundId; serialize.dart).
  final String id;

  /// Short UI label (the S9 Desk / run-setup screen reads it; R14).
  final String label;

  /// One-line perk/constraint description for the UI.
  final String blurb;

  /// Cash added to (or removed from) the Bootstrapper $20k pocket, in cents.
  final int startCashDeltaCents;

  /// OPTIONAL starting-ownership override of the seed venture, bp; null =
  /// use the economy's `startOwnership` (Bootstrapper keeps the economy
  /// default, so initRun stays economy-generic). VC Darling pre-dilutes
  /// below 100% by setting this.
  final int? startOwnershipBpOverride;

  /// Extra plays granted EVERY round on top of playsPerRound(tier)
  /// (Dealmaker's perk; the round layer adds this when staging plays — R14
  /// wires it, the dial lives here). 0 for most.
  final int extraPlaysPerRound;

  /// Whether the seed venture carries the founding-operator partner (doc 01
  /// §3.2). Always true today (organic growth attribution needs it); kept as
  /// a dial so a future "no partner" hard mode can flip it.
  final bool grantsFoundingPartner;

  /// EXTRA per-round +EBITDA on the seed venture's starting partner, cents
  /// (Operator's "free starting partner" perk — a non-zero founding engine).
  final int bonusPartnerEbitdaCents;
}

/// The canonical founder-background table (§Q7). NUMBERS ARE TUNING DIALS
/// (sane integers, not canon — economy-model.json's outOfScope block leaves
/// backgrounds unspecified). Each cites its perk + matching constraint:
///
///   BOOTSTRAPPER — the default. $20k, 100% own, no credit, the lone seed
///     venture. ZERO deltas: this IS today's pinned $56,000 seed (the
///     golden + initRun pin it). Perk: none. Constraint: none — the
///     baseline everything else is measured against.
///   OPERATOR — "you bring a team, not a war chest." Perk: a FREE starting
///     operating partner (+$1,500/round EBITDA on the seed venture, i.e. a
///     real founding engine instead of the 0-face one). Constraint: -$8,000
///     starting cash (you spent it hiring the team).
///   VC_DARLING — "termsheet in hand, cap table already carved up." Perk:
///     +$60,000 starting cash (a fat seed round). Constraint: pre-diluted
///     to 80% ownership (the VCs took 20% before you began).
///   DEALMAKER — "you live on the phone; more shots per round." Perk: +1
///     PLAY every round (extra throughput). Constraint: -$6,000 starting
///     cash (you over-extend on optionality).
const List<FounderBackground> kFounderBackgrounds = [
  FounderBackground(
    id: kBootstrapperBackgroundId,
    label: 'BOOTSTRAPPER',
    blurb: '\$20k, 100% yours, no credit. The lean climb.',
    // All zeros — the pinned $56,000 seed.
  ),
  FounderBackground(
    id: 'OPERATOR',
    label: 'OPERATOR',
    blurb: 'A free operating partner; \$8k lighter on cash.',
    startCashDeltaCents: -800000,
    bonusPartnerEbitdaCents: 150000,
  ),
  FounderBackground(
    id: 'VC_DARLING',
    label: 'VC DARLING',
    blurb: '+\$60k seed round, but pre-diluted to 80%.',
    startCashDeltaCents: 6000000,
    startOwnershipBpOverride: 8000,
  ),
  FounderBackground(
    id: 'DEALMAKER',
    label: 'DEALMAKER',
    blurb: '+1 play every round; \$6k lighter on cash.',
    startCashDeltaCents: -600000,
    extraPlaysPerRound: 1,
  ),
];

/// Looks up a background by [id]; falls back to the BOOTSTRAPPER default for
/// an unknown id (a forward-compat save from a build that knew a background
/// this one does not — never crash the run loader; docs/06 forward-only).
FounderBackground backgroundFor(String id) {
  for (final b in kFounderBackgrounds) {
    if (b.id == id) return b;
  }
  return kFounderBackgrounds.first; // BOOTSTRAPPER
}

// ===========================================================================
// REALIZED-OUTCOME TALLY + REPUTATION (doc 02 §2, §3.7)
// ===========================================================================

/// A single realized EXIT's reputation inputs (doc 02 §3.7), captured by the
/// caller at exit time from the EXIT_REALIZED event + the pre-exit venture.
/// All integer fixed-point.
class ExitOutcome {
  const ExitOutcome({
    required this.proceedsCents,
    required this.exitMultipleMilli,
    required this.sectorNormMilli,
    required this.ownershipBp,
    required this.clean,
  });

  /// Cash banked by the exit (the EXIT_REALIZED amount).
  final int proceedsCents;

  /// The exit multiple actually realized, milli.
  final int exitMultipleMilli;

  /// The sector's normalization multiple, milli ([sectorNormMilli] — the
  /// sector base, so a fair-priced exit scores its proceeds 1:1).
  final int sectorNormMilli;

  /// Ownership at exit, bp (the realized stake; dilution already counts).
  final int ownershipBp;

  /// Whether this met the CLEAN_EXIT rule (doc 02 §3.7: equity > 0 AND
  /// exitMultiple >= [kCleanExitMinMultipleMilli]). A fire-sale banks cash
  /// but earns NO reputation and is not counted in cleanExits.
  final bool clean;
}

/// The run-local tally of REALIZED outcomes (doc 02 §2): the ONLY three
/// reputation contributors — clean exits, secondary-sale proceeds, and
/// dividend cash actually banked. Accumulated by the caller AS the events
/// fire (so RUN_OVER needs no re-sim); paper net worth is never in here.
///
/// Immutable; build it up with the `with...` copy helpers (the app folds
/// EXIT_REALIZED / dividendRecap / secondary events into it).
class RunOutcomes {
  RunOutcomes({
    List<ExitOutcome> exits = const [],
    this.secondaryProceedsCents = 0,
    this.dividendBankedCents = 0,
  }) : exits = List.unmodifiable(exits);

  /// Every realized exit this run (clean and fire-sale alike; the clean
  /// flag inside each decides reputation + the cleanExits count).
  final List<ExitOutcome> exits;

  /// Total secondary-sale proceeds banked this run, cents (doc 02 §3.6
  /// PLY_SECONDARY_SALE — the per-kind resolver is future work, but the
  /// reputation channel is live).
  final int secondaryProceedsCents;

  /// Total dividend-recap cash actually banked this run, cents (doc 01 §7.7;
  /// the realized cash, not the paper EV).
  final int dividendBankedCents;

  /// Count of CLEAN exits (doc 02 §3.7) — what feeds meta.cleanExits.
  int get cleanExitCount => exits.where((e) => e.clean).length;

  /// Returns a copy with [exit] appended.
  RunOutcomes withExit(ExitOutcome exit) => RunOutcomes(
        exits: [...exits, exit],
        secondaryProceedsCents: secondaryProceedsCents,
        dividendBankedCents: dividendBankedCents,
      );

  /// Returns a copy with [cents] added to the secondary-sale total.
  RunOutcomes withSecondary(int cents) => RunOutcomes(
        exits: exits,
        secondaryProceedsCents: secondaryProceedsCents + cents,
        dividendBankedCents: dividendBankedCents,
      );

  /// Returns a copy with [cents] added to the dividend-banked total.
  RunOutcomes withDividend(int cents) => RunOutcomes(
        exits: exits,
        secondaryProceedsCents: secondaryProceedsCents,
        dividendBankedCents: dividendBankedCents + cents,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RunOutcomes ||
        other.secondaryProceedsCents != secondaryProceedsCents ||
        other.dividendBankedCents != dividendBankedCents ||
        other.exits.length != exits.length) {
      return false;
    }
    for (var i = 0; i < exits.length; i++) {
      final a = exits[i];
      final b = other.exits[i];
      if (a.proceedsCents != b.proceedsCents ||
          a.exitMultipleMilli != b.exitMultipleMilli ||
          a.sectorNormMilli != b.sectorNormMilli ||
          a.ownershipBp != b.ownershipBp ||
          a.clean != b.clean) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(exits.map((e) => Object.hash(e.proceedsCents,
            e.exitMultipleMilli, e.sectorNormMilli, e.ownershipBp, e.clean))),
        secondaryProceedsCents,
        dividendBankedCents,
      );
}

/// CLEAN_EXIT minimum multiple, milli (doc 02 §3.7 / §4 CLEAN_EXIT_MIN_MULTIPLE
/// — declared but UNSET in the docs; 2.0x is a TUNING DIAL: below a 2x exit
/// the deal is a flip, not a "clean" outcome worth reputation).
const int kCleanExitMinMultipleMilli = 2000;

/// Reputation per cent of secondary proceeds, bp (doc 02 §4 REP_SECONDARY_BP
/// — UNSET in the docs; 50% TUNING DIAL).
const int kRepSecondaryBp = 5000;

/// Reputation per cent of dividend banked, bp (doc 02 §4 REP_DIVIDEND_BP —
/// UNSET; 25% TUNING DIAL, lower than exits because recap cash is
/// debt-funded paper-to-pocket, not a true realization).
const int kRepDividendBp = 2500;

/// The sector normalization multiple (milli) used by [reputationFromOutcomes]
/// (doc 02 §2 sectorNorm): the sector BASE multiple, so a fair-priced exit
/// (exitMultiple == sectorNorm) scores its proceeds 1:1 and a bubble exit
/// scores proportionally more. Mirrors data/economy-model.json sectors[]
/// baseMultiple / docs/01 §4 (SOFTWARE 14x, SERVICES 5x, RETAIL 3x,
/// INDUSTRIAL 8x). A small TABLE the caller can also read to build
/// [ExitOutcome.sectorNormMilli].
int sectorNormMilli(Sector sector) {
  switch (sector) {
    case Sector.software:
      return 14000;
    case Sector.services:
      return 5000;
    case Sector.retail:
      return 3000;
    case Sector.industrial:
      return 8000;
    // Post-launch sectors (GDD §8 Q6): CONSUMER 6x steady brand-y mid;
    // MEDIA 16x SOFTWARE++. Mirrors data/economy-model.json sectors[].
    case Sector.consumer:
      return 6000;
    case Sector.media:
      return 16000;
  }
}

/// The doc 02 §2 realized-outcomes-only reputation for one run's [outcomes]
/// — PAPER NET WORTH NEVER COUNTS. All integer fixed-point, divisions last:
///
///   repFromExit      = mulBp(mulBp(proceeds, exitMul*10000/sectorNorm),
///                            ownershipBp)   — per CLEAN exit only
///   repFromSecondary = mulBp(secondaryProceeds, kRepSecondaryBp)
///   repFromDividend  = mulBp(dividendBanked,     kRepDividendBp)
///
/// The exit term is the doc's `mulBp(exitProceeds, trunc(exitMultiple *
/// 10000 / sectorNorm)) scaled by ownership-at-exit`: the inner factor
/// rewards selling ABOVE the sector norm (timing the bubble), and the
/// ownership scale means dilution costs reputation, not just net worth.
/// Fire-sale exits (clean == false) contribute nothing.
int reputationFromOutcomes(RunOutcomes outcomes) {
  var rep = 0;
  for (final e in outcomes.exits) {
    if (!e.clean) continue;
    // factor_bp = exitMultiple * 10000 / sectorNorm (a fair exit -> 10000).
    final factorBp = (e.exitMultipleMilli * 10000) ~/ e.sectorNormMilli;
    final beforeOwnership = mulBp(e.proceedsCents, factorBp);
    rep += mulBp(beforeOwnership, e.ownershipBp);
  }
  rep += mulBp(outcomes.secondaryProceedsCents, kRepSecondaryBp);
  rep += mulBp(outcomes.dividendBankedCents, kRepDividendBp);
  return rep;
}

/// `mulBp` (doc 02 §0.7 the canonical fixed-point scaler): the ONLY way
/// reputation money is multiplied. trunc(amount * factorBp / 10000).
int mulBp(int amountCents, int factorBp) =>
    truncDiv(amountCents * factorBp, 10000);

// ===========================================================================
// META LEVEL (the unlock-gating reputation tier)
// ===========================================================================

/// The reputation thresholds (cumulative; cents-scaled reputation) that
/// raise [metaLevelFor]. TUNING DIALS: a slow ladder so unlocks pace across
/// many runs. Level = number of crossed thresholds.
const List<int> kMetaLevelThresholds = [
  500000, // L1
  2000000, // L2
  5000000, // L3
  15000000, // L4
  50000000, // L5
];

/// The derived meta level for a [reputation] total (doc 02 §1 metaLevel —
/// "derived tier of reputation, gates unlocks"). Pure step function over
/// [kMetaLevelThresholds]; 0 below the first threshold.
int metaLevelFor(int reputation) {
  var level = 0;
  for (final t in kMetaLevelThresholds) {
    if (reputation >= t) {
      level++;
    } else {
      break;
    }
  }
  return level;
}

// ===========================================================================
// THE UNLOCK LADDER (GDD §Q7: "access, never advantage";
//   "unlock order == curriculum order")
// ===========================================================================
//
// Reputation buys ACCESS — never numeric advantage. Three things carry
// (GDD §Q7): (1) reputation + meta-level, (2) the unlocked card/sector pool,
// (3) backgrounds + hard modes. Concept-unlocks gate to TIER MILESTONES so
// the curriculum order is the unlock order:
//
//   reach T2  -> the RAISE/operating deck   (dilution, fixed-cost partners,
//                bigger platforms, cross-sector add-ons) + the OPERATOR bg
//   reach T3  -> the EXIT/EMPIRE deck        (vertical integration, refi,
//                spin-off, earn-out)         + the VC_DARLING bg
//   reach T4  -> the ACQUIRER/LBO deck       (the LBO facility) + DEALMAKER bg
//   BEAT GAME -> Endless + the Hard Modes    + the 2 post-launch SECTORS
//                (CONSUMER, MEDIA)
//
// EVERY tier stays beatable with only the prior tier's tools — these decks
// are EXPRESSION, never prerequisites (GDD §Q7 / doc 04 §0). The card-id
// decks below are the held-out-of-slice cards from doc 04 §1, grouped by
// their authored tierGate; the engine's draw pool intersects the unlocked
// set with the slice base (the always-on T1 curriculum core).

/// The RAISE / operating deck — unlocked on reaching Tier 2 (the dilution
/// wall + operating partners; doc 04 §1 tierGate-2 expression cards). These
/// are exactly the gate-2 held-out cards plus the gate-2 platform/add-on.
const List<String> kTier2UnlockCards = [
  'VEN_SW_PLATFORM', // the ideal roll-up base
  'ADD_RET_STORES', // cross-sector cash-rich trap
  'PRT_COO_FIXED', // operating leverage (fixed-cost partner)
  'PRT_GROWTH_HACKER', // a sliver of story
  'FIN_GROWTH_RAISE', // the deeper raise
  'EVT_SUPPLY_SHOCK', // the industrial wobble event
  'PLY_TENDER', // anti-dilution
  'PLY_ASSET_STRIP', // liquidity at an earnings cost
];

/// The EXIT / EMPIRE deck — unlocked on reaching Tier 3 (the exit-serial vs
/// empire fork; doc 04 §1 tierGate-3 cards).
const List<String> kTier3UnlockCards = [
  'ADD_IND_SUPPLIER', // same-sector vertical integration
  'FIN_REFI', // the survival move
  'PLY_SPIN_OFF', // unbundle the empire
  'PLY_EARN_OUT', // $0-down, scheduled drag
];

/// The ACQUIRER / LBO deck — unlocked on reaching Tier 4 ("you become the
/// money"; doc 04 §1 tierGate-4).
const List<String> kTier4UnlockCards = [
  'FIN_LBO_LOAN', // the LBO lever
];

/// The two POST-LAUNCH sectors (GDD §8 Q6 / doc 04 note), unlocked on
/// beating the game. CONSUMER = a steady brand-y mid-multiple; MEDIA =
/// SOFTWARE++ (high multiple, high vol). Their economy bands live in
/// data/economy-model.json sectors[]; here they are the unlock SET.
const List<Sector> kPostLaunchSectors = [Sector.consumer, Sector.media];

/// The Hard Mode ids unlocked on beating the game (GDD §Q7 "Hard Modes"):
/// horizontal difficulty variants, never power. Stable ids the run-setup UI
/// reads (each maps to a future founder-background-style constraint stack).
const List<String> kBeatGameHardModes = ['IRONMAN', 'COLD_OPEN', 'NO_CREDIT'];

/// The background ids gated behind tier milestones (the §Q7 backgrounds are
/// difficulty modes, so they gate to the curriculum like the decks):
///   OPERATOR    @ T2  — a team instead of a war chest
///   VC_DARLING  @ T3  — a carved-up cap table
///   DEALMAKER   @ T4  — more shots per round
/// BOOTSTRAPPER is always unlocked (the forgiving default).
const String kOperatorBackgroundId = 'OPERATOR';
const String kVcDarlingBackgroundId = 'VC_DARLING';
const String kDealmakerBackgroundId = 'DEALMAKER';

/// The COSMETIC TITLE LADDER (GDD §Q7 "a cosmetic title ladder"): one title
/// per crossed meta level, purely flair (score-chaser vanity), NEVER
/// advantage. Index i is earned at metaLevel i+1 (level 0 has no title).
const List<String> kTitleLadder = [
  'ANALYST', // L1
  'ASSOCIATE', // L2
  'PRINCIPAL', // L3
  'PARTNER', // L4
  'KINGMAKER', // L5
];

/// The cosmetic titles earned for a given [metaLevel] (the first [metaLevel]
/// entries of [kTitleLadder]; clamped to the ladder length).
List<String> titlesForLevel(int metaLevel) {
  final n = metaLevel < kTitleLadder.length ? metaLevel : kTitleLadder.length;
  return kTitleLadder.sublist(0, n < 0 ? 0 : n);
}

/// Re-derives the full unlock state for [meta] from its progress signals —
/// the curriculum-order ladder above. PURE and IDEMPOTENT: it only ever
/// ADDS to the unlock sets (access never regresses), so calling it twice is
/// a no-op and a save from an older build is upgraded forward.
///
/// [gameBeaten] is the persistent "has the player ever won?" signal; since
/// MetaState has no dedicated flag, the caller passes
/// `finishedRun.won || already-has-an-Endless-unlock` (settleRun does this),
/// so the beat-game tier stays unlocked once earned.
///
/// Unlock sources:
///   - cards/backgrounds gate off `meta.furthestTierReached`
///   - sectors/hardModes/endless gate off [gameBeaten]
///   - cosmetic titles gate off `meta.metaLevel`
/// Reputation/meta-level themselves are NOT changed here (settleRun owns
/// them); this turns the already-updated progress into access.
MetaState applyUnlocks(MetaState meta, {required bool gameBeaten}) {
  final cards = <String>{...meta.unlockedCards};
  final backgrounds = <String>{...meta.unlockedBackgrounds};
  final sectors = <Sector>{...meta.unlockedSectors};
  final hardModes = <String>{...meta.hardModes};

  final tier = meta.furthestTierReached;
  if (tier >= 2) {
    cards.addAll(kTier2UnlockCards);
    backgrounds.add(kOperatorBackgroundId);
  }
  if (tier >= 3) {
    cards.addAll(kTier3UnlockCards);
    backgrounds.add(kVcDarlingBackgroundId);
  }
  if (tier >= 4) {
    cards.addAll(kTier4UnlockCards);
    backgrounds.add(kDealmakerBackgroundId);
  }
  if (gameBeaten) {
    sectors.addAll(kPostLaunchSectors);
    hardModes.addAll(kBeatGameHardModes);
  }

  // Stable ORDER: cards in curriculum order, sectors in enum order,
  // backgrounds in table order — so the unlock sets are deterministic
  // regardless of insertion sequence (the save round-trips identically and
  // the §invariant has no churn).
  final cardOrder = <String>[
    ...kTier2UnlockCards,
    ...kTier3UnlockCards,
    ...kTier4UnlockCards,
  ];
  final orderedCards = [
    for (final id in cardOrder)
      if (cards.contains(id)) id,
  ];
  final orderedBackgrounds = [
    for (final b in kFounderBackgrounds)
      if (backgrounds.contains(b.id)) b.id,
  ];
  final orderedSectors = [
    for (final s in Sector.values)
      if (sectors.contains(s)) s,
  ];
  final orderedHardModes = [
    for (final h in kBeatGameHardModes)
      if (hardModes.contains(h)) h,
  ];

  return meta.copyWith(
    unlockedCards: orderedCards,
    unlockedBackgrounds: orderedBackgrounds,
    unlockedSectors: orderedSectors,
    hardModes: orderedHardModes,
    cosmetics: meta.cosmetics.copyWith(titles: titlesForLevel(meta.metaLevel)),
  );
}

/// Whether Endless mode is available — the beat-game gate (GDD §Q7). Derived
/// (not stored): true once the post-launch sectors are unlocked, which only
/// [applyUnlocks] grants on a win. Keeps "beat game" persistent without a
/// dedicated flag.
bool endlessUnlocked(MetaState meta) =>
    kPostLaunchSectors.every(meta.unlockedSectors.contains);

// ===========================================================================
// RUN_OVER SETTLEMENT (doc 02 §2 + docs/06 §5.1)
// ===========================================================================

/// Settles a finished run into the meta save (doc 02 §2 RUN_OVER, the strict
/// sequence; docs/06 §5.1 the double-settle guard). PURE — the app does the
/// atomic write afterwards.
///
/// [finishedRun] is the terminal GameState (won or dead; the caller asserts
/// phase == runOver). [runId] is the run's id (serialize.dart derives it
/// from the seed). [outcomes] is the run-local realized-outcome tally the
/// caller accumulated as exits/secondaries/dividends fired.
///
/// SEQUENCE (doc 02 §2, in order; the autopsy is built by the app from the
/// step log, step 1, before this is called):
///   (idempotency) if runId == meta.lastSettledRunId -> this run was already
///     settled (a mid-settlement crash left an orphan run.json, docs/06
///     §5.1): return meta UNCHANGED. Reputation is committed exactly once.
///   (2) reputation += reputationFromOutcomes(outcomes)  [realized only]
///   (2') metaLevel = metaLevelFor(new reputation)
///   (3) furthestTierReached = max(meta.furthestTierReached, finishedRun.tier)
///   (4) lastDeathCause = finishedRun.death (null on a win — the run won, it
///       did not die); runsPlayed += 1; cleanExits += outcomes.cleanExitCount
///   (5.1) lastSettledRunId = runId  (the guard, written in the same value)
/// The on-disk `run = null` + delete happen in the app AFTER this returns
/// and the meta is durably written (docs/06 §5.1 ordering).
MetaState settleRun(
  MetaState meta, {
  required GameState finishedRun,
  required String runId,
  RunOutcomes? outcomes,
}) {
  // Idempotency guard (docs/06 §5.1): never settle the same run twice.
  if (meta.lastSettledRunId == runId) return meta;

  final tally = outcomes ?? RunOutcomes();
  final newReputation = meta.reputation + reputationFromOutcomes(tally);
  final tier = finishedRun.tier;
  // Steps 2-5.1: update the progress signals (rep/level/tier/death/counts).
  final progressed = meta.copyWith(
    reputation: newReputation,
    metaLevel: metaLevelFor(newReputation),
    furthestTierReached:
        tier > meta.furthestTierReached ? tier : meta.furthestTierReached,
    // A win clears no death; a death records its cause. Either way this is
    // the LAST outcome (doc 02 §1 §Q5 opposite-death callback).
    lastDeathCause: finishedRun.death,
    clearLastDeathCause: finishedRun.death == null,
    runsPlayed: meta.runsPlayed + 1,
    cleanExits: meta.cleanExits + tally.cleanExitCount,
    lastSettledRunId: runId,
  );
  // Step 6 (R17 — the §Q7 ladder): turn the updated progress into ACCESS.
  // gameBeaten is persistent: this run's win OR an Endless unlock already
  // earned on a prior run. applyUnlocks is additive (access never regresses)
  // and idempotent, so the double-settle guard above still makes settling
  // twice a clean no-op.
  final gameBeaten = finishedRun.won || endlessUnlocked(meta);
  return applyUnlocks(progressed, gameBeaten: gameBeaten);
}
