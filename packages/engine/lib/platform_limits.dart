/// Compile-time selection of the integer-width limits for the target.
///
/// Mirrors the save-backend conditional-export idiom: native (`dart:io`
/// present) gets the int64 magnitudes in [platform_limits_io.dart]; web
/// (dart2js / dart2wasm, where `dart.library.js_interop` is available) gets
/// the 2^53-safe magnitudes in [platform_limits_web.dart]. A native/VM build
/// — including `dart test` — never parses the web file, so the engine's
/// golden replay stays byte-identical off-web.
///
/// Exposes: `kSatMulMaxCents` (money.dart satMul cap) and `kIntWidthMaxCents`
/// (round.dart endless-bar sentinel + compound overflow cap).
library;

export 'platform_limits_io.dart'
    if (dart.library.js_interop) 'platform_limits_web.dart';
