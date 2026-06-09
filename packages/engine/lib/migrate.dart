/// MIGRATION — forward-only save upgraders (docs/06 §3). Pure: operates on
/// raw `Map<String, Object?>` BEFORE typed deserialization, so an old-shape
/// file is upgraded to the current shape and only then parsed (serialize.dart
/// / meta JSON). No I/O, no clock, no float.
///
/// Two scopes, two policies (docs/06 §3 classification table):
///   - META migrates across EVERY bump, ADDITIVELY (new fields get a
///     defaulted step). A meta save is never abandoned — the player never
///     loses their Track Record to a version bump.
///   - RUN migrates forward for CONTENT-ONLY bumps, but THROWS [AbandonRun]
///     on any STREAM-BREAKING bump (RNG/draw-order/five-input/actionLog-shape
///     change): a migration cannot un-break a seed whose stream moved, so the
///     loader drops the run (keeps meta) and shows "no run in progress".
///
/// Each step `vN -> vN+1` is a tiny pure function, APPEND-ONLY and FROZEN
/// once shipped (docs/06 §3.2 rule 3) — never edit a shipped step, or you
/// desync players mid-upgrade. A schema-bump PR MUST add the prior version's
/// golden save fixture (docs/06 §3.2 rule 5; migrate_test.dart's fixtures).
///
/// Pure and dependency-free except for sibling engine libraries.
library;

import 'model.dart';

/// Thrown by [migrateRun] (and the run [migrateChain]) for any
/// STREAM-BREAKING bump — the run is unreplayable on this engine and must be
/// dropped. The loader catches it and falls back to "no run in progress";
/// the meta save loads independently and is untouched (docs/06 §3 rule 4).
class AbandonRun implements Exception {
  AbandonRun(this.reason);

  /// Why the run was abandoned (the version gap / classification).
  final String reason;

  @override
  String toString() => 'AbandonRun: $reason';
}

/// Thrown when a save is from a NEWER schema than this engine knows
/// (docs/06 §3.2 rule 1: forward-only, no downgrades — an older app refuses
/// a newer save rather than corrupting it). The app shows "this save is from
/// a newer version of the game".
class SaveFromNewerVersion implements Exception {
  SaveFromNewerVersion(this.from, this.current);
  final int from;
  final int current;
  @override
  String toString() =>
      'SaveFromNewerVersion: save is v$from, this engine is v$current';
}

/// A single migration step: a pure `vN -> vN+1` transform on the raw map.
typedef Migration = Map<String, Object?> Function(Map<String, Object?> json);

/// Applies the [steps] registry as a chain `from -> from+1 -> ... -> current`
/// (docs/06 §3.2). A missing step is the STREAM-BREAKING signal: [onMissing]
/// decides the policy (run: throw [AbandonRun]; meta: hard-fail loudly — a
/// gap in the meta chain is a build bug, not a recoverable state).
Map<String, Object?> migrateChain(
  Map<String, Object?> json,
  int from,
  int current,
  Map<int, Migration> steps, {
  required Never Function(int v) onMissing,
}) {
  if (from > current) throw SaveFromNewerVersion(from, current);
  var j = json;
  for (var v = from; v < current; v++) {
    final step = steps[v];
    if (step == null) onMissing(v); // Never-returning -> step is non-null below
    j = step(j);
  }
  return j;
}

// ===========================================================================
// META migrations (additive forward; never abandons)
// ===========================================================================

/// The meta migration registry: step `N` upgrades a v`N` map to v`N+1`,
/// ADDITIVELY (defaults for new fields). APPEND-ONLY — never edit a shipped
/// step.
///
/// Step 7->8 (R13): the save layer landed at engineSchemaVersion 8, and
/// MetaState gained the docs/06 §5.1 `lastSettledRunId` double-settle guard
/// (and formalized `cleanExits`). A synthetic v7 meta (one that predates
/// these) defaults them: lastSettledRunId -> absent/null, cleanExits -> 0.
/// (No real v<8 meta ever shipped — R13 introduced MetaState — but the chain
/// is proven against a synthetic v7 fixture per docs/06 §3.2 rule 5, so the
/// machinery is exercised and ready for the first real future bump.)
final Map<int, Migration> metaMigrations = <int, Migration>{
  7: (j) => {
        ...j,
        'schemaVersion': 8,
        // Additive defaults for the fields a v7 meta lacked:
        'lastSettledRunId': j['lastSettledRunId'], // stays null if absent
        'cleanExits': j['cleanExits'] ?? 0,
      },
  // Step 8->9 (R15): the engineSchemaVersion bumped to 9 (backgroundId on the
  // RUN state + the secondary-sale resolver + endless escalation). NONE of
  // that is META — MetaState is unchanged — so the meta step is a pure
  // version bump with no new fields. It still MUST exist: the chain hard-
  // fails on a gap, and a shipped version with no forward step is a build
  // bug (docs/06 §3.2). A v8 meta carries straight over.
  8: (j) => {
        ...j,
        'schemaVersion': 9,
      },
  // Step 9->10 (R20b): engineSchemaVersion bumped to 10 (the draw-pool
  // keystone — the full unlocked card set into play + SPIN_OFF/EARN_OUT
  // resolvers). NONE of that is META — MetaState is unchanged (the unlock
  // ladder it feeds was already there since R17) — so the meta step is a
  // pure version bump with no new fields. It still MUST exist (the chain
  // hard-fails on a gap). A v9 meta carries straight over.
  9: (j) => {
        ...j,
        'schemaVersion': 10,
      },
};

/// Migrates a raw META map from version [from] to [engineSchemaVersion]
/// (docs/06 §3). Additive; never abandons. A gap in the chain HARD-FAILS
/// (a build bug — a shipped meta version with no upgrade path).
Map<String, Object?> migrateMeta(Map<String, Object?> json, int from) {
  return migrateChain(
    json,
    from,
    engineSchemaVersion,
    metaMigrations,
    onMissing: (v) => throw StateError(
        'meta migration $v->${v + 1} is missing — a shipped meta version '
        'must have a forward step (docs/06 §3.2). This is a build bug, not a '
        'recoverable save.'),
  );
}

// ===========================================================================
// RUN migrations (forward for content-only; ABANDON on stream-breaking)
// ===========================================================================

/// The run migration registry: step `N` upgrades a v`N` run to v`N+1` ONLY
/// for a CONTENT-ONLY (replay-safe) bump. A STREAM-BREAKING bump has NO step
/// here — the chain then throws [AbandonRun] (docs/06 §3).
///
/// EMPTY today: every engineSchemaVersion bump so far moved the stream or the
/// five-input/actionLog shape (the docs/03 §6 history: v1->2 OPERATE draws,
/// 2->3 fields, 3->4 deal-flow stream, 4->5 exit-offer stream, 5->6->7 moved
/// VALUES, 7->8 the persisted actionLog CONTRACT, 8->9 widened the state
/// [backgroundId] + the persisted journal action shape [secondaryBp] + moved
/// endless behavior — a v8 run reconciles against a flatten that now includes
/// backgroundId and cannot be trusted), and v9->10 MOVED THE STREAM again
/// (R20b widened the draw pool from verticalSlice to the per-run unlocked
/// set — every no-replacement draw index changed — plus widened the state
/// with unlockedCardIds/unlockedSectors). So ANY v<10 run is abandoned. When
/// a future bump IS content-only (e.g. a new card that does not touch draw
/// order), add its `N->N+1` step here and the run will migrate-and-replay
/// instead of abandoning.
final Map<int, Migration> runMigrations = <int, Migration>{
  // (no content-only run bumps yet)
};

/// Migrates a raw RUN map from version [from] to [engineSchemaVersion]
/// (docs/06 §3). May THROW [AbandonRun] for a stream-breaking gap — the
/// loader catches it and drops the run (keeps meta). Throws
/// [SaveFromNewerVersion] for a future-version save.
Map<String, Object?> migrateRun(Map<String, Object?> json, int from) {
  return migrateChain(
    json,
    from,
    engineSchemaVersion,
    runMigrations,
    onMissing: (v) => throw AbandonRun(
        'no run migration $v->${v + 1} (STREAM-BREAKING bump — a moved '
        'seed/draw-order/actionLog-shape cannot be un-broken; docs/06 §3). '
        'The run is dropped; meta is unaffected.'),
  );
}
