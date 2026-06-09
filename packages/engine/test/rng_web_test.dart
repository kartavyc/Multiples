// Validates the WEB RNG (rng_web.dart) directly on the VM. The conditional
// export in rng.dart only swaps this in for dart2js/dart2wasm, but the file is
// pure 32-bit Dart so it runs (and is testable) on the VM too. These guard the
// API contract the engine relies on: determinism, cursor-replay, range, and
// one-draw-per-cursor — the same contract rng_test.dart pins for native.
import 'package:engine/rng_web.dart';
import 'package:test/test.dart';

void main() {
  group('web SplitMix64Rng (xorshift128, 2^53-safe)', () {
    test('same seed yields an identical sequence', () {
      final a = SplitMix64Rng(123456789);
      final b = SplitMix64Rng(123456789);
      for (var i = 0; i < 200; i++) {
        expect(a.nextRaw(), b.nextRaw());
      }
    });

    test('cursor replay: constructing with cursor:N resumes the stream', () {
      const n = 37;
      final fresh = SplitMix64Rng(2024);
      for (var i = 0; i < n; i++) {
        fresh.nextRaw();
      }
      final resumed = SplitMix64Rng(2024, cursor: n);
      expect(resumed.cursor, n);
      for (var i = 0; i < 64; i++) {
        expect(resumed.nextRaw(), fresh.nextRaw(),
            reason: 'continuation must match a stepped-forward fresh stream');
      }
    });

    test('nextInt is always in [0, bound) and never negative', () {
      final rng = SplitMix64Rng(99);
      for (var i = 0; i < 20000; i++) {
        final v = rng.nextInt(7);
        expect(v, inInclusiveRange(0, 6));
      }
    });

    test('nextInt advances the cursor by exactly 1 (one draw)', () {
      final rng = SplitMix64Rng(42);
      final c0 = rng.cursor;
      rng.nextInt(10);
      expect(rng.cursor, c0 + 1);
    });

    test('every raw output stays within 32 bits', () {
      final rng = SplitMix64Rng(7);
      for (var i = 0; i < 2000; i++) {
        expect(rng.nextRaw(), inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('near-identical seeds (consecutive clock values) diverge fast', () {
      final a = SplitMix64Rng(1750000000000);
      final b = SplitMix64Rng(1750000000001);
      var differing = 0;
      for (var i = 0; i < 24; i++) {
        if (a.nextRaw() != b.nextRaw()) differing++;
      }
      expect(differing, greaterThan(20),
          reason: 'the 16-step warmup must decorrelate adjacent seeds');
    });

    test('a large (near-2^53) seed is handled without precision loss', () {
      final a = SplitMix64Rng(9007199254740990);
      final b = SplitMix64Rng(9007199254740990);
      expect(a.nextRaw(), b.nextRaw());
      expect(a.nextInt(1000), inInclusiveRange(0, 999));
    });

    test('bound must be positive', () {
      final rng = SplitMix64Rng(1);
      expect(() => rng.nextInt(0), throwsArgumentError);
      expect(() => rng.nextInt(-3), throwsArgumentError);
    });
  });
}
