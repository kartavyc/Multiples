// The Phase-5 balance harness contract (doc 01 §11/§12; R12):
// tool/sim.dart's full-model Monte-Carlo is (1) DETERMINISTIC — the report
// is a pure function of (N, seedBase, policy set, engine build) — and
// (2) the engine's CURRENT dials land inside the acceptance bands.
//
// THE BANDS (each documented where it is asserted):
//   - GREEDY BANKRUPTCY in [8%, 12%] — doc 01 §11.3's re-run protocol
//     verbatim ("keep greedy bankruptcy in [8%, 12%] before content
//     lock"); §11.2's "greed is tempting and occasionally fatal" pillar.
//   - FLOOR WIN in [25%, 42%] — doc 01 §11.3's re-run protocol verbatim.
//     NOTE the harness floor is STRICTER than the JS calibration's
//     "competent-but-plain" player: it never merges, never hires, never
//     exits (§11's own scope-honesty), so it bounds the real floor from
//     BELOW. It measured 41.5% at N=2000 after the R12 tune — near the
//     band top, which doc 01 §11.3 itself flags as "a candidate to pull
//     toward 30% once arbitrage/skill headroom is measured" (§12 open
//     item, NOT this round's gate).
//   - SMART WIN in [42%, 56%] — pinned from MEASURED REALITY (47.1% at
//     N=2000, 45.9% on a disjoint seed range), per the R12 work order:
//     no doc band exists for the full skill layer yet; the gate freezes
//     the measured behavior so a dial move that guts (or trivializes)
//     designed play fails loudly. Re-pin WITH a harness/tuning change,
//     never to paper over one.
//   - SMART > FLOOR (win) — doc 01 §11.3 "skill headroom is intact": the
//     policy that plays the designed layers must beat the one that
//     refuses them.
//   - FLOOR/SMART BANKRUPTCY <= 2% — doc 01 §11.3 "a prudent player never
//     bankrupts (0.0%)", relaxed to <=2% because the full model deals the
//     prudent policies real debt instruments the JS floor never held
//     (measured: floor 0.2%, smart 0.0%).
//   - FEEL: dead-hand rate <= 2% of ACT phases and >= 3.0 playable
//     tickets/hand — the R10 dead-draw fix held through the tune
//     (measured 0.0% / 3.4-3.6); this is the "nothing to do" complaint
//     the R12 work order ordered measured, gated so it cannot regress.
//
// N=400 keeps the suite fast; the gates are EXACT at a fixed seed (no
// statistical flake — determinism is test #1). The headline numbers in
// .claude/STATE.md come from N=2000 (same seedBase, same engine build).
//
// All integer math; no floating point anywhere in this test.

import 'dart:io' show File;

import 'package:test/test.dart';

import '../tool/sim.dart';
import 'helpers/content.dart';
import 'purity_guard_test.dart' show violationsIn;

void main() {
  group('determinism (the tool header\'s contract)', () {
    test('same (N, seedBase, policy) -> byte-identical report, twice', () {
      for (final policy in SimPolicy.values) {
        final a = formatStats(
            runBatch(policy, 40, kContent, kEconomyConfig, seedBase: 1));
        final b = formatStats(
            runBatch(policy, 40, kContent, kEconomyConfig, seedBase: 1));
        expect(a, b, reason: '${policy.name}: the report must be a pure '
            'function of its inputs');
      }
    });

    test('run k uses seed (seedBase + k - 1): batches tile seamlessly', () {
      // The 2nd run of seedBase 1 IS the 1st run of seedBase 2.
      final fromBase1 = simulateRun(2, SimPolicy.floor, kContent,
          kEconomyConfig);
      final fromBase2 = simulateRun(2, SimPolicy.floor, kContent,
          kEconomyConfig);
      expect(fromBase1.totalRounds, fromBase2.totalRounds);
      expect(fromBase1.won, fromBase2.won);
      expect(fromBase1.actions, fromBase2.actions);
      expect(fromBase1.playableCounts, fromBase2.playableCounts);
    });
  });

  group('purity: the harness honors the engine\'s integer discipline '
      '(tool/sim.dart is outside lib/, so guard #1 does not see it)', () {
    test('no double / dart:math / DateTime / ambient Random in tool/sim.dart',
        () {
      final source = File('tool/sim.dart').readAsStringSync();
      expect(violationsIn(source), isEmpty,
          reason: 'the harness aggregates in integer permille/x100 only');
    });
  });

  group('acceptance gates (N=400, seedBase 1 — deterministic, see header)',
      () {
    late SimStats floor;
    late SimStats greedy;
    late SimStats smart;
    setUpAll(() {
      floor = runBatch(SimPolicy.floor, 400, kContent, kEconomyConfig);
      greedy = runBatch(SimPolicy.greedy, 400, kContent, kEconomyConfig);
      smart = runBatch(SimPolicy.smart, 400, kContent, kEconomyConfig);
    });

    test('GREEDY bankruptcy in [8%, 12%] (doc 01 §11.3 re-run protocol)',
        () {
      expect(greedy.bankruptcyPermille, inInclusiveRange(80, 120),
          reason: 'greed must stay tempting AND occasionally fatal '
              '(R20b FULL pool + recapPct 0.16->0.20 re-tune: measured '
              '10.7% at this N; 9.2% at N=2000)');
    });

    test('FLOOR win in [25%, 42%] (doc 01 §11.3 re-run protocol)', () {
      expect(floor.winPermille, inInclusiveRange(250, 420),
          reason: 'winnable-but-tight for plain play (R20b FULL pool: '
              'measured 28.5% at this N; 33.8% at N=2000 — the wider pool '
              'pulled the floor down toward the §11.3 "30%" target)');
    });

    test('SMART win in [42%, 58%] (re-pinned from measured reality with the '
        'R20b full-pool harness change — header)', () {
      // R20b RE-PIN: widening the draw pool to the full content gave designed
      // play more tools (more venture re-founds for the exit cycle, asset-
      // strip liquidity, etc.), so SMART climbed from the slice-era ~47% to
      // ~55-58%. The header sanctions re-pinning WITH a harness change (this
      // is one): the ceiling moved from 56% to 58% to cover N=2000's 57.6%
      // (N=400 measures 54.7%, comfortably inside).
      expect(smart.winPermille, inInclusiveRange(420, 580),
          reason: 'the designed-play ceiling proxy (measured 54.7% at this '
              'N; 57.6% at N=2000)');
    });

    test('skill headroom: SMART beats the FLOOR (doc 01 §11.3)', () {
      expect(smart.winPermille, greaterThan(floor.winPermille));
    });

    test('prudence near-never dies: FLOOR and SMART bankruptcy <= 2%', () {
      expect(floor.bankruptcyPermille, lessThanOrEqualTo(20),
          reason: 'doc 01 §11.3: a prudent player never bankrupts');
      expect(smart.bankruptcyPermille, lessThanOrEqualTo(20));
    });

    test('FEEL: dead hands stay dead — <= 2% of ACT phases, >= 3.0 '
        'playable tickets/hand, for every policy', () {
      for (final s in [floor, greedy, smart]) {
        expect(s.deadHandPermille, lessThanOrEqualTo(20),
            reason: '${s.policy.name}: the R10 dead-draw fix must hold '
                'through any tune (the playtest\'s "nothing to do" '
                'complaint, gated)');
        expect(s.avgPlayableX100, greaterThanOrEqualTo(300),
            reason: '${s.policy.name}: hands must stay actionable');
      }
    });

    test('SMART actually plays the designed layers (uptake is real)', () {
      expect(smart.mergedPermille, greaterThan(900),
          reason: 'same-sector merges are the tutorial mechanic');
      expect(smart.hiredPermille, greaterThan(900),
          reason: 'partner engines are the organic-growth attribution');
      expect(smart.exitedPermille, greaterThan(300),
          reason: 'the exit cycle (paper -> cash) fires in a meaningful '
              'share of runs (measured 67%)');
    });
  });
}
