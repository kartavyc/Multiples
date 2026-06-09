/// Web persistence backend (docs/06 §6, web port). The browser has no app
/// documents directory and no `dart:io`, so the save blobs live in
/// SharedPreferences — which on web is a thin wrapper over `window.localStorage`
/// (and on the newer async API, IndexedDB). The blobs are small JSON strings
/// (one run journal + the durable meta + a meta `.bak`), so a key-value store
/// is the right tool: each [SaveBackend] key becomes one namespaced preferences
/// key.
///
/// There is no atomic rename on the web — a `write` is a single localStorage
/// put, which is itself atomic per key, so the docs/06 §5 temp+rename dance is
/// unnecessary here (and the store's torn-read recovery ladder is the net
/// either way). Selected by the conditional export in
/// `save_backend_factory.dart` ONLY on web; no `dart:io` is referenced.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'save_backend.dart';

/// Namespace so the save blobs never collide with the audio settings keys the
/// app also keeps in SharedPreferences.
const String _prefix = 'multiples.save.';

/// The web blob backend over SharedPreferences. Keys are namespaced; values
/// are the raw JSON strings the store hands down (no transformation).
class WebSaveBackend implements SaveBackend {
  /// Builds a backend over an already-resolved [SharedPreferences] instance.
  WebSaveBackend(this._prefs);

  final SharedPreferences _prefs;

  String _k(String key) => '$_prefix$key';

  @override
  Future<String?> read(String key) async => _prefs.getString(_k(key));

  @override
  Future<void> write(String key, String body) async {
    await _prefs.setString(_k(key), body);
  }

  @override
  Future<bool> exists(String key) async => _prefs.containsKey(_k(key));

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(_k(key));
  }
}

/// Builds the production web backend (resolves SharedPreferences once).
/// Selected on web by the conditional export.
Future<SaveBackend> openPlatformBackend() async {
  final prefs = await SharedPreferences.getInstance();
  return WebSaveBackend(prefs);
}

/// The injected-directory test seam does not exist on web (there is no
/// [Directory]); calling it is a programming error in a web build.
SaveBackend backendForDirectory(Object dir) =>
    throw UnsupportedError('SaveStore.forDirectory is not supported on web');
