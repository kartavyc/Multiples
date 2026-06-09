import 'package:engine/rng.dart';
import 'package:test/test.dart';

void main() {
  group('SplitMix64Rng', () {
    test('determinism: same seed yields identical first-10 nextRaw sequence', () {
      final a = SplitMix64Rng(123456789);
      final b = SplitMix64Rng(123456789);
      for (var i = 0; i < 10; i++) {
        expect(a.nextRaw(), equals(b.nextRaw()), reason: 'draw $i diverged');
      }
    });

    test('cursor: nextRaw increments cursor by 1', () {
      final rng = SplitMix64Rng(7);
      expect(rng.cursor, equals(0));
      rng.nextRaw();
      expect(rng.cursor, equals(1));
      rng.nextRaw();
      expect(rng.cursor, equals(2));
    });

    test('cursor replay: constructing with cursor: N resumes the stream', () {
      const seed = 0xDEADBEEF;
      const n = 17;

      // Draw N times from a fresh RNG, then capture the continuation.
      final a = SplitMix64Rng(seed);
      for (var i = 0; i < n; i++) {
        a.nextRaw();
      }
      expect(a.cursor, equals(n));
      final continuation = [for (var i = 0; i < 5; i++) a.nextRaw()];

      // A fresh RNG fast-forwarded to cursor: N must match that continuation.
      final b = SplitMix64Rng(seed, cursor: n);
      expect(b.cursor, equals(n));
      for (var i = 0; i < 5; i++) {
        expect(b.nextRaw(), equals(continuation[i]),
            reason: 'replay diverged at continuation index $i');
      }
    });

    test('nextInt: always in [0, bound) and never negative', () {
      final rng = SplitMix64Rng(2024);
      for (final bound in [1, 2, 6, 7, 52, 1000, 0x7FFFFFFF]) {
        for (var i = 0; i < 1000; i++) {
          final v = rng.nextInt(bound);
          expect(v, greaterThanOrEqualTo(0),
              reason: 'negative value for bound $bound');
          expect(v, lessThan(bound), reason: 'value >= bound for bound $bound');
        }
      }
    });

    test('nextInt increments cursor by 1', () {
      final rng = SplitMix64Rng(99);
      rng.nextInt(10);
      expect(rng.cursor, equals(1));
      rng.nextInt(10);
      expect(rng.cursor, equals(2));
    });

    test('golden vector: first 5 nextRaw for seed 42', () {
      // Generated from THIS implementation of canonical SplitMix64 using the
      // constants 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB.
      // Pinned to lock the algorithm; any change to the algorithm breaks this.
      final golden = <int>[
        -4767286540954276203,
        2949826092126892291,
        5139283748462763858,
        6349198060258255764,
        701532786141963250,
      ];
      final rng = SplitMix64Rng(42);
      for (var i = 0; i < golden.length; i++) {
        expect(rng.nextRaw(), equals(golden[i]),
            reason: 'golden mismatch at index $i');
      }
    });
  });
}
