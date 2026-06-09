// AcquireAddOn — the signature multiple-arbitrage merge (doc 03 §4.2, §Q6).
//
// Covers, one behavior per test:
//   - happy path same-sector: the doc 01 §10 worked example, exact in cents
//     (platform $1.0M EBITDA @14x, addon $200k @5x -> price $1.0M, new
//     EBITDA $1.24M, multiple unchanged)
//   - faceDebt folds into the platform's netDebt
//   - cross-sector: zero synergy + 0.92 multiple drag, stacking 0.92^n
//   - rejections (insufficient cash, missing venture) leave the state
//     IDENTICAL (value equality) and emit ACTION_REJECTED
//   - the MULTIPLE_ARBITRAGE accretion amount matches the authoritative
//     arbitrageFlash formula AND is RENDER-ONLY: it is written to no field,
//     and the net-worth change equals the real deltas, not the flash
//   - §7 shape: only the five inputs + cash + actionLog bookkeeping change
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/resolver.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

// --- Worked example constants, cited from docs/01-economy-math-spec.md §10 ---
// Platform: SOFTWARE, EBITDA $1.0M (100,000,000 cents), multiple 14x (14000).
// Add-on: EBITDA $200k (20,000,000 cents) at buy multiple 5x (5000).
// price       = trunc(20,000,000 * 5000 / 1000)  = 100,000,000 ($1.0M)
// absorbed    = 20,000,000 + trunc(20,000,000 * 20 / 100) = 24,000,000
// new EBITDA  = 124,000,000 ($1.24M); multiple unchanged at 14000.
const int kPlatformEbitda = 100000000;
const int kPlatformMultiple = 14000;
const int kAddonEbitda = 20000000;
const int kAddonBuyMultiple = 5000;
const int kAddonPrice = 100000000;
const int kMergedEbitdaSameSector = 124000000;

/// The platform venture under test (the doc 01 §10 platform, simplified to
/// zero debt and 100% ownership so the delta math reads off directly).
Venture platform() => const Venture(
      id: 'p1',
      sector: Sector.software,
      ebitdaCents: kPlatformEbitda,
      multipleMilli: kPlatformMultiple,
      netDebtCents: 0,
      ownershipBp: 10000,
    );

/// A base state holding the platform and enough cash for one merge.
GameState base({int cashCents = 150000000}) => GameState(
      ventures: [platform()],
      cashCents: cashCents,
      rngCursor: 7,
      round: 3,
      tier: 2,
      playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
    );

/// Fresh deterministic RNG (the merge draws nothing; cursor must not move).
SplitMix64Rng rng() => SplitMix64Rng(1);

/// The same-sector worked-example action.
AcquireAddOn sameSectorAddOn({int faceDebtCents = 0}) => AcquireAddOn(
      targetVentureId: 'p1',
      addonSector: Sector.software,
      addonEbitdaCents: kAddonEbitda,
      addonBuyMultipleMilli: kAddonBuyMultiple,
      addonFaceDebtCents: faceDebtCents,
    );

/// The cross-sector counter-example (same chips, RETAIL home sector).
AcquireAddOn crossSectorAddOn() => const AcquireAddOn(
      targetVentureId: 'p1',
      addonSector: Sector.retail,
      addonEbitdaCents: kAddonEbitda,
      addonBuyMultipleMilli: kAddonBuyMultiple,
      addonFaceDebtCents: 0,
    );

/// Flattens the numeric gameplay + bookkeeping fields to `path -> value` so a
/// test can diff exactly which fields an action touched (doc 03 §5 behavioral
/// invariant test, hand-rolled here for the merge).
Map<String, int> flatten(GameState s) => {
      for (var i = 0; i < s.ventures.length; i++) ...{
        'ventures.$i.ebitdaCents': s.ventures[i].ebitdaCents,
        'ventures.$i.multipleMilli': s.ventures[i].multipleMilli,
        'ventures.$i.netDebtCents': s.ventures[i].netDebtCents,
        'ventures.$i.ownershipBp': s.ventures[i].ownershipBp,
      },
      'cashCents': s.cashCents,
      'rngCursor': s.rngCursor,
      'round': s.round,
      'tier': s.tier,
      'schemaVersion': s.schemaVersion,
      'actionLog.length': s.actionLog.length,
    };

/// Per-path deltas between two states (paths present in both).
Map<String, int> diff(GameState before, GameState after) {
  final a = flatten(before);
  final b = flatten(after);
  return {
    for (final key in a.keys)
      if (b[key] != a[key]) key: b[key]! - a[key]!,
  };
}

void main() {
  group('AcquireAddOn same-sector (doc 01 §10 worked example)', () {
    test('charges exactly the addonPrice formula price', () {
      // price = trunc(addon.ebitda * m_buy / 1000) — economy-model.json
      // formulas.addonPrice.
      final result = apply(base(), sameSectorAddOn(), rng(), kContent);
      expect(result.state.cashCents, 150000000 - kAddonPrice); // 50,000,000
    });

    test('absorbs EBITDA + 20% synergy; \$1.0M platform -> \$1.24M', () {
      final result = apply(base(), sameSectorAddOn(), rng(), kContent);
      expect(result.state.ventures.single.ebitdaCents, kMergedEbitdaSameSector);
    });

    test('leaves the platform multiple unchanged', () {
      final result = apply(base(), sameSectorAddOn(), rng(), kContent);
      expect(result.state.ventures.single.multipleMilli, kPlatformMultiple);
    });

    test('folds the addon face debt into the platform netDebt', () {
      final result = apply(base(), sameSectorAddOn(faceDebtCents: 5000000), rng(), kContent);
      expect(result.state.ventures.single.netDebtCents, 5000000);
    });

    test('logs a LoggedAction at the current round', () {
      final before = base();
      final result = apply(before, sameSectorAddOn(), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
    });

    test('truncates the synergy bonus toward zero on odd cents', () {
      // addon EBITDA 333 cents: synergy = trunc(333 * 20 / 100) = 66
      // (66.6 truncates); price = trunc(333 * 5000 / 1000) = 1665.
      const action = AcquireAddOn(
        targetVentureId: 'p1',
        addonSector: Sector.software,
        addonEbitdaCents: 333,
        addonBuyMultipleMilli: 5000,
        addonFaceDebtCents: 0,
      );
      final result = apply(base(), action, rng(), kContent);
      expect(
          result.state.ventures.single.ebitdaCents, kPlatformEbitda + 333 + 66);
      expect(result.state.cashCents, 150000000 - 1665);
    });

    test('a zero-EBITDA addon costs nothing and only folds in its face debt',
        () {
      // price = trunc(0 * 5000 / 1000) = 0; absorbed = 0 + trunc(0*20/100) = 0;
      // flash = trunc(0 * (14000 - 5000) / 1000) = 0.
      const action = AcquireAddOn(
        targetVentureId: 'p1',
        addonSector: Sector.software,
        addonEbitdaCents: 0,
        addonBuyMultipleMilli: 5000,
        addonFaceDebtCents: 7000000,
      );
      final before = base();
      final result = apply(before, action, rng(), kContent);
      expect(result.state.ventures.single.ebitdaCents, kPlatformEbitda);
      expect(result.state.ventures.single.netDebtCents, 7000000);
      expect(result.state.cashCents, before.cashCents);
      expect(result.events.single.type, GameEventType.multipleArbitrage);
      expect(result.events.single.amount, 0);
    });

    test(
        'same-sector merge onto a cross-dragged platform keeps the dragged '
        'multiple and flashes against it', () {
      // Cross merge first: multiple 14000 -> 12880, EBITDA -> 120,000,000.
      final crossed =
          apply(base(cashCents: 250000000), crossSectorAddOn(), rng(), kContent);
      expect(crossed.state.ventures.single.multipleMilli, 12880);
      final result = apply(crossed.state, sameSectorAddOn(), rng(), kContent);
      // EBITDA: 120,000,000 + 20,000,000 + 4,000,000 synergy = 144,000,000.
      expect(result.state.ventures.single.ebitdaCents, 144000000);
      // The dragged multiple IS the live platform multiple now; unchanged.
      expect(result.state.ventures.single.multipleMilli, 12880);
      // Flash = trunc(20,000,000 * (12880 - 5000) / 1000) = 157,600,000.
      expect(result.events.single.amount, 157600000);
    });
  });

  group('AcquireAddOn cross-sector (zero synergy + conglomerate drag)', () {
    test('absorbs the raw addon EBITDA with zero synergy', () {
      final result = apply(base(), crossSectorAddOn(), rng(), kContent);
      // 100,000,000 + 20,000,000 — no +20% bonus.
      expect(result.state.ventures.single.ebitdaCents, 120000000);
    });

    test('drags the platform multiple by 0.92 (trunc)', () {
      final result = apply(base(), crossSectorAddOn(), rng(), kContent);
      // trunc(14000 * 92 / 100) = 12880 — economy-model.json formulas.congDrag.
      expect(result.state.ventures.single.multipleMilli, 12880);
    });

    test('stacks the drag multiplicatively across repeated merges (0.92^2)', () {
      // Enough cash for two \$1.0M merges.
      final once = apply(base(cashCents: 250000000), crossSectorAddOn(), rng(), kContent);
      final twice = apply(once.state, crossSectorAddOn(), rng(), kContent);
      // trunc(12880 * 92 / 100) = 11849 (11849.6 truncates toward zero).
      expect(twice.state.ventures.single.multipleMilli, 11849);
    });

    test('clamps the dragged multiple at the 1000 (1.0x) live-venture floor',
        () {
      // economy-model.json resolverInputs.clamps: multiple >= 1000 for a live
      // venture. The floor is REACHABLE: drift floors at exactly 1000
      // (formulas.driftDelta `max(1000, ...)`), and an unclamped drag from
      // there would give trunc(1000 * 92 / 100) = 920 — a clamp violation.
      final floored = GameState(
        ventures: [platform().copyWith(multipleMilli: 1000)],
        cashCents: 150000000,
        rngCursor: 7,
        round: 3,
        tier: 2,
        playsRemaining: 3, // the doc 02 §3 plays gate (round layer)
      );
      final result = apply(floored, crossSectorAddOn(), rng(), kContent);
      expect(result.state.ventures.single.multipleMilli, 1000);
    });
  });

  group('AcquireAddOn rejection paths (PRE failed: no mutation)', () {
    test('insufficient cash leaves the state IDENTICAL', () {
      final before = base(cashCents: kAddonPrice - 1);
      final result = apply(before, sameSectorAddOn(), rng(), kContent);
      expect(result.state, before);
    });

    test('insufficient cash emits ACTION_REJECTED with a reason key', () {
      final result = apply(base(cashCents: kAddonPrice - 1), sameSectorAddOn(), rng(), kContent);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'insufficient_cash');
    });

    test('missing target venture leaves the state IDENTICAL', () {
      final before = base();
      const action = AcquireAddOn(
        targetVentureId: 'no-such-venture',
        addonSector: Sector.software,
        addonEbitdaCents: kAddonEbitda,
        addonBuyMultipleMilli: kAddonBuyMultiple,
        addonFaceDebtCents: 0,
      );
      final result = apply(before, action, rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'venture_not_found');
    });

    test('rejection does not log a LoggedAction', () {
      final before = base(cashCents: 0);
      final result = apply(before, sameSectorAddOn(), rng(), kContent);
      expect(result.state.actionLog, before.actionLog);
    });
  });

  group('MULTIPLE_ARBITRAGE accretion event (RENDER-ONLY, §Q6)', () {
    test('amount matches the arbitrageFlash formula exactly', () {
      final result = apply(base(), sameSectorAddOn(), rng(), kContent);
      // trunc(addonEbitda * (m_platform - m_buy) / 1000)
      //   = trunc(20,000,000 * (14000 - 5000) / 1000) = 180,000,000 ($1.8M).
      final expected =
          arbitrageAccretion(kAddonEbitda, kPlatformMultiple, kAddonBuyMultiple);
      expect(expected, 180000000);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.multipleArbitrage);
      expect(result.events.single.amount, expected);
      expect(result.events.single.ventureId, 'p1');
    });

    test('the flash is written to NO state field', () {
      final before = base();
      final result = apply(before, sameSectorAddOn(), rng(), kContent);
      final accretion =
          arbitrageAccretion(kAddonEbitda, kPlatformMultiple, kAddonBuyMultiple);
      // No field moved by the flash amount; the only deltas are the real ones.
      final deltas = diff(before, result.state);
      expect(deltas.values.contains(accretion), isFalse,
          reason: 'a state field moved by exactly the render-only flash');
      expect(deltas.values.contains(-accretion), isFalse);
    });

    test('net-worth change equals the real deltas, not the flash', () {
      final before = base();
      final result = apply(before, sameSectorAddOn(), rng(), kContent);
      // dEV = (124M - 100M) * 14000 / 1000 = 336,000,000 at 100% ownership and
      // zero debt; cash fell by the 100,000,000 price -> dNW = +236,000,000.
      final nwDelta = result.state.netWorthCents - before.netWorthCents;
      expect(nwDelta, 236000000);
      expect(nwDelta, isNot(180000000)); // explicitly NOT the flash amount
    });
  });

  group('§7 shape (only the five inputs + bookkeeping may change)', () {
    test('same-sector merge touches only ebitda/netDebt/cash + actionLog', () {
      final before = base();
      final result = apply(before, sameSectorAddOn(faceDebtCents: 1), rng(), kContent);
      const allowed = {
        'ventures.0.ebitdaCents',
        'ventures.0.multipleMilli',
        'ventures.0.netDebtCents',
        'ventures.0.ownershipBp',
        'cashCents',
        'actionLog.length',
      };
      final touched = diff(before, result.state).keys.toSet();
      expect(touched.difference(allowed), isEmpty,
          reason: 'merge mutated a forbidden field: $touched');
      // Identity / structure untouched.
      expect(result.state.ventures.single.id, 'p1');
      expect(result.state.ventures.single.sector, Sector.software);
      expect(result.state.ventures.length, 1);
    });

    test('the merge draws nothing: rngCursor is unchanged', () {
      final before = base();
      final stream = rng();
      final result = apply(before, sameSectorAddOn(), stream, kContent);
      expect(result.state.rngCursor, before.rngCursor);
      // The stream itself did not advance either (doc 03 §3.1: merges are
      // deterministic, 0 draws).
      expect(stream.cursor, 0);
    });
  });
}
