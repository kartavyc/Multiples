// PlayConsumable — a one-shot PLAY's deltas over the five §7 inputs
// (doc 02 §3.6 PLAY_CONSUMABLE; doc 03 §5 Deltas shape).
//
// Covers, one behavior per test:
//   - context-free cash plays need no target; targeted plays apply additive
//     deltas to all four per-venture inputs (the wire key for ownership is
//     `own` — LOCKED)
//   - result clamps per economy-model.json resolverInputs.clamps:
//     ebitda floor 0; multiple floor 1000; own 0..10000; netDebt unclamped
//     (negative = net cash, legal); cash never clamped (PRE keeps it >= 0)
//   - the playsHeld inventory (live since the deal-flow layer): the
//     play_not_held membership gate fires FIRST; success removes exactly
//     one copy of the played id (first occurrence)
//   - rejections (not held, invalid delta key, per-venture key without/with
//     a missing target, resulting negative cash) leave the WHOLE state
//     value-identical, emit ACTION_REJECTED, no log, no draw
//   - §7 shape: only the five inputs + playsHeld + actionLog change;
//     0 RNG draws
//
// PlayConsumable applies ADDITIVE integer deltas — there is no division in
// this action, so no truncation edge exists; exactness is pinned instead.
//
// All money is integer cents; no `double` anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

Venture venture({
  int ebitdaCents = 600000,
  int multipleMilli = 6000,
  int netDebtCents = 0,
  int ownershipBp = 8000,
}) =>
    Venture(
      id: 'v1',
      sector: Sector.software,
      ebitdaCents: ebitdaCents,
      multipleMilli: multipleMilli,
      netDebtCents: netDebtCents,
      ownershipBp: ownershipBp,
    );

GameState base({
  Venture? v,
  int cashCents = 2000000,
  List<String> playsHeld = const ['p'],
}) =>
    GameState(
      ventures: [v ?? venture()],
      cashCents: cashCents,
      rngCursor: 7,
      round: 2,
      tier: 2,
      playsHeld: playsHeld,
    );

/// Fresh deterministic RNG (a consumable draws nothing).
SplitMix64Rng rng() => SplitMix64Rng(1);

void main() {
  group('PlayConsumable happy path (doc 02 §3.6)', () {
    test('a context-free cash play needs no target', () {
      final result = apply(base(),
          PlayConsumable(playId: 'p', deltas: const {'cash': -300000}), rng(), kContent);
      expect(result.state.cashCents, 1700000);
    });

    test('a positive cash play credits exactly', () {
      final result = apply(base(),
          PlayConsumable(playId: 'p', deltas: const {'cash': 1500000}), rng(), kContent);
      expect(result.state.cashCents, 3500000);
    });

    test('a targeted play applies all four per-venture keys additively '
        '(ownership wire key is `own` — LOCKED)', () {
      final result = apply(
          base(),
          PlayConsumable(
            playId: 'p',
            targetVentureId: 'v1',
            deltas: const {
              'ebitda': -100000,
              'multiple': -500,
              'netDebt': 200000,
              'own': -1000,
            },
          ),
          rng(), kContent);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 500000);
      expect(v.multipleMilli, 5500);
      expect(v.netDebtCents, 200000);
      expect(v.ownershipBp, 7000);
    });

    test('a mixed venture + cash play applies both sides (ASSET_STRIP)', () {
      // ASSET_STRIP shape: cash += X; ebitda -= d (doc 02 §3.6 table).
      final before = base();
      final result = apply(
          before,
          PlayConsumable(
            playId: 'p',
            targetVentureId: 'v1',
            deltas: const {'cash': 1800000, 'ebitda': -300000},
          ),
          rng(), kContent);
      expect(result.state.cashCents, 3800000);
      expect(result.state.ventures.single.ebitdaCents, 300000);
    });

    test('logs a LoggedAction at the current round and emits no event', () {
      final before = base();
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'cash': 100000}), rng(), kContent);
      expect(result.state.actionLog.length, before.actionLog.length + 1);
      expect(result.state.actionLog.last.round, before.round);
      expect(result.events, isEmpty);
    });
  });

  group('result clamps (economy-model.json resolverInputs.clamps)', () {
    test('ebitda clamps at the 0 floor', () {
      final result = apply(
          base(),
          PlayConsumable(
              playId: 'p',
              targetVentureId: 'v1',
              deltas: const {'ebitda': -9999999}),
          rng(), kContent);
      expect(result.state.ventures.single.ebitdaCents, 0);
    });

    test('multiple clamps at the 1000-milli (1.0x) live-venture floor', () {
      final result = apply(
          base(),
          PlayConsumable(
              playId: 'p',
              targetVentureId: 'v1',
              deltas: const {'multiple': -6000}),
          rng(), kContent);
      expect(result.state.ventures.single.multipleMilli, 1000);
    });

    test('ownership clamps at 0 bp', () {
      final result = apply(
          base(),
          PlayConsumable(
              playId: 'p', targetVentureId: 'v1', deltas: const {'own': -9000}),
          rng(), kContent);
      expect(result.state.ventures.single.ownershipBp, 0);
    });

    test('ownership clamps at 10000 bp (TENDER overshoot)', () {
      final result = apply(
          base(),
          PlayConsumable(
              playId: 'p', targetVentureId: 'v1', deltas: const {'own': 5000}),
          rng(), kContent);
      expect(result.state.ventures.single.ownershipBp, 10000);
    });

    test('netDebt has no floor: a refi can go net-cash negative', () {
      final result = apply(
          base(),
          PlayConsumable(
              playId: 'p',
              targetVentureId: 'v1',
              deltas: const {'netDebt': -2500000}),
          rng(), kContent);
      expect(result.state.ventures.single.netDebtCents, -2500000);
    });

    test('cash is never clamped: the exact delta lands', () {
      // Down to a single cent — no snapping, no floor logic on cash.
      final result = apply(base(),
          PlayConsumable(playId: 'p', deltas: const {'cash': -1999999}),
          rng(), kContent);
      expect(result.state.cashCents, 1);
    });
  });

  group('the playsHeld inventory (deal-flow layer; doc 02 §3.6)', () {
    test('playing a held id REMOVES it from playsHeld', () {
      final result = apply(base(),
          PlayConsumable(playId: 'p', deltas: const {'cash': 100}),
          rng(), kContent);
      expect(result.state.playsHeld, isEmpty);
    });

    test('a duplicate-held id loses exactly ONE copy (first occurrence)',
        () {
      final before = base(playsHeld: const ['p', 'p']);
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'cash': 100}),
          rng(), kContent);
      expect(result.state.playsHeld, ['p'],
          reason: 'one play consumed, one still held');
    });

    test('an UNHELD play is rejected with play_not_held, no mutation', () {
      final before = base(playsHeld: const []);
      final stream = rng();
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'cash': 100}),
          stream, kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'play_not_held');
      expect(stream.cursor, 0);
    });

    test('holding a DIFFERENT id does not satisfy the gate', () {
      final before = base(playsHeld: const ['other']);
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'cash': 100}),
          rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'play_not_held');
    });

    test('the membership gate fires FIRST (before invalid_deltas)', () {
      final before = base(playsHeld: const []);
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'score': 1}),
          rng(), kContent);
      expect(result.events.single.reason, 'play_not_held',
          reason: 'you cannot play what you do not hold — checked before '
              'the payload is even inspected');
    });
  });

  group('PlayConsumable rejection paths (PRE failed: no mutation)', () {
    test('a delta key outside the five inputs is rejected (invalid_deltas)',
        () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'score': 1}), stream, kContent);
      expect(result.state, before);
      expect(result.events, hasLength(1));
      expect(result.events.single.type, GameEventType.actionRejected);
      expect(result.events.single.reason, 'invalid_deltas');
      expect(result.state.actionLog, before.actionLog);
      expect(stream.cursor, 0);
    });

    test('the long-form `ownership` key is NOT the wire key and is rejected',
        () {
      // The §7 delta key for ownership is `own` (LOCKED, CLAUDE.md).
      final before = base();
      final result = apply(
          before,
          PlayConsumable(
              playId: 'p',
              targetVentureId: 'v1',
              deltas: const {'ownership': -1000}),
          rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'invalid_deltas');
    });

    test('a per-venture key without a target is rejected', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'ebitda': 100000}),
          stream, kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'venture_not_found');
      expect(stream.cursor, 0);
    });

    test('a per-venture key with a missing target venture is rejected', () {
      final before = base();
      final result = apply(
          before,
          PlayConsumable(
              playId: 'p',
              targetVentureId: 'nope',
              deltas: const {'ebitda': 100000}),
          rng(), kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'venture_not_found');
    });

    test('a play that would push cash below zero is rejected', () {
      final before = base();
      final stream = rng();
      final result = apply(before,
          PlayConsumable(playId: 'p', deltas: const {'cash': -2000001}),
          stream, kContent);
      expect(result.state, before);
      expect(result.events.single.reason, 'insufficient_cash');
      expect(stream.cursor, 0);
    });

    test('cash to exactly zero is allowed (PRE is >= 0)', () {
      final result = apply(base(),
          PlayConsumable(playId: 'p', deltas: const {'cash': -2000000}),
          rng(), kContent);
      expect(result.state.cashCents, 0);
    });
  });

  group('§7 shape (five inputs + playsHeld consumption + actionLog only)',
      () {
    test('bookkeeping is untouched; 0 draws', () {
      final before = base();
      final stream = rng();
      final result = apply(
          before,
          PlayConsumable(
            playId: 'p',
            targetVentureId: 'v1',
            deltas: const {'cash': -100000, 'ebitda': 50000},
          ),
          stream, kContent);
      expect(result.state.ventures.single.passive, isFalse);
      expect(result.state.rngCursor, before.rngCursor);
      expect(stream.cursor, 0);
      expect(result.state.round, before.round);
      expect(result.state.tier, before.tier);
      expect(result.state.rerollsUsed, before.rerollsUsed);
      expect(result.state.schemaVersion, before.schemaVersion);
    });

    test('untargeted keys on the venture are untouched', () {
      final before = base();
      final result = apply(
          before,
          PlayConsumable(
              playId: 'p', targetVentureId: 'v1', deltas: const {'own': -500}),
          rng(), kContent);
      final v = result.state.ventures.single;
      expect(v.ebitdaCents, 600000);
      expect(v.multipleMilli, 6000);
      expect(v.netDebtCents, 0);
      expect(v.ownershipBp, 7500);
    });
  });

  // -----------------------------------------------------------------------
  // SECONDARY SALE (doc 02 §3.6; schemaVersion 9 — audit L3)
  // -----------------------------------------------------------------------
  group('secondary sale (sell Δownership at the live mark)', () {
    test('banks trunc(equity x bp / 10000) to cash and cuts ownership by bp',
        () {
      // EV = 1M x 8 = 8M; equity = 8M (no debt). Sell 1000 bp (10%) ->
      // proceeds = trunc(8M x 1000 / 10000) = 800k. own 10000 -> 9000.
      final v = venture(
          ebitdaCents: 1000000,
          multipleMilli: 8000,
          netDebtCents: 0,
          ownershipBp: 10000);
      final s = base(v: v, cashCents: 0);
      final r = apply(
          s,
          PlayConsumable(
              playId: 'p', deltas: const {}, targetVentureId: 'v1',
              secondaryBp: 1000),
          rng(),
          kContent);
      expect(r.events.any((e) => e.type == GameEventType.actionRejected),
          isFalse);
      expect(r.state.cashCents, 800000, reason: 'proceeds banked to cash');
      expect(r.state.ventures.single.ownershipBp, 9000,
          reason: 'sold 1000 bp of the stake');
      final sale =
          r.events.where((e) => e.type == GameEventType.secondarySale);
      expect(sale, hasLength(1));
      expect(sale.single.amount, 800000, reason: 'event carries proceeds');
      expect(r.state.playsHeld, isEmpty, reason: 'the play is consumed');
    });

    test('proceeds use the PRE-sale equity at a partial stake', () {
      // own 8000 (80%). EV 8M, equity 8M. Sell 1000 bp -> proceeds against
      // the full equity (the bp is of the COMPANY, not of the stake):
      // trunc(8M x 1000/10000) = 800k; own 8000 -> 7000.
      final v = venture(
          ebitdaCents: 1000000, multipleMilli: 8000, ownershipBp: 8000);
      final r = apply(
          base(v: v, cashCents: 0),
          PlayConsumable(
              playId: 'p', deltas: const {}, targetVentureId: 'v1',
              secondaryBp: 1000),
          rng(),
          kContent);
      expect(r.state.cashCents, 800000);
      expect(r.state.ventures.single.ownershipBp, 7000);
    });

    test('a fire-sale of NEGATIVE-equity paper banks \$0 but still moves '
        'ownership + emits the event', () {
      // EV 1M x 8 = 8M; netDebt 9M -> equity -1M (underwater). Selling
      // banks nothing (no value at the mark) but the stake still drops.
      final v = venture(
          ebitdaCents: 1000000,
          multipleMilli: 8000,
          netDebtCents: 9000000,
          ownershipBp: 10000);
      final r = apply(
          base(v: v, cashCents: 500000),
          PlayConsumable(
              playId: 'p', deltas: const {}, targetVentureId: 'v1',
              secondaryBp: 2000),
          rng(),
          kContent);
      expect(r.state.cashCents, 500000, reason: 'underwater -> \$0 proceeds');
      expect(r.state.ventures.single.ownershipBp, 8000,
          reason: 'still sold 2000 bp');
      final sale =
          r.events.where((e) => e.type == GameEventType.secondarySale);
      expect(sale, hasLength(1));
      expect(sale.single.amount, 0);
    });

    test('the bp is clamped to the held stake (cannot sell more than 100%)',
        () {
      // own 1000 (10%); ask to sell 5000 bp -> clamped to 1000, own -> 0.
      // proceeds use the clamped 1000 bp: EV 8M, equity 8M -> 800k.
      final v = venture(
          ebitdaCents: 1000000, multipleMilli: 8000, ownershipBp: 1000);
      final r = apply(
          base(v: v, cashCents: 0),
          PlayConsumable(
              playId: 'p', deltas: const {}, targetVentureId: 'v1',
              secondaryBp: 5000),
          rng(),
          kContent);
      expect(r.state.ventures.single.ownershipBp, 0);
      expect(r.state.cashCents, 800000,
          reason: 'proceeds on the clamped 1000 bp, not the asked 5000');
    });

    test('a secondary with no target rejects (value-identical)', () {
      final s = base(cashCents: 0);
      final r = apply(
          s,
          PlayConsumable(
              playId: 'p', deltas: const {}, secondaryBp: 1000),
          rng(),
          kContent);
      expect(r.events.single.type, GameEventType.actionRejected);
      expect(r.state, s, reason: 'a rejection mutates nothing');
    });
  });
}
