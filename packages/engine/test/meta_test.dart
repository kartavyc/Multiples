// The META LAYER tests (R13): founder backgrounds (§Q7), the realized-
// outcomes-only reputation formula (doc 02 §2 — paper net worth NEVER
// counts), metaLevel, and the strict RUN_OVER settleRun sequence with the
// docs/06 §5.1 double-settle guard.
//
// dart:io is TEST-ONLY (loading the real economy for initRun); the engine
// lib stays pure. cwd is the package root (wintest.bat cds there).
//
// All money is integer cents; no `double` anywhere.

import 'package:engine/init.dart';
import 'package:engine/meta.dart';
import 'package:engine/model.dart';
import 'package:engine/operate.dart' show playsGrantedForRound, playsPerRound;
import 'package:test/test.dart';

import 'helpers/content.dart';

void main() {
  group('founder backgrounds (§Q7; start-value table)', () {
    test('the table has the four documented backgrounds, Bootstrapper first',
        () {
      expect(kFounderBackgrounds.map((b) => b.id),
          [kBootstrapperBackgroundId, 'OPERATOR', 'VC_DARLING', 'DEALMAKER']);
    });

    test('Bootstrapper is the ALL-ZERO variant — today\'s exact \$56k seed',
        () {
      final bg = backgroundFor(kBootstrapperBackgroundId);
      expect(bg.startCashDeltaCents, 0);
      expect(bg.startOwnershipBpOverride, isNull,
          reason: 'Bootstrapper uses the economy ownership (economy-generic)');
      expect(bg.extraPlaysPerRound, 0);
      expect(bg.bonusPartnerEbitdaCents, 0);
      expect(bg.grantsFoundingPartner, isTrue);

      // initRun(default) is byte-identical to the pinned opening.
      final base = initRun(economy: kEconomyConfig);
      final boot =
          initRun(economy: kEconomyConfig, backgroundId: kBootstrapperBackgroundId);
      expect(boot, base);
      expect(base.netWorthCents, 5600000, reason: 'the pinned \$56,000 seed');
      expect(base.cashCents, 2000000);
      expect(base.ventures.single.ownershipBp, 10000);
      expect(base.ventures.single.partners.single,
          const PartnerEngine(defId: kFoundingPartnerDefId, perRoundEbitdaCents: 0));
    });

    test('Operator: free starting partner (+\$1,500/rd), \$8k less cash', () {
      final s = initRun(economy: kEconomyConfig, backgroundId: 'OPERATOR');
      expect(s.cashCents, 2000000 - 800000, reason: '\$20k - \$8k = \$12k');
      expect(s.ventures.single.ownershipBp, 10000);
      expect(s.ventures.single.partners.single.perRoundEbitdaCents, 150000,
          reason: 'the founding operator is a REAL engine, not 0-face');
    });

    test('VC Darling: +\$60k cash, pre-diluted to 80%', () {
      final s = initRun(economy: kEconomyConfig, backgroundId: 'VC_DARLING');
      expect(s.cashCents, 2000000 + 6000000, reason: '\$20k + \$60k = \$80k');
      expect(s.ventures.single.ownershipBp, 8000, reason: 'VCs took 20%');
      // Net worth reflects the dilution: only 80% of the seed equity is mine.
      // seed EV = trunc(600000*6000/1000)=3,600,000; equity 3,600,000;
      // mine = trunc(3,600,000*8000/10000)=2,880,000; + $80k cash.
      expect(s.netWorthCents, 2880000 + 8000000);
    });

    test('Dealmaker: +1 play/round dial, \$6k less cash', () {
      final bg = backgroundFor('DEALMAKER');
      expect(bg.extraPlaysPerRound, 1);
      final s = initRun(economy: kEconomyConfig, backgroundId: 'DEALMAKER');
      expect(s.cashCents, 2000000 - 600000, reason: '\$20k - \$6k = \$14k');
      // initRun stages NO plays for any background (the round layer grants).
      expect(s.playsRemaining, 0);
    });

    test('an unknown background id falls back to Bootstrapper DIALS '
        '(forward-compat); the raw id is still carried on the state', () {
      expect(backgroundFor('FROM_A_NEWER_BUILD').id, kBootstrapperBackgroundId);
      final s = initRun(economy: kEconomyConfig, backgroundId: 'NOPE');
      final boot = initRun(economy: kEconomyConfig);
      // The DIALS resolve to Bootstrapper (unknown -> fallback), so the
      // economic opening is byte-identical APART from the backgroundId field,
      // which faithfully carries the raw id the caller passed (so the save
      // round-trips it; backgroundFor re-applies the fallback every read).
      expect(s.backgroundId, 'NOPE',
          reason: 'the raw id is stored verbatim (save fidelity)');
      expect(s.copyWith(backgroundId: kBootstrapperBackgroundId), boot,
          reason: 'apart from the id, the unknown-background opening equals '
              'the Bootstrapper opening (the dials fell back)');
      // The plays grant also falls back to no-extra (Bootstrapper) for the
      // unknown id — the Dealmaker +1 is keyed off the resolved dials.
      expect(playsGrantedForRound(1, 'NOPE'), playsPerRound(1));
    });
  });

  group('reputation — realized outcomes ONLY (doc 02 §2)', () {
    test('a fair-priced clean exit scores its proceeds x ownership', () {
      // exitMultiple == sectorNorm -> inner factor 10000 -> proceeds 1:1,
      // then x ownership. SOFTWARE norm 14000.
      final outcomes = RunOutcomes(exits: [
        const ExitOutcome(
          proceedsCents: 1000000,
          exitMultipleMilli: 14000,
          sectorNormMilli: 14000,
          ownershipBp: 10000,
          clean: true,
        ),
      ]);
      expect(reputationFromOutcomes(outcomes), 1000000);
    });

    test('selling ABOVE the sector norm (a bubble exit) scores MORE', () {
      // exitMultiple 21000 vs norm 14000 -> factor 15000 -> 1.5x.
      final hot = RunOutcomes(exits: [
        const ExitOutcome(
          proceedsCents: 1000000,
          exitMultipleMilli: 21000,
          sectorNormMilli: 14000,
          ownershipBp: 10000,
          clean: true,
        ),
      ]);
      expect(reputationFromOutcomes(hot), 1500000);
    });

    test('dilution costs reputation: half ownership halves the exit rep', () {
      final diluted = RunOutcomes(exits: [
        const ExitOutcome(
          proceedsCents: 1000000,
          exitMultipleMilli: 14000,
          sectorNormMilli: 14000,
          ownershipBp: 5000,
          clean: true,
        ),
      ]);
      expect(reputationFromOutcomes(diluted), 500000);
    });

    test('a fire-sale (clean == false) earns ZERO reputation', () {
      final fireSale = RunOutcomes(exits: [
        const ExitOutcome(
          proceedsCents: 1000000,
          exitMultipleMilli: 1000,
          sectorNormMilli: 14000,
          ownershipBp: 10000,
          clean: false,
        ),
      ]);
      expect(reputationFromOutcomes(fireSale), 0,
          reason: 'paper-to-cash fire-sales bank money but not reputation');
    });

    test('secondaries + dividends contribute at their (lower) rates', () {
      final outcomes = RunOutcomes(
        secondaryProceedsCents: 1000000, // x50% = 500000
        dividendBankedCents: 1000000, // x25% = 250000
      );
      expect(reputationFromOutcomes(outcomes), 500000 + 250000);
    });

    test('reputation comes ONLY from the three realized channels — never '
        'from a paper net worth', () {
      // An empty tally (a run that died holding huge PAPER net worth) yields
      // zero reputation. There is no GameState/net-worth input to the
      // formula by design.
      expect(reputationFromOutcomes(RunOutcomes()), 0);
    });
  });

  group('metaLevel (derived reputation tier)', () {
    test('is a step function over the thresholds', () {
      expect(metaLevelFor(0), 0);
      expect(metaLevelFor(499999), 0);
      expect(metaLevelFor(500000), 1);
      expect(metaLevelFor(2000000), 2);
      expect(metaLevelFor(50000000), 5);
      expect(metaLevelFor(999999999), 5, reason: 'saturates at the top');
    });
  });

  group('settleRun (doc 02 §2 RUN_OVER + docs/06 §5.1 guard)', () {
    GameState deadRun({int tier = 2, DeathCause? death = DeathCause.bankruptcy}) =>
        GameState(
          ventures: const [],
          cashCents: -1,
          tier: tier,
          phase: PhaseId.runOver,
          death: death,
        );

    test('settles reputation, furthestTier, lastDeathCause, runsPlayed, '
        'cleanExits, and the runId guard', () {
      final meta = MetaState();
      final outcomes = RunOutcomes(exits: [
        const ExitOutcome(
          proceedsCents: 1000000,
          exitMultipleMilli: 14000,
          sectorNormMilli: 14000,
          ownershipBp: 10000,
          clean: true,
        ),
      ]).withDividend(400000); // +100000 rep

      final settled = settleRun(meta,
          finishedRun: deadRun(tier: 3), runId: 'r_abc', outcomes: outcomes);
      expect(settled.reputation, 1000000 + 100000);
      expect(settled.metaLevel, metaLevelFor(1100000));
      expect(settled.furthestTierReached, 3);
      expect(settled.lastDeathCause, DeathCause.bankruptcy);
      expect(settled.runsPlayed, 1);
      expect(settled.cleanExits, 1);
      expect(settled.lastSettledRunId, 'r_abc');
    });

    test('a WIN records no death cause but still counts the run + reputation',
        () {
      final meta = MetaState(lastDeathCause: DeathCause.missedDeadline);
      final won = GameState(
        ventures: const [],
        cashCents: 100000000000,
        tier: 4,
        won: true,
        phase: PhaseId.runOver,
      );
      final settled = settleRun(meta,
          finishedRun: won, runId: 'r_win', outcomes: RunOutcomes());
      expect(settled.lastDeathCause, isNull,
          reason: 'a win clears the death-cause callback (it did not die)');
      expect(settled.furthestTierReached, 4);
      expect(settled.runsPlayed, 1);
    });

    test('furthestTier never regresses', () {
      final meta = MetaState(furthestTierReached: 4);
      final settled = settleRun(meta,
          finishedRun: deadRun(tier: 1), runId: 'r1', outcomes: RunOutcomes());
      expect(settled.furthestTierReached, 4, reason: 'max(), never down');
    });

    test('the double-settle guard: re-settling the SAME runId is a no-op '
        '(docs/06 §5.1 — reputation committed exactly once)', () {
      final meta = MetaState();
      final outcomes = RunOutcomes().withDividend(400000); // +100000 rep
      final once = settleRun(meta,
          finishedRun: deadRun(), runId: 'r_dup', outcomes: outcomes);
      expect(once.reputation, 100000);
      expect(once.runsPlayed, 1);

      // A crash after the meta write but before deleting run.json leaves an
      // orphan run.json; the next boot re-settles the SAME runId -> no-op.
      final twice = settleRun(once,
          finishedRun: deadRun(), runId: 'r_dup', outcomes: outcomes);
      expect(twice, once, reason: 'identical meta — settlement is idempotent');
      expect(twice.reputation, 100000, reason: 'NOT doubled');
      expect(twice.runsPlayed, 1, reason: 'NOT incremented twice');
    });

    test('a DIFFERENT runId after a settle accrues normally (next run)', () {
      final meta = MetaState();
      final first = settleRun(meta,
          finishedRun: deadRun(), runId: 'r1',
          outcomes: RunOutcomes().withDividend(400000));
      final second = settleRun(first,
          finishedRun: deadRun(), runId: 'r2',
          outcomes: RunOutcomes().withDividend(400000));
      expect(second.runsPlayed, 2);
      expect(second.reputation, 200000);
      expect(second.lastSettledRunId, 'r2');
    });

    test('settling with no outcomes (a run that realized nothing) adds 0 '
        'reputation but still counts the run', () {
      final settled = settleRun(MetaState(),
          finishedRun: deadRun(), runId: 'r_nada');
      expect(settled.reputation, 0);
      expect(settled.runsPlayed, 1);
      expect(settled.cleanExits, 0);
    });
  });

  // =========================================================================
  // R17 — THE UNLOCK LADDER (GDD §Q7: access never advantage; unlock order
  // == curriculum order)
  // =========================================================================
  group('the unlock ladder (applyUnlocks; GDD §Q7 curriculum order)', () {
    test('a fresh meta has only the base 4 sectors, BOOTSTRAPPER, no decks',
        () {
      final m = MetaState();
      expect(m.unlockedCards, isEmpty);
      expect(m.unlockedBackgrounds, [kBootstrapperBackgroundId]);
      expect(m.unlockedSectors, [
        Sector.software,
        Sector.services,
        Sector.retail,
        Sector.industrial,
      ]);
      expect(m.hardModes, isEmpty);
      expect(endlessUnlocked(m), isFalse);
    });

    test('reach T2 -> the raise/operating deck + OPERATOR bg', () {
      final m = applyUnlocks(MetaState(furthestTierReached: 2),
          gameBeaten: false);
      expect(m.unlockedCards, containsAll(kTier2UnlockCards));
      expect(m.unlockedCards, isNot(contains('ADD_IND_SUPPLIER')),
          reason: 'T3 deck stays locked until T3 is reached');
      expect(m.unlockedCards, isNot(contains('FIN_LBO_LOAN')));
      expect(m.unlockedBackgrounds, contains(kOperatorBackgroundId));
      expect(m.unlockedBackgrounds, isNot(contains(kVcDarlingBackgroundId)));
      // No win yet -> no sectors / hard modes / endless.
      expect(m.unlockedSectors, hasLength(4));
      expect(m.hardModes, isEmpty);
      expect(endlessUnlocked(m), isFalse);
    });

    test('reach T3 -> the exit/empire deck + VC_DARLING bg (T2 deck stays)',
        () {
      final m = applyUnlocks(MetaState(furthestTierReached: 3),
          gameBeaten: false);
      expect(m.unlockedCards, containsAll(kTier2UnlockCards));
      expect(m.unlockedCards, containsAll(kTier3UnlockCards));
      expect(m.unlockedCards, isNot(contains('FIN_LBO_LOAN')));
      expect(m.unlockedBackgrounds, contains(kVcDarlingBackgroundId));
      expect(m.unlockedBackgrounds, isNot(contains(kDealmakerBackgroundId)));
    });

    test('reach T4 -> the acquirer/LBO deck + DEALMAKER bg', () {
      final m = applyUnlocks(MetaState(furthestTierReached: 4),
          gameBeaten: false);
      expect(m.unlockedCards, containsAll(kTier4UnlockCards));
      expect(m.unlockedBackgrounds, contains(kDealmakerBackgroundId));
      // Reaching T4 is NOT beating the game — still no endless/sectors.
      expect(endlessUnlocked(m), isFalse);
    });

    test('BEAT GAME -> Endless + hard modes + the 2 post-launch sectors', () {
      final m = applyUnlocks(MetaState(furthestTierReached: 4),
          gameBeaten: true);
      expect(m.unlockedSectors, containsAll(kPostLaunchSectors));
      expect(m.unlockedSectors, contains(Sector.consumer));
      expect(m.unlockedSectors, contains(Sector.media));
      expect(m.hardModes, equals(kBeatGameHardModes));
      expect(endlessUnlocked(m), isTrue);
    });

    test('applyUnlocks is ADDITIVE + IDEMPOTENT (access never regresses)', () {
      final once =
          applyUnlocks(MetaState(furthestTierReached: 4), gameBeaten: true);
      final twice = applyUnlocks(once, gameBeaten: true);
      expect(twice, once, reason: 'calling it again changes nothing');
      // Even a regressed furthest tier never strips already-earned access.
      final regressed =
          applyUnlocks(once.copyWith(furthestTierReached: 1), gameBeaten: false);
      expect(regressed.unlockedCards, containsAll(kTier4UnlockCards),
          reason: 'unlocks are append-only');
      expect(endlessUnlocked(regressed), isTrue,
          reason: 'beating the game stays beaten');
    });

    test('unlock sets are in a STABLE order (deterministic save round-trip)',
        () {
      final a =
          applyUnlocks(MetaState(furthestTierReached: 4), gameBeaten: true);
      final b =
          applyUnlocks(MetaState(furthestTierReached: 4), gameBeaten: true);
      expect(a.unlockedCards, b.unlockedCards);
      expect(a.unlockedSectors, b.unlockedSectors);
      // cards in curriculum order: T2 block, then T3, then T4.
      expect(a.unlockedCards,
          [...kTier2UnlockCards, ...kTier3UnlockCards, ...kTier4UnlockCards]);
    });

    test('the cosmetic title ladder tracks meta level (flair, never power)',
        () {
      expect(titlesForLevel(0), isEmpty);
      expect(titlesForLevel(1), ['ANALYST']);
      expect(titlesForLevel(3), ['ANALYST', 'ASSOCIATE', 'PRINCIPAL']);
      expect(titlesForLevel(5), kTitleLadder);
      expect(titlesForLevel(99), kTitleLadder, reason: 'clamps at the top');
    });
  });

  group('settleRun WIRES the unlock ladder (R17)', () {
    test('a T2-reaching run earns the raise deck + OPERATOR through settle',
        () {
      final dead = GameState(
        ventures: const [],
        cashCents: -1,
        tier: 2,
        phase: PhaseId.runOver,
        death: DeathCause.bankruptcy,
      );
      final settled =
          settleRun(MetaState(), finishedRun: dead, runId: 'r_t2');
      expect(settled.furthestTierReached, 2);
      expect(settled.unlockedCards, containsAll(kTier2UnlockCards));
      expect(settled.unlockedBackgrounds, contains(kOperatorBackgroundId));
      expect(endlessUnlocked(settled), isFalse,
          reason: 'a T2 death is not beating the game');
    });

    test('a WIN unlocks endless + the post-launch sectors, persistently', () {
      final won = GameState(
        ventures: const [],
        cashCents: 100000000000,
        tier: 4,
        won: true,
        phase: PhaseId.runOver,
      );
      final settled =
          settleRun(MetaState(), finishedRun: won, runId: 'r_win');
      expect(endlessUnlocked(settled), isTrue);
      expect(settled.unlockedSectors, containsAll(kPostLaunchSectors));
      expect(settled.hardModes, equals(kBeatGameHardModes));
      // A LATER losing run (different runId) keeps the beat-game unlocks
      // (gameBeaten is persistent via endlessUnlocked(meta)).
      final laterLoss = GameState(
        ventures: const [],
        cashCents: -1,
        tier: 1,
        phase: PhaseId.runOver,
        death: DeathCause.bankruptcy,
      );
      final after = settleRun(settled, finishedRun: laterLoss, runId: 'r2');
      expect(endlessUnlocked(after), isTrue, reason: 'stays beaten');
      expect(after.unlockedSectors, containsAll(kPostLaunchSectors));
    });

    test('the double-settle guard still holds with unlocks (idempotent)', () {
      final won = GameState(
        ventures: const [],
        cashCents: 1,
        tier: 4,
        won: true,
        phase: PhaseId.runOver,
      );
      final once = settleRun(MetaState(), finishedRun: won, runId: 'r_dup2');
      final twice = settleRun(once, finishedRun: won, runId: 'r_dup2');
      expect(twice, once, reason: 'settling twice is a clean no-op');
    });
  });
}
