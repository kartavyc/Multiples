/// GameController — the app-side state container for the run screen
/// (plan tasks 3.1-3.6).
///
/// HOLDS engine state and DISPATCHES engine calls; it computes nothing
/// economic. Every number the widgets render is read straight off
/// [GameState] / [ForwardMeters] or formatted by the engine's money.dart
/// helpers. The deliberate exceptions, all documented at their
/// declarations:
///   - the reinvest UI DIAL ([reinvestAmountCents] = a percent of pocket
///     cash) — a player-input magnitude the engine accepts as a raw action
///     payload (doc 02 §3.9), chosen by the UI; the reroll fee is NO LONGER
///     a UI dial — [rerollCostCents] now reads the engine's doc 02 §3.8/§4
///     scaling `rerollCostCents(rerollsUsed)` (resolver.dart);
///   - [runwaySegmentsLit] — a presentation-only discretization of the
///     engine-computed runway meter onto the 10-LED segbar;
///   - the round-start lever snapshot for the HUD change chips, the
///     [YearDigest] drift/net rows, and the napkin/flash before-after pairs
///     (display deltas BETWEEN two engine states or engine pure-helper
///     outputs; never fed back into the engine);
///   - [sellValueCents] — the display mirror of apply.dart's locked
///     `trunc(price / 2)` sell formula (doc 02 §3.6), shown on the key
///     face before the engine charges the real number.
///
/// SEED (determinism note): the ENGINE never reads a clock — it only ever
/// consumes the SplitMix64 stream this controller starts. The APP layer is
/// allowed wall-clock, so `main()` seeds new runs from
/// `DateTime.now().millisecondsSinceEpoch`; tests inject fixed seeds
/// through the constructor.
library;

import 'dart:async';

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/content.dart';
import 'package:engine/dealflow.dart'
    show actionForCard, exitOfferAction, runUnlockedCardIds;
import 'package:engine/describe.dart' show describeRunStep;
import 'package:engine/init.dart';
import 'package:engine/meta.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/resolver.dart';
// The engine reroll-fee function under an alias so the controller can expose
// its own `rerollCostCents` getter (doc 02 §3.8/§4 scaling fee) without the
// name colliding with the top-level resolver function it delegates to.
import 'package:engine/resolver.dart' as engine_resolver
    show rerollCostCents;
import 'package:engine/rng.dart';
import 'package:engine/round.dart';
import 'package:engine/serialize.dart';
import 'package:flutter/foundation.dart';

import 'save_store.dart';

/// One MARKET DRIFT digest row: the venture's multiple moved by
/// [deltaMilli] across the OPERATE (display delta between two engine
/// states; includes any neglect-multiple loss, which the separate decay
/// row already flags — documented blur, v1).
typedef DriftRow = ({String ventureId, Sector sector, int deltaMilli});

/// THE YEAR PASSED digest data (S2): what one OPERATE did, sourced from
/// the engine's [OperateResult] events plus engine pure helpers /
/// before-after display deltas (library header). Render-only.
class YearDigest {
  /// Builds the digest.
  const YearDigest({
    required this.operationsCents,
    required this.interestCents,
    required this.drift,
    required this.decay,
    required this.eventCardId,
    required this.marketTurn,
    required this.netCashCents,
    this.partnerAccrualCents = 0,
    this.scheduled = const [],
  });

  /// Cash yield paid in (engine `cashYieldCents` summed over the
  /// pre-OPERATE ventures — the exact amounts step 3 added).
  final int operationsCents;

  /// The interest bill (INTEREST_CHARGED event amount; 0 when debt-free).
  final int interestCents;

  /// Per-venture multiple movement (display deltas).
  final List<DriftRow> drift;

  /// NEGLECT_DECAY events (signed ebitda amounts + venture ids).
  final List<GameEvent> decay;

  /// The fired event card id (EVENT_RESOLVED reason), if any.
  final String? eventCardId;

  /// `market_now_<temp>` when the weather turned, if it did.
  final String? marketTurn;

  /// Net cash movement across the whole OPERATE (display delta:
  /// post-cash − pre-cash = yield − interest ± event cash).
  final int netCashCents;

  /// Partner-engine EBITDA accrued at OPERATE step 3a (display
  /// composition: the sum of the pre-OPERATE ventures' engine
  /// perRoundEbitdaCents — exactly what step 3a added; 0 when no
  /// partners are hired).
  final int partnerAccrualCents;

  /// SCHEDULED_EFFECT_FIRED events (step 3c — partner fixed costs etc.;
  /// each carries the signed cash delta + the owning venture).
  final List<GameEvent> scheduled;
}

/// The S6 MULTIPLE ARBITRAGE flash payload: engine values captured around
/// one successful AcquireAddOn. RENDER-ONLY — the accretion is the
/// MULTIPLE_ARBITRAGE event's amount (written to no state field); the
/// before/after pairs are the platform's engine values pre/post commit;
/// EVs come from the engine's `enterpriseValueOf`.
class ArbitrageFlashData {
  /// Builds the flash payload.
  const ArbitrageFlashData({
    required this.platformId,
    required this.addonEbitdaCents,
    required this.buyMultipleMilli,
    required this.boltInMultipleMilli,
    required this.ebitdaFromCents,
    required this.ebitdaToCents,
    required this.evFromCents,
    required this.evToCents,
    required this.multFromMilli,
    required this.multToMilli,
    required this.accretionCents,
    required this.sameSector,
  });

  /// The platform that absorbed the add-on.
  final String platformId;

  /// The add-on's face EBITDA (what was bought).
  final int addonEbitdaCents;

  /// The engine-implied buy multiple (dealflow glue).
  final int buyMultipleMilli;

  /// The PRE-merge live platform multiple the earnings bolt in at.
  final int boltInMultipleMilli;

  /// Platform EBITDA before the merge.
  final int ebitdaFromCents;

  /// Platform EBITDA after (absorption + any synergy).
  final int ebitdaToCents;

  /// Platform EV before (engine `enterpriseValueOf`).
  final int evFromCents;

  /// Platform EV after.
  final int evToCents;

  /// Platform multiple before.
  final int multFromMilli;

  /// Platform multiple after (== before when held; dragged cross-sector).
  final int multToMilli;

  /// The render-only accretion headline (the event's amount).
  final int accretionCents;

  /// Same-sector merge (multiple held) vs cross (dragged).
  final bool sameSector;
}

/// The S4 napkin's mechanical preview for an ADD-ON: every magnitude an
/// engine pure-helper output (`actionForCard` implied m_buy,
/// `enterpriseValue` price, `absorbSameSector`,
/// `absorbCrossSectorMultiple` + the 1000-milli floor); deltas are
/// compositions of those outputs. Render-only; the resolver recomputes
/// everything at EXECUTE.
class AddonPreview {
  /// Builds the preview.
  const AddonPreview({
    required this.payCents,
    required this.addonEbitdaCents,
    required this.faceDebtCents,
    required this.sameSector,
    required this.sector,
    required this.synergyCents,
    required this.multFromMilli,
    required this.multToMilli,
    required this.buyMultipleMilli,
  });

  /// The resolver's price: `trunc(ebitda × m_buy / 1000)`.
  final int payCents;

  /// Raw face EBITDA absorbed.
  final int addonEbitdaCents;

  /// Face debt the add-on brings.
  final int faceDebtCents;

  /// Sector match with the platform.
  final bool sameSector;

  /// The add-on's sector.
  final Sector sector;

  /// Synergy EBITDA on top of the face (same-sector +20%; 0 cross).
  final int synergyCents;

  /// Platform multiple before.
  final int multFromMilli;

  /// Platform multiple after (held same-sector; dragged + floored cross).
  final int multToMilli;

  /// The engine-implied buy multiple.
  final int buyMultipleMilli;
}

/// The EXIT napkin's mechanical preview (S4 for the EXIT OFFER ticket):
/// the engine fork made visible BEFORE commit. Every magnitude is an
/// engine pure-helper output or a documented mirror of apply.dart's
/// locked _exitVenture math (library header):
///   - [exitMultipleMilli] mirrors `hot ? trunc(live x 135/100)
///     : min(offer, live)` using the ENGINE's hotExitMulNum/Den consts;
///   - [equityAtExitCents] = engine `equityValue(ebitda, exitMult, debt)`;
///   - [proceedsCents] = engine `netWorth([v @ exitMult], 0)` — the same
///     `trunc(equity x own / 10000)` apply.dart charges (the round-11
///     exit test pins preview == the EXIT_REALIZED event amount).
/// Render-only; the resolver recomputes everything at EXECUTE.
class ExitPreview {
  /// Builds the preview.
  const ExitPreview({
    required this.ventureId,
    required this.offerMultipleMilli,
    required this.liveMultipleMilli,
    required this.hot,
    required this.exitMultipleMilli,
    required this.equityAtExitCents,
    required this.ownershipBp,
    required this.proceedsCents,
  });

  /// The offered venture.
  final String ventureId;

  /// The buyer's offer multiple (the per-round band draw).
  final int offerMultipleMilli;

  /// The venture's live (drifted) multiple — the other fork arm.
  final int liveMultipleMilli;

  /// True when a HOT WINDOW is armed: the exit overrides the fork with
  /// the hot multiple (doc 01 §7.6).
  final bool hot;

  /// The multiple the exit will actually roll (the fork's result).
  final int exitMultipleMilli;

  /// Equity at exit = EV(exit multiple) − net debt (may be negative).
  final int equityAtExitCents;

  /// Your slice of that equity, in bp.
  final int ownershipBp;

  /// Proceeds that land in CASH (engine helper composition; may be
  /// negative on a deep-negative-equity fire-sale).
  final int proceedsCents;
}

/// The S6-EXIT beat payload: engine values captured around one successful
/// ExitVenture — the dashed PAPER box collapses INTO the solid CASH box
/// (docs/07 "two sacred treatments" #2: "Exits additionally collapse the
/// dashed paper box INTO the solid cash box"). RENDER-ONLY: [proceedsCents]
/// is the EXIT_REALIZED event amount; the rest are pre/post engine reads.
class ExitFlashData {
  /// Builds the beat payload.
  const ExitFlashData({
    required this.ventureId,
    required this.ventureName,
    required this.exitMultipleMilli,
    required this.equityAtExitCents,
    required this.ownershipBp,
    required this.proceedsCents,
    required this.hot,
    required this.slotsUsedAfter,
    required this.slotsCap,
  });

  /// The exited venture's id.
  final String ventureId;

  /// The exited venture's flavor name (QUANTA…), captured pre-exit (the
  /// venture is gone from the live state by the time the beat shows).
  final String ventureName;

  /// The multiple the exit rolled (HOT_WINDOW_FIRED amount on a hot
  /// exit; the preview's min(offer, live) mirror otherwise).
  final int exitMultipleMilli;

  /// Equity at exit (preview composition of engine helpers).
  final int equityAtExitCents;

  /// Ownership the proceeds were sliced at (pre-exit venture bp).
  final int ownershipBp;

  /// The realized proceeds — the EXIT_REALIZED event amount.
  final int proceedsCents;

  /// The exit fired an armed hot window (HOT_WINDOW_FIRED seen).
  final bool hot;

  /// Ventures still held after the exit (the slot-freed line).
  final int slotsUsedAfter;

  /// The tier's slot cap (engine slotsMax).
  final int slotsCap;
}

/// The S4 napkin's preview for a PARTNER hire: every value off the same
/// dealflow.actionForCard glue EXECUTE dispatches (engine-derived,
/// render-only). [fixedCostCents] is the recurring-bill channel — 0 for
/// every v1 slice card (the schema has no fixed-cost face yet); the
/// napkin warns when content lands one.
class PartnerPreview {
  /// Builds the preview.
  const PartnerPreview({
    required this.costCents,
    required this.perRoundEbitdaCents,
    required this.multipleDeltaMilli,
    required this.fixedCostCents,
  });

  /// Hire price (cost.cash face; charged at EXECUTE).
  final int costCents;

  /// The engine's per-round +EBITDA accrual (OPERATE step 3a).
  final int perRoundEbitdaCents;

  /// One-time story bump on the venture multiple (0 for most).
  final int multipleDeltaMilli;

  /// Recurring fixed cost (ScheduledCost channel; 0 in the v1 slice).
  final int fixedCostCents;
}

/// The S7 deadline-check panel data, captured around one
/// `runDeadlineCheck` (engine events + state reads + the documented
/// presentation discretizations).
class DeadlineData {
  /// Builds the panel data.
  const DeadlineData({
    required this.cleared,
    required this.nwCents,
    required this.barCents,
    required this.roundsUsed,
    required this.deadlineRounds,
    required this.prevTier,
    required this.newTier,
    required this.pctOfBar,
    required this.neededMilli,
    required this.realizedMilli,
  });

  /// The bar was cleared (TIER_CLEARED fired).
  final bool cleared;

  /// Net worth at the check (the event's bar-clearing amount when
  /// cleared; the live derived value otherwise).
  final int nwCents;

  /// The evaluated tier's bar (engine `tierBarCents`).
  final int barCents;

  /// Rounds used in the evaluated tier.
  final int roundsUsed;

  /// The evaluated tier's deadline (0 = endless, shown ∞).
  final int deadlineRounds;

  /// The tier that was evaluated.
  final int prevTier;

  /// The tier the run is in after the check.
  final int newTier;

  /// nw as a whole-percent of the bar — PRESENTATION discretization for
  /// the tier bar fill (`(nw × 100) ~/ bar`, truncating; 0 in endless).
  final int pctOfBar;

  /// Growth needed per round (engine meters, post-check state).
  final int neededMilli;

  /// Realized growth per round (engine meters).
  final int realizedMilli;
}

/// The app-side run container (library header = the full contract).
class GameController extends ChangeNotifier {
  /// Parses the content once and opens a fresh run from [seed], posed by
  /// [backgroundId] (§Q7; default BOOTSTRAPPER). [store] is the save layer
  /// (null in pure-logic tests — the controller then runs without persistence
  /// and never settles); [meta] is the durable Track Record loaded at boot
  /// (defaults to a fresh [MetaState] when the caller has none).
  GameController({
    required String cardsJson,
    required String economyJson,
    required int seed,
    String backgroundId = kBootstrapperBackgroundId,
    SaveStore? store,
    MetaState? meta,
  })  : content = loadCards(cardsJson),
        // ignore: prefer_initializing_formals
        _store = store,
        _meta = meta ?? MetaState() {
    _economy = loadEconomy(economyJson);
    _startRun(seed, backgroundId: backgroundId);
  }

  /// Re-opens a controller from a resumed run (docs/06): the engine already
  /// replayed [resume] into [RunLoadResult.state]; this seats that state, the
  /// rng AT the resumed cursor, and the journal so autosave keeps appending.
  /// CONTINUE on the title screen builds the controller this way.
  GameController.resume({
    required String cardsJson,
    required String economyJson,
    required RunLoadResult resume,
    SaveStore? store,
    MetaState? meta,
  })  : content = loadCards(cardsJson),
        // ignore: prefer_initializing_formals
        _store = store,
        _meta = meta ?? MetaState() {
    _economy = loadEconomy(economyJson);
    _seed = resume.seed;
    _backgroundId = resume.backgroundId;
    _state = resume.state;
    // R20b: restore the run's frozen unlock snapshot (replay rebuilt it onto
    // the state from the save's startConfig, so the resumed run keeps drawing
    // from the same pool).
    _unlockedCardIds = List<String>.from(resume.state.unlockedCardIds);
    _unlockedSectors = List<Sector>.from(resume.state.unlockedSectors);
    _steps = [...resume.steps];
    // Rounds aren't persisted; backfill the resumed steps with the resumed
    // round (display only — newly recorded steps get exact rounds). The
    // autopsy broke-line stays sensible after a resume.
    _stepRounds = List<int>.filled(resume.steps.length, resume.state.round);
    _settled = false;
    _resumable = true;
    _outcomes = RunOutcomes();
    // Position the rng exactly where replay left it (docs/06 §2.2: one cursor
    // on disk; SplitMix64 fast-forwards directly).
    _rng = SplitMix64Rng(resume.seed, cursor: resume.cursor);
    _nextVentureN = _highestVentureN(_state);
    _prevEbitdaCents = null;
    _prevMultipleMilli = null;
    _prevNetDebtCents = null;
    _prevOwnershipBp = null;
    _yearDigest = null;
    _digestOpen = false;
    _lastOperateEvents = const [];
    _pendingFlash = null;
    _pendingExitFlash = null;
    _reinvestPct = 50;
    _deadline = null;
  }

  /// The loaded card database (faces for ids in hand/shopOffers/playsHeld).
  final ContentDb content;

  /// The save layer (docs/06); null disables persistence (pure-logic tests).
  final SaveStore? _store;

  /// The current run's founder background id (§Q7; persisted in startConfig).
  late String _backgroundId;

  /// The current run's FROZEN draw-pool unlock snapshot (schemaVersion 10):
  /// taken from the meta at run start, threaded into initRun, and persisted
  /// in the save's startConfig so a resume reproduces the same pool. Defaults
  /// to the base curriculum (a fresh controller before any run).
  List<String> _unlockedCardIds = kDefaultUnlockedCardIds;
  List<Sector> _unlockedSectors = kDefaultUnlockedSectors;

  /// The replayable journal (serialize.dart RunStep): one entry per engine
  /// call that advances the run, appended as the player dispatches and
  /// persisted on each committed mutation (docs/06 §4 cadence).
  List<RunStep> _steps = [];

  /// The round each [_steps] entry was recorded in — DISPLAY ONLY (the
  /// autopsy's "THE ROUND IT BROKE" line via describeRunStep, which needs the
  /// round). Parallel to [_steps]; not persisted (the on-disk record is the
  /// journal alone — replay regenerates the display log with its own rounds).
  List<int> _stepRounds = [];

  /// The run-local realized-outcome tally (meta.dart): folded from
  /// EXIT_REALIZED / dividendRecap / secondary events as they fire, so
  /// settleRun has the reputation inputs without a re-sim (doc 02 §2).
  RunOutcomes _outcomes = RunOutcomes();

  /// The durable Track Record (doc 02 §1); settled at RUN_OVER through the
  /// engine's settleRun and written back via [_store].
  MetaState _meta;

  /// Guards the one-shot RUN_OVER settlement (the controller can rebuild the
  /// end screen many times; settle exactly once — settleRun is also
  /// idempotent on runId, this just avoids redundant writes).
  bool _settled = false;

  /// False once the run leaves the replayable model (ENDLESS re-entry): the
  /// journal can no longer reconstruct the state, so autosave stops writing.
  bool _resumable = true;

  /// The most recent eager autosave's in-flight write (docs/06 §4). Autosave
  /// is fire-and-forget for the UI (it never awaits disk), but tests need a
  /// deterministic join point: [debugSettled] awaits this instead of sleeping
  /// for an arbitrary delay. Product behavior is unchanged — nothing in the
  /// app awaits it.
  Future<void> _lastAutosave = Future<void>.value();

  /// TEST SEAM: completes when the last eager [_autosave] has flushed to the
  /// store (or immediately if none is in flight). Lets save round-trip tests
  /// await the autosave deterministically instead of `Future.delayed`.
  @visibleForTesting
  Future<void> get debugSettled => _lastAutosave;

  late final EconomyConfig _economy;
  late SplitMix64Rng _rng;
  late GameState _state;
  late int _seed;

  /// The current immutable engine state.
  GameState get state => _state;

  /// The run seed (app-layer lifecycle; shown in the statline).
  int get seed => _seed;

  /// Statline seed tag: the last four uppercase hex digits (mockup №4F2A).
  String get seedTag {
    final hex = _seed.toRadixString(16).toUpperCase().padLeft(4, '0');
    return hex.substring(hex.length - 4);
  }

  /// The durable Track Record (doc 02 §1; settled at RUN_OVER). The Desk /
  /// victory / autopsy screens read it; never mutated outside settleRun.
  MetaState get meta => _meta;

  /// The current run's founder background id (§Q7).
  String get backgroundId => _backgroundId;

  /// The seed-derived run id (docs/06 §2.1; the settlement guard key).
  String get runId => runIdForSeed(_seed);

  /// The derived forward meters (engine-computed, never stored).
  ForwardMeters get meters => computeMeters(_state);

  /// The carried platform = ventures.first (engine reseed convention);
  /// null when the slot rail is empty.
  Venture? get platform =>
      _state.ventures.isEmpty ? null : _state.ventures.first;

  // --- THE YEAR PASSED digest (S2) ---

  YearDigest? _yearDigest;
  bool _digestOpen = false;
  List<GameEvent> _lastOperateEvents = const [];

  /// The most recent OPERATE's digest (null before the first round).
  YearDigest? get yearDigest => _yearDigest;

  /// True while the YEAR PASSED interstitial should cover the stage.
  bool get digestOpen => _digestOpen;

  /// The raw events of the most recent OPERATE (the autopsy quotes the
  /// fatal interest bill off these).
  List<GameEvent> get lastOperateEvents => _lastOperateEvents;

  // --- S6 arbitrage flash ---

  ArbitrageFlashData? _pendingFlash;

  /// The undismissed MULTIPLE ARBITRAGE takeover, if one is showing.
  ArbitrageFlashData? get pendingFlash => _pendingFlash;

  /// BOOK IT: closes the flash (the run screen then releases any deferred
  /// net-worth surge).
  void dismissFlash() {
    _pendingFlash = null;
    notifyListeners();
  }

  // --- S6-EXIT beat (round 11) ---

  ExitFlashData? _pendingExitFlash;

  /// The undismissed EXIT beat (paper-collapses-into-cash), if showing.
  ExitFlashData? get pendingExitFlash => _pendingExitFlash;

  /// CASHED OUT: closes the exit beat (the run screen then releases any
  /// deferred net-worth surge — hot exits can rise).
  void dismissExitFlash() {
    _pendingExitFlash = null;
    notifyListeners();
  }

  // --- The EXIT OFFER ticket (round 11; engine exitOffer + glue) ---

  /// True when the state carries a resolvable EXIT OFFER (the dealflow
  /// glue maps it onto an ExitVenture; a stale ticket maps to nothing).
  bool get exitOfferPending => exitOfferAction(_state) != null;

  /// The EXIT napkin's engine-derived preview (class doc lists every
  /// source); null when no offer is pending.
  ExitPreview? exitPreview() {
    final action = exitOfferAction(_state);
    if (action == null) return null;
    final v =
        _state.ventures.firstWhere((v) => v.id == action.ventureId);
    final hot = _state.market.hotWindowArmed;
    // Documented MIRROR of apply.dart's _exitVenture fork (the engine's
    // own hotExitMulNum/Den consts; min() is a comparison, not math).
    final exitMult = hot
        ? (action.liveMarketMultipleMilli * hotExitMulNum) ~/ hotExitMulDen
        : (action.offerMultipleMilli < action.liveMarketMultipleMilli
            ? action.offerMultipleMilli
            : action.liveMarketMultipleMilli);
    return ExitPreview(
      ventureId: v.id,
      offerMultipleMilli: action.offerMultipleMilli,
      liveMultipleMilli: action.liveMarketMultipleMilli,
      hot: hot,
      exitMultipleMilli: exitMult,
      equityAtExitCents:
          equityValue(v.ebitdaCents, exitMult, v.netDebtCents),
      // Engine F3 over the one venture marked at the exit multiple, no
      // cash: exactly apply.dart's trunc((EV − debt) x own / 10000).
      proceedsCents: netWorth([v.copyWith(multipleMilli: exitMult)], 0),
      ownershipBp: v.ownershipBp,
    );
  }

  /// EXECUTE on the EXIT napkin: resolves the pending offer through the
  /// real engine path (dealflow.exitOfferAction -> apply). On success the
  /// S6-EXIT beat payload is captured ([pendingExitFlash]) — proceeds and
  /// the hot multiple come off the ENGINE events.
  List<GameEvent> exitVenture() {
    final action = exitOfferAction(_state);
    if (action == null) return const [];
    final preview = exitPreview()!;
    // The pre-exit venture carries the realized ownership/sector the
    // reputation tally needs (the exit removes it from the list).
    final exited = targetVenture(action.ventureId);
    final result = apply(_state, action, _rng, content);
    _state = result.state;
    final rejected =
        result.events.any((e) => e.type == GameEventType.actionRejected);
    if (!rejected) {
      var proceeds = 0;
      var hotMult = 0;
      var hot = false;
      for (final e in result.events) {
        if (e.type == GameEventType.exitRealized) proceeds = e.amount;
        if (e.type == GameEventType.hotWindowFired) {
          hot = true;
          hotMult = e.amount;
        }
      }
      _pendingExitFlash = ExitFlashData(
        ventureId: action.ventureId,
        ventureName: exited?.displayName ?? action.ventureId.toUpperCase(),
        exitMultipleMilli: hot ? hotMult : preview.exitMultipleMilli,
        equityAtExitCents: preview.equityAtExitCents,
        ownershipBp: preview.ownershipBp,
        proceedsCents: proceeds,
        hot: hot,
        slotsUsedAfter: _state.ventures.length,
        slotsCap: slotsMax(_state.tier),
      );
      // Journal + persist + fold the realized exit into the reputation tally.
      _record(ApplyStep(action));
      _tallyOutcomes(result.events, exitedVenture: exited);
      _autosave();
    }
    notifyListeners();
    return result.events;
  }

  // --- S7 deadline panel ---

  DeadlineData? _deadline;

  /// The open deadline/tier-clear panel data, if the panel is showing.
  DeadlineData? get deadline => _deadline;

  /// True while the S7 panel should take over the stage.
  bool get deadlineOpen => _deadline != null;

  /// The raw events of the most recent DEADLINE_CHECK (R18 audio reads the
  /// tier-clear / won / missed-deadline stingers off these — render-only,
  /// like [lastOperateEvents]; never persisted).
  List<GameEvent> get lastDeadlineEvents => _lastDeadlineEvents;
  List<GameEvent> _lastDeadlineEvents = const [];

  // --- HUD change chips (previous-round lever snapshot) ---

  int? _prevEbitdaCents;
  int? _prevMultipleMilli;
  int? _prevNetDebtCents;
  int? _prevOwnershipBp;

  int? _chip(int? prev, int? current) =>
      (prev == null || current == null) ? null : current - prev;

  /// Signed EBITDA change vs the last round (cents), null when underivable.
  int? get ebitdaChip => _chip(_prevEbitdaCents, platform?.ebitdaCents);

  /// Signed multiple change vs the last round (milli).
  int? get multipleChip => _chip(_prevMultipleMilli, platform?.multipleMilli);

  /// Signed net-debt change vs the last round (cents).
  int? get netDebtChip => _chip(_prevNetDebtCents, platform?.netDebtCents);

  /// Signed ownership change vs the last round (bp).
  int? get ownershipChip => _chip(_prevOwnershipBp, platform?.ownershipBp);

  void _snapshotLevers() {
    final p = platform;
    _prevEbitdaCents = p?.ebitdaCents;
    _prevMultipleMilli = p?.multipleMilli;
    _prevNetDebtCents = p?.netDebtCents;
    _prevOwnershipBp = p?.ownershipBp;
  }

  // --- UI DIALS (documented; the engine treats both as raw player input) ---

  /// REINVEST quick-key percents (the round-11 amount picker; UI DIAL —
  /// the engine accepts any amount, doc 02 §3.9).
  static const List<int> kReinvestPcts = [25, 50, 100];

  int _reinvestPct = 50;

  /// The selected quick-key percent (defaults to the R7 half-pocket dial).
  int get reinvestPct => _reinvestPct;

  /// Picks a REINVEST quick key (25/50/100).
  void setReinvestPct(int pct) {
    _reinvestPct = pct;
    notifyListeners();
  }

  /// REINVEST amount: [reinvestPct] of the pocket cash, truncating —
  /// a player-input magnitude (UI DIAL, not canon); the engine charges
  /// exactly what it is handed.
  int get reinvestAmountCents => (_state.cashCents * _reinvestPct) ~/ 100;

  /// The engine's reinvest efficiency for THIS round/tier (resolver
  /// reinvestEfficiencyBp — the napkin's `AT Y%` read).
  int get reinvestEffBp =>
      reinvestEfficiencyBp(round: _state.round, tier: _state.tier);

  /// The napkin's `+$X EBITDA` preview: a documented MIRROR of
  /// apply.dart's _reinvestBaseline `trunc(amount x effBp / 10000)` (the
  /// §0.7 mulBp shape) off the engine's own efficiency curve. Render-only;
  /// the resolver recomputes at EXECUTE (round-11 test pins the match).
  int get reinvestGainCents =>
      (reinvestAmountCents * reinvestEffBp) ~/ bpScale;

  /// REROLL fee for the CURRENT reroll, in cents (printed on the key). Reads
  /// the engine's doc 02 §3.8/§4 scaling `rerollCostCents(rerollsUsed)`
  /// (resolver.dart): the first reroll of a round is $15k (the old flat
  /// face), each subsequent one costs $15k more, capped at $150k; the count
  /// resets every round. ALL game math stays in the engine — the controller
  /// only reads the live fee off the current `rerollsUsed`.
  int get rerollCostCents =>
      engine_resolver.rerollCostCents(_state.rerollsUsed);

  /// True when the pocket covers the CURRENT reroll fee (the key disables
  /// cash-short instead of bouncing — the engine still gates at apply).
  bool get canReroll => _state.cashCents >= rerollCostCents;

  // --- venture id minting (the engine never mints ids) ---

  int _nextVentureN = 0;

  String _mintVentureId() => 'v${++_nextVentureN}';

  /// The highest `vN` id number among [s]'s ventures (so a resumed run keeps
  /// minting fresh ids above the replayed ones; the engine never mints).
  int _highestVentureN(GameState s) {
    var max = 0;
    for (final v in s.ventures) {
      final id = v.id;
      if (id.startsWith('v')) {
        final n = int.tryParse(id.substring(1));
        if (n != null && n > max) max = n;
      }
    }
    return max;
  }

  void _startRun(int seed, {String backgroundId = kBootstrapperBackgroundId}) {
    _seed = seed;
    _backgroundId = backgroundId;
    _rng = SplitMix64Rng(seed);
    // R20b: freeze this run's draw-pool unlock set from the live meta (the
    // base curriculum ∪ the §Q7 ladder's cross-run unlocks), so the run draws
    // from the full unlocked pool and the save can reproduce it.
    _unlockedCardIds = runUnlockedCardIds(_meta, content);
    _unlockedSectors = List<Sector>.from(_meta.unlockedSectors);
    _state = initRun(
      economy: _economy,
      backgroundId: backgroundId,
      unlockedCardIds: _unlockedCardIds,
      unlockedSectors: _unlockedSectors,
    );
    _steps = [];
    _stepRounds = [];
    _outcomes = RunOutcomes();
    _settled = false;
    _resumable = true;
    _yearDigest = null;
    _digestOpen = false;
    _lastOperateEvents = const [];
    _pendingFlash = null;
    _pendingExitFlash = null;
    _reinvestPct = 50;
    _deadline = null;
    _nextVentureN = _state.ventures.length; // 'v1' is the seed venture
    _prevEbitdaCents = null;
    _prevMultipleMilli = null;
    _prevNetDebtCents = null;
    _prevOwnershipBp = null;
  }

  /// Starts a brand-new run. Prod calls pass no seed and get wall-clock
  /// (app layer only; see the library header); tests pass a fixed [seed].
  /// [backgroundId] picks the founder background (§Q7; defaults to the
  /// current one so RETRY reuses the chosen background).
  void newRun({int? seed, String? backgroundId}) {
    _startRun(seed ?? DateTime.now().millisecondsSinceEpoch,
        backgroundId: backgroundId ?? _backgroundId);
    notifyListeners();
  }

  // --- journal + autosave (docs/06 §4: the app records the typed RunStep
  //     log as the player dispatches and persists on each committed mutation;
  //     ALL of this is I/O — the engine owns the step semantics) ---

  /// Appends one [step] to the replayable journal (the on-disk actionLog),
  /// tagging it with the current round for the autopsy display line.
  void _record(RunStep step) {
    _steps.add(step);
    _stepRounds.add(_state.round);
  }

  /// The autopsy's "THE ROUND IT BROKE" line (doc 02 §Q5): the last DECISIVE
  /// player step (an apply / playCard / buyShop — system OPERATE/END_TURN/
  /// DEADLINE_CHECK steps are not "the move"), money-formatted by the engine's
  /// describeRunStep (no raw cents). Null when the run made no player move.
  String? get brokeLine {
    for (var i = _steps.length - 1; i >= 0; i--) {
      final step = _steps[i];
      final decisive =
          step is ApplyStep || step is PlayCardStep || step is BuyShopStep;
      if (decisive) {
        return describeRunStep(
          step,
          round: _stepRounds[i],
          content: content,
          ventures: _state.ventures,
        );
      }
    }
    return null;
  }

  /// Persists the run eagerly (docs/06 §4: after each committed action + each
  /// phase transition). The cache is the live state snapshot (rng-stripped by
  /// the engine). A no-op when no [_store] is wired (pure-logic tests) or the
  /// run is already over (the save was deleted at settlement). Fire-and-forget
  /// — the UI does not await disk; a failed write logs and the next one
  /// overwrites it.
  void _autosave() {
    final store = _store;
    if (store == null || !_resumable) return;
    if (_state.phase == PhaseId.runOver) return;
    final seed = _seed;
    final cursor = _state.rngCursor;
    final backgroundId = _backgroundId;
    final steps = List<RunStep>.of(_steps);
    final cache = _state;
    final write = store.writeRun(
      seed: seed,
      cursor: cursor,
      backgroundId: backgroundId,
      steps: steps,
      cacheState: cache,
      unlockedCardIds: _unlockedCardIds,
      unlockedSectors: _unlockedSectors,
    );
    // Track the in-flight write for [debugSettled] (the store serializes
    // writes, so awaiting the latest joins all earlier ones too). Still
    // fire-and-forget for the UI; a failed write logs and the next overwrites.
    _lastAutosave = write;
    unawaited(write);
  }

  /// Forces a synchronous-ish flush of the current run (docs/06 §4 lifecycle:
  /// AppLifecycleState.paused/inactive). Returns the write future so the
  /// observer can await it. A no-op when there is nothing to persist.
  Future<void> flush() async {
    final store = _store;
    if (store == null || !_resumable || _state.phase == PhaseId.runOver) return;
    await store.writeRun(
      seed: _seed,
      cursor: _state.rngCursor,
      backgroundId: _backgroundId,
      steps: List<RunStep>.of(_steps),
      cacheState: _state,
      unlockedCardIds: _unlockedCardIds,
      unlockedSectors: _unlockedSectors,
    );
  }

  /// Folds a resolved engine event list into the run-local realized-outcome
  /// tally (meta.dart [RunOutcomes]) so settleRun has the reputation inputs.
  /// EXIT_REALIZED -> a clean/fire-sale [ExitOutcome]; dividend recap cash and
  /// secondary proceeds add to their channels. Paper net worth never enters.
  void _tallyOutcomes(List<GameEvent> events, {Venture? exitedVenture}) {
    for (final e in events) {
      switch (e.type) {
        case GameEventType.exitRealized:
          final v = exitedVenture;
          // The realized exit multiple: the HOT_WINDOW_FIRED amount if armed,
          // else the venture's live multiple at exit (the fork the engine
          // took). Ownership/sector come off the pre-exit venture.
          var exitMul = v?.multipleMilli ?? 0;
          for (final h in events) {
            if (h.type == GameEventType.hotWindowFired) exitMul = h.amount;
          }
          final sector = v?.sector ?? Sector.software;
          final ownBp = v?.ownershipBp ?? 0;
          final equityPositive = e.amount > 0;
          final clean =
              equityPositive && exitMul >= kCleanExitMinMultipleMilli;
          _outcomes = _outcomes.withExit(ExitOutcome(
            proceedsCents: e.amount,
            exitMultipleMilli: exitMul,
            sectorNormMilli: sectorNormMilli(sector),
            ownershipBp: ownBp,
            clean: clean,
          ));
        case GameEventType.dividendRecap:
          _outcomes = _outcomes.withDividend(e.amount);
        default:
          break;
      }
    }
  }

  /// Settles the finished run into the durable meta (doc 02 §2 / docs/06
  /// §5.1): build outcomes -> settleRun -> write meta atomically -> delete
  /// run.json. One-shot ([_settled]); settleRun is also idempotent on runId.
  /// Synchronous to the engine; the disk writes are awaited so the order
  /// (meta THEN delete) holds. The end screens call this on first build.
  Future<void> settleRunOver() async {
    if (_settled) return;
    if (_state.phase != PhaseId.runOver) return;
    _settled = true;
    _meta = settleRun(
      _meta,
      finishedRun: _state,
      runId: runId,
      outcomes: _outcomes,
    );
    final store = _store;
    if (store != null) {
      // docs/06 §5.1 ordering: durably write meta, THEN delete run.json.
      await store.writeMeta(_meta);
      await store.deleteRun();
    }
    notifyListeners();
  }

  /// ENDLESS (S10): re-enters the machine at tier 5 after a win and runs
  /// the next OPERATE. The tier-entry snapshot rebaselines so the growth
  /// meter and the endless escalation read off the entry net worth. ENDLESS
  /// now ESCALATES engine-side (R15 / audit L1): T5 runs in antes against a
  /// rising survival bar derived from this entry NW (round.dart
  /// endlessSurvivalBarCents) — clear an ante to escalate, miss it to fail
  /// out MISSED_DEADLINE; endless never wins.
  void enterEndless() {
    // ENDLESS re-enters via a direct copyWith, not an engine step, so the
    // replayable journal can no longer reproduce the state — mark the run
    // non-resumable so autosave stops writing an unreplayable run.json (the
    // win was already settled + run.json deleted at RUN_OVER).
    _resumable = false;
    _state = _state.copyWith(
      tier: 5,
      round: 1,
      won: false,
      phase: PhaseId.operate,
      netWorthAtTierEntry: _state.netWorthCents,
    );
    beginRound(); // notifies
  }

  /// Runs the OPERATE step — called on entering the operate phase (run
  /// start and every deadline-panel proceed) — and opens the YEAR PASSED
  /// digest. On a bankruptcy the digest stays closed: the autopsy owns
  /// that beat.
  void beginRound() {
    assert(_state.phase == PhaseId.operate,
        'beginRound requires the operate phase');
    _snapshotLevers();
    final pre = _state;

    // OPERATIONS row: the exact step-3 yield, via the engine's pure
    // cashYieldCents over the pre-OPERATE ventures (drift moves only
    // multiples, decay runs after yield — so face EBITDA here IS the
    // yield base; operate.dart steps 2-4).
    // PARTNERS row: what step 3a accrues — the sum of each venture's
    // engine perRoundEbitdaCents (display composition of state values).
    // The OPERATIONS row yields on the POST-accrual EBITDA, exactly like
    // operate.dart step 3b (the yield converts partner earnings too) —
    // including the v6 ORGANIC GROWTH a partnered venture earns
    // (engine organicGrowthCents, doc 01 §3.2; schemaVersion 6).
    var operations = 0;
    var partnerAccrual = 0;
    for (final v in pre.ventures) {
      var perRound = 0;
      for (final p in v.partners) {
        perRound += p.perRoundEbitdaCents;
      }
      partnerAccrual += perRound;
      final organic = v.partners.isEmpty
          ? 0
          : organicGrowthCents(v.ebitdaCents, passive: v.passive);
      operations += cashYieldCents(v.ebitdaCents + organic + perRound,
          passive: v.passive);
    }

    final result = runOperate(_state, _rng, content);
    _state = result.state;
    _lastOperateEvents = result.events;
    // Journal the OPERATE step (docs/06 §4: a phase transition is persisted so
    // the resumed phase is exact) and autosave the round's resolved state.
    _record(const OperateStep());
    _autosave();

    var interest = 0;
    String? eventCardId;
    String? marketTurn;
    final decay = <GameEvent>[];
    final scheduled = <GameEvent>[];
    for (final e in result.events) {
      switch (e.type) {
        case GameEventType.interestCharged:
          interest = e.amount;
        case GameEventType.eventResolved:
          eventCardId = e.reason;
        case GameEventType.marketStateChanged:
          marketTurn = e.reason;
        case GameEventType.neglectDecay:
          decay.add(e);
        case GameEventType.scheduledEffectFired:
          scheduled.add(e);
        default:
          break;
      }
    }
    final drift = <DriftRow>[];
    for (final v0 in pre.ventures) {
      for (final v1 in _state.ventures) {
        if (v1.id == v0.id) {
          final d = v1.multipleMilli - v0.multipleMilli;
          if (d != 0) {
            drift.add(
                (ventureId: v0.id, sector: v0.sector, deltaMilli: d));
          }
          break;
        }
      }
    }
    _yearDigest = YearDigest(
      operationsCents: operations,
      interestCents: interest,
      drift: drift,
      decay: decay,
      eventCardId: eventCardId,
      marketTurn: marketTurn,
      netCashCents: _state.cashCents - pre.cashCents,
      partnerAccrualCents: partnerAccrual,
      scheduled: scheduled,
    );
    _digestOpen = _state.phase != PhaseId.runOver;
    notifyListeners();
  }

  /// Closes the YEAR PASSED interstitial (CONTINUE key).
  void dismissDigest() {
    _digestOpen = false;
    notifyListeners();
  }

  /// The ACT blotter rows: the hand (ventures + addons) plus any financing
  /// offers still on the SHOP counter — financing EXERCISES during ACT
  /// through playCard (apply.dart's documented engine decision).
  List<String> get blotterIds => [
        ..._state.hand,
        ..._state.shopOffers
            .where((id) => content.byId(id).type == CardType.financing),
      ];

  /// The implied add-on buy multiple (milli) for the ticket midline
  /// (mockup `40k EBITDA @ 4.5×`). The v1 addon schema carries no buy
  /// multiple, so the ENGINE derives it — this just reads the field off
  /// the same dealflow.actionForCard glue that EXECUTE will dispatch.
  /// Render-only; never stored. The target id is irrelevant to the
  /// derivation (faces only), so a placeholder satisfies the glue's
  /// non-null gate when the rail is empty.
  int addonBuyMultipleMilli(String cardId) {
    final action = actionForCard(content.byId(cardId),
        targetVentureId: platform?.id ?? 'px');
    return (action as AcquireAddOn).addonBuyMultipleMilli;
  }

  /// The venture [id] points at, falling back to the platform (the
  /// single-venture auto-target); null when the rail is empty.
  Venture? targetVenture(String? id) {
    if (id != null) {
      for (final v in _state.ventures) {
        if (v.id == id) return v;
      }
    }
    return platform;
  }

  /// A venture's total partner accrual per round (display composition of
  /// the engine PartnerEngine values — the holdings-rail `+$X/RD` tag).
  int partnerPerRoundCents(Venture v) {
    var sum = 0;
    for (final p in v.partners) {
      sum += p.perRoundEbitdaCents;
    }
    return sum;
  }

  /// The S4 napkin's mechanical preview for an addon [cardId] against the
  /// aimed venture ([targetVentureId]; platform when null — the
  /// single-venture auto-target) — every magnitude an engine pure-helper
  /// output (the class doc lists them).
  AddonPreview addonPreview(String cardId, {String? targetVentureId}) {
    final card = content.byId(cardId);
    final p = targetVenture(targetVentureId)!;
    final action =
        actionForCard(card, targetVentureId: p.id) as AcquireAddOn;
    // The resolver's addonPrice: trunc(ebitda × m_buy / 1000) — the same
    // F1 shape apply.dart charges (can land a sub-dollar sliver under the
    // face; the truncation goes to the player).
    final pay =
        enterpriseValue(action.addonEbitdaCents, action.addonBuyMultipleMilli);
    final same = action.addonSector == p.sector;
    final absorbed = absorbSameSector(
      platformEbitda: p.ebitdaCents,
      addonEbitda: action.addonEbitdaCents,
    );
    // Synergy = the engine's absorbed total minus the raw parts (display
    // composition of engine outputs; +20% same-sector, 0 cross).
    final synergy =
        same ? absorbed - p.ebitdaCents - action.addonEbitdaCents : 0;
    final dragged = absorbCrossSectorMultiple(p.multipleMilli);
    final multTo = same
        ? p.multipleMilli
        : (dragged < multipleFloorMilli ? multipleFloorMilli : dragged);
    return AddonPreview(
      payCents: pay,
      addonEbitdaCents: action.addonEbitdaCents,
      faceDebtCents: action.addonFaceDebtCents,
      sameSector: same,
      sector: action.addonSector,
      synergyCents: synergy,
      multFromMilli: p.multipleMilli,
      multToMilli: multTo,
      buyMultipleMilli: action.addonBuyMultipleMilli,
    );
  }

  /// The S4 napkin's preview for a partner [cardId]: read off the same
  /// dealflow.actionForCard glue EXECUTE dispatches (render-only). The
  /// target id is irrelevant to the faces, so the platform placeholder
  /// satisfies the glue's non-null gate.
  PartnerPreview partnerPreview(String cardId) {
    final action = actionForCard(content.byId(cardId),
        targetVentureId: platform?.id ?? 'px') as HirePartner;
    return PartnerPreview(
      costCents: action.costCents,
      perRoundEbitdaCents: action.perRoundEbitdaCents,
      multipleDeltaMilli: action.multipleDeltaMilli,
      fixedCostCents: action.fixedCostCents,
    );
  }

  /// Plays a blotter card by id through the real engine path
  /// (dealflow.actionForCard -> apply). Venture cards target a freshly
  /// minted id; everything else targets [targetVentureId] (the rail
  /// picker's aim) or the platform. Returns the engine events (rejections
  /// included). A successful AcquireAddOn captures the S6 flash payload
  /// off the MULTIPLE_ARBITRAGE event + the target's before/after engine
  /// values.
  List<GameEvent> playBlotterCard(String cardId, {String? targetVentureId}) {
    final card = content.byId(cardId);
    final target = card.type == CardType.venture
        ? _mintVentureId()
        : (targetVentureId ?? platform?.id);
    final pre = _state;
    final result =
        playCard(_state, cardId, _rng, content, targetVentureId: target);
    _state = result.state;
    final rejected =
        result.events.any((e) => e.type == GameEventType.actionRejected);
    if (!rejected) {
      // Journal the play with the SAME target the engine resolved (a minted
      // venture id replays identically — initRun + replay mint the same ids).
      _record(PlayCardStep(cardId, targetVentureId: target));
      _tallyOutcomes(result.events);
      _autosave();
    }

    for (final e in result.events) {
      if (e.type == GameEventType.multipleArbitrage) {
        Venture? p0;
        Venture? p1;
        for (final v in pre.ventures) {
          if (v.id == e.ventureId) p0 = v;
        }
        for (final v in _state.ventures) {
          if (v.id == e.ventureId) p1 = v;
        }
        if (p0 != null && p1 != null) {
          final action =
              actionForCard(card, targetVentureId: p0.id) as AcquireAddOn;
          _pendingFlash = ArbitrageFlashData(
            platformId: p0.id,
            addonEbitdaCents: action.addonEbitdaCents,
            buyMultipleMilli: action.addonBuyMultipleMilli,
            boltInMultipleMilli: p0.multipleMilli,
            ebitdaFromCents: p0.ebitdaCents,
            ebitdaToCents: p1.ebitdaCents,
            evFromCents: enterpriseValueOf(p0),
            evToCents: enterpriseValueOf(p1),
            multFromMilli: p0.multipleMilli,
            multToMilli: p1.multipleMilli,
            accretionCents: e.amount,
            sameSector: action.addonSector == p0.sector,
          );
        }
      }
    }
    notifyListeners();
    return result.events;
  }

  /// REINVEST baseline on the platform at the [reinvestAmountCents] dial.
  List<GameEvent> reinvest() {
    final action = ReinvestBaseline(
      ventureId: platform?.id ?? '',
      amountCents: reinvestAmountCents,
    );
    final result = apply(_state, action, _rng, content);
    _state = result.state;
    if (!result.events.any((e) => e.type == GameEventType.actionRejected)) {
      _record(ApplyStep(action));
      _autosave();
    }
    notifyListeners();
    return result.events;
  }

  /// REROLL at the engine's live scaling fee ([rerollCostCents], doc 02
  /// §3.8/§4) — redraws the current phase's deck engine-side. The fee rides
  /// the current `rerollsUsed`, so the recorded ApplyStep carries the exact
  /// cost the engine charged (replay reproduces the same `rerollsUsed` and
  /// thus the same fee).
  List<GameEvent> reroll() {
    final action = Reroll(costCents: rerollCostCents);
    final result = apply(_state, action, _rng, content);
    _state = result.state;
    if (!result.events.any((e) => e.type == GameEventType.actionRejected)) {
      _record(ApplyStep(action));
      _autosave();
    }
    notifyListeners();
    return result.events;
  }

  /// END TURN: leaves ACT for SHOP (the engine deals the counter).
  void endTurnToShop() {
    _state = endTurn(_state, _rng, content);
    _record(const EndTurnStep());
    _autosave();
    notifyListeners();
  }

  /// SHOP buy: takes a consumable off the counter into the held inventory.
  List<GameEvent> buyOffer(String cardId) {
    final result = buyShopOffer(_state, cardId, content);
    _state = result.state;
    if (!result.events.any((e) => e.type == GameEventType.actionRejected)) {
      _record(BuyShopStep(cardId));
      _autosave();
    }
    notifyListeners();
    return result.events;
  }

  /// USE a held play (ACT): dispatches the consumable through the same
  /// dealflow.actionForCard glue card play uses (purchase mirror stripped;
  /// HOT_WINDOW/MARKET_READ arm their flags engine-side). Per-venture
  /// deltas land on [targetVentureId] (platform when null).
  List<GameEvent> playHeld(String cardId, {String? targetVentureId}) {
    final target = targetVentureId ?? platform?.id;
    final action = actionForCard(content.byId(cardId), targetVentureId: target);
    final result = apply(_state, action, _rng, content);
    _state = result.state;
    if (!result.events.any((e) => e.type == GameEventType.actionRejected)) {
      // A held consumable is dispatched through apply(PlayConsumable) (it is
      // already in playsHeld, not the hand/shop), so the journal records the
      // typed ApplyStep — replay re-issues the SAME apply path, not playCard.
      _record(ApplyStep(action));
      _tallyOutcomes(result.events);
      _autosave();
    }
    notifyListeners();
    return result.events;
  }

  /// SELL a held play for the engine's trunc(price/2) (doc 02 §3.6).
  List<GameEvent> sellPlay(String cardId) {
    final card = content.byId(cardId);
    final action =
        SellPlay(playId: cardId, purchasePriceCents: card.cost.cashCents);
    final result = apply(_state, action, _rng, content);
    _state = result.state;
    if (!result.events.any((e) => e.type == GameEventType.actionRejected)) {
      _record(ApplyStep(action));
      _autosave();
    }
    notifyListeners();
    return result.events;
  }

  /// The SELL key face for a held play: the display MIRROR of apply.dart's
  /// locked `trunc(purchasePrice / 2)` (doc 02 §3.6) — shown before the
  /// engine charges the real (identical) number at [sellPlay].
  int sellValueCents(String cardId) => content.byId(cardId).cost.cashCents ~/ 2;

  /// ADVANCE: runs the DEADLINE_CHECK. A win / missed deadline lands
  /// runOver (the end screens read the state directly); any other outcome
  /// opens the S7 panel ([deadline]) — [proceedFromDeadline] then runs the
  /// next OPERATE.
  void advance() {
    final prevTier = _state.tier;
    final prevRound = _state.round;
    final result = runDeadlineCheck(_state);
    _state = result.state;
    _lastDeadlineEvents = result.events;
    // Always journal the deadline check (it is a phase-advancing step; a
    // win/death lands runOver and settlement deletes the save, so the
    // autosave below no-ops there).
    _record(const DeadlineCheckStep());

    if (_state.phase == PhaseId.runOver) {
      _deadline = null;
      notifyListeners();
      return;
    }
    // Survived (tier clear or advance): persist the post-check state so a
    // resume lands on the right round/tier (docs/06 §4 phase transition).
    _autosave();

    var cleared = false;
    var clearedNw = 0;
    for (final e in result.events) {
      if (e.type == GameEventType.tierCleared) {
        cleared = true;
        clearedNw = e.amount;
      }
    }
    final nw = cleared ? clearedNw : _state.netWorthCents;
    final endless = prevTier == 5;
    final bar = endless ? 0 : tierBarCents(prevTier);
    final m = computeMeters(_state);
    _deadline = DeadlineData(
      cleared: cleared,
      nwCents: nw,
      barCents: bar,
      roundsUsed: prevRound,
      deadlineRounds: endless ? 0 : tierDeadlineRounds(prevTier),
      prevTier: prevTier,
      newTier: _state.tier,
      pctOfBar: bar > 0 ? (nw * 100) ~/ bar : 0,
      neededMilli: m.growthRateNeededMilli,
      realizedMilli: m.growthRateThisTierMilli,
    );
    notifyListeners();
  }

  /// NEXT TIER / NEXT ROUND: closes the S7 panel and runs the next
  /// OPERATE (the digest then opens).
  void proceedFromDeadline() {
    _deadline = null;
    beginRound(); // notifies
  }

  // --- presentation discretizations (documented; meters stay engine-made) ---

  /// Discrete RUNWAY fill for the 10-LED segbar. PRESENTATION ONLY: the
  /// underlying numbers are the engine's [ForwardMeters]. Mapping: 4 LEDs
  /// represent the worst-case interest bill, so lit = projected cash in
  /// quarter-bills, capped at 10; a debt-free book reads fully lit.
  int get runwaySegmentsLit {
    final m = meters;
    if (m.debtServiceNextRoundCents <= 0) return 10;
    final lit =
        (m.projectedCashNextRoundCents * 4) ~/ m.debtServiceNextRoundCents;
    if (lit < 0) return 0;
    return lit > 10 ? 10 : lit;
  }

  /// TEST HOOK: swaps the engine state under the controller so widget
  /// tests can drive doomed/terminal fixtures through the REAL screens
  /// (e.g. set a debt-crushed operate-phase state, then let the screen's
  /// own beginRound run the fatal OPERATE). Never called by app code.
  @visibleForTesting
  void debugSetState(GameState state) {
    _state = state;
    notifyListeners();
  }
}
