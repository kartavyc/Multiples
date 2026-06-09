/// Deterministic SplitMix64 pseudo-random number generator with an explicit
/// cursor.
///
/// The whole game is deterministic and replayable: the same `seed` plus the
/// same `cursor` reproduces the exact output stream. This relies on 64-bit
/// integer math. Dart's `int` is 64-bit on native targets and wraps on
/// overflow, which is exactly what the canonical SplitMix64 algorithm expects.
/// The web is NOT a target (web ints are doubles and would break this).
///
/// Algorithm reference (canonical SplitMix64). Each draw does:
/// ```
/// state = state + 0x9E3779B97F4A7C15;   // wrapping add
/// int z = state;
/// z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
/// z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
/// z = z ^ (z >>> 31);
/// return z;
/// ```
class SplitMix64Rng {
  /// The golden-gamma increment added to the internal state on every draw.
  static const int _gamma = 0x9E3779B97F4A7C15;
  static const int _mix1 = 0xBF58476D1CE4E5B9;
  static const int _mix2 = 0x94D049BB133111EB;

  int _state;
  int _cursor;

  /// Creates an RNG from [seed]. If [cursor] is given (the number of draws
  /// already consumed), the stream is fast-forwarded so the next draw matches
  /// what you'd get by drawing [cursor] times from a fresh RNG with the same
  /// seed.
  ///
  /// The state after `n` draws is simply `seed + n * gamma` (the gamma is added
  /// before each output is computed), so we can jump directly to any cursor
  /// position without stepping. Multiplication wraps mod 2^64, matching the
  /// repeated wrapping adds.
  SplitMix64Rng(int seed, {int cursor = 0})
      : _state = seed + cursor * _gamma,
        _cursor = cursor;

  /// Number of draws consumed so far.
  int get cursor => _cursor;

  /// Returns the next 64-bit SplitMix64 output and advances the cursor by 1.
  ///
  /// The returned value can be negative: it is the full signed 64-bit result.
  int nextRaw() {
    _state += _gamma; // wrapping add on overflow (native int)
    var z = _state;
    z = (z ^ (z >>> 30)) * _mix1;
    z = (z ^ (z >>> 27)) * _mix2;
    z = z ^ (z >>> 31);
    _cursor++;
    return z;
  }

  /// Returns a value in `[0, bound)` and advances the cursor by 1.
  ///
  /// [bound] must be positive. In Dart, `x % bound` with a positive `bound`
  /// always yields a non-negative result even when `x` is negative, so the
  /// output is guaranteed non-negative. Note: this uses plain modulo, which
  /// carries a small modulo bias when `bound` does not evenly divide 2^64.
  /// That bias is negligible and acceptable for game use.
  int nextInt(int bound) {
    if (bound <= 0) {
      throw ArgumentError.value(bound, 'bound', 'must be positive');
    }
    return nextRaw() % bound;
  }
}
