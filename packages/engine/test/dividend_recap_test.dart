// THE CANONICAL DIVIDEND RECAP (doc 01 §7.7; economy-model.json
// formulas.dividendRecap "cash += trunc(EV * recapPct); netDebt +=
// trunc(EV * recapPct)"; constants.recapPct = 0.16 since the R12 tune —
// dealflow.dart kRecapPctBp documents the turn) — the R12 balance
// round's canon reconciliation.
//
// Before R12 the engine charged PLY_DIVIDEND_RECAP's card faces (+$30k
// cash / +$30k debt, fixed) — which neither scales with EV nor matches
// the doc's formula, so the "primary greed-death dial" (economy
// tuningKnobs.recapPct) was inert: the full-model harness measured greedy
// bankruptcy at ~1.6% against the doc 01 §11 [8%, 12%] gate. The glue now
// strips the illustrative faces and routes the pull through
// PlayConsumable.recapBp = kRecapPctBp; apply computes against the live
// EV at resolve time. (The action-level pull tests below pass an explicit
// recapBp — they pin the FORMULA, not the dial.)
//
// All money is integer cents; no floating point anywhere in this test.

import 'package:engine/actions.dart';
import 'package:engine/apply.dart';
import 'package:engine/content.dart' show CardType;
import 'package:engine/dealflow.dart';
import 'package:engine/model.dart';
import 'package:engine/rng.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

void main() {
  GameState fixture({
    int ebitdaCents = 1000000,
    int multipleMilli = 8000,
    int netDebtCents = 0,
    int cashCents = 500000,
  }) =>
      GameState(
        ventures: [
          Venture(
            id: 'v1',
            sector: Sector.software,
            ebitdaCents: ebitdaCents,
            multipleMilli: multipleMilli,
            netDebtCents: netDebtCents,
            ownershipBp: 10000,
            roundsNeglected: 2,
          ),
        ],
        cashCents: cashCents,
        round: 3,
        tier: 2,
        phase: PhaseId.act,
        playsRemaining: 3,
        playsHeld: const ['PLY_DIVIDEND_RECAP'],
      );

  group('actionForCard maps PLY_DIVIDEND_RECAP onto the canonical recap',
      () {
    test('the illustrative fixed faces are STRIPPED; recapBp = 2000 '
        '(recapPct 0.20 — R20b re-tune from 0.16 for the wider pool)', () {
      final card = kContent.byId('PLY_DIVIDEND_RECAP');
      // The card still carries the faces (content untouched — they are
      // doc 04 §0 human-facing summary)...
      expect(card.deltas['cash'], 3000000);
      expect(card.deltas['netDebt'], 3000000);
      // ...but the glue replaces them with the resolve-time formula.
      final action =
          actionForCard(card, targetVentureId: 'v1') as PlayConsumable;
      expect(action.recapBp, kRecapPctBp);
      expect(kRecapPctBp, 2000);
      expect(action.deltas.containsKey('cash'), isFalse,
          reason: 'the fixed face must never be charged');
      expect(action.deltas.containsKey('netDebt'), isFalse);
    });

    test('no other consumable carries a recapBp', () {
      for (final card in kContent.cards) {
        if (card.type != CardType.consumable) continue;
        if (card.id == 'PLY_DIVIDEND_RECAP') continue;
        final action =
            actionForCard(card, targetVentureId: 'v1') as PlayConsumable;
        expect(action.recapBp, 0, reason: card.id);
      }
    });
  });

  group('the resolve-time pull (doc 01 §7.7 exactly)', () {
    PlayConsumable recap({String? target = 'v1'}) => PlayConsumable(
          playId: 'PLY_DIVIDEND_RECAP',
          deltas: const {},
          targetVentureId: target,
          recapBp: 3000,
        );

    test('cash += trunc(EV x 30%) and the SAME amount lands as new debt '
        'on the target', () {
      final s = fixture(); // EV = 1,000,000 x 8000 / 1000 = 8,000,000
      final r = apply(s, recap(), SplitMix64Rng(1), kContent);
      const pull = 2400000; // trunc(8,000,000 x 3000 / 10000)
      expect(r.state.cashCents, 500000 + pull);
      expect(r.state.ventures.single.netDebtCents, pull);
      final e = r.events
          .singleWhere((e) => e.type == GameEventType.dividendRecap);
      expect(e.amount, pull);
      expect(e.ventureId, 'v1');
    });

    test('the pull truncates toward zero (division LAST)', () {
      // EV = 333 x 8000 / 1000 = 2664; pull = trunc(2664 x 0.3) = 799.
      final s = fixture(ebitdaCents: 333);
      final r = apply(s, recap(), SplitMix64Rng(1), kContent);
      expect(r.state.cashCents, 500000 + 799);
      expect(r.state.ventures.single.netDebtCents, 799);
    });

    test('the pull scales with the LIVE EV — the greed dial compounds, '
        'unlike the old fixed face', () {
      final small = apply(fixture(ebitdaCents: 100000), recap(),
          SplitMix64Rng(1), kContent);
      final big = apply(fixture(ebitdaCents: 10000000), recap(),
          SplitMix64Rng(1), kContent);
      expect(small.state.ventures.single.netDebtCents, 240000);
      expect(big.state.ventures.single.netDebtCents, 24000000,
          reason: '100x the EBITDA = 100x the pull');
    });

    test('recap targets: no target / unknown target reject with '
        'venture_not_found and NO state change', () {
      for (final target in [null, 'ghost']) {
        final s = fixture();
        final rng = SplitMix64Rng(1);
        final r = apply(s, recap(target: target), rng, kContent);
        expect(r.events.single.type, GameEventType.actionRejected);
        expect(r.events.single.reason, 'venture_not_found');
        expect(r.state, s);
        expect(rng.cursor, 0);
      }
    });

    test('a worthless (non-positive-EV) venture pulls NOTHING — value is '
        'never conjured from a dead EV', () {
      final s = fixture(ebitdaCents: 0);
      final r = apply(s, recap(), SplitMix64Rng(1), kContent);
      expect(r.state.cashCents, 500000);
      expect(r.state.ventures.single.netDebtCents, 0);
      expect(
          r.events.any((e) => e.type == GameEventType.dividendRecap),
          isFalse);
      expect(r.state.playsHeld, isEmpty,
          reason: 'the play is still consumed — a dud recap is spent');
    });

    test('the recap is a targeting Act: roundsNeglected resets', () {
      final r = apply(fixture(), recap(), SplitMix64Rng(1), kContent);
      expect(r.state.ventures.single.roundsNeglected, 0);
    });

    test('§7 reconciliation: dNetWorth == dCash + dEquityStake == 0 net '
        '(the pull converts paper EV into cash 1:1 via new debt)', () {
      final s = fixture();
      final r = apply(s, recap(), SplitMix64Rng(1), kContent);
      // own = 100%: equity falls by the pull, cash rises by the pull.
      expect(r.state.netWorthCents, s.netWorthCents,
          reason: 'a recap moves value paper -> pocket, never mints it');
    });

    test('draws NOTHING and replays deterministically', () {
      final rng = SplitMix64Rng(7);
      final r1 = apply(fixture(), recap(), rng, kContent);
      expect(rng.cursor, 0);
      final r2 = apply(fixture(), recap(), SplitMix64Rng(7), kContent);
      expect(r1.state, r2.state);
    });

    test('end to end through the held-play path: buy in SHOP, play in '
        'ACT', () {
      // T2 SHOP holds the recap (tierGate 2): buy it, then play it.
      var s = fixture().copyWith(
        phase: PhaseId.shop,
        playsHeld: const <String>[],
        shopOffers: const ['PLY_DIVIDEND_RECAP'],
      );
      final bought = buyShopOffer(s, 'PLY_DIVIDEND_RECAP', kContent);
      expect(
          bought.events
              .any((e) => e.type == GameEventType.actionRejected),
          isFalse);
      s = bought.state.copyWith(phase: PhaseId.act);
      expect(s.playsHeld, contains('PLY_DIVIDEND_RECAP'));
      final card = kContent.byId('PLY_DIVIDEND_RECAP');
      final r = apply(s, actionForCard(card, targetVentureId: 'v1'),
          SplitMix64Rng(1), kContent);
      expect(r.events.any((e) => e.type == GameEventType.dividendRecap),
          isTrue);
      expect(r.state.ventures.single.netDebtCents, 1600000,
          reason: 'the canonical 20%-of-EV pull (8e6 x 2000/10000 — R20b '
              're-tune), not the \$30k face');
    });
  });
}
