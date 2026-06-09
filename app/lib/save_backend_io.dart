/// Native ([dart:io]) persistence backend (docs/06 §6). The original file
/// layer, unchanged in behavior: two plain JSON files in the app's private
/// documents directory, written atomically (temp + rename). The directory is
/// INJECTED so widget/unit tests drive a temp dir with no plugin; production
/// resolves `getApplicationDocumentsDirectory()` once.
///
/// This file is selected by the conditional export in
/// `save_backend_factory.dart` on every NON-web platform; web never imports
/// it, so no `dart:io` symbol is referenced in a web build.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'save_backend.dart';

/// Maps the fixed blob keys onto sibling files in [dir].
const Map<String, String> _fileFor = {
  kRunKey: 'run.json',
  kMetaKey: 'meta.json',
  kMetaBakKey: 'meta.json.bak',
};

/// The dart:io blob backend over a real directory. `write` is the docs/06 §5
/// atomic fast path (write `<name>.tmp`, flush, rename over the target);
/// `read`/`delete`/`exists` are the obvious file ops. Identical on-disk
/// behavior to the pre-refactor SaveStore (the run/meta/.bak files, their
/// `.tmp` siblings, the rename-over commit).
class IoSaveBackend implements SaveBackend {
  /// Builds a backend rooted at [dir] (the app documents dir in prod; a temp
  /// dir in tests).
  IoSaveBackend(this.dir);

  /// The directory run.json / meta.json (+ their .tmp/.bak siblings) live in.
  final Directory dir;

  File _file(String key) => File('${dir.path}/${_fileFor[key]}');
  File _tmp(String key) => File('${dir.path}/${_fileFor[key]}.tmp');

  @override
  Future<String?> read(String key) async {
    final f = _file(key);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  Future<void> write(String key, String body) async {
    final tmp = _tmp(key);
    await tmp.writeAsString(body, flush: true);
    // Atomic-ish rename (docs/06 §5): on the common path `rename` replaces the
    // destination atomically. dart:io does not guarantee atomicity on every
    // Android backend, but the load path treats a torn file as corrupt and
    // recovers — atomic-rename is the fast path, corrupt-recovery is the net.
    await tmp.rename(_file(key).path);
  }

  @override
  Future<bool> exists(String key) => _file(key).exists();

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    final tmp = _tmp(key);
    if (await f.exists()) await f.delete();
    if (await tmp.exists()) await tmp.delete();
  }
}

/// Builds the production backend over the resolved app documents directory
/// (docs/06 §6: `getApplicationDocumentsDirectory`). Selected on native.
Future<SaveBackend> openPlatformBackend() async {
  final d = await getApplicationDocumentsDirectory();
  return IoSaveBackend(d);
}

/// Builds a backend over an injected directory ([Directory]) — the test seam
/// (`SaveStore.forDirectory`). Native only; the web factory throws.
SaveBackend backendForDirectory(Object dir) => IoSaveBackend(dir as Directory);
