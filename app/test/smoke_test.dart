// ASSET STALENESS PIN — app/assets/data/*.json must stay byte-identical
// to /data/*.json (the source of truth), same pattern as the engine's own
// assets/ pin. A drifted copy fails here, loudly.
//
// (The Task-3.0 smoke-screen widget tests that used to live here were
// retired with the smoke screen itself; the run screen's widget tests are
// test/run_screen_test.dart.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('asset staleness pin (assets/data == /data, byte-identical)', () {
    for (final name in ['cards.json', 'economy-model.json']) {
      test('$name copy matches the source of truth', () {
        final copy = File('assets/data/$name').readAsBytesSync();
        final source = File('../data/$name').readAsBytesSync();
        expect(copy, equals(source),
            reason: 'app/assets/data/$name has drifted from /data/$name — '
                're-copy it (copy /b); /data is the source of truth '
                '(assets/data/README.md)');
      });
    }
  });
}
