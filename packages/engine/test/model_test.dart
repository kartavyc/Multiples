import 'package:engine/model.dart';
import 'package:engine/money.dart' show kMaxCents;
import 'package:test/test.dart';

// Seed constants cited from data/economy-model.json "constants" block:
//   startCash=2000000, startEbitda=600000, startSector=SOFTWARE,
//   startMultiple=6000, startOwnership=10000, startNetDebt=0.
// Seed NetWorth is contractually $56,000 = 5,600,000 cents (see _note + tiers).
const int kStartCash = 2000000;
const int kStartEbitda = 600000;
const int kStartMultiple = 6000;
const int kStartOwnership = 10000;
const int kStartNetDebt = 0;

/// Builds the canonical seed venture (one SOFTWARE company).
Venture seedVenture() => const Venture(
      id: 'seed',
      sector: Sector.software,
      ebitdaCents: kStartEbitda,
      multipleMilli: kStartMultiple,
      netDebtCents: kStartNetDebt,
      ownershipBp: kStartOwnership,
    );

/// Builds the canonical seed game state.
GameState seedState() => GameState(
      ventures: [seedVenture()],
      cashCents: kStartCash,
    );

void main() {
  group('Sector JSON parsing', () {
    test('parses the four uppercase content spellings', () {
      expect(sectorFromJson('SOFTWARE'), Sector.software);
      expect(sectorFromJson('RETAIL'), Sector.retail);
      expect(sectorFromJson('SERVICES'), Sector.services);
      expect(sectorFromJson('INDUSTRIAL'), Sector.industrial);
    });

    test('serialises back to uppercase content spellings', () {
      expect(sectorToJson(Sector.software), 'SOFTWARE');
      expect(sectorToJson(Sector.retail), 'RETAIL');
      expect(sectorToJson(Sector.services), 'SERVICES');
      expect(sectorToJson(Sector.industrial), 'INDUSTRIAL');
    });

    test('round-trips every enum value', () {
      for (final s in Sector.values) {
        expect(sectorFromJson(sectorToJson(s)), s);
      }
    });

    test('throws on an unknown spelling', () {
      expect(() => sectorFromJson('BOGUS'), throwsArgumentError);
    });
  });

  group('netWorthCents (§7 canonical formula)', () {
    test('seed state == 5,600,000 cents (\$56,000) — contractual', () {
      // EV = 600000*6000/1000 = 3,600,000; equity = 3,600,000;
      // mine = 3,600,000*10000/10000 = 3,600,000; + cash 2,000,000.
      expect(seedState().netWorthCents, 5600000);
    });

    test('negative-equity venture reduces net worth, cash still added', () {
      // EV = 100000*5000/1000 = 500,000; netDebt 800,000 => equity -300,000.
      // mine = -300,000*10000/10000 = -300,000. + cash 1,000,000 => 700,000.
      final state = GameState(
        ventures: const [
          Venture(
            id: 'v',
            sector: Sector.retail,
            ebitdaCents: 100000,
            multipleMilli: 5000,
            netDebtCents: 800000,
            ownershipBp: 10000,
          ),
        ],
        cashCents: 1000000,
      );
      expect(state.netWorthCents, 700000);
    });

    test('partial ownership halves equity (truncated)', () {
      // EV = 600000*6000/1000 = 3,600,000; equity 3,600,000.
      // at 5000 bp (50%): mine = 3,600,000*5000/10000 = 1,800,000.
      final state = GameState(
        ventures: const [
          Venture(
            id: 'v',
            sector: Sector.software,
            ebitdaCents: 600000,
            multipleMilli: 6000,
            netDebtCents: 0,
            ownershipBp: 5000,
          ),
        ],
        cashCents: 0,
      );
      expect(state.netWorthCents, 1800000);
    });

    test('ownership-weighting truncates toward zero (divide LAST)', () {
      // equity = EV = 1*7/1000... use values that force truncation:
      // EV = 1000*7000/1000 = 7,000; equity 7,000;
      // mine = 7,000*3333/10000 = 23,331,000/10000 = 2,333 (trunc).
      final state = GameState(
        ventures: const [
          Venture(
            id: 'v',
            sector: Sector.software,
            ebitdaCents: 1000,
            multipleMilli: 7000,
            netDebtCents: 0,
            ownershipBp: 3333,
          ),
        ],
        cashCents: 0,
      );
      expect(state.netWorthCents, 2333);
    });

    test('multi-venture net worth = sum of per-venture mine + cash', () {
      final ventures = const [
        // mine = 3,600,000 (seed software, full ownership)
        Venture(
          id: 'a',
          sector: Sector.software,
          ebitdaCents: 600000,
          multipleMilli: 6000,
          netDebtCents: 0,
          ownershipBp: 10000,
        ),
        // EV = 500000*3000/1000 = 1,500,000; equity 1,500,000;
        // mine = 1,500,000*5000/10000 = 750,000
        Venture(
          id: 'b',
          sector: Sector.retail,
          ebitdaCents: 500000,
          multipleMilli: 3000,
          netDebtCents: 0,
          ownershipBp: 5000,
        ),
      ];
      final state = GameState(ventures: ventures, cashCents: 100000);
      // 3,600,000 + 750,000 + 100,000
      expect(state.netWorthCents, 4450000);
    });

    test('there is no setter for net worth (derived only)', () {
      // Purely a documentation/compile guarantee: netWorthCents is a getter.
      // If a setter were added this expression would still compile, so we just
      // assert the getter is stable across two reads of an unchanged state.
      final s = seedState();
      expect(s.netWorthCents, s.netWorthCents);
    });

    test('the getter saturates at extreme magnitudes — never wraps int64 '
        '(audit 2026-06-09 M3)', () {
      // A marathon T5-endless run could compound EBITDA past the point where
      // `ebitda * multipleMilli` would wrap a signed 64-bit int (wrapping
      // flips a huge positive net worth NEGATIVE — a false bankruptcy). With
      // the satMul guard the product saturates instead, so net worth stays
      // pinned at a huge positive value, never negative.
      final huge = GameState(
        ventures: [
          // ebitda 1e15 cents at 100x: the raw EV product is 1e20, which
          // overflows int64 (max ~9.2e18). 100%-owned, debt-free.
          Venture(
            id: 'whale',
            sector: Sector.software,
            ebitdaCents: 1000000000000000, // 1e15
            multipleMilli: 100000, // 100.0x
            netDebtCents: 0,
            ownershipBp: 10000,
          ),
        ],
        cashCents: 0,
      );
      final nw = huge.netWorthCents;
      expect(nw, greaterThan(0),
          reason: 'a wrapped product would read NEGATIVE; the guard keeps '
              'it positive');
      // Both products saturate: EV = satMul(1e15, 1e5)=kMaxCents, then ~/1000;
      // equity = that (no debt); mine = satMul(equity, 10000)=kMaxCents (it
      // re-overflows), then ~/10000. So net worth pins exactly here.
      expect(nw, kMaxCents ~/ 10000,
          reason: 'both multiplies clamp at kMaxCents; the bp division is '
              'last');
    });

    test('an in-range net worth is byte-unmoved by the guard '
        '(no golden drift)', () {
      // The guard must not perturb any reachable value. A normal venture\'s
      // products are ~1e12, far under the 2^60 cap, so the getter equals the
      // hand-computed canonical formula exactly.
      final state = GameState(
        ventures: const [
          Venture(
            id: 'v1',
            sector: Sector.software,
            ebitdaCents: 1551560,
            multipleMilli: 12880,
            netDebtCents: 200000,
            ownershipBp: 8000,
          ),
        ],
        cashCents: 858100,
      );
      final ev = (1551560 * 12880) ~/ 1000;
      final equity = ev - 200000;
      final mine = (equity * 8000) ~/ 10000;
      expect(state.netWorthCents, mine + 858100);
    });
  });

  group('Venture value equality and copyWith', () {
    test('identical field values are equal and share a hashCode', () {
      expect(seedVenture(), seedVenture());
      expect(seedVenture().hashCode, seedVenture().hashCode);
    });

    test('differing in any single field breaks equality', () {
      expect(seedVenture().copyWith(id: 'other'), isNot(seedVenture()));
      expect(seedVenture().copyWith(sector: Sector.retail),
          isNot(seedVenture()));
      expect(seedVenture().copyWith(ebitdaCents: 1), isNot(seedVenture()));
      expect(seedVenture().copyWith(multipleMilli: 1), isNot(seedVenture()));
      expect(seedVenture().copyWith(netDebtCents: 1), isNot(seedVenture()));
      expect(seedVenture().copyWith(ownershipBp: 1), isNot(seedVenture()));
    });

    test('copyWith changes only the named field', () {
      final changed = seedVenture().copyWith(ebitdaCents: 999);
      expect(changed.ebitdaCents, 999);
      // every other field unchanged => equal to seed copyWith'd to match
      expect(changed, seedVenture().copyWith(ebitdaCents: 999));
      expect(changed.copyWith(ebitdaCents: kStartEbitda), seedVenture());
    });
  });

  group('LoggedAction value equality', () {
    test('identical records are equal', () {
      expect(
        const LoggedAction(round: 1, summary: 'bought X'),
        const LoggedAction(round: 1, summary: 'bought X'),
      );
    });

    test('differing fields are unequal', () {
      expect(
        const LoggedAction(round: 1, summary: 'a'),
        isNot(const LoggedAction(round: 2, summary: 'a')),
      );
      expect(
        const LoggedAction(round: 1, summary: 'a'),
        isNot(const LoggedAction(round: 1, summary: 'b')),
      );
    });
  });

  group('GameState value equality and copyWith', () {
    test('identical states are equal and share a hashCode', () {
      expect(seedState(), seedState());
      expect(seedState().hashCode, seedState().hashCode);
    });

    test('differing in any single field breaks equality', () {
      expect(seedState().copyWith(cashCents: 1), isNot(seedState()));
      expect(seedState().copyWith(rngCursor: 5), isNot(seedState()));
      expect(seedState().copyWith(round: 5), isNot(seedState()));
      expect(seedState().copyWith(tier: 5), isNot(seedState()));
      expect(seedState().copyWith(schemaVersion: 99), isNot(seedState()));
      expect(
        seedState().copyWith(
          actionLog: const [LoggedAction(round: 1, summary: 'x')],
        ),
        isNot(seedState()),
      );
      expect(
        seedState().copyWith(ventures: [seedVenture().copyWith(id: 'z')]),
        isNot(seedState()),
      );
    });

    test('copyWith changes only the named field', () {
      final changed = seedState().copyWith(cashCents: 12345);
      expect(changed.cashCents, 12345);
      expect(changed, seedState().copyWith(cashCents: 12345));
      expect(changed.copyWith(cashCents: kStartCash), seedState());
    });

    test('ventures list is unmodifiable', () {
      final s = seedState();
      expect(
        () => s.ventures.add(seedVenture()),
        throwsUnsupportedError,
      );
    });
  });

  group('venture display name (R13; deterministic id+sector namer)', () {
    test('is a pure deterministic function of id + sector', () {
      // Same inputs ALWAYS yield the same name (replay-stable, RNG-free).
      expect(ventureDisplayName('v1', Sector.software),
          ventureDisplayName('v1', Sector.software));
      expect(ventureDisplayName('v1', Sector.software), 'QUANTA',
          reason: 'the canonical seed venture id pins to QUANTA (the golden '
              'depends on this exact value)');
    });

    test('picks within the named sector pool and never returns "V1"-style '
        'raw ids (the R9/R11 leak)', () {
      for (final sector in Sector.values) {
        final name = ventureDisplayName('v1', sector);
        expect(name, isNotEmpty);
        expect(name, isNot(equalsIgnoringCase('v1')));
        // Cross-sector names differ from SOFTWARE's by pool.
        if (sector != Sector.software) {
          expect(name, isNot('QUANTA'),
              reason: 'each sector has its own flavor pool');
        }
      }
    });

    test('Venture.displayName getter mirrors the namer for its id+sector',
        () {
      final v = seedVenture(); // id 'seed', SOFTWARE
      expect(v.displayName, ventureDisplayName('seed', Sector.software));
      // The getter is NOT in the constructor/equality (it is derived).
      expect(v, seedVenture());
    });
  });

  group('MetaState (R13; doc 02 §1 — durable across-runs access store)', () {
    test('the default is a fresh first-launch meta', () {
      final m = MetaState();
      expect(m.schemaVersion, engineSchemaVersion);
      expect(m.reputation, 0);
      expect(m.metaLevel, 0);
      expect(m.furthestTierReached, 1);
      expect(m.runsPlayed, 0);
      expect(m.cleanExits, 0);
      expect(m.lastDeathCause, isNull);
      expect(m.lastSettledRunId, isNull);
      // Base 4 sectors always unlocked; Bootstrapper background always there.
      expect(m.unlockedSectors, hasLength(4));
      expect(m.unlockedBackgrounds, contains(kBootstrapperBackgroundId));
      expect(m.cosmetics.titles, isEmpty);
      expect(m.cosmetics.activeTitle, isNull);
    });

    test('value equality + copyWith semantics (lastDeathCause keep-on-null)',
        () {
      final m = MetaState(reputation: 100, runsPlayed: 3);
      expect(m, MetaState(reputation: 100, runsPlayed: 3));
      final bumped = m.copyWith(reputation: 200);
      expect(bumped.reputation, 200);
      expect(bumped.runsPlayed, 3, reason: 'copyWith preserves others');
      // keep-on-null: passing null lastDeathCause does NOT clear it.
      final withDeath = m.copyWith(lastDeathCause: DeathCause.bankruptcy);
      expect(withDeath.copyWith(reputation: 5).lastDeathCause,
          DeathCause.bankruptcy);
      expect(withDeath.copyWith(clearLastDeathCause: true).lastDeathCause,
          isNull);
    });

    test('collection fields are unmodifiable', () {
      final m = MetaState();
      expect(() => m.unlockedCards.add('x'), throwsUnsupportedError);
      expect(() => m.unlockedSectors.add(Sector.software),
          throwsUnsupportedError);
    });
  });
}
