// CONTENT-COPY SYNC PIN (audit 2026-06-09 M1) — the three hand-synced copies
// of the content JSON MUST stay byte-identical, or silent drift creeps in
// between what the engine tests read, what the engine package bundles, and
// what the app ships.
//
// The content lives in THREE places (decisions log 2026-06-07 explains why:
// the engine purity guard bans a `flutter:` key in its pubspec, and Flutter
// cannot bundle a dependency's assets, so each consumer keeps a build copy):
//   1. /data/                     — the SOURCE OF TRUTH (authoring lives here)
//   2. /packages/engine/assets/   — the engine package's build copy
//   3. /app/assets/data/          — the Flutter app's bundled copy
// for BOTH files: cards.json AND economy-model.json.
//
// Before this round only two of the three pairings were pinned: the app-side
// smoke_test pinned /app/assets/data == /data, and the engine read its own
// /assets copy with no cross-check against /data at all. A drifted engine
// assets copy (or a one-sided edit to any copy) was silent. This test closes
// the gap: it asserts ALL THREE copies of BOTH files are byte-identical, so
// editing one without the others fails the engine suite loudly.
//
// dart:io is TEST-ONLY (reading files); the test cwd is the engine package
// root, so /data and /app are reached by `../../`.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('content-copy sync (all three copies byte-identical — audit M1)', () {
    // Relative to the engine package root (the test cwd):
    //   data source -> repo-root/data, engine copy -> ./assets,
    //   app copy    -> repo-root/app/assets/data.
    const dataDir = '../../data';
    const engineAssetsDir = 'assets';
    const appAssetsDir = '../../app/assets/data';
    const files = ['cards.json', 'economy-model.json'];

    test('every copy of every content file exists', () {
      for (final dir in [dataDir, engineAssetsDir, appAssetsDir]) {
        for (final name in files) {
          expect(File('$dir/$name').existsSync(), isTrue,
              reason: '$dir/$name is missing — a content copy went away');
        }
      }
    });

    for (final name in files) {
      test('$name is byte-identical across /data, engine assets, app assets',
          () {
        final source = File('$dataDir/$name').readAsBytesSync();
        final engineCopy = File('$engineAssetsDir/$name').readAsBytesSync();
        final appCopy = File('$appAssetsDir/$name').readAsBytesSync();

        // Compare on a stable digest-free basis: exact byte sequence. (A
        // length check first gives a clearer failure than a per-byte diff.)
        expect(engineCopy.length, source.length,
            reason: 'packages/engine/assets/$name drifted in SIZE from '
                'data/$name — re-sync the build copy from /data (the '
                'source of truth)');
        expect(_bytesEqual(engineCopy, source), isTrue,
            reason: 'packages/engine/assets/$name has drifted from '
                'data/$name (byte content) — re-sync from /data');

        expect(appCopy.length, source.length,
            reason: 'app/assets/data/$name drifted in SIZE from data/$name '
                '— re-sync the build copy from /data');
        expect(_bytesEqual(appCopy, source), isTrue,
            reason: 'app/assets/data/$name has drifted from data/$name '
                '(byte content) — re-sync from /data');
      });
    }
  });
}

/// True iff [a] and [b] are the same length and every byte matches (the
/// package avoids a `collection` dependency, so this is hand-rolled).
bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
