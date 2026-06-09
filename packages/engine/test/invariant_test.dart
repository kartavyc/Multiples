// The §7 invariant test — the most important test in the project.
// NEVER weaken it to make something pass; reconcile against the docs.
//
// Doc 02 §0.1/§5, doc 03 §5, economy-model.json resolverInputs.invariant:
// every card, consumable, and event resolves as deltas over EXACTLY five
// mutable inputs {ebitda, multiple, netDebt, own, cash}; net worth is
// always derived, never stored; structural ops (venture add/remove/merge)
// must reconcile to those deltas.
//
// Sections:
//   (a) content: every deltas object in data/cards.json keys only the five
//       inputs (all 33 cards checked)
//   (b) behavioral: EVERY implemented action, applied against a live
//       fixture, touches only the five economic paths + whitelisted
//       bookkeeping (actionLog, rerollsUsed, passive, roundsNeglected,
//       playsRemaining — doc 02 §5.2.1 whitelists play counters; actions
//       decrement on success — venture add/remove,
//       round/tier/rngCursor/schemaVersion) — via the shared flatten()
//       state walker. THE DEAL-FLOW LISTS ARE ACTION-SCOPED (the work
//       order's whitelist split): hand.*/shopOffers.* are writable only by
//       the draw steps + the card-consuming actions (Reroll redraws the
//       current phase's deck; playCard removes the played id);
//       playsHeld.* only by the shop buy + PlayConsumable/SellPlay. The
//       SYSTEM steps run through the SAME diff with step-scoped extra
//       whitelists: runOperate (drift/decay/EVENT CARDS/interest, economy
//       resolverInputs.systemEventsThroughResolver) may also touch
//       market.*/phase/netWorthLastRound/death/hand.*; endTurn
//       phase/shopOffers.*/rngCursor (it deals the counter);
//       runDeadlineCheck (the §3.3 reseed + advance) may also touch
//       phase/round/tier/netWorthAtTierEntry/won/death — and still NO
//       deck paths. Each whitelist is scoped to ITS step/action, so an
//       action that touched the market, or a non-card action that touched
//       a deck, would still fail
//   (c) reconciliation: StartVenture / ExitVenture (the structural ops)
//       and the tier RESEED change net worth by exactly their economic
//       deltas — no value is conjured by adding/removing/reseeding a
//       venture
//   (d) directionality: signs, not magnitudes (doc 02 §5.2.3)
//   (e) no writable field / setter named like score|netWorth|points on the
//       model (source-text scan of lib/model.dart; the §7 name rule) —
//       except the doc 02 §5.1 SCORE_SNAPSHOT_WHITELIST, matched by EXACT
//       name: netWorthAtTierEntry / netWorthLastRound must exist as final
//       (write-once) fields and nothing else score-named may be a field
//
// dart:io and dart:convert are TEST-ONLY here (reading repo content files);
// the engine lib itself stays pure. The test runner's cwd is the package
// root (tool/wintest.bat cds there), so repo paths are ../../.
//
// All money is integer cents; no `double` anywhere in this test.

import 'dart:convert';
import 'dart:io';

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/content.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/resolver.dart';
import 'package:engine/rng.dart';
import 'package:engine/round.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';
import 'helpers/flatten.dart';

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

/// Tier 4 (3 SLOTS, recap un-gated) with one slot free and equity-positive
/// ventures, so every action's SUCCESS path is reachable from one state.
GameState fixture() => GameState(
      ventures: const [
        Venture(
          id: 'v1',
          sector: Sector.software,
          ebitdaCents: 600000,
          multipleMilli: 14000,
          netDebtCents: 100000,
          ownershipBp: 8000,
        ),
        Venture(
          id: 'v2',
          sector: Sector.retail,
          ebitdaCents: 400000,
          multipleMilli: 3000,
          netDebtCents: 0,
          ownershipBp: 10000,
        ),
      ],
      cashCents: 5000000,
      rngCursor: 7,
      round: 2,
      tier: 4,
      playsRemaining: 3, // the doc 02 §3 plays gate PREs every paid action
      playsHeld: const ['p'], // PlayConsumable/SellPlay membership gate
    );

SplitMix64Rng rng() => SplitMix64Rng(1);

/// Every implemented action's success-path payload against [fixture],
/// keyed by a label for failure messages. ALL ELEVEN union variants appear:
/// this doubles as the dispatcher-completeness check (an unimplemented
/// variant would throw, an illegal one would reject and show as a no-op).
Map<String, Action> allActions() => {
      'StartVenture': const StartVenture(
        ventureId: 'v3',
        sector: Sector.services,
        ebitdaCents: 500000,
        multipleMilli: 6000,
        priceCents: 1000000,
        faceDebtCents: 200000,
      ),
      'RaiseEquity': const RaiseEquity(ventureId: 'v1', raiseCents: 1000000),
      'TakeDebt': const TakeDebt(
          ventureId: 'v1', proceedsCents: 1000000, faceDebtCents: 1150000),
      'AcquireAddOn': const AcquireAddOn(
        targetVentureId: 'v1',
        addonSector: Sector.software,
        addonEbitdaCents: 100000,
        addonBuyMultipleMilli: 5000,
        addonFaceDebtCents: 50000,
      ),
      'DividendRecap': const DividendRecap(ventureId: 'v1', recapPctBp: 3000),
      'ExitVenture': const ExitVenture(
          ventureId: 'v2',
          offerMultipleMilli: 3500,
          liveMarketMultipleMilli: 3200),
      'HireCEO': const HireCEO(ventureId: 'v1', costCents: 500000),
      'SellPlay': const SellPlay(playId: 'p', purchasePriceCents: 400000),
      'Reroll': const Reroll(costCents: 250000),
      'PlayConsumable (context-free)':
          PlayConsumable(playId: 'p', deltas: const {'cash': -300000}),
      'PlayConsumable (targeted)': PlayConsumable(
        playId: 'p',
        targetVentureId: 'v1',
        deltas: const {'ebitda': 50000, 'own': -500, 'cash': -100000},
      ),
      'ReinvestBaseline':
          const ReinvestBaseline(ventureId: 'v1', amountCents: 1000000),
      // The 12th variant (PartnerEngine layer): fixedCost > 0 so the
      // scheduled-list write is exercised non-vacuously.
      'HirePartner': const HirePartner(
        ventureId: 'v1',
        defId: 'PRT_SALES_LEAD',
        costCents: 600000,
        perRoundEbitdaCents: 150000,
        fixedCostCents: 50000,
      ),
    };

// ---------------------------------------------------------------------------
// The flatten() walker (doc 03 §5) lives in helpers/flatten.dart — the ONE
// shared implementation, keyed by venture ID so venture add/remove shows up
// as added/removed paths, not index shifts. The golden replay contract
// serializes through the same walker, so the two tests can never disagree
// about what state "is".
// ---------------------------------------------------------------------------

/// All paths whose value changed, appeared, or disappeared between states.
Set<String> changedPaths(GameState before, GameState after) {
  final a = flatten(before);
  final b = flatten(after);
  return {
    for (final key in {...a.keys, ...b.keys})
      if (a[key] != b[key]) key,
  };
}

/// The five economic paths: the four per-venture inputs + global cash.
final RegExp _economicVenturePath =
    RegExp(r'^venture\.[^.]+\.(ebitda|multiple|netDebt|own)$');

/// Whitelisted bookkeeping (doc 02 §5.2.1 + this round's additions).
final RegExp _passivePath = RegExp(r'^venture\.[^.]+\.passive$');

/// roundsNeglected: bookkeeping (a counter, never money) — actions reset it
/// on their target, OPERATE increments it. Replay-relevant, hence flattened.
final RegExp _neglectPath = RegExp(r'^venture\.[^.]+\.roundsNeglected$');

/// displayName (schemaVersion 8): bookkeeping — a deterministic string
/// DERIVED from the venture's (id, sector), never money, never independently
/// writable (it is a getter, like netWorthCents). It appears/disappears with
/// the venture in the structural add/remove ops (StartVenture / ExitVenture)
/// and is otherwise constant, so it is a legal bookkeeping path. The §7
/// reconciliation (section c) still proves the structural op conjures no
/// economic value — the name rides along, it does not create one.
final RegExp _displayNamePath = RegExp(r'^venture\.[^.]+\.displayName$');
const Set<String> _bookkeepingPaths = {
  'actionLog.length',
  'rerollsUsed',
  'rngCursor',
  'round',
  'tier',
  'schemaVersion',
  // backgroundId (schemaVersion 9): the founder background carried on the
  // run state — access/setup bookkeeping, never economy. initRun seats it
  // and copyWith preserves it; NO action or step ever changes it, so it
  // never appears in an action diff, but it is a legal constant flatten path
  // (it steers the per-round plays grant — replay-relevant).
  'backgroundId',
  // doc 02 §5.2.1 whitelists "slot/play counters": play-costing actions
  // decrement playsRemaining by 1 on success (the round layer's gate).
  'playsRemaining',
};

/// The FROZEN draw-pool unlock snapshot paths (schemaVersion 10; R20b):
/// access/setup bookkeeping, never economy. initRun seats them and copyWith
/// preserves them; NO action or step ever changes them mid-run (the pool is
/// fixed at start — that is the whole point). They steer every draw, so they
/// are replay-relevant constant flatten paths — like backgroundId, legal but
/// never appearing in any action/step DIFF.
final RegExp _unlockedCardIdsPath = RegExp(r'^unlockedCardIds\.\d+$');
final RegExp _unlockedSectorsPath = RegExp(r'^unlockedSectors\.\d+$');

/// The three deal-flow deck path families (indexed flatten paths).
/// Deliberately NOT in [isAllowedPath]: deck writes are scoped to the draw
/// steps and the card-consuming actions (the work order's whitelist split).
final RegExp _handPath = RegExp(r'^hand\.\d+$');
final RegExp _shopOffersPath = RegExp(r'^shopOffers\.\d+$');
final RegExp _playsHeldPath = RegExp(r'^playsHeld\.\d+$');

/// Partner-engine membership paths (doc 02 §7 whitelists `partners[]`
/// membership). Scoped to HIRE_PARTNER only — no other action and NO step
/// may write an engine (OPERATE reads them; the accrual writes ebitda).
final RegExp _partnersPath = RegExp(r'^venture\.[^.]+\.partners\.\d+\.');

/// Scheduled-cost membership paths (doc 02 §7 whitelists `scheduled[]`
/// membership). Writable by HIRE_PARTNER (registers the fixed cost) and by
/// runOperate (fires/prunes entries at step 3c) — nobody else.
final RegExp _scheduledPath = RegExp(r'^scheduled\.\d+\.');

/// The exit-offer ticket paths (v5): deck-like — written by the hand
/// routine (OPERATE step 0, an ACT Reroll) and cleared by an EXIT of the
/// offered venture. Nobody else.
const Set<String> _exitOfferPaths = {
  'exitOffer.ventureId',
  'exitOffer.multiple',
};

/// The four consumable-flag paths (doc 02 §1 hotWindow/marketRead). NOT
/// generally writable: scoped to PlayConsumable (arms/reveals), ExitVenture
/// (clears a fired window), and OPERATE (the step-1 expiry sweep).
const Set<String> _marketFlagPaths = {
  'market.hotWindowArmed',
  'market.hotWindowExpiresRound',
  'market.marketReadHint',
  'market.marketReadExpiresRound',
};

/// The hot-window pair alone (what an EXIT may clear when it fires the
/// window — it never touches the read hint).
const Set<String> _hotWindowPaths = {
  'market.hotWindowArmed',
  'market.hotWindowExpiresRound',
};

/// Bookkeeping ONLY the OPERATE step may touch (market machinery, phase,
/// the step-9 snapshot, the F6 death). Deliberately NOT in [isAllowedPath]:
/// a player action that mutated the market would be a §7 violation and must
/// still fail. (The HOT_WINDOW / MARKET_READ consumable-flag paths widened
/// this case-by-case when they landed in round 10 — see [_marketFlagPaths];
/// OPERATE's step-1 expiry owns them too.)
const Set<String> _operateOnlyBookkeepingPaths = {
  'phase',
  'market.temp',
  'market.roundsInState',
  'market.stateDurationRounds',
  'market.liveRateBp',
  'market.hotWindowArmed', // step-1 expiry sweep
  'market.hotWindowExpiresRound',
  'market.marketReadHint',
  'market.marketReadExpiresRound',
  'netWorthLastRound', // doc 02 §2 step 9 snapshot (§5.1 whitelisted name)
  'death', // F6 bankruptcy
};

/// Bookkeeping ONLY the DEADLINE_CHECK step may touch (the advance + the
/// §5.1 tier-entry snapshot + the end-of-run flags). The five-input venture
/// paths cover the §3.3 reseed writes; actionLog covers its log entry.
/// NOTE: no deck path here — the fresh hand on an advance is the NEXT
/// OPERATE's draw (dealflow.dart timing contract).
const Set<String> _deadlineOnlyBookkeepingPaths = {
  'phase',
  'netWorthAtTierEntry',
  'won',
  'death',
};

bool isAllowedPath(String path) =>
    path == 'cash' ||
    _economicVenturePath.hasMatch(path) ||
    _passivePath.hasMatch(path) ||
    _neglectPath.hasMatch(path) ||
    _displayNamePath.hasMatch(path) ||
    _unlockedCardIdsPath.hasMatch(path) ||
    _unlockedSectorsPath.hasMatch(path) ||
    _bookkeepingPaths.contains(path);

/// runOperate: + market/phase/snapshot/death + the HAND + EXIT OFFER it
/// deals (step 0) + the scheduled entries it fires/prunes (step 3c).
bool isAllowedOperatePath(String path) =>
    isAllowedPath(path) ||
    _operateOnlyBookkeepingPaths.contains(path) ||
    _handPath.hasMatch(path) ||
    _exitOfferPaths.contains(path) ||
    _scheduledPath.hasMatch(path);

bool isAllowedDeadlinePath(String path) =>
    isAllowedPath(path) || _deadlineOnlyBookkeepingPaths.contains(path);

/// endTurn: phase + the OFFERS it deals (+ rngCursor via the base set).
bool isAllowedEndTurnPath(String path) =>
    path == 'phase' ||
    path == 'rngCursor' ||
    _shopOffersPath.hasMatch(path);

/// The per-ACTION deck allowances (the work order's whitelist split):
/// Reroll redraws the current phase's deck; the two inventory actions
/// consume from playsHeld. Every OTHER action gets NO deck path.
bool Function(String) extraAllowedFor(String label) {
  if (label == 'Reroll') {
    // An ACT reroll re-runs the FULL hand routine — exit offer included.
    return (p) =>
        _handPath.hasMatch(p) ||
        _shopOffersPath.hasMatch(p) ||
        _exitOfferPaths.contains(p);
  }
  if (label.startsWith('PlayConsumable')) {
    // The inventory consumption + the two consumable flags it may arm
    // (doc 02 §3.6 HOT_WINDOW / MARKET_READ — round 10).
    return (p) => _playsHeldPath.hasMatch(p) || _marketFlagPaths.contains(p);
  }
  if (label == 'SellPlay') {
    return _playsHeldPath.hasMatch;
  }
  if (label == 'ExitVenture') {
    // A fired hot window is cleared by the exit that consumed it
    // (doc 02 §3.7); an exit of the OFFERED venture clears the ticket.
    // The read hint is never exit-touched.
    return (p) => _hotWindowPaths.contains(p) || _exitOfferPaths.contains(p);
  }
  if (label == 'HirePartner') {
    // The engine push (partners[] membership) + the fixed-cost
    // registration (scheduled[] membership) — doc 02 §3.5 / §7.
    return (p) => _partnersPath.hasMatch(p) || _scheduledPath.hasMatch(p);
  }
  return (_) => false;
}

void main() {
  // -------------------------------------------------------------------------
  // (a) Content invariant: cards.json deltas
  // -------------------------------------------------------------------------
  group('(a) content: cards.json deltas obey the five-input invariant', () {
    test('all 33 cards key deltas only over {ebitda, multiple, netDebt, own, '
        'cash}', () {
      final raw = jsonDecode(
              File('../../data/cards.json').readAsStringSync())
          as List<dynamic>;
      expect(raw, hasLength(33),
          reason: 'cards.json card count changed — re-verify the content '
              'lint covers every new card');
      for (final card in raw.cast<Map<String, dynamic>>()) {
        final deltas = card['deltas'] as Map<String, dynamic>;
        expect(deltas.keys.toSet().difference(kMutableInputs), isEmpty,
            reason: 'card ${card['id']} writes outside the five inputs');
        expect(deltas, isNotEmpty,
            reason: 'card ${card['id']} has an empty deltas object');
      }
    });
  });

  // -------------------------------------------------------------------------
  // (b) Behavioral invariant: every action, diffed via flatten()
  // -------------------------------------------------------------------------
  group('(b) behavioral: every action touches only the five inputs + '
      'whitelisted bookkeeping', () {
    for (final entry in allActions().entries) {
      test(entry.key, () {
        final before = fixture();
        final result = apply(before, entry.value, rng(), kContent);
        final changed = changedPaths(before, result.state);
        // The action genuinely did something (success path, not a silent
        // rejection) ...
        expect(changed, isNotEmpty,
            reason: '${entry.key} was a no-op — fixture no longer reaches '
                'its success path');
        expect(
            result.events
                .where((e) => e.type == GameEventType.actionRejected),
            isEmpty,
            reason: '${entry.key} was rejected against the fixture');
        // ... and everything it touched is an economic path, whitelisted
        // bookkeeping, or ITS OWN deck allowance (Reroll: the redraw;
        // PlayConsumable/SellPlay: the playsHeld consumption). ANY other
        // path failing here is a §7 violation.
        final extra = extraAllowedFor(entry.key);
        final illegal =
            changed.where((p) => !isAllowedPath(p) && !extra(p)).toSet();
        expect(illegal, isEmpty,
            reason: '${entry.key} mutated forbidden state paths: $illegal');
      });
    }

    test('the action log grows on every success (autopsy trail)', () {
      for (final entry in allActions().entries) {
        final before = fixture();
        final result = apply(before, entry.value, rng(), kContent);
        expect(result.state.actionLog.length, before.actionLog.length + 1,
            reason: '${entry.key} did not log exactly one LoggedAction');
      }
    });

    test('the deck allowances are non-vacuous AND action-scoped: the '
        'Reroll diff redraws the hand; the inventory actions consume '
        'playsHeld; nobody else touches a deck', () {
      // Reroll (act): hand paths appear in ITS diff...
      final rerolled =
          apply(fixture(), const Reroll(costCents: 250000), rng(), kContent);
      final rerollChanged = changedPaths(fixture(), rerolled.state);
      expect(rerollChanged.where(_handPath.hasMatch), isNotEmpty,
          reason: 'the ACT reroll really redraws (non-vacuous allowance)');
      // ... and the consumption paths appear in the inventory actions':
      final played = apply(
          fixture(),
          PlayConsumable(playId: 'p', deltas: const {'cash': -300000}),
          rng(),
          kContent);
      expect(
          changedPaths(fixture(), played.state)
              .where(_playsHeldPath.hasMatch),
          isNotEmpty,
          reason: 'playing consumes the held play');
      // A non-card action (TakeDebt) touches NO deck path:
      final debt = apply(
          fixture(),
          const TakeDebt(
              ventureId: 'v1', proceedsCents: 1000000, faceDebtCents: 1150000),
          rng(),
          kContent);
      final debtChanged = changedPaths(fixture(), debt.state);
      expect(
          debtChanged.where((p) =>
              _handPath.hasMatch(p) ||
              _shopOffersPath.hasMatch(p) ||
              _playsHeldPath.hasMatch(p)),
          isEmpty,
          reason: 'deck writes are scoped to the card-consuming actions');
    });

    test('runOperate (hand draw + drift + decay + event + interest system '
        'events) touches only the five inputs + operate bookkeeping', () {
      // A fixture where EVERY operate sub-step moves something: a neglected
      // indebted active venture AND a neglected passive one (decay both
      // curves), debt (interest), EBITDA (yield), a market boundary
      // (transition draws + temp/duration writes).
      final before = GameState(
        ventures: const [
          Venture(
            id: 'v1',
            sector: Sector.software,
            ebitdaCents: 600000,
            multipleMilli: 14000,
            netDebtCents: 2000000,
            ownershipBp: 8000,
            roundsNeglected: 2,
          ),
          Venture(
            id: 'v2',
            sector: Sector.retail,
            ebitdaCents: 400000,
            multipleMilli: 3000,
            netDebtCents: 0,
            ownershipBp: 10000,
            passive: true,
            roundsNeglected: 3,
          ),
        ],
        cashCents: 5000000,
        round: 2,
        tier: 4,
        phase: PhaseId.operate,
        market: const MarketState(
          temp: MarketTemp.neutral,
          roundsInState: 2,
          stateDurationRounds: 2, // at the boundary: transition draws too
          liveRateBp: 0,
        ),
      );
      final result = runOperate(before, rng(), kContent);
      final changed = changedPaths(before, result.state);
      expect(changed, isNotEmpty);
      final illegal =
          changed.where((p) => !isAllowedOperatePath(p)).toSet();
      expect(illegal, isEmpty,
          reason: 'runOperate mutated forbidden state paths: $illegal');
      // And the operate-only paths really are exercised by this fixture, so
      // the whitelist is not vacuous (hand.0 = the step-0 deal):
      expect(changed,
          containsAll({'cash', 'market.liveRateBp', 'phase', 'hand.0'}));
      expect(
          changed.where((p) =>
              _shopOffersPath.hasMatch(p) || _playsHeldPath.hasMatch(p)),
          isEmpty,
          reason: 'OPERATE deals the HAND only — never the shop counter '
              'or the held inventory');
      expect(result.state.actionLog.length, before.actionLog.length,
          reason: 'OPERATE is a system step: it never writes the action '
              'log (the autopsy log is for player actions)');
    });

    test('player actions still may NOT touch the market/phase/snapshot '
        'bookkeeping (the step whitelists are step-scoped)', () {
      // Planted violation: if an action's diff contained a market path, the
      // (b) loop's isAllowedPath would reject it. Pin the predicate split
      // directly so a future merge of the whitelists fails here.
      expect(isAllowedPath('market.temp'), isFalse);
      expect(isAllowedPath('market.liveRateBp'), isFalse);
      expect(isAllowedPath('phase'), isFalse);
      expect(isAllowedPath('netWorthLastRound'), isFalse,
          reason: 'the §5.1 snapshots are step-owned, never action-written');
      expect(isAllowedPath('netWorthAtTierEntry'), isFalse);
      expect(isAllowedPath('won'), isFalse);
      expect(isAllowedPath('death'), isFalse);
      expect(isAllowedPath('playsRemaining'), isTrue,
          reason: 'doc 02 §5.2.1 whitelists play counters: paid actions '
              'decrement playsRemaining on success');
      // Consumable flags: scoped, never general (round 10 planted pins).
      expect(isAllowedPath('market.hotWindowArmed'), isFalse);
      expect(isAllowedPath('market.marketReadHint'), isFalse);
      expect(extraAllowedFor('PlayConsumable (context-free)')(
              'market.hotWindowArmed'),
          isTrue);
      expect(
          extraAllowedFor('PlayConsumable (targeted)')(
              'market.marketReadExpiresRound'),
          isTrue);
      expect(extraAllowedFor('ExitVenture')('market.hotWindowArmed'), isTrue,
          reason: 'a fired window is cleared by the exit');
      expect(extraAllowedFor('ExitVenture')('market.marketReadHint'),
          isFalse, reason: 'an exit never touches the read hint');
      expect(extraAllowedFor('TakeDebt')('market.hotWindowArmed'), isFalse);
      expect(isAllowedOperatePath('market.hotWindowArmed'), isTrue,
          reason: 'OPERATE step 1 sweeps expired flags');
      expect(isAllowedOperatePath('market.marketReadHint'), isTrue);
      expect(isAllowedOperatePath('market.temp'), isTrue);
      expect(isAllowedOperatePath('phase'), isTrue);
      expect(isAllowedOperatePath('netWorthLastRound'), isTrue);
      expect(isAllowedOperatePath('netWorthAtTierEntry'), isFalse,
          reason: 'the tier-entry snapshot belongs to DEADLINE_CHECK only');
      expect(isAllowedOperatePath('won'), isFalse);
      expect(isAllowedDeadlinePath('netWorthAtTierEntry'), isTrue);
      expect(isAllowedDeadlinePath('won'), isTrue);
      expect(isAllowedDeadlinePath('market.temp'), isFalse,
          reason: 'DEADLINE_CHECK never touches the market');
      expect(isAllowedDeadlinePath('netWorthLastRound'), isFalse,
          reason: 'the step-9 snapshot belongs to OPERATE only');
      // and the five inputs stay allowed for every step:
      expect(isAllowedOperatePath('cash'), isTrue);
      expect(isAllowedDeadlinePath('cash'), isTrue);
      expect(isAllowedPath('venture.v1.roundsNeglected'), isTrue,
          reason: 'targeting resets neglect — action-side bookkeeping');
    });

    test('the DECK whitelists are split by step AND by action (planted '
        'predicate pins)', () {
      // Base actions: NO deck path is generally writable.
      expect(isAllowedPath('hand.0'), isFalse);
      expect(isAllowedPath('shopOffers.0'), isFalse);
      expect(isAllowedPath('playsHeld.0'), isFalse);
      // OPERATE deals the hand — and ONLY the hand.
      expect(isAllowedOperatePath('hand.0'), isTrue);
      expect(isAllowedOperatePath('hand.4'), isTrue);
      expect(isAllowedOperatePath('shopOffers.0'), isFalse,
          reason: 'the shop counter belongs to endTurn');
      expect(isAllowedOperatePath('playsHeld.0'), isFalse);
      // endTurn deals the offers — and ONLY the offers.
      expect(isAllowedEndTurnPath('shopOffers.0'), isTrue);
      expect(isAllowedEndTurnPath('shopOffers.2'), isTrue);
      expect(isAllowedEndTurnPath('phase'), isTrue);
      expect(isAllowedEndTurnPath('rngCursor'), isTrue,
          reason: 'endTurn draws now, so the mirror reconciles');
      expect(isAllowedEndTurnPath('hand.0'), isFalse);
      expect(isAllowedEndTurnPath('cash'), isFalse,
          reason: 'END_TURN still has no economic delta (doc 02 §3.11)');
      // DEADLINE_CHECK touches NO deck (the fresh hand is the next
      // OPERATE's draw).
      expect(isAllowedDeadlinePath('hand.0'), isFalse);
      expect(isAllowedDeadlinePath('shopOffers.0'), isFalse);
      expect(isAllowedDeadlinePath('playsHeld.0'), isFalse);
      // Per-action: Reroll redraws decks; the inventory pair consumes
      // playsHeld; an arbitrary other action gets nothing.
      expect(extraAllowedFor('Reroll')('hand.0'), isTrue);
      expect(extraAllowedFor('Reroll')('shopOffers.1'), isTrue);
      expect(extraAllowedFor('Reroll')('playsHeld.0'), isFalse,
          reason: 'a reroll never touches the held inventory');
      expect(extraAllowedFor('SellPlay')('playsHeld.0'), isTrue);
      expect(extraAllowedFor('PlayConsumable (targeted)')('playsHeld.1'),
          isTrue);
      expect(extraAllowedFor('SellPlay')('hand.0'), isFalse);
      expect(extraAllowedFor('TakeDebt')('hand.0'), isFalse);
      expect(extraAllowedFor('TakeDebt')('playsHeld.0'), isFalse);
      // Partner/scheduled membership is HIRE_PARTNER-scoped (+ OPERATE's
      // step-3c fire/prune for scheduled) — planted pins:
      expect(extraAllowedFor('HirePartner')('venture.v1.partners.0.defId'),
          isTrue);
      expect(extraAllowedFor('HirePartner')('scheduled.0.cashDelta'),
          isTrue);
      expect(extraAllowedFor('HirePartner')('hand.0'), isFalse,
          reason: 'a hire never touches a deck (playCard owns the hand '
              'consumption path)');
      expect(extraAllowedFor('TakeDebt')('venture.v1.partners.0.defId'),
          isFalse);
      expect(extraAllowedFor('TakeDebt')('scheduled.0.cashDelta'), isFalse);
      expect(isAllowedPath('venture.v1.partners.0.defId'), isFalse,
          reason: 'partner membership is never generally writable');
      expect(isAllowedPath('scheduled.0.recurring'), isFalse);
      expect(isAllowedOperatePath('scheduled.0.cashDelta'), isTrue,
          reason: 'OPERATE step 3c fires and prunes scheduled entries');
      expect(isAllowedOperatePath('venture.v1.partners.0.defId'), isFalse,
          reason: 'OPERATE reads engines (the accrual writes ebitda) but '
              'never attaches/removes one');
      expect(isAllowedEndTurnPath('scheduled.0.cashDelta'), isFalse);
      expect(isAllowedDeadlinePath('scheduled.0.cashDelta'), isFalse);
      // The exit-offer ticket is deck-like (v5): hand-routine + exit only.
      expect(isAllowedPath('exitOffer.ventureId'), isFalse);
      expect(isAllowedOperatePath('exitOffer.ventureId'), isTrue);
      expect(isAllowedOperatePath('exitOffer.multiple'), isTrue);
      expect(extraAllowedFor('Reroll')('exitOffer.multiple'), isTrue,
          reason: 'an ACT reroll re-runs the full hand routine');
      expect(extraAllowedFor('ExitVenture')('exitOffer.ventureId'), isTrue,
          reason: 'exiting the offered venture clears the ticket');
      expect(extraAllowedFor('TakeDebt')('exitOffer.ventureId'), isFalse);
      expect(isAllowedEndTurnPath('exitOffer.ventureId'), isFalse,
          reason: 'the shop deal never touches the offer');
      expect(isAllowedDeadlinePath('exitOffer.ventureId'), isFalse);
    });

    test('a PLANTED rogue deck mutation routed through the (b) diff '
        'machinery is caught for a non-card action', () {
      final before = fixture();
      final rogue = before.copyWith(
        cashCents: before.cashCents - 1000, // a legal economic delta
        hand: const ['VEN_SW_GARAGE'], // §7-forbidden for, say, TakeDebt
        playsHeld: const [], // rogue consumption ('p' vanished)
      );
      final changed = changedPaths(before, rogue);
      final extra = extraAllowedFor('TakeDebt');
      final illegal =
          changed.where((p) => !isAllowedPath(p) && !extra(p)).toSet();
      expect(illegal, {'hand.0', 'playsHeld.0'},
          reason: 'every planted deck write surfaces; the legal cash '
              'delta does not');
    });

    test('a PLANTED rogue mutation (market/phase/snapshot) routed through '
        'the (b) diff machinery is caught end-to-end', () {
      // Simulate what a buggy action WOULD produce: a legal cash delta plus
      // §7-forbidden writes. The exact walker + predicate the (b) loop uses
      // must flag every planted path and nothing else.
      final before = fixture();
      final rogue = before.copyWith(
        cashCents: before.cashCents - 1000, // a legal economic delta
        market: before.market.copyWith(temp: MarketTemp.hot),
        phase: PhaseId.shop,
        netWorthLastRound: 999999,
      );
      final changed = changedPaths(before, rogue);
      final illegal = changed.where((p) => !isAllowedPath(p)).toSet();
      expect(illegal, {'market.temp', 'phase', 'netWorthLastRound'},
          reason: 'every planted write surfaces as a §7 violation; the '
              'legal cash delta does not');
    });

    test('runDeadlineCheck (tier clear + the §3.3 reseed SYSTEM EVENT) '
        'touches only the five inputs + deadline bookkeeping', () {
      // A clearing fixture: NW = 168e6 stake + 32e6 cash = 200e6 >= the T1
      // bar, so the diff covers the reseed writes (ebitda/multiple), the
      // advance (round/tier/phase/plays/rerolls), the snapshot, and the log.
      final before = GameState(
        ventures: const [
          Venture(
            id: 'plat',
            sector: Sector.software,
            ebitdaCents: 12000000,
            multipleMilli: 14000,
            netDebtCents: 0,
            ownershipBp: 10000,
          ),
        ],
        cashCents: 32000000,
        round: 3,
        tier: 1,
        rerollsUsed: 2,
        phase: PhaseId.shop,
      );
      final result = runDeadlineCheck(before);
      final changed = changedPaths(before, result.state);
      expect(changed, isNotEmpty);
      final illegal =
          changed.where((p) => !isAllowedDeadlinePath(p)).toSet();
      expect(illegal, isEmpty,
          reason: 'runDeadlineCheck mutated forbidden state paths: '
              '$illegal');
      // The deadline-only paths really are exercised (non-vacuous):
      expect(
          changed,
          containsAll({
            'venture.plat.ebitda', // the reseed IS five-input deltas
            'venture.plat.multiple',
            'netWorthAtTierEntry',
            'tier',
            'round',
            'phase',
            'actionLog.length', // the reseed is logged (doc 01 §3.3)
          }));
      // RESEED RECONCILIATION (doc 02 §5.2.2 extended to the system event):
      // the net-worth move equals the reseeded venture's stake delta — cash
      // carried as-is, nothing conjured outside the five inputs.
      expect(result.state.netWorthCents - before.netWorthCents, -94000000,
          reason: 'R12 carrySeedFrac 0.37: stake 168e6 -> 0.37x200e6 = 74e6');
      expect(result.state.cashCents, before.cashCents);
      expect(result.state.netWorthCents,
          lessThanOrEqualTo(before.netWorthCents),
          reason: 'the reseed haircut only ever REDUCES derived net worth');
    });

    test('endTurn touches only phase + the offers it deals + the cursor '
        'mirror', () {
      final before = fixture();
      final after = endTurn(before, rng(), kContent);
      final changed = changedPaths(before, after);
      final illegal =
          changed.where((p) => !isAllowedEndTurnPath(p)).toSet();
      expect(illegal, isEmpty,
          reason: 'endTurn mutated forbidden state paths: $illegal');
      // Non-vacuous: the deal really happened.
      expect(changed, containsAll({'phase', 'shopOffers.0', 'rngCursor'}));
    });

    test('buyShopOffer (the SHOP counter) touches only cash + the offer '
        'consumption + the held push + the log', () {
      // A shop-phase fixture holding an offered consumable and room to buy.
      final before = fixture().copyWith(
        phase: PhaseId.shop,
        shopOffers: const ['PLY_MARKET_READ', 'FIN_TERM_LOAN'],
        playsHeld: const [],
      );
      final result = buyShopOffer(before, 'PLY_MARKET_READ', kContent);
      expect(
          result.events
              .where((e) => e.type == GameEventType.actionRejected),
          isEmpty,
          reason: 'the buy must reach its success path');
      final changed = changedPaths(before, result.state);
      bool allowed(String p) =>
          p == 'cash' ||
          p == 'actionLog.length' ||
          _shopOffersPath.hasMatch(p) ||
          _playsHeldPath.hasMatch(p);
      final illegal = changed.where((p) => !allowed(p)).toSet();
      expect(illegal, isEmpty,
          reason: 'buyShopOffer mutated forbidden state paths: $illegal');
      expect(
          changed,
          containsAll(
              {'cash', 'playsHeld.0', 'shopOffers.0', 'actionLog.length'}),
          reason: 'non-vacuous: the offer left the counter and joined the '
              'inventory, cash moved, the buy was logged');
    });

    test('playCard (an addon merge from the hand) reconciles to the '
        'underlying action + the hand consumption', () {
      final before = fixture().copyWith(hand: const ['ADD_SW_PLUGIN']);
      final result = playCard(before, 'ADD_SW_PLUGIN', rng(), kContent,
          targetVentureId: 'v1');
      expect(
          result.events
              .where((e) => e.type == GameEventType.actionRejected),
          isEmpty,
          reason: 'the play must reach its success path');
      final changed = changedPaths(before, result.state);
      bool allowed(String p) =>
          isAllowedPath(p) || _handPath.hasMatch(p);
      final illegal = changed.where((p) => !allowed(p)).toSet();
      expect(illegal, isEmpty,
          reason: 'playCard mutated forbidden state paths: $illegal');
      expect(changed, contains('hand.0'),
          reason: 'the played card left the hand (non-vacuous)');
      expect(result.state.hand, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // (b2) No-unwinnable-hand (doc 02 §5.2 #5; §Q3)
  // -------------------------------------------------------------------------
  group('(b2) no-unwinnable-hand (doc 02 §5.2 #5)', () {
    // Doc 02 §5.2 #5: "every drawn hand contains a legal REINVEST path
    // within current cash, or the baseline reinvest is injected." The
    // engine's answer is STRUCTURAL: ReinvestBaseline is an always-
    // available ACTION (doc 03 §4.1), never a card — the baseline is
    // permanently "injected", so no draw can brick a run. These tests pin
    // that property against live draws.
    test('across a 60-seed sweep, the baseline reinvest is legal no '
        'matter WHAT the hand contains', () {
      for (var seed = 0; seed < 60; seed++) {
        // A modest one-venture T1 state, mid-ACT after a real hand draw.
        var state = GameState(
          ventures: const [
            Venture(
              id: 'v1',
              sector: Sector.software,
              ebitdaCents: 600000,
              multipleMilli: 6000,
              netDebtCents: 0,
              ownershipBp: 10000,
            ),
          ],
          cashCents: 50000,
          round: 1,
          tier: 1,
          phase: PhaseId.operate,
        );
        final rng = SplitMix64Rng(seed);
        state = runOperate(state, rng, kContent).state;
        if (state.phase != PhaseId.act) continue; // debt-free: unreachable
        final result = apply(
            state,
            ReinvestBaseline(
                ventureId: 'v1',
                amountCents:
                    state.cashCents < 10000 ? state.cashCents : 10000),
            rng,
            kContent);
        expect(
            result.events
                .where((e) => e.type == GameEventType.actionRejected),
            isEmpty,
            reason: 'seed $seed: the baseline must be playable within '
                'current cash regardless of the dealt hand '
                '(${state.hand})');
      }
    });

    test('even at ZERO cash the baseline degenerates legally (amount 0, '
        'gain 0) — a hand can never be a dead end', () {
      final state = GameState(
        ventures: const [
          Venture(
            id: 'v1',
            sector: Sector.software,
            ebitdaCents: 600000,
            multipleMilli: 6000,
            netDebtCents: 0,
            ownershipBp: 10000,
          ),
        ],
        cashCents: 0,
        round: 2,
        tier: 1,
        phase: PhaseId.act,
        playsRemaining: 2,
        hand: const ['VEN_SW_GARAGE'], // unaffordable — the hand is "bad"
      );
      final result = apply(state,
          const ReinvestBaseline(ventureId: 'v1', amountCents: 0),
          rng(), kContent);
      expect(
          result.events
              .where((e) => e.type == GameEventType.actionRejected),
          isEmpty,
          reason: 'cash >= amount holds at 0 >= 0: the baseline is never '
              'gated away');
    });

    test('every dealt hand card is an ACT-PLAYABLE type '
        '(venture/addon/partner since v5) — the pool can never deal a card '
        'the resolver cannot honestly apply', () {
      for (var seed = 0; seed < 60; seed++) {
        final state = GameState(
          ventures: const [],
          cashCents: 0,
          tier: 5, // the widest pool
          phase: PhaseId.act,
        );
        final dealt =
            apply(state, const Reroll(costCents: 0), SplitMix64Rng(seed),
                    kContent)
                .state
                .hand;
        expect(dealt.length, inInclusiveRange(3, 5), reason: 'seed $seed');
        for (final id in dealt) {
          final type = kContent.byId(id).type;
          expect(
              type == CardType.venture ||
                  type == CardType.addon ||
                  type == CardType.partner,
              isTrue,
              reason: 'seed $seed dealt a ${type.name} into the hand — '
                  'partners JOINED the pool at v5 (the PartnerEngine layer '
                  'is live); events and financing/consumables keep their '
                  'own channels');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // (c) Structural-op reconciliation (doc 02 §3 note + §5.2.2)
  // -------------------------------------------------------------------------
  group('(c) reconciliation: structural ops conjure no value', () {
    test('StartVenture: dNetWorth == the new venture stake - the price', () {
      final before = fixture();
      const action = StartVenture(
        ventureId: 'v3',
        sector: Sector.services,
        ebitdaCents: 500000,
        multipleMilli: 6000,
        priceCents: 1000000,
        faceDebtCents: 200000,
      );
      final after = apply(before, action, rng(), kContent).state;
      final newVenture = after.ventures.firstWhere((v) => v.id == 'v3');
      final stake =
          (equityValueOf(newVenture) * newVenture.ownershipBp) ~/ bpScale;
      expect(after.netWorthCents - before.netWorthCents,
          stake - action.priceCents,
          reason: 'a venture add must reconcile to stake-in minus cash-out');
      // Pinned absolutely too: EV 3,000,000 - debt 200,000 at 100% = a
      // 2,800,000 stake for 1,000,000 cash -> dNW = +1,800,000.
      expect(after.netWorthCents - before.netWorthCents, 1800000);
    });

    test('ExitVenture: dNetWorth == proceeds - the removed venture stake', () {
      final before = fixture();
      final exited = before.ventures.firstWhere((v) => v.id == 'v2');
      final preStake =
          (equityValueOf(exited) * exited.ownershipBp) ~/ bpScale;
      const action = ExitVenture(
          ventureId: 'v2',
          offerMultipleMilli: 3500,
          liveMarketMultipleMilli: 3200);
      final result = apply(before, action, rng(), kContent);
      final proceeds = result.events
          .firstWhere((e) => e.type == GameEventType.exitRealized)
          .amount;
      expect(result.state.netWorthCents - before.netWorthCents,
          proceeds - preStake,
          reason: 'a venture remove must reconcile to cash-in minus '
              'stake-out');
      // Pinned absolutely: exit at min(3500, 3200) = 3200 -> proceeds
      // 1,280,000 vs a 1,200,000 stake at the stored 3000 multiple.
      expect(proceeds, 1280000);
      expect(result.state.netWorthCents - before.netWorthCents, 80000);
    });
  });

  // -------------------------------------------------------------------------
  // (d) Directionality: signs, not magnitudes (doc 02 §5.2.3)
  // -------------------------------------------------------------------------
  group('(d) directionality (signs are real even where magnitudes are '
      'gamified)', () {
    int netDebtOf(GameState s, String id) =>
        s.ventures.firstWhere((v) => v.id == id).netDebtCents;

    test('TakeDebt strictly increases netDebt', () {
      final before = fixture();
      final after = apply(
              before,
              const TakeDebt(
                  ventureId: 'v1',
                  proceedsCents: 1000000,
                  faceDebtCents: 1150000),
              rng(),
              kContent)
          .state;
      expect(netDebtOf(after, 'v1'), greaterThan(netDebtOf(before, 'v1')));
    });

    test('DividendRecap strictly increases netDebt', () {
      final before = fixture();
      final after = apply(before,
              const DividendRecap(ventureId: 'v1', recapPctBp: 3000), rng(),
              kContent)
          .state;
      expect(netDebtOf(after, 'v1'), greaterThan(netDebtOf(before, 'v1')));
    });

    test('RaiseEquity strictly decreases ownership and increases cash', () {
      final before = fixture();
      final after = apply(before,
              const RaiseEquity(ventureId: 'v1', raiseCents: 1000000), rng(),
              kContent)
          .state;
      final ownBefore =
          before.ventures.firstWhere((v) => v.id == 'v1').ownershipBp;
      final ownAfter =
          after.ventures.firstWhere((v) => v.id == 'v1').ownershipBp;
      expect(ownAfter, lessThan(ownBefore));
      expect(after.cashCents, greaterThan(before.cashCents));
    });

    test('a same-sector merge is net-accretive at a fixed multiple', () {
      // Buy cheap earnings (5x) onto the expensive 14x platform: the
      // absorbed EBITDA revalues up, so dNW > 0 with the multiple unchanged.
      final before = fixture();
      final result = apply(
          before,
          const AcquireAddOn(
            targetVentureId: 'v1',
            addonSector: Sector.software,
            addonEbitdaCents: 100000,
            addonBuyMultipleMilli: 5000,
            addonFaceDebtCents: 0,
          ),
          rng(),
          kContent);
      final mBefore =
          before.ventures.firstWhere((v) => v.id == 'v1').multipleMilli;
      final mAfter =
          result.state.ventures.firstWhere((v) => v.id == 'v1').multipleMilli;
      expect(mAfter, mBefore); // fixed multiple
      expect(result.state.netWorthCents, greaterThan(before.netWorthCents));
    });

    test('a cross-sector merge drags the platform multiple down', () {
      final before = fixture();
      final result = apply(
          before,
          const AcquireAddOn(
            targetVentureId: 'v1',
            addonSector: Sector.industrial,
            addonEbitdaCents: 100000,
            addonBuyMultipleMilli: 5000,
            addonFaceDebtCents: 0,
          ),
          rng(),
          kContent);
      final mBefore =
          before.ventures.firstWhere((v) => v.id == 'v1').multipleMilli;
      final mAfter =
          result.state.ventures.firstWhere((v) => v.id == 'v1').multipleMilli;
      expect(mAfter, lessThan(mBefore));
    });
  });

  // -------------------------------------------------------------------------
  // (e) No score-shaped writable state on the model (doc 02 §5.1/§5.2.1)
  // -------------------------------------------------------------------------
  group('(e) no writable score/netWorth/points state on the model', () {
    // GameState/Venture have only final fields (compile-time argument: any
    // assignment like `state.netWorthCents = x` is a compile error because
    // no such setter exists). This scan backs that with the §5.2 name rule
    // against future regressions: any non-comment model.dart line naming
    // score|netWorth|points must be the derived GETTER, never a field or
    // setter declaration — EXCEPT the doc 02 §5.1 SCORE_SNAPSHOT_WHITELIST,
    // matched by EXACT name (the two write-once meter baselines; their
    // occurrences are stripped from a line before the rule applies, so a
    // line naming ONLY whitelisted snapshots passes while any OTHER
    // score-like name on the same line still fails).
    final source = File('lib/model.dart').readAsLinesSync();
    final namePattern = RegExp('score|netWorth|points', caseSensitive: false);
    const scoreSnapshotWhitelist = ['netWorthAtTierEntry', 'netWorthLastRound'];
    String stripWhitelisted(String line) {
      var out = line;
      for (final name in scoreSnapshotWhitelist) {
        out = out.replaceAll(name, '');
      }
      return out;
    }

    test('every score-named code line is a getter, never a field/setter '
        '(whitelisted snapshots aside)', () {
      var getterSeen = false;
      for (var i = 0; i < source.length; i++) {
        final line = stripWhitelisted(source[i].trim());
        if (line.startsWith('//') || line.startsWith('*')) continue;
        if (!namePattern.hasMatch(line)) continue;
        expect(line.contains('get '), isTrue,
            reason: 'lib/model.dart:${i + 1} names score-like state outside '
                'a getter: "$line"');
        expect(line.contains('set '), isFalse,
            reason: 'lib/model.dart:${i + 1} declares a score-like setter');
        getterSeen = true;
      }
      // The scan is not vacuous: the derived netWorthCents getter exists.
      expect(getterSeen, isTrue,
          reason: 'expected to find the netWorthCents getter in model.dart');
    });

    test('the §5.1 whitelisted snapshots exist as FINAL (write-once) '
        'fields, by exact name', () {
      final whole = source.join('\n');
      for (final name in scoreSnapshotWhitelist) {
        expect(whole.contains('final int $name;'), isTrue,
            reason: '$name must be a final int field — write-once at '
                'construction, no setter (doc 02 §5.1)');
      }
      // The whitelist strip is surgical: a name it does not list still
      // trips the rule (planted check on the stripper itself).
      expect(namePattern.hasMatch(stripWhitelisted('int netWorthHack = 1;')),
          isTrue,
          reason: 'stripping must not swallow non-whitelisted score names');
      expect(
          namePattern
              .hasMatch(stripWhitelisted('final int netWorthAtTierEntry;')),
          isFalse,
          reason: 'a line naming only whitelisted snapshots passes');
    });

    test('no setter named like score/netWorth/points anywhere in the model',
        () {
      final whole = source.join('\n');
      expect(
          RegExp(r'set\s+\w*(score|networth|points)\w*',
                  caseSensitive: false)
              .hasMatch(whole),
          isFalse);
    });

    test('netWorthCents is derived: rebuilding from raw fields reproduces it',
        () {
      // No hidden stored component: a state rebuilt from nothing but the
      // five inputs + bookkeeping computes the identical net worth.
      final s = fixture();
      final rebuilt = GameState(
        ventures: [
          for (final v in s.ventures)
            Venture(
              id: v.id,
              sector: v.sector,
              ebitdaCents: v.ebitdaCents,
              multipleMilli: v.multipleMilli,
              netDebtCents: v.netDebtCents,
              ownershipBp: v.ownershipBp,
              passive: v.passive,
            ),
        ],
        cashCents: s.cashCents,
      );
      expect(rebuilt.netWorthCents, s.netWorthCents);
      expect(s.netWorthCents, netWorth(s.ventures, s.cashCents)); // F3
    });
  });
}
