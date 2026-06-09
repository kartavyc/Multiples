// WEB SAVE BACKEND round-trip (B1 web port, docs/06 §6).
//
// The web build persists the save blobs in SharedPreferences instead of
// dart:io files. This drives the real WebSaveBackend (over the prefs mock)
// THROUGH the store's public API + the real engine serialize/replay path —
// proving a run written on web reads back to the byte-identical flattened
// state, and that meta + wipe behave. No files, no plugin channel.

import 'dart:io' show File;

import 'package:engine/content.dart';
import 'package:engine/model.dart';
import 'package:engine/serialize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiples_app/controller.dart';
import 'package:multiples_app/save_backend_web.dart';
import 'package:multiples_app/save_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int kSeed = 2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cardsJson = File('assets/data/cards.json').readAsStringSync();
  final economyJson =
      File('assets/data/economy-model.json').readAsStringSync();
  final economy = loadEconomy(economyJson);
  final content = loadCards(cardsJson);

  late SaveStore store;

  setUp(() async {
    // Fresh, empty browser storage for every test.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    store = SaveStore.forBackend(WebSaveBackend(prefs));
  });

  GameController fresh() => GameController(
        cardsJson: cardsJson,
        economyJson: economyJson,
        seed: kSeed,
        backgroundId: kBootstrapperBackgroundId,
        store: store,
        meta: MetaState(),
      );

  test('web backend: a mid-run save replays to the identical state', () async {
    final c = fresh();
    addTearDown(c.dispose);
    c.beginRound();
    if (c.canReroll) c.reroll();
    c.endTurnToShop();
    await c.debugSettled;

    final savedFlat = flatten(c.state);
    final savedCursor = c.state.rngCursor;

    final resume = await store.loadRun(
        economy: economy, content: content, meta: MetaState());
    expect(resume.hasRun, isTrue, reason: 'a run blob was written to prefs');
    final load = resume.load!;
    expect(load.seed, kSeed);
    expect(load.cursor, savedCursor);
    expect(flatten(load.state), equals(savedFlat));
  });

  test('web backend: writeMeta -> loadMeta round-trips the Track Record',
      () async {
    final meta = MetaState(
      reputation: 1820000,
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

  test('web backend: a missing meta loads a fresh default (first launch)',
      () async {
    final back = await store.loadMeta();
    expect(back.reputation, 0);
    expect(back.runsPlayed, 0);
    expect(back.unlockedBackgrounds, contains(kBootstrapperBackgroundId));
  });

  test('web backend: wipeSave clears run + meta (true fresh install)',
      () async {
    await store.writeMeta(MetaState(reputation: 42, runsPlayed: 1));
    await store.writeRun(
      seed: kSeed,
      cursor: 0,
      backgroundId: kBootstrapperBackgroundId,
      steps: const [OperateStep()],
    );
    expect(await store.hasRunFile(), isTrue);

    await store.wipeSave();
    expect(await store.hasRunFile(), isFalse);
    final back = await store.loadMeta();
    expect(back.reputation, 0);
    expect(back.runsPlayed, 0);
  });
}
