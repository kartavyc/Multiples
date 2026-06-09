/// The first-run TUTORIAL overlay (docs/05 teach-by-play): a dim-everything-
/// but-the-target spotlight + one terse line + TAP TO CONTINUE, with a
/// persistent SKIP TUTORIAL. Mounts above the run stage (below the CRT) only
/// while [TutorialController.currentStep] is non-null.
///
/// SKIN ONLY: terminal tokens (theme.dart). The spotlight rect comes from the
/// run screen, which resolves each [SpotlightTarget]'s GlobalKey to a screen
/// rectangle; [SpotlightTarget.none] dims the whole stage (the closing line
/// is the payoff, not a pointer). The whole overlay is one tappable surface
/// that calls [onContinue] — except the SKIP key, which calls [onSkip]. It is
/// NON-DESTRUCTIVE: tapping it only advances the tutorial; the real keys
/// beneath are covered, never fired through.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tutorial.dart';

/// The coachmark overlay for one [step]. [spotlight] is the cut-out rect in
/// the overlay's local coordinates (null = dim the whole screen).
class TutorialOverlay extends StatelessWidget {
  /// Builds the overlay.
  const TutorialOverlay({
    super.key,
    required this.step,
    required this.spotlight,
    required this.onContinue,
    required this.onSkip,
  });

  /// The step to render.
  final TutorialStep step;

  /// The highlighted rect (overlay-local); null dims everything.
  final Rect? spotlight;

  /// TAP TO CONTINUE handler.
  final VoidCallback onContinue;

  /// SKIP TUTORIAL handler.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('tutorialOverlay'),
      fit: StackFit.expand,
      children: [
        // The dim scrim with a spotlight cut-out. One tap surface = advance.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onContinue,
          child: CustomPaint(
            painter: _SpotlightPainter(spotlight),
            size: Size.infinite,
          ),
        ),
        // A blue ring around the spotlit target (when there is one).
        if (spotlight != null)
          Positioned.fromRect(
            rect: spotlight!.inflate(4),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kAccent, width: 2),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: Color(0x664DA3FF), blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
        // The callout card: title + line + TAP TO CONTINUE, anchored away
        // from the spotlight so it never covers the thing it points at.
        _Callout(
          step: step,
          spotlight: spotlight,
          onContinue: onContinue,
        ),
        // SKIP — always reachable, top-right, its own tap target.
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSkip,
            child: Container(
              key: const Key('tutorialSkip'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xCC07090C),
                border: Border.all(color: kFaint),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('SKIP TUTORIAL ✕',
                  style: labelStyle(size: 8, color: kDim, tracking: 1.5)),
            ),
          ),
        ),
      ],
    );
  }
}

/// The terse callout card. Sits BELOW the spotlight when the target is in the
/// top half, ABOVE it otherwise — so it always reads in clear space.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.step,
    required this.spotlight,
    required this.onContinue,
  });

  final TutorialStep step;
  final Rect? spotlight;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // Default: center it. With a spotlight, push to the opposite half.
        final spot = spotlight;
        final topHalf = spot != null && spot.center.dy < h / 2;
        final align = spot == null
            ? Alignment.center
            : (topHalf ? Alignment.bottomCenter : Alignment.topCenter);
        return Align(
          alignment: align,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 56, 18, 26),
            child: IgnorePointer(
              ignoring: false,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onContinue,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xF210151B),
                    border: Border.all(color: kAccent, width: 2),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x4D4DA3FF), blurRadius: 16),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title,
                          key: const Key('tutorialTitle'),
                          style: labelStyle(
                              size: 10, color: kAccentHi, tracking: 2)),
                      const SizedBox(height: 7),
                      Text(step.line,
                          key: const Key('tutorialLine'),
                          style: bodyStyle(size: 13, color: kFg)
                              .copyWith(height: 1.35)),
                      if (step.fact != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('▸ ',
                                style: bodyStyle(size: 11, color: kGain)),
                            Expanded(
                              child: Text(step.fact!,
                                  key: const Key('tutorialFact'),
                                  style: bodyStyle(size: 11, color: kGain)
                                      .copyWith(
                                          height: 1.3,
                                          fontStyle: FontStyle.italic)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 11),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('TAP TO CONTINUE ▸',
                              key: const Key('tutorialContinue'),
                              style: labelStyle(
                                  size: 9, color: kAccent, tracking: 1.5)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the dim scrim with a rounded rect cut-out over the spotlight (the
/// target stays at full brightness; everything else dims ~72%). With no
/// spotlight it dims the whole surface.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.spotlight);

  final Rect? spotlight;

  static const Color _scrim = Color(0xB8000000); // ~72% black

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final scrim = Paint()..color = _scrim;
    final spot = spotlight;
    if (spot == null) {
      canvas.drawRect(full, scrim);
      return;
    }
    // Even-odd: outer full rect minus the inflated spotlight = the dim ring.
    final hole = RRect.fromRectAndRadius(
        spot.inflate(4), const Radius.circular(4));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRRect(hole);
    canvas.drawPath(path, scrim);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.spotlight != spotlight;
}
