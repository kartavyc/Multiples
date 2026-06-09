/// RUN INIT — `initRun(economy: ...)` builds the canonical opening
/// [GameState] for a fresh run from economy-model.json's `constants` block
/// (the STATE.md "run-init layer" hook): $20k pocket cash plus one
/// 100%-owned, debt-free SOFTWARE venture ($6k EBITDA at the LOW 6x seed
/// multiple — NOT the 14x sector base; the JSON `_note` is explicit), for
/// the contractual $56k seed net worth doc 01 §6 keys Tier 1 off.
///
/// Opening shape (doc 02 §2: the run starts at the top of the loop):
///   - round 1, tier 1, `phase == OPERATE` — the first OPERATE is the
///     run's first step; it draws the first hand (doc 03 §3.1 step 1),
///     rolls the market, and grants the round's plays. initRun itself
///     stages NOTHING (playsRemaining 0, rerollsUsed 0).
///   - `market == kOpeningMarket` (NEUTRAL, round 1 of 2, rate not yet
///     drawn — model.dart documents the choice).
///   - `hand`/`shopOffers`/`playsHeld` EMPTY: decks are drawn by the steps
///     that own them (OPERATE / endTurn), never by init.
///   - the two doc 02 §5.1 snapshots (`netWorthAtTierEntry`,
///     `netWorthLastRound`) seed at the DERIVED opening net worth, so the
///     T1 growth meters read the $56k baseline before the first OPERATE.
///
/// Design decisions (documented per the work order):
///   - initRun takes the typed [EconomyConfig] (the work order sketched
///     "ContentDb"; the opening state is fully determined by the economy
///     CONSTANTS, which parse into EconomyConfig — the card database enters
///     the engine at the draw functions instead, so a ContentDb parameter
///     here would be dead weight).
///   - initRun draws NOTHING and takes no RNG — per the package convention
///     the caller owns the SplitMix64Rng and passes it to the functions
///     that consume the stream (`runOperate`, `endTurn`, `apply`). The run
///     SEED itself is save-layer state (doc 02 §1 RngState), not engine
///     state; the engine only mirrors the cursor.
///   - the seed venture id is the deterministic [kSeedVentureId] — the
///     engine does not mint ids (actions.dart convention), and a fixed id
///     keeps the golden replay and save format stable.
///
/// Pure and dependency-free except for sibling engine libraries (only
/// `dart:core`).
library;

import 'content.dart';
import 'meta.dart';
import 'model.dart';

/// The deterministic id of the run's seed venture (see the library header).
const String kSeedVentureId = 'v1';

/// The FOUNDING OPERATOR (doc 01 §3.2): the "default starting operating
/// partner" every run begins with, attached to the seed venture as a
/// 0-face [PartnerEngine]. Its entire effect is the organic-growth
/// attribution — doc 01 §3.2's organicGrowthDefault (0.10/round) applies
/// to PARTNERED ventures only ("attributed to the seed partner every run
/// and to any hired partner; a venture with no partner gets 0"), so the
/// seed venture must actually carry its seed partner. NOT a content-DB
/// card id by design: no card deals it, the engine owns it (landed in the
/// R12 balance round; operate.dart step 3a applies the growth).
const String kFoundingPartnerDefId = 'PRT_FOUNDING_OPERATOR';

/// Builds the canonical opening state for a fresh run (library header =
/// the full contract) from [economy]'s `constants` block, posed by the
/// chosen founder background (§Q7; [backgroundId] defaults to
/// [kBootstrapperBackgroundId] = today's EXACT pinned $56,000 seed — the
/// Bootstrapper background is the all-zero variant, so an unqualified
/// `initRun(economy:)` is byte-identical to before the R13 background layer).
///
/// The background (meta.dart [kFounderBackgrounds]) supplies deltas off the
/// Bootstrapper base: a starting-cash delta, the seed-venture ownership, and
/// the founding partner's per-round +EBITDA (Operator's "free starting
/// partner" perk). The Dealmaker's +1-play perk is staged by the round layer
/// each round (the dial is on the background; R14 wires the grant), not at
/// init — initRun stages NO plays for ANY background (playsRemaining 0).
GameState initRun({
  required EconomyConfig economy,
  String backgroundId = kBootstrapperBackgroundId,
  List<String> unlockedCardIds = kDefaultUnlockedCardIds,
  List<Sector> unlockedSectors = kDefaultUnlockedSectors,
}) {
  final c = economy.constants;
  final bg = backgroundFor(backgroundId);
  final ventures = [
    Venture(
      id: kSeedVentureId,
      sector: c.startSector,
      ebitdaCents: c.startEbitdaCents,
      multipleMilli: c.startMultipleMilli,
      netDebtCents: c.startNetDebtCents,
      // Background ownership: the economy default unless the background
      // pre-dilutes (VC Darling). Bootstrapper's null override keeps initRun
      // economy-generic (a custom economy's startOwnership flows through).
      ownershipBp: bg.startOwnershipBpOverride ?? c.startOwnershipBp,
      // The founding operating partner (doc 01 §3.2; see
      // kFoundingPartnerDefId): a 0-face engine whose presence attributes
      // the organicGrowthDefault compounding to the seed venture — UNLESS
      // the background grants a real founding partner (Operator's perk:
      // bonusPartnerEbitdaCents). Bootstrapper keeps it 0-face (pinned).
      partners: bg.grantsFoundingPartner
          ? [
              PartnerEngine(
                defId: kFoundingPartnerDefId,
                perRoundEbitdaCents: bg.bonusPartnerEbitdaCents,
              ),
            ]
          : const [],
    ),
  ];
  // Derive the opening net worth ONCE for the two §5.1 snapshots; the
  // state's own netWorthCents getter recomputes the same value.
  final state = GameState(
    ventures: ventures,
    cashCents: c.startCashCents + bg.startCashDeltaCents,
    round: 1,
    tier: 1,
    phase: PhaseId.operate,
    market: kOpeningMarket,
    // Carry the chosen background on the run state (schemaVersion 9) so the
    // round layer can honor its per-round perk (the Dealmaker +1 play).
    backgroundId: backgroundId,
    // FREEZE the run's draw-pool unlock set (schemaVersion 10): a per-run
    // snapshot so the legal pool is fixed at start and replay-stable. The
    // caller passes `dealflow.runUnlockedCardIds(meta, content)` ∪ the
    // base curriculum from a real MetaState; the defaults are the base
    // curriculum + the four base sectors (a Bootstrapper / new-player run).
    unlockedCardIds: unlockedCardIds,
    unlockedSectors: unlockedSectors,
  );
  return state.copyWith(
    netWorthAtTierEntry: state.netWorthCents,
    netWorthLastRound: state.netWorthCents,
  );
}
