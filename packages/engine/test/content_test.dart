// Typed content loading (plan task 2.1; doc 03 §5 pipeline; doc 04 §0 units).
//
// Covers, one behavior per test group:
//   - the assets/ build copies are byte-identical with /data (source of truth)
//   - cards.json parses into 33 typed cards with the doc 04 §2 type counts
//   - economy-model.json parses into 4 sectors (correct base multiples +
//     volatility as integer permille), tier bars in exact cents, deadlines,
//     and startCash
//   - VALIDATION fails loudly (FormatException naming the offending card id)
//     on: unknown delta keys, unknown top-level card keys, unknown
//     sector/type/rarity spellings, non-integer money values, and negative
//     cost face values (the Phase-1 audit requirement: the engine charges
//     exactly what it is handed, so the content layer must guarantee
//     non-negative face magnitudes per doc 04 §0 sign conventions)
//
// loadCards/loadEconomy take raw JSON STRINGS — the engine lib stays pure
// (no dart:io in lib; doc 03 §4). dart:io here is TEST-ONLY file reading;
// the test runner's cwd is the package root (tool/wintest.bat cds there).
//
// All money is integer cents; no `double` anywhere in this test.

import 'dart:convert';
import 'dart:io';

import 'package:engine/content.dart';
import 'package:engine/model.dart';
import 'package:test/test.dart';

String readAsset(String name) => File('assets/$name').readAsStringSync();

/// A minimal well-formed single-card JSON array, with string replacement
/// hooks for the malformed-fixture tests.
const String kGoodCard = '''
[
  {
    "id": "FIX_GOOD",
    "name": "Fixture Card",
    "type": "venture",
    "sector": "SOFTWARE",
    "rarity": "common",
    "tierGate": 1,
    "cost": { "cash": 1200000, "debt": 0, "dilution": 0 },
    "deltas": { "cash": -1200000, "ebitda": 400000, "multiple": 14000, "own": 10000 },
    "lesson": "fixture lesson",
    "flavor": "fixture flavor",
    "inVerticalSlice": true
  }
]
''';

/// Asserts [json] fails to load with a [FormatException] whose message names
/// the offending card id (so a 33-card file pinpoints the bad row).
void expectCardLoadFailure(String json, String cardId,
    {Pattern? alsoMentions}) {
  expect(
    () => loadCards(json),
    throwsA(isA<FormatException>().having(
        (e) => e.message, 'message', allOf([
      contains(cardId),
      if (alsoMentions != null) contains(alsoMentions),
    ]))),
  );
}

void main() {
  group('assets/ build copies match /data (source of truth)', () {
    for (final name in ['cards.json', 'economy-model.json']) {
      test('$name is byte-identical with data/$name', () {
        final asset = File('assets/$name').readAsBytesSync();
        final source = File('../../data/$name').readAsBytesSync();
        expect(asset, source,
            reason: 'assets/$name is a stale build copy; re-copy from /data '
                '(see assets/README.md)');
      });
    }
  });

  group('loadCards on the real cards.json', () {
    late ContentDb db;
    setUpAll(() => db = loadCards(readAsset('cards.json')));

    test('parses all 33 cards', () {
      expect(db.cards, hasLength(33));
    });

    test('type counts match doc 04 §2 (5/5/3/5/5/10)', () {
      int count(CardType t) =>
          db.cards.where((c) => c.type == t).length;
      expect(count(CardType.venture), 5);
      expect(count(CardType.addon), 5);
      expect(count(CardType.partner), 3);
      expect(count(CardType.financing), 5);
      expect(count(CardType.event), 5);
      expect(count(CardType.consumable), 10);
    });

    test('byId resolves and carries typed fields (spot checks)', () {
      final garage = db.byId('VEN_SW_GARAGE');
      expect(garage.name, 'Garage SaaS');
      expect(garage.type, CardType.venture);
      expect(garage.sector, Sector.software);
      expect(garage.rarity, Rarity.common);
      expect(garage.tierGate, 1);
      expect(garage.inVerticalSlice, isTrue);
      expect(garage.cost.cashCents, 1200000);
      expect(garage.cost.debtCents, 0);
      expect(garage.cost.dilutionBp, 0);
      expect(garage.deltas, {
        'cash': -1200000,
        'ebitda': 400000,
        'multiple': 14000,
        'own': 10000,
      });
      expect(garage.lesson, isNotEmpty);
      expect(garage.flavor, isNotEmpty);

      final loan = db.byId('FIN_TERM_LOAN');
      expect(loan.type, CardType.financing);
      expect(loan.sector, isNull, reason: 'sector-agnostic cards parse null');
      expect(loan.cost.debtCents, 1500000);
      expect(loan.deltas, {'cash': 1500000, 'netDebt': 1500000});

      final recap = db.byId('PLY_DIVIDEND_RECAP');
      expect(recap.type, CardType.consumable);
      expect(recap.rarity, Rarity.rare);
      expect(recap.tierGate, 2);
    });

    test('byId throws on an unknown id', () {
      expect(() => db.byId('NOPE'), throwsA(isA<ArgumentError>()));
    });

    test('raw-integer cross-check: parsed values == data/cards.json literals '
        '(Phase-2 audit pin; VEN_SW_GARAGE is pinned in the spot checks)', () {
      // PLY_BRIDGE_LOAN: the 1.15x repay premium is authored directly as the
      // netDebt delta (economy bridgeLoanRepayMul = 1150 milli).
      final bridge = db.byId('PLY_BRIDGE_LOAN');
      expect(bridge.type, CardType.consumable);
      expect(bridge.tierGate, 1);
      expect(bridge.cost.cashCents, 200000);
      expect(bridge.cost.debtCents, 0);
      expect(bridge.deltas, {'cash': 1000000, 'netDebt': 1150000});
      expect(bridge.deltas['netDebt'], bridge.deltas['cash']! * 1150 ~/ 1000,
          reason: 'the authored netDebt must be cash x the 1.15 repay '
              'multiplier (economy-model.json bridgeLoanRepayMul)');

      // FIN_LBO_LOAN: the T4 LBO lever, face debt landing 1:1 as netDebt.
      final lbo = db.byId('FIN_LBO_LOAN');
      expect(lbo.type, CardType.financing);
      expect(lbo.tierGate, 4);
      expect(lbo.rarity, Rarity.rare);
      expect(lbo.sector, isNull);
      expect(lbo.cost.debtCents, 20000000);
      expect(lbo.deltas, {'cash': 20000000, 'netDebt': 20000000});
    });

    test('verticalSlice getter returns exactly the flagged cards, in file '
        'order (Phase-3 app surface)', () {
      final slice = db.verticalSlice;
      expect(slice, hasLength(19));
      expect(slice.map((c) => c.id),
          db.cards.where((c) => c.inVerticalSlice).map((c) => c.id),
          reason: 'verticalSlice must preserve cards.json file order');
      expect(slice.every((c) => c.inVerticalSlice), isTrue);
      expect(() => slice.add(slice.first), throwsUnsupportedError,
          reason: 'verticalSlice must be unmodifiable like cards');
    });
  });

  group('fixedPointFromJsonNum (decimal-text integer conversion edges)', () {
    // Fraction inputs come from jsonDecode (never a literal in this test —
    // no `double` anywhere in the engine package, tests included). The
    // converter must only ever STRINGIFY the decoded number; all arithmetic
    // is integer. These edges pin that claim.
    Object? n(String json) => jsonDecode(json);

    test('trailing zeros do not matter: 0.3 == 0.30 == 0.300', () {
      expect(fixedPointFromJsonNum(n('0.3'), 1000, 'edge'), 300);
      expect(fixedPointFromJsonNum(n('0.30'), 1000, 'edge'), 300);
      expect(fixedPointFromJsonNum(n('0.300'), 1000, 'edge'), 300);
    });

    test('integers scale directly (3 -> 3000 milli, 1 -> 10000 bp)', () {
      expect(fixedPointFromJsonNum(3, 1000, 'edge'), 3000);
      expect(fixedPointFromJsonNum(1, 10000, 'edge'), 10000);
      expect(fixedPointFromJsonNum(0, 10000, 'edge'), 0);
    });

    test('negative fractions keep their sign exactly', () {
      expect(fixedPointFromJsonNum(n('-0.5'), 10000, 'edge'), -5000);
      expect(fixedPointFromJsonNum(n('-0.08'), 10000, 'edge'), -800);
    });

    test('a JSON decimal authored as x.0 equals the integer (3.0 == 3)', () {
      expect(fixedPointFromJsonNum(n('3.0'), 1000, 'edge'), 3000);
    });

    test('exact at one scale, rejected at a coarser one (0.0005)', () {
      // 0.0005 is exact at bp x10000 (= 5) but NOT at permille x1000.
      expect(fixedPointFromJsonNum(n('0.0005'), 10000, 'edge'), 5);
      expect(
        () => fixedPointFromJsonNum(n('0.0005'), 1000, 'edge'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('not exactly representable'))),
      );
    });

    test('0.125 is exact at both milli and bp (binary-float repr is moot: '
        'only the shortest decimal text is parsed)', () {
      expect(fixedPointFromJsonNum(n('0.125'), 1000, 'edge'), 125);
      expect(fixedPointFromJsonNum(n('0.125'), 10000, 'edge'), 1250);
    });

    test('exponent forms are rejected loudly, never silently converted', () {
      // jsonDecode('1e-7') yields a number whose shortest text is "1e-7";
      // the converter must refuse it rather than guess.
      expect(
        () => fixedPointFromJsonNum(n('1e-7'), 10000, 'edge'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('exponent'))),
      );
      expect(
        () => fixedPointFromJsonNum(n('1e21'), 1000, 'edge'),
        throwsA(isA<FormatException>()),
      );
    });

    test('non-numbers are rejected', () {
      expect(() => fixedPointFromJsonNum('0.3', 1000, 'edge'),
          throwsA(isA<FormatException>()));
      expect(() => fixedPointFromJsonNum(null, 1000, 'edge'),
          throwsA(isA<FormatException>()));
    });
  });

  group('loadEconomy on the real economy-model.json', () {
    late EconomyConfig eco;
    setUpAll(() => eco = loadEconomy(readAsset('economy-model.json')));

    test('startCash is 2000000 cents and seed constants are fixed-point', () {
      expect(eco.constants.startCashCents, 2000000);
      expect(eco.constants.startEbitdaCents, 600000);
      expect(eco.constants.startSector, Sector.software);
      expect(eco.constants.startMultipleMilli, 6000);
      expect(eco.constants.startOwnershipBp, 10000);
      expect(eco.constants.startNetDebtCents, 0);
    });

    test('fractional constants convert to integer fixed-point at parse', () {
      // economy-model.json authors fractions as JSON decimals; the loader
      // converts them ONCE here, so the engine only ever sees integers.
      expect(eco.constants.cashYieldBp, 3500); // 0.35
      expect(eco.constants.organicGrowthDefaultBp, 2000); // 0.20 (R12 tune)
      expect(eco.constants.carrySeedFracBp, 3700); // 0.37 (R12 tune)
      expect(eco.constants.reseedMultMilli, 8000); // already milli
      expect(eco.constants.interestMinBp, 800); // 0.08
      expect(eco.constants.interestMaxBp, 1200); // 0.12 (R12 tune)
      expect(eco.constants.targetLeverageMilli, 3000); // 3.0
      expect(eco.constants.dangerLeverageMilli, 6000); // 6.0
      expect(eco.constants.reinvestStartBp, 5500); // 0.55
      expect(eco.constants.reinvestEndBp, 3500); // 0.35
      expect(eco.constants.synergySameSectorBp, 2000); // 0.20
      expect(eco.constants.congDiscountPerAddonBp, 800); // 0.08
      expect(eco.constants.recapPctBp, 1600); // 0.16 (R12 tune)
      expect(eco.constants.bridgeLoanRepayMulMilli, 1150); // 1.15
    });

    test('4 sectors parse with correct base multiples (milli)', () {
      // R17: the two POST-LAUNCH sectors (CONSUMER, MEDIA) join the block
      // (GDD §8 Q6). They parse + carry economy bands but are reputation-
      // gated out of the base draw pool (meta.dart kPostLaunchSectors).
      expect(eco.sectors, hasLength(6));
      int base(Sector s) =>
          eco.sectors.singleWhere((c) => c.sector == s).baseMultipleMilli;
      expect(base(Sector.software), 14000);
      expect(base(Sector.services), 5000);
      expect(base(Sector.retail), 3000);
      expect(base(Sector.industrial), 8000);
      expect(base(Sector.consumer), 6000, reason: 'brand-y mid-multiple');
      expect(base(Sector.media), 16000, reason: 'SOFTWARE++ high multiple');
    });

    test('sector volatility converts to integer permille', () {
      int vol(Sector s) =>
          eco.sectors.singleWhere((c) => c.sector == s).volatilityPermille;
      expect(vol(Sector.software), 300); // 0.30
      expect(vol(Sector.services), 220); // 0.22
      expect(vol(Sector.retail), 100); // 0.10
      expect(vol(Sector.industrial), 120); // 0.12
      expect(vol(Sector.consumer), 150); // 0.15 (steady brand-y)
      expect(vol(Sector.media), 350); // 0.35 (SOFTWARE++, whips hardest)
    });

    test('tier bars are exact cents with deadlines [9,10,9,10] (T1/T2 '
        'loosened in the R12 tune)', () {
      expect(eco.tierBars, hasLength(4));
      expect(eco.tierBars.map((t) => t.tier), [1, 2, 3, 4]);
      expect(eco.tierBars.map((t) => t.barCents),
          [100000000, 1000000000, 10000000000, 100000000000]);
      expect(eco.tierBars.map((t) => t.deadlineRounds), [9, 10, 9, 10]);
    });
  });

  group('loadCards validation fails loudly with the offending card id', () {
    test('the fixture itself is well-formed (sanity)', () {
      expect(loadCards(kGoodCard).cards, hasLength(1));
    });

    test('unknown delta key (the §7 invariant at the content boundary)', () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_DELTA"')
          .replaceFirst('"ebitda": 400000', '"score": 400000');
      expectCardLoadFailure(bad, 'FIX_BAD_DELTA', alsoMentions: 'score');
    });

    test('unknown top-level card key', () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_KEY"')
          .replaceFirst('"flavor"', '"power": 9000, "flavor"');
      expectCardLoadFailure(bad, 'FIX_BAD_KEY', alsoMentions: 'power');
    });

    test('unknown sector spelling', () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_SECTOR"')
          .replaceFirst('"SOFTWARE"', '"CRYPTO"');
      expectCardLoadFailure(bad, 'FIX_BAD_SECTOR', alsoMentions: 'CRYPTO');
    });

    test('unknown type spelling', () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_TYPE"')
          .replaceFirst('"type": "venture"', '"type": "weapon"');
      expectCardLoadFailure(bad, 'FIX_BAD_TYPE', alsoMentions: 'weapon');
    });

    test('unknown rarity spelling', () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_RARITY"')
          .replaceFirst('"rarity": "common"', '"rarity": "legendary"');
      expectCardLoadFailure(bad, 'FIX_BAD_RARITY', alsoMentions: 'legendary');
    });

    test('non-integer money value in deltas', () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_FLOAT"')
          .replaceFirst('"ebitda": 400000', '"ebitda": 400000.5');
      expectCardLoadFailure(bad, 'FIX_BAD_FLOAT');
    });

    test('non-integer money value in cost', () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_COST_FLOAT"')
          .replaceFirst('"cash": 1200000,', '"cash": 1200000.25,');
      expectCardLoadFailure(bad, 'FIX_BAD_COST_FLOAT');
    });

    test('negative cost face value (Phase-1 audit: signs invert economics)',
        () {
      final bad = kGoodCard
          .replaceFirst('"id": "FIX_GOOD"', '"id": "FIX_BAD_SIGN"')
          .replaceFirst('"cash": 1200000,', '"cash": -1200000,');
      expectCardLoadFailure(bad, 'FIX_BAD_SIGN');
    });

    test('duplicate card ids are rejected', () {
      final twice =
          '[${kGoodCard.trim().substring(1, kGoodCard.trim().length - 1)},'
          '${kGoodCard.trim().substring(1, kGoodCard.trim().length - 1)}]';
      expectCardLoadFailure(twice, 'FIX_GOOD');
    });

    test('the real cards.json passes every validation (no false positives)',
        () {
      expect(() => loadCards(readAsset('cards.json')), returnsNormally);
    });
  });
}
