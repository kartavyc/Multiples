// MIGRATION tests (R13; docs/06 §3) — the forward-only save upgraders +
// the golden-fixtures regression net (docs/06 §3.2 rule 5: every schema-bump
// PR commits the prior version's fixture; a load through migrateChain must
// reach the current schema, or — for a run on a stream-breaking version —
// abandon cleanly).
//
// No real pre-current saves exist in the wild, so the fixtures are SYNTHETIC
// v7 AND v8 saves (test/golden/saves/*.json) that prove the chain runs and
// that a stream-breaking run abandons. Per docs/06 §3.2 rule 5 each schema
// bump commits the PRIOR version's fixture — R15 (v9) added meta_v8/run_v8.
//
// dart:io / dart:convert are TEST-ONLY (reading the fixtures). No double.

import 'dart:convert';
import 'dart:io';

import 'package:engine/migrate.dart';
import 'package:engine/model.dart';
import 'package:engine/serialize.dart';
import 'package:test/test.dart';

Map<String, Object?> _loadFixture(String name) =>
    jsonDecode(File('test/golden/saves/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  group('migrateChain mechanics (docs/06 §3.2)', () {
    test('a no-op chain (from == current) returns the map unchanged', () {
      final j = {'schemaVersion': engineSchemaVersion, 'x': 1};
      expect(migrateMeta(j, engineSchemaVersion), j);
    });

    test('a save from a NEWER version is refused (forward-only)', () {
      expect(() => migrateMeta({'schemaVersion': 99}, engineSchemaVersion + 1),
          throwsA(isA<SaveFromNewerVersion>()));
      expect(() => migrateRun({'schemaVersion': 99}, engineSchemaVersion + 1),
          throwsA(isA<SaveFromNewerVersion>()));
    });
  });

  group('META migration (additive forward; never abandons)', () {
    test('the synthetic v7 meta fixture migrates to the current schema and '
        'gains the new fields with safe defaults', () {
      final v7 = _loadFixture('meta_v7.json');
      expect(v7['schemaVersion'], 7);
      expect(v7.containsKey('lastSettledRunId'), isFalse,
          reason: 'the v7 fixture predates the double-settle guard');
      expect(v7.containsKey('cleanExits'), isFalse);

      final migrated = migrateMeta(v7, 7);
      expect(migrated['schemaVersion'], engineSchemaVersion);
      // Additive defaults landed:
      expect(migrated['lastSettledRunId'], isNull);
      expect(migrated['cleanExits'], 0);
      // Existing access state PRESERVED (the player keeps their record):
      expect(migrated['reputation'], 184200);
      expect(migrated['furthestTierReached'], 3);
      expect(migrated['lastDeathCause'], 'MISSED_DEADLINE');
      expect(migrated['runsPlayed'], 27);
    });

    test('the migrated v7 meta deserializes into a valid MetaState', () {
      final migrated = migrateMeta(_loadFixture('meta_v7.json'), 7);
      final meta = metaStateFromJson(migrated);
      expect(meta.schemaVersion, engineSchemaVersion);
      expect(meta.reputation, 184200);
      expect(meta.furthestTierReached, 3);
      expect(meta.lastDeathCause, DeathCause.missedDeadline);
      expect(meta.runsPlayed, 27);
      expect(meta.cleanExits, 0, reason: 'defaulted by the migration');
      expect(meta.lastSettledRunId, isNull);
      expect(meta.unlockedBackgrounds, contains('OPERATOR'));
    });

    test('the synthetic v8 meta fixture migrates to the current schema '
        '(8->9->10 are pure version bumps — no new meta fields; R20b\'s '
        'unlock snapshot is RUN state, not meta)', () {
      final v8 = _loadFixture('meta_v8.json');
      expect(v8['schemaVersion'], 8);
      final migrated = migrateMeta(v8, 8);
      expect(migrated['schemaVersion'], engineSchemaVersion);
      expect(migrated['schemaVersion'], 10);
      // Every v8 field PRESERVED (the unlock snapshot is RUN state, not meta
      // — meta is unchanged across 8->9->10):
      expect(migrated['reputation'], 312500);
      expect(migrated['cleanExits'], 9);
      expect(migrated['lastSettledRunId'], 'r_0000002a');
      final meta = metaStateFromJson(migrated);
      expect(meta.schemaVersion, 10);
      expect(meta.cleanExits, 9);
      expect(meta.unlockedBackgrounds, contains('DEALMAKER'));
    });

    test('a CURRENT-version meta round-trips toJson -> fromJson unchanged', () {
      final m = MetaState(
        reputation: 500000,
        metaLevel: 1,
        furthestTierReached: 2,
        unlockedBackgrounds: const ['BOOTSTRAPPER', 'VC_DARLING'],
        lastDeathCause: DeathCause.bankruptcy,
        runsPlayed: 5,
        cleanExits: 2,
        lastSettledRunId: 'r_0000002a',
      );
      final round = metaStateFromJsonString(metaStateToJsonString(m));
      expect(round, m);
    });
  });

  group('RUN migration (abandons on stream-breaking)', () {
    test('the synthetic v7 run fixture ABANDONS cleanly (no replay path)', () {
      final v7 = _loadFixture('run_v7.json');
      expect(v7['schemaVersion'], 7);
      expect(() => migrateRun(v7, 7), throwsA(isA<AbandonRun>()),
          reason: 'a v7 run has no typed RunStep journal — unreplayable on '
              'v8; docs/06 §3 STREAM-BREAKING -> drop the run');
    });

    test('AbandonRun carries a reason naming the version gap', () {
      try {
        migrateRun(_loadFixture('run_v7.json'), 7);
        fail('expected AbandonRun');
      } on AbandonRun catch (e) {
        expect(e.reason, contains('7->8'));
      }
    });

    test('the synthetic v8 run fixture ABANDONS cleanly (R15: 8->9 widened '
        'the state + journal action shape — stream-breaking)', () {
      final v8 = _loadFixture('run_v8.json');
      expect(v8['schemaVersion'], 8);
      expect(() => migrateRun(v8, 8), throwsA(isA<AbandonRun>()),
          reason: 'a v8 run reconciles against a flatten that now includes '
              'backgroundId; docs/06 §3 STREAM-BREAKING -> drop the run');
      try {
        migrateRun(v8, 8);
        fail('expected AbandonRun');
      } on AbandonRun catch (e) {
        expect(e.reason, contains('8->9'));
      }
    });

    test('a current-version run needs no migration (from == current is a '
        'no-op, the loader then replays it)', () {
      final j = {'schemaVersion': engineSchemaVersion};
      expect(migrateRun(j, engineSchemaVersion), j);
    });
  });

  group('the loader policy contract (docs/06 §3): run drops, meta survives',
      () {
    test('an old save set: the run abandons but the meta migrates — the '
        'player loses one mid-run, never their Track Record', () {
      // Meta migrates (additive):
      final meta = metaStateFromJson(migrateMeta(_loadFixture('meta_v7.json'), 7));
      expect(meta.reputation, 184200, reason: 'Track Record preserved');
      // Run abandons (the two files load independently — docs/06 §3 rule 4):
      var runAbandoned = false;
      try {
        migrateRun(_loadFixture('run_v7.json'), 7);
      } on AbandonRun {
        runAbandoned = true;
      }
      expect(runAbandoned, isTrue);
    });
  });
}
