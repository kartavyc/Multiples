// describeAction tests (R13) — the autopsy "THE ROUND IT BROKE" human line
// (doc 02 §Q5). The headline regression this fixes: R9 flagged the S8 round
// row printing the raw engine summary (`cost 100000` — cents straight to the
// player). Every number here MUST be money/multiple-formatted.
//
// dart:io is TEST-ONLY (loading content for the card-name lines). No double.

import 'package:engine/actions.dart';
import 'package:engine/describe.dart';
import 'package:engine/model.dart';
import 'package:engine/serialize.dart';
import 'package:test/test.dart';

import 'helpers/content.dart';

void main() {
  group('describeAction (typed -> money-formatted line)', () {
    test('TakeDebt reads as leverage with FORMATTED money, not raw cents', () {
      final line = describeAction(
          const TakeDebt(ventureId: 'v1', proceedsCents: 500000, faceDebtCents: 575000),
          round: 6);
      expect(line, startsWith('Round 6: '));
      expect(line, contains('leverage'));
      expect(line, contains('\$5,750'), reason: 'faceDebt formatted');
      expect(line, contains('\$5,000'), reason: 'proceeds formatted');
      // THE FIX: no raw cents integers leak.
      expect(line, isNot(contains('500000')));
      expect(line, isNot(contains('575000')));
    });

    test('Reroll formats the fee (the exact R9 leak case: cost 100000)', () {
      final line = describeAction(const Reroll(costCents: 100000), round: 3);
      expect(line, contains('\$1,000'));
      expect(line, isNot(contains('100000')),
          reason: 'the "cost 100000" cents leak R9 flagged is gone');
    });

    test('ExitVenture formats the multiple', () {
      final line = describeAction(
          const ExitVenture(
              ventureId: 'v1', offerMultipleMilli: 6000, liveMarketMultipleMilli: 5900),
          round: 8);
      expect(line, contains('6.0x'));
      expect(line, contains('exited'));
      expect(line, isNot(contains('6000')));
    });

    test('weaves a venture display name when supplied', () {
      final line = describeAction(
          const ReinvestBaseline(ventureId: 'v1', amountCents: 200000),
          round: 2,
          ventureName: 'QUANTA');
      expect(line, contains('QUANTA'));
      expect(line, contains('\$2,000'));
      expect(line, isNot(contains('v1')), reason: 'the name replaced the id');
    });

    test('every one of the 12 action variants yields a clean, formatted line',
        () {
      final actions = <Action>[
        const StartVenture(
            ventureId: 'v1',
            sector: Sector.software,
            ebitdaCents: 600000,
            multipleMilli: 6000,
            priceCents: 1200000,
            faceDebtCents: 0),
        const RaiseEquity(ventureId: 'v1', raiseCents: 1000000),
        const TakeDebt(ventureId: 'v1', proceedsCents: 500000, faceDebtCents: 575000),
        const AcquireAddOn(
            targetVentureId: 'v1',
            addonSector: Sector.software,
            addonEbitdaCents: 100000,
            addonBuyMultipleMilli: 5000,
            addonFaceDebtCents: 0),
        const DividendRecap(ventureId: 'v1', recapPctBp: 1600),
        const ExitVenture(
            ventureId: 'v1', offerMultipleMilli: 6000, liveMarketMultipleMilli: 5900),
        const HireCEO(ventureId: 'v1', costCents: 300000),
        const SellPlay(playId: 'PLY_X', purchasePriceCents: 100000),
        const Reroll(costCents: 15000),
        PlayConsumable(playId: 'PLY_X', deltas: const {'cash': -100000}),
        const ReinvestBaseline(ventureId: 'v1', amountCents: 200000),
        const HirePartner(
            ventureId: 'v1',
            defId: 'PRT_SALES_LEAD',
            costCents: 500000,
            perRoundEbitdaCents: 150000),
      ];
      expect(actions, hasLength(12));
      // The leak detector: a long run of digits (>= 5) is a raw cents/milli
      // integer that escaped formatting. Formatted money has commas
      // ($1,200,000) or short suffixes ($1.2M); a bare 1200000 is the bug.
      final rawIntRun = RegExp(r'\d{5,}');
      for (final a in actions) {
        final line = describeAction(a, round: 4);
        expect(line, startsWith('Round 4: '));
        expect(line.length, greaterThan('Round 4: '.length));
        expect(rawIntRun.hasMatch(line), isFalse,
            reason: 'a raw cents/milli integer leaked into "$line"');
      }
    });
  });

  group('describeRunStep (the journal -> line)', () {
    test('dispatches a player ApplyStep through describeAction', () {
      final line = describeRunStep(
          const ApplyStep(Reroll(costCents: 100000)),
          round: 3);
      expect(line, contains('\$1,000'));
    });

    test('resolves a played card to its flavor NAME (not the raw id)', () {
      final line = describeRunStep(const PlayCardStep('ADD_SW_PLUGIN'),
          round: 4, content: kContent);
      final cardName = kContent.byId('ADD_SW_PLUGIN').name;
      expect(line, contains(cardName));
      expect(line, isNot(contains('ADD_SW_PLUGIN')),
          reason: 'the flavor name replaced the id');
    });

    test('a BuyShopStep reads as buying the named consumable', () {
      final line = describeRunStep(const BuyShopStep('PLY_MARKET_READ'),
          round: 1, content: kContent);
      expect(line, contains(kContent.byId('PLY_MARKET_READ').name));
      expect(line, contains('counter'));
    });

    test('names the target venture by displayName when in the holdings', () {
      final ventures = [
        const Venture(
          id: 'v1',
          sector: Sector.software,
          ebitdaCents: 600000,
          multipleMilli: 6000,
          netDebtCents: 0,
          ownershipBp: 10000,
        ),
      ];
      final line = describeRunStep(
          const PlayCardStep('ADD_SW_PLUGIN', targetVentureId: 'v1'),
          round: 4,
          content: kContent,
          ventures: ventures);
      expect(line, contains(ventures.single.displayName)); // QUANTA
    });

    test('system steps get a phase line (complete trail)', () {
      expect(describeRunStep(const OperateStep(), round: 1), contains('quarter'));
      expect(describeRunStep(const EndTurnStep(), round: 1), contains('books'));
      expect(
          describeRunStep(const DeadlineCheckStep(), round: 9), contains('deadline'));
    });
  });
}
