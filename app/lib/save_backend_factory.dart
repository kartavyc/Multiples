/// Picks the platform [SaveBackend] at COMPILE time (docs/06 §6 web port).
///
/// The conditional export below re-exports exactly ONE backend
/// implementation's factory functions — the dart:io one everywhere `dart:io`
/// exists, the web one when it does not. Because the selection is a static
/// `export ... if (...)`, a web build never even parses `save_backend_io.dart`,
/// so no `dart:io` symbol leaks into the web compile (the B1 blocker).
///
/// Exposes:
///   - `openPlatformBackend()`        — the production backend (path_provider
///                                       dir on native; SharedPreferences on web)
///   - `backendForDirectory(Object)`  — the native test seam (throws on web)
library;

export 'save_backend_io.dart'
    if (dart.library.js_interop) 'save_backend_web.dart';
