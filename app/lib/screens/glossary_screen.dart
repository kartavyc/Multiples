/// TIPS · GLOSSARY (R22 tutorial design): an always-available reference for
/// every finance term the game throws at you — one snarky-but-correct line
/// each, grouped by the loop (the math you read → the moves you make → how you
/// cash out). Reached from the title menu; pure reference, no game logic.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class _Term {
  const _Term(this.term, this.def);
  final String term;
  final String def;
}

class _Group {
  const _Group(this.title, this.terms);
  final String title;
  final List<_Term> terms;
}

const List<_Group> _kGlossary = [
  _Group('THE MATH (what a company is worth)', [
    _Term('EBITDA',
        'A company’s core profit before the boring deductions. Your growth engine. It compounds.'),
    _Term('MULTIPLE',
        'How many years of profit buyers will pay — the market’s hype score. EV = EBITDA × Multiple.'),
    _Term('ENTERPRISE VALUE (EV)',
        'What the whole company is worth: EBITDA × Multiple, debt and all.'),
    _Term('NET DEBT',
        'Borrowed money minus cash on hand. Subtracted from EV when figuring your stake.'),
    _Term('NET WORTH',
        'Your slice of every company (EV − net debt, times ownership) plus cash. The high score. Paper.'),
    _Term('CASH',
        'Real, spendable money. Doesn’t swing with the market. The only thing that pays the bills.'),
  ]),
  _Group('THE MOVES (how you build)', [
    _Term('ADD-ON',
        'A small company you bolt onto a bigger one you own. The Lego brick of empire-building.'),
    _Term('PLATFORM',
        'Your flagship company that swallows add-ons whole — the mothership with the good multiple.'),
    _Term('ARBITRAGE',
        'Buy at a low multiple, revalue at your higher one, pocket the gap. Legal alchemy. The whole game.'),
    _Term('LEVERAGE (DEBT)',
        'Borrow to buy bigger than your cash. Multiplies your wins — and your faceplants. Interest never sleeps.'),
    _Term('DILUTION (RAISE EQUITY)',
        'Sell new shares for cash now. Same pie, more forks — your slice quietly gets thinner.'),
    _Term('DIVIDEND RECAP',
        'Borrow against a company to pay yourself cash while still owning it. Eat the goose, keep the eggs.'),
    _Term('REROLL',
        'Swap your current hand of plays for fresh ones, at a cost. A dead hand costs more.'),
    _Term('MARKET TEMP',
        'HOT lifts everyone’s multiples; COLD crushes them and spikes interest rates. You don’t control it.'),
  ]),
  _Group('THE CASH-OUT (how you win)', [
    _Term('EXIT',
        'Sell a company so its paper value becomes real, spendable cash. Timing is everything.'),
    _Term('TRADE SALE / IPO / SPIN-OFF / EARN-OUT',
        'Four ways to exit: sell to a buyer, list publicly, split a piece out, or get paid on future performance.'),
    _Term('REPUTATION',
        'Meta-progression from CLEAN exits. Carries across runs. Burn people and the next deal costs more.'),
    _Term('DEADLINE / PACE',
        'Each tier has a round limit. Clear its net-worth bar in time or the run’s over. The pace meter warns you.'),
    _Term('RESEED',
        'Clear a tier and the board refreshes with bigger companies and pricier mistakes. Onward and upmarket.'),
    _Term('THE LADDER',
        '\$1M → \$10M → \$100M → \$1B (the win). Tier 5 is endless — score-chase until the escalating bar buries you.'),
  ]),
];

/// The glossary screen. [onBack] returns to wherever it was opened from.
class GlossaryScreen extends StatelessWidget {
  /// Builds the glossary; [onBack] handles the BACK key.
  const GlossaryScreen({super.key, required this.onBack});

  /// BACK handler.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBezel,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: kBg,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header bar.
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: kLine)),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onBack,
                              child: Container(
                                key: const Key('glossaryBack'),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  border: Border.all(color: kFaint),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text('◂ BACK',
                                    style: labelStyle(
                                        size: 9, color: kDim, tracking: 1.5)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('TIPS · GLOSSARY',
                                style: labelStyle(
                                    size: 12,
                                    color: kAccentHi,
                                    tracking: 2)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          key: const Key('glossaryList'),
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                          children: [
                            for (final g in _kGlossary) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 10),
                                child: Text(g.title,
                                    style: labelStyle(
                                        size: 10,
                                        color: kGain,
                                        tracking: 1.5)),
                              ),
                              for (final t in g.terms)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(t.term,
                                          style: labelStyle(
                                              size: 10,
                                              color: kAccentHi,
                                              tracking: 1)),
                                      const SizedBox(height: 3),
                                      Text(t.def,
                                          style: bodyStyle(size: 12, color: kFg)
                                              .copyWith(height: 1.4)),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const CrtOverlay(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
