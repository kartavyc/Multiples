// SAVE/PERSISTENCE round-trip + recovery tests (R14 #7, docs/06).
//
// The store's directory is INJECTED (SaveStore.forDirectory over a dart:io
// temp dir), so these exercise the REAL engine serialize/migrate/replay path
// with no plugin. State equality uses the engine's own flatten() walker (the
// same one the cache reconciliation + invariant test use) — a resumed run is
// byte-for-byte the run that was saved.
//
// Seed is fixed; no widgets, no pumps — this is pure I/O + engine.

import 'dart:io';

import 'package:engine/content.dart';
import 'package:engine/model.dart';
import 'package:engine/serialize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/controller.dart';
import 'package:multiples_app/save_store.dart';

const int kSeed = 2;

void main() {
  final cardsJson = File('assets/data/cards.json').readAsStringSync();
  final economyJson =
      File('assets/data/economy-model.json').readAsStringSync();
  final economy = loadEconomy(economyJson);
  final content = loadCards(cardsJson);

  late Directory dir;
  late SaveStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('multiples_save_test');
    store = SaveStore.forDirectory(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  GameController fresh({String bg = kBootstrapperBackgroundId}) =>
      GameController(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kSeed,
        backgroundId: bg,
        store: store,
        meta: MetaState(),
      );

  group('run save round-trip (write -> read -> resume == state)', () {
    test('a mid-run save replays to the identical flattened state', () async {
      final c = fresh();
      addTearDown(c.dispose);
      // Advance the run a few committed steps (each autosaves).
      c.beginRound(); // OPERATE -> ACT, the first hand/market drawn
      // A draw-free, always-legal move: REROLL the deck (charges the fee,
      // commits, journals an ApplyStep). Cash-gated, so guard it.
      if (c.canReroll) c.reroll();
      c.endTurnToShop(); // ACT -> SHOP
      // Deterministically join the eager autosave (no arbitrary sleep): the
      // store serializes writes, so awaiting the last settles all of them.
      await c.debugSettled;

      final savedFlat = flatten(c.state);
      final savedCursor = c.state.rngCursor;

      // Read it back through the store (migrate -> replay -> reconcile).
      final resume = await store.loadRun(
          economy: economy, content: content, meta: MetaState());
      expect(resume.hasRun, isTrue, reason: 'a run.json was written');
      final load = resume.load!;
      expect(load.seed, kSeed);
      expect(load.cursor, savedCursor);
      expect(load.backgroundId, kBootstrapperBackgroundId);
      // The reconstructed state equals the saved one on every economic +
      // replay-relevant path (the engine flatten walker).
      expect(flatten(load.state), equals(savedFlat));
    });

    test('resuming a controller seats the identical state + keeps appending',
        () async {
      final c = fresh();
      addTearDown(c.dispose);
      c.beginRound();
      c.endTurnToShop();
      await c.debugSettled;
      final beforeFlat = flatten(c.state);

      final resume = await store.loadRun(
          economy: economy, content: content, meta: MetaState());
      final c2 = GameController.resume(
        cardsJson: cardsJson,
        economyJson: economyJson,
        resume: resume.load!,
        store: store,
        meta: MetaState(),
      );
      addTearDown(c2.dispose);
      expect(flatten(c2.state), equals(beforeFlat));
      // The resumed controller is at the same RNG cursor, so its next engine
      // call continues the SAME stream (no desync on further play).
      expect(c2.state.rngCursor, c.state.rngCursor);
    });
  });

  group('meta persistence (durable across runs)', () {
    test('writeMeta -> loadMeta round-trips the Track Record', () async {
      final meta = MetaState(
        reputation: 1820000,
        metaLevel: 2,
        furthestTierReached: 3,
        runsPlayed: 7,
        cleanExits: 4,
      );
      await store.writeMeta(meta);
      final back = await store.loadMeta();
      expect(back.reputation, 1820000);
      expect(back.furthestTierReached, 3);
      expect(back.runsPlayed, 7);
      expect(back.cleanExits, 4);
    });

    test('a missing meta.json loads a fresh default (first launch)', () async {
      final back = await store.loadMeta();
      expect(back.reputation, 0);
      expect(back.runsPlayed, 0);
      expect(back.unlockedBackgrounds, contains(kBootstrapperBackgroundId));
    });
  });

  group('recovery (docs/06 §3, §5)', () {
    test('a corrupt run.json is discarded, no run resumes', () async {
      File('${dir.path}/run.json').writeAsStringSync('{not valid json');
      final resume = await store.loadRun(
          economy: economy, content: content, meta: MetaState());
      expect(resume.hasRun, isFalse);
      expect(resume.abandonedReason, isNotNull);
      // The corrupt file was deleted (next boot is clean).
      expect(File('${dir.path}/run.json').existsSync(), isFalse);
    });

    test('a stream-breaking (old-schema) run is ABANDONED, meta untouched',
        () async {
      // A v7 run (any v<8) has no typed RunStep journal -> migrateRun throws
      // AbandonRun (docs/06 §3). The store drops it.
      final stale = '{"schemaVersion":7,"seed":$kSeed,"cursor":0,'
          '"startConfig":{"runId":"r_x","backgroundId":"BOOTSTRAPPER"},'
          '"actionLog":[]}';
      File('${dir.path}/run.json').writeAsStringSync(stale);
      // A real meta sits next to it; it must survive.
      final meta = MetaState(reputation: 999, runsPlayed: 5);
      await store.writeMeta(meta);

      final resume =
          await store.loadRun(economy: economy, content: content, meta: meta);
      expect(resume.hasRun, isFalse);
      expect(resume.abandonedReason, contains('abandoned'));
      expect(File('${dir.path}/run.json').existsSync(), isFalse);
      // Meta is intact (the player loses one mid-run, never their Track Record).
      final metaBack = await store.loadMeta();
      expect(metaBack.reputation, 999);
      expect(metaBack.runsPlayed, 5);
    });

    test('a NEWER-version run keeps its file and does not resume', () async {
      final future = '{"schemaVersion":${engineSchemaVersion + 5},'
          '"seed":$kSeed,"cursor":0,'
          '"startConfig":{"runId":"r_x","backgroundId":"BOOTSTRAPPER"},'
          '"actionLog":[]}';
      File('${dir.path}/run.json').writeAsStringSync(future);
      final resume = await store.loadRun(
          economy: economy, content: content, meta: MetaState());
      expect(resume.hasRun, isFalse);
      expect(resume.abandonedReason, contains('newer'));
      // Forward-only: the file is kept (a future upgrade may read it).
      expect(File('${dir.path}/run.json').existsSync(), isTrue);
    });

    test('the lastSettledRunId orphan guard discards an already-settled run',
        () async {
      // Play + save a real run, then settle it (writes meta, deletes run).
      final c = fresh();
      addTearDown(c.dispose);
      c.beginRound();
      await c.debugSettled;
      final runId = c.runId;
      // Re-create the run.json (simulate the §5.1 crash window: meta settled
      // with lastSettledRunId, but run.json was not yet deleted).
      await store.writeRun(
        seed: kSeed,
        cursor: c.state.rngCursor,
        backgroundId: c.backgroundId,
        steps: const [OperateStep()],
        cacheState: c.state,
      );
      final settledMeta = MetaState(lastSettledRunId: runId);

      final resume = await store.loadRun(
          economy: economy, content: content, meta: settledMeta);
      expect(resume.hasRun, isFalse);
      expect(resume.abandonedReason, contains('settled'));
      expect(File('${dir.path}/run.json').existsSync(), isFalse);
    });
  });

  group('settlement (doc 02 §2 / docs/06 §5.1)', () {
    test('migrateMeta from v7 preserves the Track Record (additive)', () {
      // The engine's own migrate path, exercised through the store's parse.
      final v7 = '{"schemaVersion":7,"reputation":4200,"metaLevel":1,'
          '"furthestTierReached":2,"unlockedCards":[],'
          '"unlockedSectors":["SOFTWARE","SERVICES","RETAIL","INDUSTRIAL"],'
          '"unlockedBackgrounds":["BOOTSTRAPPER"],"hardModes":[],'
          '"cosmetics":{"titles":[],"activeTitle":null,"iconSkins":[]},'
          '"lastDeathCause":null,"runsPlayed":3}';
      final m = SaveStore.parseMetaString(v7);
      expect(m.schemaVersion, engineSchemaVersion);
      expect(m.reputation, 4200);
      expect(m.runsPlayed, 3);
      expect(m.cleanExits, 0); // defaulted by the 7->8 step
    });
  });
}
