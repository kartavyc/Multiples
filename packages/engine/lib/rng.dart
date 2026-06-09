/// The engine RNG, selected at compile time for the target platform.
///
/// Native (VM + AOT, `dart:io` present) gets the canonical 64-bit SplitMix64
/// in [rng_native.dart] — the byte-stable stream every golden test and mobile
/// build depends on. Web (dart2js / dart2wasm, where `dart.library.js_interop`
/// is available and `int` is a 53-bit-exact double) gets the 32-bit xorshift128
/// in [rng_web.dart], which is web-safe and self-consistent but a different
/// stream. Both expose the same `SplitMix64Rng` type and API, so every call
/// site, the replay/serialize paths, and the save format are unchanged.
///
/// Because the selection is a static `export ... if (...)`, a native/VM build
/// — including `dart test` — never parses the web file (so the engine's golden
/// replay stays byte-identical off-web), and a web build never parses the
/// 64-bit file (so no out-of-range integer literal reaches dart2js).
library;

export 'rng_native.dart' if (dart.library.js_interop) 'rng_web.dart';
