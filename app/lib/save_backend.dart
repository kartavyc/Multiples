/// SaveBackend — the platform persistence seam under [SaveStore] (docs/06 §6).
///
/// The store owns ALL of the docs/06 sequencing (the two-file split, the
/// `.bak` discipline, the migrate-then-parse load ladder, the write-chain
/// ordering). It moves only opaque JSON STRING blobs through this seam — no
/// game logic, no engine types. That keeps the one thing that is genuinely
/// platform-specific (where bytes live) isolated, so the app compiles on BOTH
/// native (dart:io files in the app documents dir) and web (browser
/// key-value), with NO `dart:io` symbol referenced on web.
///
/// A backend is a flat blob KV over a small fixed key set ([kRunKey],
/// [kMetaKey], [kMetaBakKey]). Writes are atomic on the native backend
/// (temp-file + rename, docs/06 §5); a torn read surfaces as a parse failure
/// the store's recovery ladder already absorbs.
library;

/// Blob keys (the docs/06 §2 two-file split + the meta `.bak` sibling). The
/// native backend maps these to `run.json` / `meta.json` / `meta.json.bak`;
/// the web backend maps them to namespaced SharedPreferences keys.
const String kRunKey = 'run';
const String kMetaKey = 'meta';
const String kMetaBakKey = 'meta.bak';

/// The platform persistence seam: opaque string blobs under a fixed key set.
/// All higher-level discipline (which key is durable, when to refresh `.bak`,
/// how to recover a torn read) lives in [SaveStore] — this is just bytes.
abstract class SaveBackend {
  /// Reads the blob at [key], or null if it does not exist. A torn/unreadable
  /// blob may throw; the store treats any failure as "absent/corrupt".
  Future<String?> read(String key);

  /// Writes [body] at [key]. Atomic where the platform allows (native:
  /// temp-write + rename; web: a single KV put). Overwrites any prior value.
  Future<void> write(String key, String body);

  /// True iff a blob currently exists at [key] (the store's cheap pre-check).
  Future<bool> exists(String key);

  /// Deletes the blob at [key] if present. Idempotent.
  Future<void> delete(String key);
}
