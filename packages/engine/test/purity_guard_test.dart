// The two static purity guards from doc 03 §4 (float/clock/RNG ban + the
// no-Flutter package boundary), plus doc 03 §3's determinism rules:
//
//   1. Source scan over EVERY lib/*.dart file: no `double` type usage, no
//      `.toDouble(`, no `dart:math`, no `DateTime`, no `Random(` — anywhere
//      in CODE. The word `double` is allowed in comments only (the lib
//      headers say "no double anywhere" — that must keep passing).
//   2. pubspec.yaml declares no flutter dependency: the engine is a pure,
//      headless library that runs under plain `dart test`.
//
// Related-but-separate scan: invariant_test.dart §(e) checks lib/model.dart
// for score/netWorth/points-shaped writable state (the §7 name rule). That
// guard lives there because it IS the §7 invariant; these are the
// determinism/purity guards. Consolidated here, not duplicated.
//
// dart:io is TEST-ONLY (reading the package's own source); the engine lib
// stays pure. The test runner's cwd is the package root (tool/wintest.bat
// cds there), so lib/ and pubspec.yaml resolve directly.

import 'dart:io';

import 'package:test/test.dart';

/// Strips `/* ... */` block comments and `//`-to-end-of-line comments
/// (which covers `///` doc comments) so the bans only see CODE.
String stripComments(String source) {
  final noBlocks =
      source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlocks
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx < 0 ? line : line.substring(0, idx);
      })
      .join('\n');
}

/// The banned constructs (doc 03 §3 determinism rules + §4 guard #1), as
/// label -> pattern over comment-stripped source.
final Map<String, RegExp> kBans = {
  'double type usage': RegExp(r'\bdouble\b'),
  '.toDouble( call': RegExp(r'\.toDouble\('),
  'dart:math import/use': RegExp(r'dart:math'),
  'DateTime (wall clock)': RegExp(r'\bDateTime\b'),
  'Random( (ambient RNG)': RegExp(r'\bRandom\s*\('),
};

/// Every banned construct found in [source] (after comment stripping),
/// as `label @ line N` strings for failure messages.
List<String> violationsIn(String source) {
  final code = stripComments(source);
  final lines = code.split('\n');
  final found = <String>[];
  for (final entry in kBans.entries) {
    for (var i = 0; i < lines.length; i++) {
      if (entry.value.hasMatch(lines[i])) {
        found.add('${entry.key} @ line ${i + 1}: "${lines[i].trim()}"');
      }
    }
  }
  return found;
}

void main() {
  group('guard #1: engine source is float-free, clock-free, ambient-RNG-free',
      () {
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    test('the scan is not vacuous: every engine library is covered', () {
      final names =
          libFiles.map((f) => f.uri.pathSegments.last).toSet();
      expect(
          names,
          containsAll(
              {'actions.dart', 'apply.dart', 'model.dart', 'money.dart',
                'operate.dart', 'resolver.dart', 'rng.dart', 'round.dart',
                'content.dart', 'content.g.dart', 'dealflow.dart',
                'init.dart', 'meta.dart', 'serialize.dart', 'migrate.dart',
                'describe.dart'}),
          reason: 'expected to scan every engine library INCLUDING the '
              'json_serializable-generated content.g.dart (codegen output '
              'must obey the same float/clock/RNG bans) and the deal-flow '
              'layer; a rename here must keep the scan exhaustive');
    });

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      test('${file.path} contains no banned construct', () {
        final found = violationsIn(file.readAsStringSync());
        expect(found, isEmpty,
            reason: '${file.path} violates the doc 03 §3 determinism rules '
                '(a float/clock/ambient-RNG anywhere below the UI boundary '
                'breaks byte-identical replay): $found');
      });
    }
  });

  group('guard #2: the engine package has no flutter dependency (doc 03 §4)',
      () {
    test('pubspec.yaml never names flutter', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'^\s*flutter\s*:', multiLine: true).hasMatch(pubspec),
          isFalse,
          reason: 'packages/engine must stay pure Dart — the app depends '
              'on the engine, never the reverse');
      expect(pubspec.contains('sdk: flutter'), isFalse);
    });
  });

  group('the detector itself bites (planted-violation self-test)', () {
    test('flags each banned construct in code', () {
      expect(violationsIn('double x = 0;'), isNotEmpty);
      expect(violationsIn('final y = x.toDouble();'), isNotEmpty);
      expect(violationsIn("import 'dart:math';"), isNotEmpty);
      expect(violationsIn('final t = DateTime.now();'), isNotEmpty);
      expect(violationsIn('final r = Random(7);'), isNotEmpty);
    });

    test('allows the same words in comments, and clean code', () {
      expect(violationsIn('// no double anywhere in this package'), isEmpty);
      expect(violationsIn('/// Never call dart:math Random() here.'), isEmpty);
      expect(violationsIn('/* DateTime is banned */ final int x = 1;'),
          isEmpty);
      expect(violationsIn('final int cents = ebitda * milli ~/ 1000;'),
          isEmpty);
    });

    test('does not false-positive on identifiers containing the words', () {
      // `SplitMix64Rng(...)` is not `Random(`; `doubled` is not `double`.
      expect(violationsIn('final rng = SplitMix64Rng(42);'), isEmpty);
      expect(violationsIn('final int doubled = x * 2;'), isEmpty);
    });
  });
}
