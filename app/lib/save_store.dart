/// SaveStore — the app-side save/persistence I/O layer (docs/06).
///
/// This file does PERSISTENCE ORCHESTRATION ONLY. Every byte of game/meta
/// LOGIC — the save format, replay reconstruction, migration, settlement —
/// lives in the pure engine (serialize.dart / migrate.dart / meta.dart). The
/// store's whole job is docs/06 §6: two plain JSON blobs (run + durable meta)
/// written atomically, loaded through the engine's migrate-then-parse path,
/// with the meta `.bak` discipline and the reconcile-or-discard recovery the
/// doc spells out.
///
/// Platform seam (web port): WHERE the bytes live is the only thing that is
/// platform-specific, so it sits behind [SaveBackend] (string blobs only,
/// keyed [kRunKey]/[kMetaKey]/[kMetaBakKey]). A conditional export
/// (`save_backend_factory.dart`) binds the dart:io file backend on native and
/// a SharedPreferences backend on web, so this file references NO `dart:io`
/// and the app compiles on both. The store's public API and the engine are
/// unchanged.
///
/// Testability: the backend is INJECTED ([SaveStore.forDirectory] over a temp
/// dir on native; [SaveStore.forBackend] for a fake) so tests drive it with no
/// plugin; production uses [SaveStore.open] which resolves the platform
/// backend once. No game logic means the round-trip is exercised entirely
/// against the real engine funcs.
library;

import 'dart:async';
import 'dart:convert';

import 'package:engine/content.dart';
import 'package:engine/migrate.dart';
import 'package:engine/model.dart';
import 'package:engine/serialize.dart';
import 'package:flutter/foundation.dart';

import 'save_backend.dart';
import 'save_backend_factory.dart';

/// The outcome of attempting to load a run.json at boot (docs/06 §2.2 / §5.1):
/// either a resumable run, or nothing (missing / corrupt / abandoned on a
/// stream-breaking version / already-settled orphan).
class RunResumeResult {
  const RunResumeResult({this.load, this.abandonedReason});

  /// The reconstructed run (null when there is nothing to resume).
  final RunLoadResult? load;

  /// Why a run.json existed but was NOT resumed (corrupt / abandoned /
  /// already-settled), for a dev log; null when [load] is non-null or no
  /// file existed.
  final String? abandonedReason;

  /// True iff a run is resumable.
  bool get hasRun => load != null;
}

/// The on-device save layer (library header = the full contract). All methods
/// are async; the platform I/O is delegated to a [SaveBackend] and all
/// parsing/replay/migration to engine pure funcs.
class SaveStore {
  /// Builds a store over an explicit [backend] (the general seam; the fake
  /// in-memory backend in tests, or a platform backend).
  SaveStore.forBackend(this._backend);

  /// Builds a store rooted at [dir] (a dart:io [Directory]; the app documents
  /// dir in prod, a temp dir in tests). NATIVE ONLY — on web there is no
  /// directory, so use [SaveStore.open] / [SaveStore.forBackend]. Use
  /// [SaveStore.open] in app code.
  SaveStore.forDirectory(Object dir) : _backend = backendForDirectory(dir);

  /// The platform persistence seam (string blobs, fixed key set).
  final SaveBackend _backend;

  /// Resolves the real platform backend (docs/06 §6: the app documents dir on
  /// native via `getApplicationDocumentsDirectory`; SharedPreferences on web)
  /// and returns a store over it.
  static Future<SaveStore> open() async {
    final backend = await openPlatformBackend();
    return SaveStore.forBackend(backend);
  }

  /// Serializes all mutating ops (write/delete) so concurrent eager autosaves
  /// + a lifecycle flush + the settlement delete never interleave. Reads are
  /// not serialized. Chains as a tail-Future (docs/06 §5 atomic-write fast
  /// path stays intact; this just orders the writes).
  Future<void> _writeChain = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _writeChain = _writeChain.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // =========================================================================
  // META (durable; docs/06 §2.3, §5: migrate forward, never abandon; .bak)
  // =========================================================================

  /// Loads the durable meta save (docs/06 §5): parse the meta blob; on a schema
  /// mismatch, migrate forward (additive — never abandons); on a parse/migrate
  /// failure, fall back to the meta `.bak`; if both fail (or neither exists),
  /// return a FRESH [MetaState]. The game always boots with a meta.
  Future<MetaState> loadMeta() async {
    final fromMain = await _tryLoadMeta(kMetaKey);
    if (fromMain != null) return fromMain;
    final fromBak = await _tryLoadMeta(kMetaBakKey);
    if (fromBak != null) {
      debugPrint('SaveStore: meta blob unreadable; recovered from .bak');
      return fromBak;
    }
    return MetaState(); // first launch, or last-resort access-state loss
  }

  /// Parses one meta blob through migrate-then-parse (docs/06 §6), returning
  /// null on any failure (so the caller can fall through to .bak / fresh).
  Future<MetaState?> _tryLoadMeta(String key) async {
    try {
      final raw = await _backend.read(key);
      if (raw == null) return null;
      return _parseMeta(raw);
    } catch (e) {
      debugPrint('SaveStore: meta load failed for $key: $e');
      return null;
    }
  }

  /// Pure parse seam (no I/O) — visible for tests that inject a JSON string.
  /// Runs migrate.dart's [migrateMeta] FIRST (additive forward) then the
  /// engine's [metaStateFromJson]. The raw int `schemaVersion` decides the
  /// `from`.
  @visibleForTesting
  static MetaState parseMetaString(String raw) => _parseMeta(raw);

  static MetaState _parseMeta(String raw) {
    final json = _decodeObject(raw);
    final from = json['schemaVersion'];
    final fromV = from is int ? from : engineSchemaVersion;
    final migrated = migrateMeta(json, fromV);
    return metaStateFromJson(migrated);
  }

  /// Writes [meta] atomically with the docs/06 §5 backup discipline:
  ///   1. snapshot the CURRENT good meta into the `.bak` blob (so a crash
  ///      mid-write cannot lose the last-known-good meta);
  ///   2. write the new meta over the durable meta blob.
  /// (The native backend makes each blob write atomic via temp+rename; on web
  /// each is a single atomic key put.)
  Future<void> writeMeta(MetaState meta) => _serialized(() async {
        final body = metaStateToJsonString(meta);
        // (1) snapshot the current good meta into .bak before we overwrite it.
        try {
          final current = await _backend.read(kMetaKey);
          if (current != null) {
            await _backend.write(kMetaBakKey, current);
          }
        } catch (e) {
          // A failed backup must never block the new write (the .bak is the
          // safety net, not the primary); log and continue.
          debugPrint('SaveStore: meta .bak refresh failed: $e');
        }
        // (2) the new meta becomes current.
        await _backend.write(kMetaKey, body);
      });

  // =========================================================================
  // RUN (resumable autosave; docs/06 §2.1-2.2, §3, §5.1)
  // =========================================================================

  /// Loads the resumable run (docs/06 §2.2 / §3 / §5.1), reconciling against
  /// [meta] for the double-settle orphan guard. The full recovery ladder:
  ///   - no run blob               -> no run in progress
  ///   - JSON parse fails / corrupt  -> discard run, no run in progress
  ///   - schemaVersion mismatch:
  ///       CONTENT-ONLY  -> migrateRun upgrades it, then replay
  ///       STREAM-BREAK  -> AbandonRun -> drop run, keep meta
  ///       NEWER VERSION -> SaveFromNewerVersion -> keep blob, do not resume
  ///   - run already settled (startConfig.runId == meta.lastSettledRunId, a
  ///     mid-settlement crash orphan, docs/06 §5.1) -> delete it, no resume
  ///   - replay desync / cursor mismatch -> corrupt, discard, no resume
  ///
  /// On any "drop" outcome the blob is deleted here (so the next boot is
  /// clean). The returned [RunResumeResult.abandonedReason] is for a dev log.
  Future<RunResumeResult> loadRun({
    required EconomyConfig economy,
    required ContentDb content,
    required MetaState meta,
  }) async {
    String? raw;
    try {
      raw = await _backend.read(kRunKey);
    } catch (e) {
      await deleteRun();
      return RunResumeResult(abandonedReason: 'unreadable: $e');
    }
    if (raw == null) {
      return const RunResumeResult();
    }

    Map<String, Object?> json;
    try {
      json = _decodeObject(raw);
    } catch (e) {
      await deleteRun();
      return RunResumeResult(abandonedReason: 'corrupt JSON: $e');
    }

    // docs/06 §5.1 orphan guard: a run whose id was already settled is a
    // mid-settlement crash leftover — discard, never re-settle.
    final startConfig = json['startConfig'];
    if (startConfig is Map && meta.lastSettledRunId != null) {
      final runId = startConfig['runId'];
      if (runId is String && runId == meta.lastSettledRunId) {
        await deleteRun();
        return const RunResumeResult(
            abandonedReason: 'already settled (orphan run.json)');
      }
    }

    // docs/06 §3: migrate FIRST (AbandonRun on stream-breaking; the
    // SaveFromNewerVersion on a future save), THEN reconstruct by replay.
    final fromRaw = json['schemaVersion'];
    final fromV = fromRaw is int ? fromRaw : engineSchemaVersion;
    Map<String, Object?> migrated;
    try {
      migrated = migrateRun(json, fromV);
    } on AbandonRun catch (e) {
      await deleteRun(); // a moved stream cannot be un-broken; meta untouched
      return RunResumeResult(abandonedReason: 'abandoned: ${e.reason}');
    } on SaveFromNewerVersion catch (e) {
      // Forward-only: keep the blob (an upgrade may read it), do not resume.
      return RunResumeResult(abandonedReason: 'newer version: $e');
    }

    try {
      final load =
          runSaveFromJson(migrated, economy: economy, content: content);
      if (!load.usedCache) {
        debugPrint('SaveStore: run cache discarded; resumed from replay');
      }
      return RunResumeResult(load: load);
    } catch (e) {
      // ReplayDesyncError / FormatException / a cursor mismatch — corrupt.
      await deleteRun();
      return RunResumeResult(abandonedReason: 'replay/parse failed: $e');
    }
  }

  /// Writes the resumable run blob atomically (docs/06 §4 cadence, §5 atomic
  /// write). [steps] is the typed replay journal (the source of truth);
  /// [cacheState] is the optional hot-path snapshot (rng-stripped by the
  /// engine). One committed action / phase transition = one call.
  Future<void> writeRun({
    required int seed,
    required int cursor,
    required String backgroundId,
    required List<RunStep> steps,
    GameState? cacheState,
    List<String> unlockedCardIds = kDefaultUnlockedCardIds,
    List<Sector> unlockedSectors = kDefaultUnlockedSectors,
  }) {
    final body = runSaveToJsonString(
      seed: seed,
      cursor: cursor,
      backgroundId: backgroundId,
      steps: steps,
      cacheState: cacheState,
      unlockedCardIds: unlockedCardIds,
      unlockedSectors: unlockedSectors,
    );
    return _serialized(() => _backend.write(kRunKey, body));
  }

  /// Deletes the run blob (docs/06 §5.1: AFTER the settled meta is durably
  /// written, or to drop a corrupt/abandoned blob). Idempotent. Serialized
  /// after any pending autosave so a settlement delete can't race a write.
  Future<void> deleteRun() => _serialized(() async {
        try {
          await _backend.delete(kRunKey);
        } catch (e) {
          debugPrint('SaveStore: deleteRun failed: $e');
        }
      });

  /// True iff a run blob currently exists (a cheap pre-check; the
  /// authoritative resumability decision is [loadRun]).
  Future<bool> hasRunFile() => _backend.exists(kRunKey);

  /// WIPE SAVE (R20 SETTINGS danger action): deletes the run blob AND the
  /// durable meta (+ its .bak), so the next boot is a true fresh install.
  /// Idempotent; serialized after any pending write. Pure I/O — the caller
  /// resets its in-memory MetaState to a fresh one.
  Future<void> wipeSave() => _serialized(() async {
        for (final key in [kRunKey, kMetaKey, kMetaBakKey]) {
          try {
            await _backend.delete(key);
          } catch (e) {
            debugPrint('SaveStore: wipeSave delete failed for $key: $e');
          }
        }
      });
}

// ===========================================================================
// Small helpers (the only non-engine work the store does)
// ===========================================================================

/// Decodes a JSON object string into a typed map, throwing on a non-object
/// (a torn or foreign blob). JSON decode is plain parsing, not game logic, so
/// it lives here rather than in the engine.
Map<String, Object?> _decodeObject(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) return decoded.cast<String, Object?>();
  throw const FormatException('save file is not a JSON object');
}
