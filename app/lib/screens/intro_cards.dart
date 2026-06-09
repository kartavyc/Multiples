/// The first-run INTRO CARDS (R22 tutorial design): a short, swipeable
/// full-screen opener shown once at the start of a tutorial run. It teaches
/// the ABSTRACT stuff you can't discover by playing — the one equation, the
/// loop, the goal — in the game's snarky voice, then hands off to the in-run
/// coachmarks (tutorial.dart) which teach on the live beats.
///
/// PURE UI: no game logic. [onDone] fires when the player finishes or skips;
/// the run screen then drops the gate and the run begins underneath.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// One opener card: a Silkscreen heading + a couple of body lines.
class _Card {
  const _Card(this.heading, this.lines);
  final String heading;
  final List<String> lines;
}

/// THE OPENER SCRIPT — 8 cards, synthesized snark + real facts, each tight.
const List<_Card> _kCards = [
  _Card("YOU'RE A DEALMAKER", [
    'Buy companies. Grow them. Flip them.',
    'Turn pocket change into \$1,000,000,000 — without becoming a cautionary podcast.',
  ]),
  _Card('ONE FORMULA RUNS EVERYTHING', [
    'A company is worth  EBITDA × MULTIPLE.',
    'Profit, times how much the market believes in it. Yes, vibes are a number now.',
  ]),
  _Card('TWO KINDS OF MONEY', [
    'CASH is real and spends. NET WORTH is paper — it swings with the market and can vanish.',
    'WeWork once invented “community-adjusted EBITDA.” Don’t be WeWork.',
  ]),
  _Card('EVERY ROUND, FOUR BEATS', [
    'OPERATE  (your companies earn)  →  ACT  (make your moves)',
    '→  SHOP  (buy cards)  →  DEADLINE  (clear the bar, or you’re out).',
  ]),
  _Card('THE CHEAT CODE', [
    'Buy a small company cheap, fold it into a bigger one.',
    'It instantly inherits the higher multiple. Free value, legally. That gap is the whole game.',
  ]),
  _Card('TWO WAYS TO GET BIGGER (OR BROKE)', [
    'DEBT buys above your cash — but interest accrues every round, forever.',
    'Raising EQUITY hands you cash but shrinks your ownership. Pick your poison.',
  ]),
  _Card('PAPER ISN’T MONEY UNTIL YOU EXIT', [
    'Sell a company — trade sale, IPO, spin-off — to turn paper into spendable cash.',
    'Clean exits build your reputation. Pulling a Theranos does not.',
  ]),
  _Card('THE CLIMB', [
    '\$1M → \$10M → \$100M → \$1B. Beat the clock at each tier.',
    'We’ll point things out as you go. Now — let’s make a deal.',
  ]),
];

/// The swipe-through opener. Dim full-stage scrim, a bordered terminal card,
/// page dots, NEXT / START, and an always-present SKIP.
class IntroCards extends StatefulWidget {
  /// Builds the opener; [onDone] fires on finish or skip.
  const IntroCards({super.key, required this.onDone});

  /// Called when the player finishes the last card or taps SKIP.
  final VoidCallback onDone;

  @override
  State<IntroCards> createState() => _IntroCardsState();
}

class _IntroCardsState extends State<IntroCards> {
  final PageController _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _kCards.length - 1) {
      widget.onDone();
      return;
    }
    _page.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _kCards.length - 1;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xF207090C),
        child: SafeArea(
          child: Column(
            key: const Key('introCards'),
            children: [
              // SKIP — top-right, always reachable.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 10, 0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDone,
                    child: Container(
                      key: const Key('introSkip'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: kFaint),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('SKIP ✕',
                          style:
                              labelStyle(size: 8, color: kDim, tracking: 1.5)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _kCards.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _CardView(card: _kCards[i]),
                ),
              ),
              // Page dots.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _kCards.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? kAccent : kFaint,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // NEXT / START.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _next,
                  child: Container(
                    key: const Key('introNext'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12324A),
                      border: Border.all(color: kAccent, width: 2),
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: const [
                        BoxShadow(color: Color(0x4D4DA3FF), blurRadius: 14),
                      ],
                    ),
                    child: Center(
                      child: Text(last ? "LET'S MAKE A DEAL ▸" : 'NEXT ▸',
                          style: labelStyle(
                              size: 12, color: kAccentHi, tracking: 2)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card});
  final _Card card;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
          decoration: BoxDecoration(
            color: const Color(0xF210151B),
            border: Border.all(color: kAccent, width: 2),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(color: Color(0x334DA3FF), blurRadius: 18),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.heading,
                  style: labelStyle(size: 15, color: kAccentHi, tracking: 1.5)
                      .copyWith(height: 1.3)),
              const SizedBox(height: 16),
              for (final line in card.lines) ...[
                Text(line,
                    style: bodyStyle(size: 14, color: kFg)
                        .copyWith(height: 1.45)),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
