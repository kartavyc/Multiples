/// The WEB implementation of the engine RNG (dart2js / dart2wasm), where
/// Dart `int` is a JavaScript number and only integers up to 2^53-1 are
/// exact — so the native 64-bit SplitMix64 (rng_native.dart) cannot run.
///
/// It keeps the SAME public type and API as the native generator
/// (`SplitMix64Rng(seed, {cursor})`, [cursor], [nextRaw], [nextInt]) so every
/// call site, replay path, and save format is unchanged. Internally it is a
/// 32-bit xorshift128 (Marsaglia 2003): all state and arithmetic stay within
/// 32 bits via `& _mask32`, so every operation is exact under dart2js.
///
/// IMPORTANT — the stream is its own. This is NOT bit-identical to the native
/// SplitMix64 stream: a given seed yields a DIFFERENT sequence of draws on web
/// than on native. That is invisible to players (seeds are auto-generated from
/// the clock, never shown or shared) and harmless to balance (draws are still
/// uniform via `% bound`). It is fully deterministic and self-consistent on
/// web: the same `seed`+`cursor` always reproduces the same continuation, so
/// in-browser save/resume and replay-verify work exactly as on native.
///
/// The class name is kept as `SplitMix64Rng` purely for drop-in API parity;
/// the algorithm here is xorshift128.
class SplitMix64Rng {
  static const int _mask32 = 0xFFFFFFFF;

  int _x = 0;
  int _y = 0;
  int _z = 0;
  int _w = 0;
  int _cursor;

  /// Creates a web RNG from [seed], optionally fast-forwarded past [cursor]
  /// already-consumed draws (so it resumes a stream exactly like the native
  /// generator's cursor constructor). [seed] is the run seed (the app derives
  /// it from the clock, so it is a non-negative value well under 2^53).
  SplitMix64Rng(int seed, {int cursor = 0}) : _cursor = 0 {
    final s = seed < 0 ? -seed : seed;
    final lo = s & _mask32;
    // High word: seed <= 2^53 means hi <= 2^21 (use ~/ , not a 64-bit shift).
    final hi = (s ~/ 0x100000000) & _mask32;
    _x = (lo ^ 0x9E3779B9) & _mask32;
    _y = (hi ^ 0x243F6A88) & _mask32;
    _z = ((lo + hi) ^ 0x85EBCA6B) & _mask32;
    _w = ((lo ^ hi) ^ 0xC2B2AE35) & _mask32;
    // xorshift dies at the all-zero fixed point; never let the state be zero.
    if ((_x | _y | _z | _w) == 0) _x = 0x9E3779B9;
    // Diffuse the seed so near-identical seeds (consecutive clock values)
    // produce well-separated streams. These warmup steps are NOT counted in
    // the cursor (they are part of constructing a "fresh" generator).
    for (var i = 0; i < 16; i++) {
      _step();
    }
    // Fast-forward to the requested cursor.
    for (var i = 0; i < cursor; i++) {
      _step();
    }
    _cursor = cursor;
  }

  /// Number of draws consumed so far.
  int get cursor => _cursor;

  /// Advances the xorshift128 state one step and returns a 32-bit result in
  /// `[0, 2^32)`. Does NOT touch the cursor.
  int _step() {
    var t = _x ^ ((_x << 11) & _mask32);
    t &= _mask32;
    _x = _y;
    _y = _z;
    _z = _w;
    _w = (_w ^ (_w >> 19) ^ (t ^ (t >> 8))) & _mask32;
    return _w;
  }

  /// Returns the next raw generator output and advances the cursor by 1.
  ///
  /// On web this is a non-negative 32-bit value (not the signed 64-bit value
  /// the native generator returns). The engine never consumes `nextRaw`
  /// directly — only [nextInt] and [cursor] — so the width difference is
  /// internal; the method exists for API parity with the native generator.
  int nextRaw() {
    final v = _step();
    _cursor++;
    return v;
  }

  /// Returns a value in `[0, bound)` and advances the cursor by 1.
  ///
  /// [bound] must be positive. The 32-bit raw output modulo a positive bound
  /// is non-negative and in range (a negligible modulo bias when `bound` does
  /// not divide 2^32, exactly as on native). One [nextInt] == one cursor
  /// advance, matching the native generator.
  int nextInt(int bound) {
    if (bound <= 0) {
      throw ArgumentError.value(bound, 'bound', 'must be positive');
    }
    return nextRaw() % bound;
  }
}
