/// S9 — THE DESK (mockup #scr-s9, docs/05 meta): the between-runs meta
/// screen. TRACK RECORD (rep level + total + next-unlock line) off MetaState;
/// the founder-background picker (§Q7 kFounderBackgrounds — perk + constraint
/// face, locked when not in meta.unlockedBackgrounds); UNLOCKED counts; the
/// cosmetic title; START RUN (with the chosen background). Reachable from the
/// title and after a run (victory/autopsy -> THE DESK).
///
/// LOGIC-FREE: every number is read off [MetaState] or the engine's pure meta
/// tables (kFounderBackgrounds / kMetaLevelThresholds / metaLevelFor); the
/// screen never computes economy. Selecting a background sets the id START RUN
/// hands to the controller (which feeds initRun).
library;

import 'package:engine/meta.dart';
import 'package:engine/model.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Total cards / sectors in the full game (mockup `22/35 · 4/6`): the
/// denominators the UNLOCKED row counts against. Display constants (the
/// content roadmap target, not engine state).
const int _kTotalCards = 35;
const int _kTotalSectors = 6;

/// The S9 meta screen.
class DeskScreen extends StatefulWidget {
  /// Builds THE DESK over [meta]; [onStartRun] opens a run with the chosen
  /// background id; [onBack] returns to the title.
  const DeskScreen({
    super.key,
    required this.meta,
    required this.onStartRun,
    required this.onBack,
    this.onSettings,
  });

  /// The durable Track Record (read-only here).
  final MetaState meta;

  /// START RUN handler — receives the selected founder background id.
  final void Function(String backgroundId) onStartRun;

  /// Back-to-title handler (the gear/back affordance).
  final VoidCallback onBack;

  /// SETTINGS handler (R20 gear); null hides the affordance.
  final VoidCallback? onSettings;

  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> {
  /// The selected founder background id (defaults to BOOTSTRAPPER).
  String _selected = kBootstrapperBackgroundId;

  bool _unlocked(FounderBackground bg) =>
      widget.meta.unlockedBackgrounds.contains(bg.id);

  /// The next reputation threshold above the current total, or null if all
  /// thresholds are crossed (the "NEXT UNLOCK n: ..." line, mockup).
  int? get _nextThreshold {
    for (final t in kMetaLevelThresholds) {
      if (widget.meta.reputation < t) return t;
    }
    return null;
  }

  /// Rep-bar fill: the current level's progress toward the next threshold,
  /// discretized onto 15 white LEDs (mockup S9 segbar, 15 segs). At max level
  /// the bar reads full.
  List<SegState> get _repSegs {
    const total = 15;
    final next = _nextThreshold;
    if (next == null) {
      return List.filled(total, SegState.onWhite);
    }
    // Previous threshold (the floor of this level's band); 0 below L1.
    var prev = 0;
    for (final t in kMetaLevelThresholds) {
      if (t <= widget.meta.reputation) prev = t;
    }
    final span = next - prev;
    final into = widget.meta.reputation - prev;
    final lit = span <= 0 ? 0 : (into * total) ~/ span;
    return [
      for (var i = 0; i < total; i++)
        i < lit ? SegState.onWhite : SegState.off,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meta;
    final level = metaLevelFor(m.reputation);
    final next = _nextThreshold;
    return Scaffold(
      backgroundColor: kBezel,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: kBg,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      key: const Key('desk'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _head(),
                        const SizedBox(height: 10),
                        _trackRecord(level, m.reputation, next),
                        const SizedBox(height: 14),
                        _sectionHead('START AS · FOUNDER BACKGROUND'),
                        const SizedBox(height: 6),
                        _founderGrid(),
                        const SizedBox(height: 10),
                        _unlockedRow(m),
                        const SizedBox(height: 6),
                        _titleRow(m),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: ChunkyKey(
                                key: const Key('startRun'),
                                icon: '▶',
                                label: 'START RUN',
                                variant: ChunkyKeyVariant.primary,
                                onTap: () => widget.onStartRun(_selected),
                              ),
                            ),
                            if (widget.onSettings != null) ...[
                              const SizedBox(width: 7),
                              SizedBox(
                                width: 64,
                                child: ChunkyKey(
                                  key: const Key('deskSettings'),
                                  icon: '⚙',
                                  label: 'SET',
                                  onTap: widget.onSettings,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
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

  Widget _head() => GestureDetector(
        onTap: widget.onBack,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kLine, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('THE DESK',
                  style: TextStyle(
                    fontFamily: kFontLabel,
                    fontSize: 13,
                    letterSpacing: 3,
                    color: kFg,
                    shadows: kGlowFg,
                  )),
              Text('✕',
                  key: const Key('deskBack'),
                  style: TextStyle(
                      fontFamily: kFontNum, fontSize: 13, color: kFaint)),
            ],
          ),
        ),
      );

  Widget _trackRecord(int level, int rep, int? next) => Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: kPanel,
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('TRACK RECORD',
                    style: labelStyle(size: 9, tracking: 1.5)),
                Text('Lv $level · ${_fmtRep(rep)} REP',
                    key: const Key('trackRecord'),
                    style: numStyle(19)),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(height: 12, child: SegBar(segs: _repSegs)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: bodyStyle(size: 11, color: kDim),
                children: next == null
                    ? const [TextSpan(text: 'ALL DECKS UNLOCKED')]
                    : [
                        TextSpan(text: 'NEXT UNLOCK ${_fmtRep(next)}: '),
                        TextSpan(
                          text: _nextUnlockName(level),
                          style: numStyle(15,
                              color: kAccentHi, glow: kGlowAcc),
                        ),
                      ],
              ),
            ),
          ],
        ),
      );

  Widget _sectionHead(String text) => Text(text,
      style: labelStyle(size: 9, tracking: 2, color: kDim));

  Widget _founderGrid() {
    final cards = [
      for (final bg in kFounderBackgrounds) _founderCard(bg),
    ];
    return Column(
      children: [
        Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 7),
          Expanded(child: cards[1]),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: cards[2]),
          const SizedBox(width: 7),
          Expanded(child: cards[3]),
        ]),
      ],
    );
  }

  Widget _founderCard(FounderBackground bg) {
    final unlocked = _unlocked(bg);
    final selected = _selected == bg.id;
    final faces = _faces(bg, unlocked);
    return GestureDetector(
      onTap: unlocked ? () => setState(() => _selected = bg.id) : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: unlocked ? 1 : .42,
        child: Container(
          key: Key('founder-${bg.id}'),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: kPanel,
            border: Border(
              top: BorderSide(color: selected ? kAccent : kLine),
              right: BorderSide(color: selected ? kAccent : kLine),
              bottom: BorderSide(color: selected ? kAccent : kLine),
              left: BorderSide(
                  color: selected
                      ? kAccentHi
                      : (unlocked ? kDim : kFaint),
                  width: 3),
            ),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x384DA3FF), blurRadius: 14)]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(unlocked ? bg.label : '${bg.label} 🔒',
                  style: labelStyle(
                      size: 9,
                      tracking: 1,
                      color: unlocked ? kFg : kDim)),
              const SizedBox(height: 5),
              for (final f in faces)
                Text(f.text,
                    style: numStyle(15, color: f.color, glow: const [])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unlockedRow(MetaState m) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('UNLOCKED', style: labelStyle(size: 8, tracking: 1.5)),
            Text(
              'CARDS ${m.unlockedCards.length}/$_kTotalCards · '
              'SECTORS ${m.unlockedSectors.length}/$_kTotalSectors',
              key: const Key('unlockedCounts'),
              style: numStyle(19),
            ),
          ],
        ),
      );

  Widget _titleRow(MetaState m) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('TITLE', style: labelStyle(size: 8, tracking: 1.5)),
            Container(
              padding: const EdgeInsets.fromLTRB(7, 2, 7, 1),
              decoration: BoxDecoration(
                color: kDim,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                (m.cosmetics.activeTitle ?? 'NONE').toUpperCase(),
                style: labelStyle(size: 9, tracking: 1, color: kBadgeInk),
              ),
            ),
          ],
        ),
      );

  /// The +/− perk/constraint faces for a background (mockup `.fperk`),
  /// derived from the engine background's dials. A locked card shows the rep
  /// gate instead of its perk constraint.
  List<({String text, Color color})> _faces(
      FounderBackground bg, bool unlocked) {
    final out = <({String text, Color color})>[];
    // PERK (the headline plus).
    if (bg.bonusPartnerEbitdaCents > 0) {
      out.add((text: '+ FREE PARTNER', color: kGain));
    } else if (bg.startCashDeltaCents > 0) {
      out.add((text: '+ CASH', color: kGain));
    } else if (bg.extraPlaysPerRound > 0) {
      out.add((text: '+ EXTRA PLAY', color: kGain));
    } else if (bg.startOwnershipBpOverride == null) {
      // Bootstrapper: its "perk" is keeping 100% ownership / no dilution.
      out.add((text: '+ HIGH OWN%', color: kGain));
    } else {
      out.add((text: '+ —', color: kFaint));
    }
    // CONSTRAINT (the matching minus), or the rep gate when locked.
    if (!unlocked) {
      out.add((text: 'NEEDS ${_fmtRep(_gateFor(bg))} REP', color: kFaint));
      return out;
    }
    if (bg.startOwnershipBpOverride != null &&
        bg.startOwnershipBpOverride! < 10000) {
      out.add((text: '− OWN%', color: kLoss));
    } else if (bg.startCashDeltaCents < 0) {
      out.add((text: '− LESS CASH', color: kLoss));
    } else if (bg.id == kBootstrapperBackgroundId) {
      out.add((text: '− NO CREDIT', color: kLoss));
    } else {
      out.add((text: '− —', color: kFaint));
    }
    return out;
  }

  /// The rep gate shown on a locked founder card. The unlock thresholds are
  /// meta dials; for the display we surface the first uncrossed threshold (a
  /// locked background unlocks at a future reputation milestone).
  int _gateFor(FounderBackground bg) => _nextThreshold ?? 0;

  /// The flavor name of the next unlock (the deck a level grants). Display
  /// flavor keyed off the level reached — not engine state, so a small table.
  String _nextUnlockName(int level) {
    const names = ['STARTER DECK', 'LBO DECK', 'GROWTH DECK', 'BUYOUT DECK',
        'EMPIRE DECK'];
    final i = level.clamp(0, names.length - 1);
    return names[i];
  }

  /// Formats a reputation total with thousands separators (display only;
  /// reputation is an integer fixed-point count, not money).
  String _fmtRep(int rep) {
    final s = rep.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
