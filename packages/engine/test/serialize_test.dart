// SERIALIZATION + REPLAY tests (R13; docs/06). Proves the run save is the
// docs/06 minimal reproducible record, that replay reconstructs the EXACT
// state (the save format IS replay, doc 03 §3.1), and that the optional
// cache is reconciled-or-discarded (§2.2). Ties the typed RunStep journal to
// the v8 golden: the seed-42 scripted run, recorded as steps, round-trips
// through run.json and reproduces the golden end state.
//
// dart:io is TEST-ONLY (loading the real content/economy). No double anywhere.

import 'dart:convert';

import 'package:engine/actions.dart';
import 'package:engine/init.dart';
import 'package:engine/model.dart';
import 'package:engine/serialize.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

/// The seed-42 gameplay-completeness run, expressed as the REPLAYABLE journal
/// (the same sequence golden_replay_test.dart scripts imperatively).
const int kSeed = 42;
final List<RunStep> kScript = [
  const OperateStep(), // round 1 operate
  const PlayCardStep('PRT_SALES_LEAD', targetVentureId: kSeedVentureId),
  const PlayCardStep('ADD_SW_PLUGIN', targetVentureId: kSeedVentureId),
  const EndTurnStep(),
  const ApplyStep(Reroll(costCents: 100000)), // SHOP reroll
  const BuyShopStep('PLY_MARKET_READ'),
  const DeadlineCheckStep(), // plain advance to round 2
  const OperateStep(), // round 2 operate (boundary)
  const PlayCardStep('PLY_MARKET_READ'), // held play
  const ApplyStep(
      ReinvestBaseline(ventureId: kSeedVentureId, amountCents: 200000)),
];

void main() {
  group('Action <-> JSON round-trips (all 12 variants)', () {
    final actions = <Action>[
      const StartVenture(
        ventureId: 'v9',
        sector: Sector.retail,
        ebitdaCents: 500000,
        multipleMilli: 3000,
        priceCents: 700000,
        faceDebtCents: 0,
      ),
      const RaiseEquity(
          ventureId: 'v1',
          raiseCents: 1000000,
          ebitdaDeltaCents: 200000,
          multipleDeltaMilli: 1000),
      const TakeDebt(ventureId: 'v1', proceedsCents: 500000, faceDebtCents: 575000),
      const AcquireAddOn(
        targetVentureId: 'v1',
        addonSector: Sector.software,
        addonEbitdaCents: 100000,
        addonBuyMultipleMilli: 5000,
        addonFaceDebtCents: 0,
      ),
      const DividendRecap(ventureId: 'v1', recapPctBp: 1600),
      const ExitVenture(
          ventureId: 'v1',
          offerMultipleMilli: 6000,
          liveMarketMultipleMilli: 5900),
      const HireCEO(ventureId: 'v1', costCents: 300000),
      const SellPlay(playId: 'PLY_X', purchasePriceCents: 100000),
      const Reroll(costCents: 15000),
      PlayConsumable(
        playId: 'PLY_HOT_WINDOW',
        deltas: const {'cash': -100000},
        targetVentureId: 'v1',
        armsHotWindow: true,
        readsMarket: false,
        recapBp: 0,
      ),
      // A SECONDARY SALE (schemaVersion 9): secondaryBp must survive the
      // journal round-trip (it is part of the persisted action shape).
      PlayConsumable(
        playId: 'PLY_SECONDARY_SALE',
        deltas: const {},
        targetVentureId: 'v1',
        secondaryBp: 1500,
      ),
      const ReinvestBaseline(ventureId: 'v1', amountCents: 200000),
      const HirePartner(
        ventureId: 'v1',
        defId: 'PRT_SALES_LEAD',
        costCents: 500000,
        perRoundEbitdaCents: 150000,
        multipleDeltaMilli: 0,
        fixedCostCents: 0,
      ),
    ];

    test('every action survives toJson -> fromJson by value equality', () {
      expect(actions, hasLength(13),
          reason: 'the closed union is 12 variants (+ a 2nd PlayConsumable '
              'covering the schemaVersion-9 secondaryBp field)');
      for (final a in actions) {
        final round = actionFromJson(actionToJson(a));
        expect(round, a, reason: '$a did not round-trip');
      }
    });

    test('survives a JSON string encode/decode too (the real wire path)', () {
      for (final a in actions) {
        final round =
            actionFromJson(jsonDecode(jsonEncode(actionToJson(a)))
                as Map<String, dynamic>);
        expect(round, a);
      }
    });

    test('an unknown discriminator fails loudly', () {
      expect(() => actionFromJson({'t': 'NoSuchAction'}),
          throwsFormatException);
    });
  });

  group('RunStep <-> JSON round-trips', () {
    test('every step kind survives the round-trip', () {
      final steps = <RunStep>[
        const OperateStep(),
        const EndTurnStep(),
        const DeadlineCheckStep(),
        const ApplyStep(Reroll(costCents: 100000)),
        const PlayCardStep('ADD_SW_PLUGIN', targetVentureId: 'v1'),
        const PlayCardStep('PLY_MARKET_READ'), // no target
        const BuyShopStep('PLY_MARKET_READ'),
      ];
      for (final s in steps) {
        final round = runStepFromJson(
            jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
        expect(round.toJson(), s.toJson(),
            reason: '${s.runtimeType} did not round-trip');
      }
    });
  });

  group('runId derivation', () {
    test('is a stable seed-derived hex tag', () {
      expect(runIdForSeed(42), runIdForSeed(42));
      expect(runIdForSeed(42), 'r_0000002a', reason: '42 == 0x2a');
      expect(runIdForSeed(1), 'r_00000001');
      // Different seeds -> different ids (the low-32 collision space is wide
      // enough for display/guard purposes).
      expect(runIdForSeed(42), isNot(runIdForSeed(43)));
    });
  });

  group('replay reconstruction (docs/06 §3.1: replay IS the save format)', () {
    test('the seed-42 journal replays to the SAME state as the imperative '
        'golden script (flatten-equal, cursor 28)', () {
      final replayed = replayRun(kScript,
          seed: kSeed,
          backgroundId: kBootstrapperBackgroundId,
          economy: kEconomyConfig,
          content: kContent);
      expect(replayed.rngCursor, 28, reason: 'the v8 draw contract');
      expect(replayed.round, 2);
      expect(replayed.phase, PhaseId.act);
      expect(replayed.ventures.single.displayName, 'QUANTA');
      // Golden-pinned end-state values (must match replay_seed42_v8.txt):
      expect(replayed.cashCents, 858100);
      expect(replayed.ventures.single.ebitdaCents, 1551560);
      expect(replayed.market.marketReadHint, isNotNull);
    });

    test('replaying twice yields value-identical states', () {
      final a = replayRun(kScript,
          seed: kSeed,
          backgroundId: kBootstrapperBackgroundId,
          economy: kEconomyConfig,
          content: kContent);
      final b = replayRun(kScript,
          seed: kSeed,
          backgroundId: kBootstrapperBackgroundId,
          economy: kEconomyConfig,
          content: kContent);
      expect(a, b);
      expect(flatten(a), flatten(b));
    });

    test('a lying journal (a step that rejects) throws ReplayDesyncError', () {
      // ReinvestBaseline before any OPERATE: phase is OPERATE at init, so an
      // ACT-only action rejects (wrong_phase) -> desync.
      expect(
          () => replayRun(
                [
                  const ApplyStep(
                      ReinvestBaseline(ventureId: kSeedVentureId, amountCents: 1)),
                ],
                seed: kSeed,
                backgroundId: kBootstrapperBackgroundId,
                economy: kEconomyConfig,
                content: kContent,
              ),
          throwsA(isA<ReplayDesyncError>()));
    });
  });

  group('run.json round-trip (the docs/06 minimal record)', () {
    // Build the live run once (drive the engine exactly as the app would),
    // capturing the end state + cursor for the save.
    ({GameState state, int cursor}) liveRun() {
      final replayed = replayRun(kScript,
          seed: kSeed,
          backgroundId: kBootstrapperBackgroundId,
          economy: kEconomyConfig,
          content: kContent);
      return (state: replayed, cursor: replayed.rngCursor);
    }

    test('toJson produces the docs/06 §2.1 minimal record shape', () {
      final live = liveRun();
      final json = runSaveToJson(
        seed: kSeed,
        cursor: live.cursor,
        backgroundId: kBootstrapperBackgroundId,
        steps: kScript,
        cacheState: live.state,
      );
      expect(json['schemaVersion'], engineSchemaVersion);
      expect(json['seed'], kSeed);
      expect(json['cursor'], 28);
      final startConfig = json['startConfig'] as Map<String, Object?>;
      expect(startConfig['runId'], 'r_0000002a');
      expect(startConfig['backgroundId'], kBootstrapperBackgroundId);
      expect((json['actionLog'] as List), hasLength(kScript.length));
      expect((json['cache'] as Map)['schemaVersion'], engineSchemaVersion);
    });

    test('fromJson reconstructs the EXACT state via replay (no cache)', () {
      final live = liveRun();
      final str = runSaveToJsonString(
        seed: kSeed,
        cursor: live.cursor,
        backgroundId: kBootstrapperBackgroundId,
        steps: kScript,
        // no cache -> pure replay path
      );
      final loaded = runSaveFromJsonString(str,
          economy: kEconomyConfig, content: kContent);
      expect(loaded.usedCache, isFalse);
      expect(loaded.runId, 'r_0000002a');
      expect(loaded.cursor, 28);
      expect(loaded.state, live.state,
          reason: 'replay reconstructs the identical RunState');
      expect(flatten(loaded.state), flatten(live.state));
    });

    test('fromJson TRUSTS a consistent cache (reconciles flatten-equal)', () {
      final live = liveRun();
      final str = runSaveToJsonString(
        seed: kSeed,
        cursor: live.cursor,
        backgroundId: kBootstrapperBackgroundId,
        steps: kScript,
        cacheState: live.state, // a faithful cache
      );
      final loaded = runSaveFromJsonString(str,
          economy: kEconomyConfig, content: kContent);
      expect(loaded.usedCache, isTrue,
          reason: 'the cache equals replay, so it is trusted (hot path)');
      expect(loaded.state, live.state);
    });

    test('fromJson DISCARDS a divergent cache and silently replays', () {
      final live = liveRun();
      // Hand-corrupt the cache: a state that does NOT equal replay.
      final corruptCache = live.state.copyWith(cashCents: 999999999);
      final json = runSaveToJson(
        seed: kSeed,
        cursor: live.cursor,
        backgroundId: kBootstrapperBackgroundId,
        steps: kScript,
        cacheState: corruptCache,
      );
      final loaded = runSaveFromJson(json,
          economy: kEconomyConfig, content: kContent);
      expect(loaded.usedCache, isFalse,
          reason: 'the cache disagreed with replay -> discarded');
      expect(loaded.state.cashCents, 858100,
          reason: 'replay (the truth) won, not the corrupt 999999999 cache');
      expect(loaded.state, live.state);
    });

    test('fromJson DROPS a stale-schema cache unread', () {
      final live = liveRun();
      final json = runSaveToJson(
        seed: kSeed,
        cursor: live.cursor,
        backgroundId: kBootstrapperBackgroundId,
        steps: kScript,
        cacheState: live.state,
      );
      // Force the cache schema to an older version (a pre-migration cache).
      (json['cache'] as Map)['schemaVersion'] = engineSchemaVersion - 1;
      final loaded = runSaveFromJson(json,
          economy: kEconomyConfig, content: kContent);
      expect(loaded.usedCache, isFalse, reason: 'stale-schema cache dropped');
      expect(loaded.state, live.state, reason: 'replay reconstructs it');
    });

    test('a cursor that disagrees with the replayed stream is corruption', () {
      final live = liveRun();
      final json = runSaveToJson(
        seed: kSeed,
        cursor: live.cursor,
        backgroundId: kBootstrapperBackgroundId,
        steps: kScript,
      );
      json['cursor'] = 27; // wrong
      expect(
          () => runSaveFromJson(json,
              economy: kEconomyConfig, content: kContent),
          throwsFormatException);
    });

    test('a wrong-schema top-level fails loudly (migrate must run first)', () {
      final json = runSaveToJson(
        seed: kSeed,
        cursor: 0,
        backgroundId: kBootstrapperBackgroundId,
        steps: const [],
      );
      json['schemaVersion'] = 7;
      expect(
          () => runSaveFromJson(json,
              economy: kEconomyConfig, content: kContent),
          throwsFormatException);
    });
  });

  group('background round-trips through the save', () {
    test('a non-default background is preserved and re-applied on load', () {
      // A fresh VC_DARLING run with just an opening OPERATE.
      final steps = <RunStep>[const OperateStep()];
      final replayed = replayRun(steps,
          seed: 7,
          backgroundId: 'VC_DARLING',
          economy: kEconomyConfig,
          content: kContent);
      final str = runSaveToJsonString(
        seed: 7,
        cursor: replayed.rngCursor,
        backgroundId: 'VC_DARLING',
        steps: steps,
      );
      final loaded = runSaveFromJsonString(str,
          economy: kEconomyConfig, content: kContent);
      expect(loaded.backgroundId, 'VC_DARLING');
      // The pre-dilution survived: ownership 80% (8000 bp) on the seed.
      expect(loaded.state.ventures.single.ownershipBp, 8000);
      expect(loaded.state, replayed);
    });
  });
}
