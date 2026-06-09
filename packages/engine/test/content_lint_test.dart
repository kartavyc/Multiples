// Content lints (doc 03 §5.1; doc 02 §1 content guarantees; doc 04 §3).
// These are tests over the SHIPPED content, not the loader: they keep the
// locked design bans true as cards.json grows.
//
//   1. The §Q2 MEMO ban (GDD §8 Q2; doc 03 §5.1): no CONSUMABLE writes a
//      positive `multiple` delta.
//
//      DOC RECONCILIATION (recorded as an errata line in doc 03 §5.1):
//      doc 03 §5.1 said the lint covers "no card/consumable", but doc 04
//      §1's locked card table legally gives raise/partner cards positive
//      multiple deltas (FIN_SEED_RAISE +1000, PRT_GROWTH_HACKER +500), and
//      the GDD §8 Q2 ban targets the banned consumable ("MEMO", a permanent
//      sector-multiple buff PLAY). Events are exempt too: they are
//      resolver-side market weather (EVT_SECTOR_BUBBLE's +4200 is the
//      market, exogenous by design — doc 03 §5.1's own drift argument).
//      Resolution: the lint bans positive multiple deltas on CONSUMABLES
//      only; raise/partner growth deltas are legal per doc 04 §1.
//
//   2. Venture/addon face multiples sit inside their sector band (doc 02 §1
//      content guarantee). The strict band is sectorBase ±1σ, but volatility
//      makes that fuzzy at authoring time, so the lint uses a GENEROUS sanity
//      band — face multiple > 0 and <= 2x sectorBase — to catch unit mistakes
//      (e.g. authoring 14 instead of 14000) without false-positives on tuning.
//      Negative multiple deltas on add-ons are conglomerate DRAG, not face
//      multiples, and are exempt (doc 04 §4: the engine recomputes real drag
//      against the live platform multiple at merge).
//
//   3. The v1 vertical-slice subset is exactly the 19 cards doc 04 §3 lists
//      (`inVerticalSlice` in the JSON is the machine-readable source of
//      truth; this lint keeps it honest against the doc).
//
//   4. Directionality signs where doc 04 §0 LOCKS them ("directionality is
//      real, even where magnitudes are gamified"):
//      - leverage: a positive `cost.debt` face must land as `deltas.netDebt`
//        >= face (the face debt at minimum becomes net debt; a premium like
//        the bridge loan's 1.15x may book more), and a FINANCING instrument
//        with face debt must pay `+cash` now;
//      - dilution: a positive `cost.dilution` face never pairs with `+own`;
//        a CONSUMABLE's dilution is authored literally (`own == -face`,
//        doc 04 §1 PLY_DOWN_ROUND), while a FINANCING raise must NOT author
//        an `own` delta at all (doc 04 §0: the ownership cut is a SEPARATE
//        engine-computed post-money recompute, doc 02 §3.2 F5);
//      - purchases: venture/addon/partner `deltas.cash == -cost.cash`
//        (doc 04 §0: "for most cards cost.cash mirrors the negative
//        deltas.cash");
//      - ventures start at 100%: `deltas.own == 10000` (doc 04 §1).
//
//      NOT lintable without false positives (documented, deliberately
//      unchecked): consumable cost.cash vs deltas.cash (PLY_BRIDGE_LOAN's
//      fee nets against proceeds; PLY_SECONDARY_SALE's proceeds are
//      resolver-computed at the live mark, doc 04 §4) and financing/event
//      cost relationships (annotated per-card in doc 04 §1). Magnitudes are
//      tuning territory (doc 04 §4) — only signs/structure are linted.
//
// Each lint's predicate is a named function so a planted-violation test can
// prove the lint BITES (a guard that cannot fail guards nothing).
//
// dart:io is TEST-ONLY (reading assets); cwd is the package root.

import 'dart:io';

import 'package:engine/content.dart';
import 'package:engine/model.dart';
import 'package:test/test.dart';

String readAsset(String name) => File('assets/$name').readAsStringSync();

// ---------------------------------------------------------------------------
// Lint predicates (offender-listing functions, shared by real + planted runs)
// ---------------------------------------------------------------------------

/// Lint 1: the banned MEMO shape — a CONSUMABLE buying `+multiple`.
List<String> memoBanOffenders(Iterable<Card> cards) => [
      for (final c in cards)
        if (c.type == CardType.consumable && (c.deltas['multiple'] ?? 0) > 0)
          c.id,
    ];

/// Lint 4a: leverage signs (doc 04 §0 "Leverage adds +cash AND +netDebt").
List<String> leverageSignOffenders(Iterable<Card> cards) {
  final out = <String>[];
  for (final c in cards) {
    if (c.cost.debtCents <= 0) continue;
    final netDebt = c.deltas['netDebt'] ?? 0;
    if (netDebt < c.cost.debtCents) {
      out.add('${c.id}: deltas.netDebt $netDebt < face cost.debt '
          '${c.cost.debtCents} (face debt must land as net debt)');
    }
    if (c.type == CardType.financing && (c.deltas['cash'] ?? 0) <= 0) {
      out.add('${c.id}: financing with face debt must pay +cash now');
    }
  }
  return out;
}

/// Lint 4b: dilution signs (doc 04 §0 "Dilution is always −own"; the raise
/// ownership cut is engine-computed, never authored).
List<String> dilutionSignOffenders(Iterable<Card> cards) {
  final out = <String>[];
  for (final c in cards) {
    if (c.cost.dilutionBp <= 0) continue;
    final own = c.deltas['own'];
    if (own != null && own > 0) {
      out.add('${c.id}: +own delta on a card with a dilution face');
    }
    if (c.type == CardType.financing && own != null) {
      out.add('${c.id}: financing raise authors an own delta; the post-money '
          'recompute is the engine\'s job (doc 04 §0/§4, doc 02 §3.2)');
    }
    if (c.type == CardType.consumable && own != -c.cost.dilutionBp) {
      out.add('${c.id}: consumable dilution must be authored literally '
          '(own ${own ?? 'missing'} != -${c.cost.dilutionBp})');
    }
  }
  return out;
}

/// Lint 4c: purchase mirror for venture/addon/partner (doc 04 §0).
List<String> costMirrorOffenders(Iterable<Card> cards) {
  const mirrored = {CardType.venture, CardType.addon, CardType.partner};
  return [
    for (final c in cards)
      if (mirrored.contains(c.type) &&
          (c.deltas['cash'] ?? 0) != -c.cost.cashCents)
        '${c.id}: deltas.cash ${c.deltas['cash'] ?? 0} != '
            '-cost.cash ${c.cost.cashCents}',
  ];
}

/// Lint 4d: every venture starts at 100% ownership (doc 04 §1).
List<String> ventureOwnOffenders(Iterable<Card> cards) => [
      for (final c in cards)
        if (c.type == CardType.venture && c.deltas['own'] != 10000)
          '${c.id}: venture own delta ${c.deltas['own']} != 10000',
    ];

/// A minimal in-memory card for planted-violation tests.
Card fixtureCard({
  required String id,
  required CardType type,
  Sector? sector,
  CardCost cost = const CardCost(cashCents: 0, debtCents: 0, dilutionBp: 0),
  Map<String, int> deltas = const {},
}) =>
    Card(
      id: id,
      name: 'Fixture',
      type: type,
      sector: sector,
      rarity: Rarity.common,
      tierGate: 1,
      cost: cost,
      deltas: deltas,
      lesson: 'fixture',
      flavor: 'fixture',
      inVerticalSlice: false,
    );

/// Doc 04 §3's locked 19-card v1 vertical-slice subset.
const Set<String> kVerticalSlice = {
  // Ventures (4): one starter per sector.
  'VEN_SW_GARAGE', 'VEN_SVC_AGENCY', 'VEN_RET_KIOSK', 'VEN_IND_WORKSHOP',
  // Add-ons (3): two same-sector (synergy + revaluation), one cross (drag).
  'ADD_SW_PLUGIN', 'ADD_SW_MICRO', 'ADD_SVC_TEAM',
  // Partner (1).
  'PRT_SALES_LEAD',
  // Financing (2): dilution + leverage.
  'FIN_SEED_RAISE', 'FIN_TERM_LOAN',
  // Events (3).
  'EVT_SECTOR_BUBBLE', 'EVT_CREDIT_CRUNCH', 'EVT_KEY_CLIENT_LOSS',
  // PLAYS (6).
  'PLY_BRIDGE_LOAN', 'PLY_SECONDARY_SALE', 'PLY_DOWN_ROUND',
  'PLY_DIVIDEND_RECAP', 'PLY_HOT_WINDOW', 'PLY_MARKET_READ',
};

void main() {
  late ContentDb db;
  late EconomyConfig eco;
  setUpAll(() {
    db = loadCards(readAsset('cards.json'));
    eco = loadEconomy(readAsset('economy-model.json'));
  });

  group('lint 1: the §Q2 MEMO ban (consumables never buy multiple)', () {
    test('no consumable card has a positive multiple delta', () {
      final offenders = memoBanOffenders(db.cards);
      expect(offenders, isEmpty,
          reason: 'GDD §8 Q2 bans the permanent sector-multiple buff '
              '("MEMO"): multiple expansion is exogenous market weather the '
              'player reads and rides, never a consumable purchase. '
              'Offending PLAYS: $offenders');
    });

    test('the ban is scoped per the doc reconciliation (not vacuous)', () {
      // The legal positive-multiple cards the reconciliation exempts really
      // exist; if they vanish, revisit the lint scope note above.
      expect(db.byId('FIN_SEED_RAISE').deltas['multiple'], 1000);
      expect(db.byId('PRT_GROWTH_HACKER').deltas['multiple'], 500);
      expect(db.byId('EVT_SECTOR_BUBBLE').deltas['multiple'], 4200);
    });

    test('PLANTED VIOLATION: a MEMO-shaped consumable IS caught', () {
      final memo = fixtureCard(
          id: 'PLY_MEMO_PLANTED',
          type: CardType.consumable,
          deltas: const {'multiple': 500});
      expect(memoBanOffenders([...db.cards, memo]), ['PLY_MEMO_PLANTED'],
          reason: 'the ban must flag exactly the planted card — if this '
              'fails the lint is decorative');
      // And the exemptions stay exempt: the same +multiple on a partner or
      // event is legal, so the predicate must NOT flag it.
      final partner = fixtureCard(
          id: 'PRT_PLANTED',
          type: CardType.partner,
          deltas: const {'multiple': 500});
      expect(memoBanOffenders([partner]), isEmpty);
    });
  });

  group('lint 2: venture/addon face multiples within sector band sanity', () {
    test('every venture face multiple is > 0 and <= 2x its sector base', () {
      for (final card in db.cards.where((c) => c.type == CardType.venture)) {
        final face = card.deltas['multiple'];
        expect(face, isNotNull,
            reason: 'Venture ${card.id} must seed a face multiple');
        expect(card.sector, isNotNull,
            reason: 'Venture ${card.id} must belong to a sector');
        final base = eco.sectors
            .singleWhere((s) => s.sector == card.sector)
            .baseMultipleMilli;
        expect(face, greaterThan(0),
            reason: 'Venture ${card.id} face multiple must be positive');
        expect(face, lessThanOrEqualTo(2 * base),
            reason: 'Venture ${card.id} face multiple $face is outside the '
                'generous sanity band (0, 2x sector base $base] — likely a '
                'fixed-point unit mistake');
      }
    });

    test('addon positive multiple deltas (if any) honor the same band; '
        'negative deltas are drag and exempt', () {
      for (final card in db.cards.where((c) => c.type == CardType.addon)) {
        final delta = card.deltas['multiple'] ?? 0;
        if (delta <= 0) continue; // conglomerate drag, doc 04 §4 — exempt
        expect(card.sector, isNotNull,
            reason: 'Add-on ${card.id} with a face multiple needs a sector');
        final base = eco.sectors
            .singleWhere((s) => s.sector == card.sector)
            .baseMultipleMilli;
        expect(delta, lessThanOrEqualTo(2 * base),
            reason: 'Add-on ${card.id} face multiple $delta is outside the '
                'sanity band (0, 2x sector base $base]');
      }
    });
  });

  group('lint 3: the vertical-slice subset is exactly doc 04 §3', () {
    test('inVerticalSlice flags match the locked 19-card list', () {
      final flagged = db.cards
          .where((c) => c.inVerticalSlice)
          .map((c) => c.id)
          .toSet();
      expect(flagged, kVerticalSlice,
          reason: 'data/cards.json inVerticalSlice flags drifted from '
              'doc 04 §3 (19 locked cards)');
      expect(flagged, hasLength(19));
    });
  });

  group('lint 4: doc 04 §0 directionality signs over the shipped content',
      () {
    test('4a leverage: face debt lands as +netDebt; financing debt pays '
        '+cash', () {
      expect(leverageSignOffenders(db.cards), isEmpty);
    });

    test('4a PLANTED: missing netDebt and debt-without-cash are caught', () {
      final silentDebt = fixtureCard(
          id: 'FIN_PLANTED_NO_NETDEBT',
          type: CardType.financing,
          cost: const CardCost(
              cashCents: 0, debtCents: 1000000, dilutionBp: 0),
          deltas: const {'cash': 1000000}); // forgot the netDebt side
      final noCash = fixtureCard(
          id: 'FIN_PLANTED_NO_CASH',
          type: CardType.financing,
          cost: const CardCost(
              cashCents: 0, debtCents: 1000000, dilutionBp: 0),
          deltas: const {'netDebt': 1000000}); // debt with no proceeds
      final offenders = leverageSignOffenders([silentDebt, noCash]);
      expect(offenders.join('\n'), contains('FIN_PLANTED_NO_NETDEBT'));
      expect(offenders.join('\n'), contains('FIN_PLANTED_NO_CASH'));
      // The legal premium pattern (bridge loan: cost.debt 0, netDebt
      // authored directly) stays exempt.
      expect(leverageSignOffenders([db.byId('PLY_BRIDGE_LOAN')]), isEmpty);
    });

    test('4b dilution: never +own with a dilution face; consumables author '
        'own == -face; financing raises author NO own delta', () {
      expect(dilutionSignOffenders(db.cards), isEmpty);
    });

    test('4b PLANTED: +own with dilution, financing-authored own, and a '
        'mismatched consumable cut are all caught', () {
      final plusOwn = fixtureCard(
          id: 'PLY_PLANTED_PLUS_OWN',
          type: CardType.consumable,
          cost: const CardCost(cashCents: 0, debtCents: 0, dilutionBp: 1000),
          deltas: const {'own': 1000});
      final finOwn = fixtureCard(
          id: 'FIN_PLANTED_AUTHORED_OWN',
          type: CardType.financing,
          cost: const CardCost(cashCents: 0, debtCents: 0, dilutionBp: 1500),
          deltas: const {'cash': 3000000, 'own': -1500});
      final mismatch = fixtureCard(
          id: 'PLY_PLANTED_MISMATCH',
          type: CardType.consumable,
          cost: const CardCost(cashCents: 0, debtCents: 0, dilutionBp: 4000),
          deltas: const {'cash': 2500000, 'own': -400}); // unit slip x10
      final offenders =
          dilutionSignOffenders([plusOwn, finOwn, mismatch]).join('\n');
      expect(offenders, contains('PLY_PLANTED_PLUS_OWN'));
      expect(offenders, contains('FIN_PLANTED_AUTHORED_OWN'));
      expect(offenders, contains('PLY_PLANTED_MISMATCH'));
    });

    test('4c purchases: venture/addon/partner deltas.cash mirrors '
        '-cost.cash', () {
      expect(costMirrorOffenders(db.cards), isEmpty);
    });

    test('4c PLANTED: a sign-flipped purchase is caught; exempt types pass',
        () {
      final flipped = fixtureCard(
          id: 'VEN_PLANTED_FLIP',
          type: CardType.venture,
          sector: Sector.software,
          cost: const CardCost(
              cashCents: 1200000, debtCents: 0, dilutionBp: 0),
          deltas: const {'cash': 1200000, 'ebitda': 400000, // + not -
            'multiple': 14000, 'own': 10000});
      expect(costMirrorOffenders([flipped]).join('\n'),
          contains('VEN_PLANTED_FLIP'));
      // Consumables are exempt by design (resolver-computed proceeds).
      expect(costMirrorOffenders([db.byId('PLY_BRIDGE_LOAN')]), isEmpty);
    });

    test('4d every venture starts at 100% own (10000 bp)', () {
      expect(ventureOwnOffenders(db.cards), isEmpty);
    });

    test('4d PLANTED: a venture missing its own delta is caught', () {
      final noOwn = fixtureCard(
          id: 'VEN_PLANTED_NO_OWN',
          type: CardType.venture,
          sector: Sector.retail,
          cost: const CardCost(
              cashCents: 700000, debtCents: 0, dilutionBp: 0),
          deltas: const {'cash': -700000, 'ebitda': 500000,
            'multiple': 3000});
      expect(ventureOwnOffenders([noOwn]).join('\n'),
          contains('VEN_PLANTED_NO_OWN'));
    });
  });
}
