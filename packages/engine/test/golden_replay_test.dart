// The golden replay-determinism contract, VERSION 8 (doc 03 §3/§3.1/§6).
//
// *** ANY CHANGE TO A GOLDEN FILE IS STREAM-BREAKING (docs/03 §6) ***
// test/golden/replay_seed42_v8.txt pins (seed 42, the scripted gameplay-
// completeness run below) -> byte-identical end state. If this test fails
// because engine behavior changed, that change broke every in-progress
// save and replay: NEVER edit the golden in place — version a NEW file
// (v9), point this test at it, and bump engineSchemaVersion so old runs
// are abandoned, not silently mis-replayed. A migration cannot fix a
// moved stream.
//
// v7 -> v8 (the locked docs/03 §6 procedure, eighth execution — the R13
// SAVE-PERSISTENCE round): the PERSISTED CONTRACT changed. run.json is now
// the docs/06 minimal record {seed, cursor, startConfig:{runId,
// backgroundId}, actionLog} replayed through the engine, and the
// actionLog's on-disk form is serialize.dart's typed RunStep journal —
// part of the on-disk contract now. Additive to the state too: every
// venture gained a deterministic displayName (R9/R11's "V1 vs NIMBUS"
// flag), which flatten() serializes, so the golden's path SET grew by one
// venture.displayName line per venture (here just venture.v1.displayName=
// NIMBUS). The RNG DRAW ORDER IS UNCHANGED (cursor still 28; nothing in
// the R13 work touches the stream) — the bump is the persisted-contract
// change + the widened flatten, not a moved stream. replay_seed42_v7.txt
// is RETIRED — sealed below like v1..v6.
//
// v6 -> v7 (the locked docs/03 §6 procedure, seventh execution — the R12
// balance round's TUNING PASS, measured by tool/sim.dart against doc 01
// §11's bands): organicGrowthDefault 0.10 -> 0.20, interestMax 0.14 ->
// 0.12, crunch rateMul 1.8 -> 1.3, crunch entry 0.18 -> 0.12, recapPct
// 0.30 -> 0.16, carrySeedFrac 0.24 -> 0.37, deadlineRounds [8,8,9,10] ->
// [9,10,9,10]. The RNG DRAW ORDER IS UNCHANGED (cursor still 28; the
// boundary draw's hot bucket did not move) — the bump is for the moved
// VALUES: the EBITDA path (organic) and the live-rate values (interest
// band) land differently, so a v6 save replayed here diverges.
// replay_seed42_v6.txt is RETIRED — sealed below like v1..v5.
//
// v5 -> v6 (the locked docs/03 §6 + docs/06 §3.1 procedure, sixth
// execution — the R12 balance round's ORGANIC GROWTH): economy
// constants.organicGrowthDefault (0.10/round, doc 01 §3.2/§6.1 step 3 —
// parsed since Phase 2, never applied) now lands at OPERATE step 3a on
// PARTNERED ventures, and initRun attaches the FOUNDING OPERATOR (a
// 0-face PartnerEngine) to the seed venture. The RNG DRAW ORDER IS
// UNCHANGED from v5 (the cursor pin below is still 28) — the bump is for
// the moved VALUES: every partnered venture's EBITDA path compounds
// differently, so a v5 save replayed on this engine lands a different
// state. replay_seed42_v5.txt is RETIRED — kept byte-for-byte, never
// edited, sealed by the retirement tests below — exactly as v1..v4 were.
//
// The v5 script covers the round-10 systems END TO END: initRun ->
// round 1 OPERATE (the dead-draw-filtered 3-card T1 hand: both addons +
// the partner; the exit-offer pair) -> HIRE PARTNER from the hand + the
// ADD_SW_PLUGIN merge -> endTurn -> a SHOP consumable buy ->
// DEADLINE_CHECK advance -> round 2 OPERATE at the market boundary (the
// partner's +150k accrues pre-yield) -> the held consumable played (the
// MARKET_READ hint when dealt — flags in the end state) -> reinvest ->
// final flatten + cursor. Systems no T1 slice card reaches in-script
// (raise riders: FIN_SEED_RAISE is tierGate 2; the hot-window exit:
// PLY_HOT_WINDOW is tierGate 2; partner FIXED costs: no v1 schema face)
// are pinned by their own unit suites (action_raise_equity_test,
// consumable_flags_test, action_hire_partner_test).
//
// All money is integer cents; no floating point anywhere in this test.

import 'dart:io';

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/content.dart';
import 'package:engine/dealflow.dart';
import 'package:engine/init.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart';
import 'package:engine/rng.dart';
import 'package:engine/round.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';
import 'helpers/flatten.dart';

/// The pinned run seed for this contract.
const int kSeed = 42;

/// The committed golden snapshot (version 10 — never edit in place).
const String kGoldenPathV10 = 'test/golden/replay_seed42_v10.txt';

/// The RETIRED version-9 golden (schemaVersion 9, the backgroundId-on-state
/// era, before the R20b draw-pool keystone widened the pool + the state).
const String kGoldenPathV9 = 'test/golden/replay_seed42_v9.txt';

/// The RETIRED version-8 golden (schemaVersion 8, the save-persistence era,
/// before backgroundId-on-state / secondary-sale resolver / endless
/// escalation).
const String kGoldenPathV8 = 'test/golden/replay_seed42_v8.txt';

/// The RETIRED version-7 golden (schemaVersion 7, the tuning-pass era,
/// before the save-persistence contract + venture displayName).
const String kGoldenPathV7 = 'test/golden/replay_seed42_v7.txt';

/// The RETIRED version-6 golden (schemaVersion 6, the pre-tuning-pass
/// constants: organic 0.10 / interestMax 0.14 / crunch 1.8).
const String kGoldenPathV6 = 'test/golden/replay_seed42_v6.txt';

/// The RETIRED version-5 golden (schemaVersion 5, pre-organic-growth era).
const String kGoldenPathV5 = 'test/golden/replay_seed42_v5.txt';

/// The RETIRED version-4 golden (schemaVersion 4, deal-flow era).
const String kGoldenPathV4 = 'test/golden/replay_seed42_v4.txt';

/// The RETIRED version-3 golden (schemaVersion 3, round-machine era).
const String kGoldenPathV3 = 'test/golden/replay_seed42_v3.txt';

/// The RETIRED version-2 golden (schemaVersion 2, OPERATE-layer era).
const String kGoldenPathV2 = 'test/golden/replay_seed42_v2.txt';

/// The RETIRED version-1 golden (schemaVersion 1, all-zero cursor era).
const String kGoldenPathV1 = 'test/golden/replay_seed42_v1.txt';

/// Header written into the v10 golden file; part of the exact-equality
/// contract.
const String kGoldenHeader = '''
# Golden replay snapshot v10 — MULTIPLES engine (Phase 6 / R20b DRAW-POOL
# KEYSTONE). (seed 42, the scripted run in test/golden_replay_test.dart,
# now started with the FULL unlocked card set + all six sectors so the pool
# is the whole content: initRun (founding operator; full unlock pool) ->
# operate (organic compounding; the EVENT pool now includes the gate-1
# EVT_VIRAL_QUARTER — the keystone's newly-drawable card) -> hire partner +
# merge -> shop deal + SHOP reroll + buy -> advance -> boundary operate
# (organic + partner accrual) -> held play -> reinvest)
# -> this exact end state, one path=value per line, sorted.
# Supersedes replay_seed42_v9.txt (RETIRED at engineSchemaVersion 10). The
# state gained the FROZEN draw-pool unlock snapshot
# (unlockedCardIds.*/unlockedSectors.*, serialized by flatten()), and the
# DRAW POOL WIDENED from content.verticalSlice to `content.cards` ∩ the
# per-run unlocked predicate — so the event pool grew and every
# no-replacement draw index moved (a MOVED STREAM, docs/03 §6). Also: the
# PLY_SPIN_OFF/PLY_EARN_OUT resolvers + the ScheduledCost roundsLeft/
# pctEbitdaBp widening landed (pinned by spin_off_earn_out_test).
# ANY change to this file is STREAM-BREAKING: never edit it in place.
# Version a new file (v11), point the test at it, and bump
# engineSchemaVersion so in-progress runs are abandoned, not mis-replayed.
''';

/// Replays the scripted run (the round-10 gameplay-completeness script,
/// carried unchanged since v5 and pinned by the v8 golden) from the
/// canonical initRun opening with a fresh seed-42 stream, asserting every
/// step lands its success path. Returns the end state and the RNG (for its
/// final cursor).
({GameState state, SplitMix64Rng rng}) replay() {
  void expectClean(ApplyResult r, String step) {
    expect(r.events.any((e) => e.type == GameEventType.actionRejected),
        isFalse,
        reason: '$step was rejected — the script no longer reaches its '
            'success path');
  }

  // R20b: the run is started with the FULL unlocked card set + all six
  // sectors (a beat-the-game meta), so the draw pool is the WHOLE content —
  // the keystone "the full unlocked card set into play". The base curriculum
  // already fills the T1 hand/shop pools, but the EVENT pool now also holds
  // the gate-1 EVT_VIRAL_QUARTER (previously held out of the slice), which
  // is the newly-drawable card the v10 script exercises (it widens the
  // event-roll pool — the stream move).
  final fullUnlock = [for (final c in kContent.cards) c.id];
  var state = initRun(
    economy: kEconomyConfig,
    unlockedCardIds: fullUnlock,
    unlockedSectors: Sector.values,
  );
  final rng = SplitMix64Rng(kSeed);

  // ROUND 1 — OPERATE #1: opening market ticks (1 of 2); draws = hand
  // (1 size + 3 cards: T1's slot is FULL from initRun, so the pool is the
  // 3-card addon+partner set and the size draw clamps) + the exit-offer
  // pair + rate + v1's drift pair + the event roll.
  state = runOperate(state, rng, kContent).state;
  expect(state.phase, PhaseId.act, reason: 'the run must stay alive');
  expect(state.hand.toSet(),
      {'ADD_SW_PLUGIN', 'ADD_SW_MICRO', 'PRT_SALES_LEAD'},
      reason: 'the v5 dead-draw filter leaves exactly the 3-card T1 '
          'addon+partner pool — every hand is all of it');
  expect(state.exitOffer, isNotNull,
      reason: 'ventures exist, so the hand draw appended an exit offer');
  expect(state.exitOffer!.ventureId, kSeedVentureId);

  // ACT: HIRE THE PARTNER from the hand (the round-10 system), then the
  // signature merge — 2 plays, exactly T1's budget.
  var r = playCard(state, 'PRT_SALES_LEAD', rng, kContent,
      targetVentureId: kSeedVentureId);
  expectClean(r, 'playCard(PRT_SALES_LEAD)');
  expect(r.state.ventures.single.partners.last.defId, 'PRT_SALES_LEAD',
      reason: 'the engine is attached at hire (after the v6 founding '
          'operator, list order = replay contract)');
  state = r.state;

  r = playCard(state, 'ADD_SW_PLUGIN', rng, kContent,
      targetVentureId: kSeedVentureId);
  expectClean(r, 'playCard(ADD_SW_PLUGIN)');
  expect(r.events.any((e) => e.type == GameEventType.multipleArbitrage),
      isTrue, reason: 'the merge IS the arbitrage moment');
  state = r.state;

  // SHOP: endTurn deals the counter (3 draws). Seed 42's first counter
  // misses the MARKET READ, so the script pays the banker for a SHOP
  // reroll (3 more draws — reroll coverage, like v4's ACT reroll) and
  // buys the read off the refreshed counter (flag coverage for round 2).
  state = endTurn(state, rng, kContent);
  expect(state.shopOffers, isNot(contains('PLY_MARKET_READ')),
      reason: 'seed 42\'s FIRST counter misses the read — the pinned '
          'stream the reroll below exists to fix');
  r = apply(state, const Reroll(costCents: 100000), rng, kContent);
  expectClean(r, 'Reroll (shop)');
  state = r.state;
  expect(state.shopOffers, contains('PLY_MARKET_READ'),
      reason: 'seed 42\'s rerolled counter deals the read the script '
          'buys; if this moved, the shop pool or the draw contract '
          'changed');
  r = buyShopOffer(state, 'PLY_MARKET_READ', kContent);
  expectClean(r, 'buyShopOffer(PLY_MARKET_READ)');
  state = r.state;

  // DEADLINE_CHECK: NW is far under the $1M bar — a plain round advance.
  final check = runDeadlineCheck(state);
  expect(check.state.phase, PhaseId.operate);
  expect(check.state.round, 2);
  state = check.state;

  final ebitdaBefore = state.ventures.single.ebitdaCents;

  // ROUND 2 — OPERATE #2: market BOUNDARY (2 of 2): hand (1 size + 3
  // cards) + exit-offer pair + transition + duration + rate + drift pair
  // + event roll. The partner's +150k accrues at step 3a.
  final op2 = runOperate(state, rng, kContent);
  state = op2.state;
  expect(state.phase, PhaseId.act, reason: 'the run must stay alive');
  final eventDelta = op2.events
      .where((e) => e.type == GameEventType.eventResolved)
      .isEmpty
      ? 0
      : null; // a fired ebitda event would unsettle the accrual pin
  if (eventDelta == 0) {
    expect(state.ventures.single.ebitdaCents,
        ebitdaBefore + (ebitdaBefore * 20) ~/ 100 + 150000,
        reason: 'step 3a: the organic growth (20% of the pre-accrual '
            'base, doc 01 §3.2 at the R12-tuned 0.20) AND the partner '
            'engine\'s +150k, both pre-yield (no event fired at seed 42 '
            '— pinned by the golden stream)');
  }

  // ACT: play the held MARKET READ (free; sets the hint — the flags land
  // in the end-state flatten), then the reinvest baseline (1 play).
  r = playCard(state, 'PLY_MARKET_READ', rng, kContent);
  expectClean(r, 'playCard(PLY_MARKET_READ)');
  expect(r.state.market.marketReadHint, isNotNull,
      reason: 'the read reveals a direction (model.dart documents what '
          'is honestly knowable)');
  expect(r.state.playsHeld, isEmpty, reason: 'the played card is consumed');
  state = r.state;

  r = apply(
      state,
      const ReinvestBaseline(ventureId: kSeedVentureId, amountCents: 200000),
      rng,
      kContent);
  expectClean(r, 'ReinvestBaseline');
  state = r.state;

  return (state: state, rng: rng);
}

/// Serializes the end state through the SHARED flatten() walker plus the
/// final RNG cursor: header, then one `path=value` per line, sorted.
String serialize(GameState state, SplitMix64Rng rng) {
  final map = <String, Object>{...flatten(state), 'rng.cursor': rng.cursor};
  final keys = map.keys.toList()..sort();
  final buffer = StringBuffer(kGoldenHeader);
  for (final key in keys) {
    buffer.writeln('$key=${map[key]}');
  }
  return buffer.toString();
}

void main() {
  group('golden replay-determinism contract (seed 42, v10)', () {
    test('the scripted gameplay-completeness replay reproduces the '
        'committed golden byte-for-byte', () {
      final end = replay();
      final actual = serialize(end.state, end.rng);

      final file = File(kGoldenPathV10);
      if (!file.existsSync()) {
        fail('Golden file $kGoldenPathV10 is missing. To create a NEW '
            'versioned golden (never to overwrite an old one), commit '
            'exactly this content:\n$actual');
      }
      // Normalize checkout-side CRLF so the contract is over CONTENT; the
      // serializer itself emits \n only.
      final golden = file.readAsStringSync().replaceAll('\r\n', '\n');
      expect(actual, golden,
          reason: 'replay diverged from the v10 golden — this is '
              'STREAM-BREAKING (docs/03 §6). Do NOT regenerate in place: '
              'version a new golden + bump engineSchemaVersion.');
    });

    test('the FULL pool is active: a newly-drawable card (EVT_VIRAL_QUARTER, '
        'held out of the v1 slice, gate-1) is in the run\'s live event pool '
        '— the keystone "the full unlocked set into play"', () {
      final fullUnlock = {for (final c in kContent.cards) c.id};
      final pool = eventPool(kContent, 1,
          unlockedCardIds: fullUnlock,
          unlockedSectors: Sector.values.toSet());
      expect(pool.map((c) => c.id), contains('EVT_VIRAL_QUARTER'),
          reason: 'EVT_VIRAL_QUARTER (inVerticalSlice == false) NEVER drew '
              'before R20b; the widened pool now deals it');
      // And it does NOT appear under the DEFAULT (base-curriculum) pool —
      // proving the unlock predicate actually gates it.
      final basePool = eventPool(kContent, 1);
      expect(basePool.map((c) => c.id), isNot(contains('EVT_VIRAL_QUARTER')),
          reason: 'the base curriculum still excludes the held-out card');
    });

    test('the cursor arithmetic matches the v10 draw contract: exactly 28 '
        'draws (the seed-42 stream COUNT is unchanged — the v10 pool widened '
        'the event pool but the seed-42 event roll still misses, so the '
        'pick draw never fires; the bump is the moved pool INDICES + the '
        'widened state, not the draw COUNT)', () {
      final end = replay();
      // Hand-verified against dealflow.dart + operate.dart's headers:
      //   OPERATE #1: (1 size + 3 cards + 2 exit-offer) + 0 boundary
      //               + 1 rate + 2 drift (one venture)
      //               + 1 event roll (miss)                          = 10
      //   endTurn #1: 3 offer draws (no size draw)                   =  3
      //   SHOP reroll: 3 offer draws (no size draw)                  =  3
      //   OPERATE #2: (1 size + 3 cards + 2 exit-offer) + 2 boundary
      //               + 1 rate + 2 drift + 1 event roll (miss)       = 12
      // playCard/buyShopOffer/runDeadlineCheck draw NOTHING.  Total = 28
      expect(end.rng.cursor, 28);
      expect(end.state.rngCursor, end.rng.cursor,
          reason: 'the state mirror must reconcile to the stream');
    });

    test('replaying the identical sequence twice yields value-identical '
        'GameState objects (golden-file independent)', () {
      final first = replay();
      final second = replay();
      expect(identical(first.state, second.state), isFalse,
          reason: 'the two replays must be independent object graphs');
      expect(first.state, second.state,
          reason: 'same seed + same action log must reproduce the exact '
              'same state (doc 03 §3: replay is the save format)');
      expect(first.rng.cursor, second.rng.cursor);
      expect(flatten(first.state), flatten(second.state));
    });

    test('the script covered what the round-10 work order demands', () {
      final end = replay();
      final s = end.state;
      // A full round-1 loop ran and the check advanced: mid-ACT round 2.
      expect(s.round, 2);
      expect(s.tier, 1);
      expect(s.phase, PhaseId.act);
      final v1 = s.ventures.singleWhere((v) => v.id == kSeedVentureId);
      // PARTNER ENGINES: the v6 founding operator from initRun (doc 01
      // §3.2's seed partner), then the hire — list order is the replay
      // contract.
      expect(v1.partners, [
        const PartnerEngine(
            defId: kFoundingPartnerDefId, perRoundEbitdaCents: 0),
        const PartnerEngine(
            defId: 'PRT_SALES_LEAD', perRoundEbitdaCents: 150000),
      ]);
      // EXIT OFFER: one pending ticket on the live venture, in-band.
      expect(s.exitOffer, isNotNull);
      expect(s.exitOffer!.ventureId, kSeedVentureId);
      expect(
          s.exitOffer!.offerMultipleMilli,
          inInclusiveRange((v1.multipleMilli * 900) ~/ 1000,
              (v1.multipleMilli * 1200) ~/ 1000),
          reason: 'the offer rode the band around the live multiple');
      expect(exitOfferAction(s), isNotNull,
          reason: 'the ticket maps onto a playable ExitVenture');
      // CONSUMABLE FLAGS: the market read is live with its expiry.
      expect(s.market.marketReadHint, isNotNull);
      expect(s.market.marketReadExpiresRound, 103,
          reason: 'flatRound(T1 r2) + 1');
      // DEAD-DRAW FIX: no venture card was ever dealt (T1's slot is full).
      for (final id in s.hand) {
        expect(kContent.byId(id).type, isNot(CardType.venture),
            reason: 'the v5 pool filter keeps venture tickets out of a '
                'full-slot tier');
      }
      // The merge + reinvest landed inside the five inputs.
      expect(v1.ebitdaCents, greaterThan(600000));
      expect(s.playsRemaining, 1,
          reason: 'round 2 spent 1 of 2 plays (the held play is free)');
      expect(s.actionLog, hasLength(6),
          reason: 'hire, merge, reroll, buy, play, reinvest — all logged');
      expect(s.rerollsUsed, 0,
          reason: 'the round-1 shop reroll was reset by the advance '
              '(doc 02 §2)');
      expect(s.won, isFalse);
      expect(s.death, isNull);
      expect(s.schemaVersion, engineSchemaVersion);
      expect(engineSchemaVersion, 10);
      // R20b: the FROZEN draw-pool unlock snapshot — the run was started with
      // the full unlocked set, so all 33 card ids + all 6 sectors are pinned
      // on the state (and golden-serialized).
      expect(s.unlockedCardIds, hasLength(33),
          reason: 'the v10 golden run unlocked the full content');
      expect(s.unlockedSectors, Sector.values,
          reason: 'all six sectors frozen on the run');
      expect(s.unlockedCardIds, contains('EVT_VIRAL_QUARTER'),
          reason: 'the held-out card is in the run pool (the keystone)');
      // The R13 venture-display-name layer: the seed venture pins to QUANTA
      // (the deterministic id+sector namer; codeUnits('v1') % pool.length
      // selects the SOFTWARE entry — RNG-free, id+sector-stable).
      expect(v1.displayName, 'QUANTA',
          reason: 'venture.v1.displayName is golden-pinned (ventureDisplayName '
              'is RNG-free and id+sector-stable)');
      // The R15 backgroundId-on-state field (schemaVersion 9): the seed-42
      // golden run is the default Bootstrapper.
      expect(s.backgroundId, 'BOOTSTRAPPER',
          reason: 'backgroundId is golden-pinned at schemaVersion 9 (the '
              'default background; it steers the per-round plays grant)');
    });
  });

  group('golden v9 (RETIRED at schemaVersion 10) — the docs/03 §6 procedure',
      () {
    test('the v9 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV9);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      // Seal the retired content (any regeneration would move these):
      expect(
          lines.first,
          '# Golden replay snapshot v9 — MULTIPLES engine (Phase 6 / R15 '
          'engine round,');
      expect(lines, contains('schemaVersion=9'),
          reason: 'v9 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=28'),
          reason: 'v9 consumed the same 28 draws — the v10 bump widened the '
              'pool (moved indices) + the state, but the seed-42 draw COUNT '
              'is unchanged');
      expect(lines, contains('cash=858100'));
      expect(lines, contains('backgroundId=BOOTSTRAPPER'),
          reason: 'v9 has the backgroundId (its own addition)');
      expect(lines, isNot(contains('unlockedCardIds.0=VEN_SW_GARAGE')),
          reason: 'v9 predates the frozen unlock snapshot — frozen in the '
              'artifact (the v10 engine adds it)');
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          39,
          reason: 'the v9 path set is frozen (no unlockedCardIds/Sectors — '
              'those are the v10 additions, taking the v10 set far higher)');
    });

    test('the engine moved past v9: the SAME seed-42 draw COUNT lands but '
        'the pool widened + the state now carries the frozen unlock '
        'snapshot the v9 artifact lacks', () {
      // A v9 save replayed on the v10 engine reconciles against a flatten
      // that now includes unlockedCardIds/unlockedSectors AND was drawn from
      // a widened pool (indices moved), so it is abandoned (docs/06 §3).
      final opening = initRun(economy: kEconomyConfig);
      expect(opening.unlockedCardIds, kDefaultUnlockedCardIds,
          reason: 'v10 adds the frozen unlock snapshot on the state; v9 '
              'states had none');
      expect(opening.schemaVersion, 10);
    });
  });

  group('golden v8 (RETIRED at schemaVersion 9) — the docs/03 §6 procedure',
      () {
    test('the v8 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV8);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      // Seal the retired content (any regeneration would move these):
      expect(
          lines.first,
          '# Golden replay snapshot v8 — MULTIPLES engine (Phase 4 / R13 '
          'SAVE-');
      expect(lines, contains('schemaVersion=8'),
          reason: 'v8 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=28'),
          reason: 'v8 consumed the same 28 draws — the v9 bump widened the '
              'state/flatten + the journal action shape + endless behavior, '
              'not the stream');
      expect(lines, contains('cash=858100'));
      expect(lines, contains('venture.v1.displayName=QUANTA'),
          reason: 'v8 has the displayName (its own addition)');
      expect(lines, isNot(contains('backgroundId=BOOTSTRAPPER')),
          reason: 'v8 predates the backgroundId field — frozen in the '
              'artifact (the v9 engine adds it)');
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          38,
          reason: 'the v8 path set is frozen (no backgroundId — that is the '
              'v9 addition, taking the v9 set to 39)');
    });

    test('the engine moved past v8: the SAME stream still lands but the '
        'state now carries a backgroundId the v8 artifact lacks', () {
      // The draw order is unchanged (cursor 28), but the state widened: a v8
      // save replayed on the v9 engine reconciles against a flatten that now
      // includes backgroundId, so it is abandoned (docs/06 §3).
      final opening = initRun(economy: kEconomyConfig);
      expect(opening.backgroundId, 'BOOTSTRAPPER',
          reason: 'v9 adds backgroundId on the state; v8 states had none');
      expect(opening.schemaVersion, 10);
    });
  });

  group('golden v7 (RETIRED at schemaVersion 8) — the docs/03 §6 procedure',
      () {
    test('the v7 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV7);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      // Seal the retired content (any regeneration would move these):
      expect(
          lines.first,
          '# Golden replay snapshot v7 — MULTIPLES engine (Phase 5 / R12 '
          'balance');
      expect(lines, contains('schemaVersion=7'),
          reason: 'v7 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=28'),
          reason: 'v7 consumed the same 28 draws — the v8 bump moved the '
              'persisted CONTRACT + added a field, not the stream');
      expect(lines, contains('cash=858100'));
      expect(lines, contains('venture.v1.ebitda=1551560'));
      expect(lines, isNot(contains('venture.v1.displayName=QUANTA')),
          reason: 'v7 predates the displayName field — frozen in the '
              'artifact (the v8 engine adds it)');
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          37,
          reason: 'the v7 path set is frozen (no venture.displayName — that '
              'is the v8 addition, taking the v8 set to 38)');
    });

    test('the engine moved past v7: the SAME stream still lands but the '
        'state now carries a displayName the v7 artifact lacks', () {
      // The draw order is unchanged (cursor 28), but the persisted contract
      // moved: a v7 save replayed on the current engine would reconcile
      // against a flatten that now includes venture.displayName (a v8
      // addition) and backgroundId (a v9 addition), so it is abandoned
      // (docs/06 §3) rather than mis-trusted.
      final opening = initRun(economy: kEconomyConfig);
      expect(opening.ventures.single.displayName, 'QUANTA',
          reason: 'the displayName (a v8 addition) is present; v7 had none');
      expect(opening.schemaVersion, 10);
    });
  });

  group('golden v6 (RETIRED at schemaVersion 7) — the docs/03 §6 procedure',
      () {
    test('the v6 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV6);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      // Seal the retired content (any regeneration would move these):
      expect(
          lines.first,
          '# Golden replay snapshot v6 — MULTIPLES engine (Phase 5 / R12 '
          'balance');
      expect(lines, contains('schemaVersion=6'),
          reason: 'v6 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=28'),
          reason: 'v6 consumed the same 28 draws — the v7 bump moved '
              'VALUES, not the stream');
      expect(lines, contains('cash=776200'));
      expect(lines, contains('venture.v1.ebitda=1377000'),
          reason: 'the organic-0.10-era EBITDA path, frozen in the '
              'artifact (the v7 engine compounds past it)');
      expect(lines, contains('market.liveRateBp=1084'),
          reason: 'the interestMax-0.14-era rate band, frozen in the '
              'artifact (the v7 band tops out at 1199 base)');
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          37,
          reason: 'the v6 path set is frozen (the v7 bump added no '
              'fields — only the VALUES moved)');
    });

    test('the engine moved past v6: the same opening reads the SAME '
        'stream but lands DIFFERENT values (the tuned organic rate '
        'compounds)', () {
      final opening = initRun(economy: kEconomyConfig);
      final rng = SplitMix64Rng(kSeed);
      final result = runOperate(opening, rng, kContent);
      // Draw count is v6's exactly (the tuning pass is draw-free)...
      final handSize = result.state.hand.length;
      final fired = result.events
          .where((e) => e.type == GameEventType.eventResolved)
          .length;
      expect(rng.cursor, (1 + handSize + 2) + 1 + 2 + 1 + fired);
      // ...but the EBITDA path moved: 600000 + trunc(600000 x 20/100)
      // (no slice event touches a SOFTWARE venture's ebitda) — a v6 save
      // replayed here would diverge, which is why v6 runs are abandoned.
      expect(result.state.ventures.single.ebitdaCents, 720000,
          reason: 'the v6-era engine left this at 660000');
    });
  });

  group('golden v5 (RETIRED at schemaVersion 6) — the docs/03 §6 procedure',
      () {
    test('the v5 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV5);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      // Seal the retired content (any regeneration would move these):
      expect(
          lines.first,
          '# Golden replay snapshot v5 — MULTIPLES engine (Phase 3 '
          'round 10: the');
      expect(lines, contains('schemaVersion=5'),
          reason: 'v5 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=28'),
          reason: 'v5 consumed the same 28 draws — the v6 bump moved '
              'VALUES, not the stream');
      expect(lines, contains('cash=698500'));
      expect(lines, contains('venture.v1.ebitda=1215000'),
          reason: 'the pre-organic-growth EBITDA path, frozen in the '
              'artifact (the v6 engine compounds past it)');
      expect(lines, contains('venture.v1.partners.0.defId=PRT_SALES_LEAD'),
          reason: 'v5 initRun attached NO founding operator — the hire '
              'was the only engine');
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          35,
          reason: 'the v5 path set is frozen (no founding-operator '
              'partner paths — those are v6 additions)');
    });

    test('the engine moved past v5: the same opening reads the SAME '
        'stream but lands DIFFERENT values (organic growth compounds)',
        () {
      final opening = initRun(economy: kEconomyConfig);
      expect(opening.ventures.single.partners.single.defId,
          kFoundingPartnerDefId,
          reason: 'v6 initRun seeds the founding operator');
      final rng = SplitMix64Rng(kSeed);
      final result = runOperate(opening, rng, kContent);
      // Draw count is v5's exactly (organic growth is draw-free)...
      final handSize = result.state.hand.length;
      final fired = result.events
          .where((e) => e.type == GameEventType.eventResolved)
          .length;
      expect(rng.cursor, (1 + handSize + 2) + 1 + 2 + 1 + fired);
      // ...but the EBITDA path moved: 600000 + trunc(600000 x 20/100 at
      // the R12-tuned organic 0.20; no slice event touches a SOFTWARE
      // venture's ebitda) — a v5 save replayed here would diverge, which
      // is why v5 runs are abandoned.
      expect(result.state.ventures.single.ebitdaCents, 720000,
          reason: 'the v5-era engine left this at 600000 (and the '
              'v6-era one at 660000)');
    });
  });

  group('golden v4 (RETIRED at schemaVersion 5) — still sealed',
      () {
    test('the v4 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV4);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      // Seal the retired content (any regeneration would move these):
      expect(
          lines.first,
          '# Golden replay snapshot v4 — MULTIPLES engine (Phase 3 '
          'round 4: the');
      expect(lines, contains('schemaVersion=4'),
          reason: 'v4 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=28'),
          reason: 'v4 is from the pre-exit-offer era (its two operates + '
              'shop deal + reroll consumed 28 draws)');
      expect(lines, contains('cash=3884500'));
      expect(lines, contains('hand.0=VEN_IND_WORKSHOP'),
          reason: 'v4 hands still dealt venture cards into a full-slot '
              'tier — the dead-draw bug the v5 filter fixed, frozen in '
              'the artifact');
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          31,
          reason: 'the v4 path set is frozen (no partners/scheduled/'
              'flags/exitOffer — those are v5 additions)');
    });

    test('the engine moved past v4: the same opening now consumes MORE '
        'draws (the stream moved, not just the fields)', () {
      // v4's OPERATE over one venture consumed (1+size) + 1 + 2 + 1
      // draws; the v5 engine adds the exit-offer pair. Pin the off-by-two
      // on the SAME shape (mid-state, one venture, no event variance —
      // we count via two stream twins).
      final opening = initRun(economy: kEconomyConfig);
      final rng = SplitMix64Rng(kSeed);
      final result = runOperate(opening, rng, kContent);
      final handSize = result.state.hand.length;
      final fired = result.events
          .where((e) => e.type == GameEventType.eventResolved)
          .length;
      expect(rng.cursor, (1 + handSize + 2) + 1 + 2 + 1 + fired,
          reason: 'v4 replays CANNOT be re-run on the v5 engine: the same '
              'step reads a different stream now (docs/03 §6: abandoned, '
              'never migrated)');
    });
  });

  group('golden v3 (RETIRED at schemaVersion 4) — still sealed', () {
    test('the v3 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV3);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      expect(
          lines.first,
          '# Golden replay snapshot v3 — MULTIPLES engine (Phase 3 '
          'round 2: the round');
      expect(lines, contains('schemaVersion=3'),
          reason: 'v3 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=9'),
          reason: 'v3 is from the pre-deal-flow era (three operates, '
              'cursor 9)');
      expect(lines, contains('cash=35615425'));
      expect(lines, contains('netWorthAtTierEntry=134802450'));
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          24,
          reason: 'the v3 path set is frozen (no hand/shopOffers/playsHeld '
              '— those are v4 additions)');
    });
  });

  group('golden v2 (RETIRED at schemaVersion 3) — still sealed', () {
    test('the v2 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV2);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      expect(
          lines.first,
          '# Golden replay snapshot v2 — MULTIPLES engine (Phase 3 '
          'round 1: OPERATE).');
      expect(lines, contains('schemaVersion=2'),
          reason: 'v2 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=19'),
          reason: 'v2 is from the OPERATE-only era (five operates, '
              'cursor 19)');
      expect(lines, contains('cash=8871900'));
      expect(lines, contains('playsRemaining=4'));
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          20,
          reason: 'the v2 path set is frozen (no §5.1 snapshots, no '
              'won/death — those are v3 additions)');
    });

    test('the engine moved past v2: its script is not even runnable under '
        'the strict gates', () {
      final fresh = GameState(
        ventures: const [],
        cashCents: 10000000,
        round: 1,
        tier: 4,
      );
      final opening = apply(
          fresh,
          const StartVenture(
            ventureId: 'v1',
            sector: Sector.software,
            ebitdaCents: 600000,
            multipleMilli: 8000,
            priceCents: 2000000,
            faceDebtCents: 0,
          ),
          SplitMix64Rng(kSeed),
          kContent);
      expect(
          opening.events.single.reason, 'no_plays_remaining',
          reason: 'v2\'s opening move is gated now');
      expect(() => runOperate(fresh, SplitMix64Rng(kSeed), kContent),
          throwsStateError,
          reason: 'v2\'s states defaulted to phase act; OPERATE now '
              'requires the operate phase');
    });
  });

  group('golden v1 (RETIRED at schemaVersion 2) — still sealed', () {
    test('the v1 artifact is preserved byte-for-byte, never edited in place',
        () {
      final file = File(kGoldenPathV1);
      expect(file.existsSync(), isTrue,
          reason: 'retired goldens are historical artifacts — kept, not '
              'deleted');
      final lines =
          file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      expect(lines.first,
          '# Golden replay snapshot v1 — MULTIPLES engine (Task 1.7).');
      expect(lines, contains('schemaVersion=1'),
          reason: 'v1 pins the RETIRED schema version');
      expect(lines, contains('rng.cursor=0'),
          reason: 'v1 is from the all-actions-draw-0 era');
      expect(lines, contains('cash=16357421'));
      expect(
          lines.where((l) => !l.startsWith('#') && l.contains('=')).length,
          13,
          reason: 'the v1 path set is frozen');
    });

    test('the engine moved past v1..v9: an older-schema run is abandoned, '
        'not migrated', () {
      expect(engineSchemaVersion, 10);
      expect(initRun(economy: kEconomyConfig).schemaVersion, 10,
          reason: 'newly built states carry the current schema');
      // docs/03 §6 + docs/06: on load, schemaVersion mismatch -> discard
      // the run. The save layer (R13 serialize.dart/migrate.dart)
      // implements that rule against THIS constant; v1..v9 replays are not
      // re-runnable on the v10 engine by construction (see the retirement
      // tests above).
    });
  });

  group('bankruptcy mini-script (separate from the living-run golden)', () {
    /// A run one interest charge from death: $0.5M debt at any in-band
    /// rate out-bills the $30k cash + $2.1k yield (slice events carry no
    /// cash delta, so the doom is event-proof).
    GameState doomedState() => GameState(
          ventures: const [
            Venture(
              id: 'doomed',
              sector: Sector.industrial,
              ebitdaCents: 6000,
              multipleMilli: 8000,
              netDebtCents: 50000000,
              ownershipBp: 10000,
            ),
          ],
          cashCents: 3000000,
          round: 3,
          tier: 2,
          phase: PhaseId.operate,
        );

    OperateResult die() =>
        runOperate(doomedState(), SplitMix64Rng(606), kContent);

    test('the run ends in RUN_OVER with strictly negative cash (F6)', () {
      final result = die();
      expect(result.state.phase, PhaseId.runOver);
      expect(result.state.cashCents, lessThan(0),
          reason: 'cash is NEVER clamped at 0 — the deficit IS the death '
              'signal (doc 01 §2.2)');
      expect(result.state.playsRemaining, 0);
      expect(result.state.death, DeathCause.bankruptcy,
          reason: 'the autopsy reads the cause from the state');
      expect(result.state.won, isFalse);
      expect(result.state.netWorthLastRound, result.state.netWorthCents,
          reason: 'the step-9 snapshot is taken on the bankrupt branch '
              'too');
      expect(result.state.hand.length, inInclusiveRange(3, 5),
          reason: 'the hand was dealt at step 0, before the F6 verdict');
      expect(result.state.exitOffer, isNotNull,
          reason: 'the exit-offer pair was drawn at step 0 too — the '
              'ticket the dead run never got to play');
      final death =
          result.events.where((e) => e.type == GameEventType.bankruptcy);
      expect(death, hasLength(1));
      expect(death.single.amount, result.state.cashCents);
    });

    test('the death replays deterministically', () {
      expect(die().state, die().state);
    });

    test('a dead run cannot OPERATE again', () {
      final dead = die().state;
      expect(() => runOperate(dead, SplitMix64Rng(606), kContent),
          throwsStateError);
    });
  });
}
