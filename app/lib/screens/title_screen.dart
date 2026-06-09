/// S0 — TITLE (mockup #scr-s0): wordmark, tagline, the 14× glyph, the key
/// stack (CONTINUE / NEW RUN / THE DESK). The front door before the run
/// screen. CONTINUE shows only when a resumable run.json exists (docs/06);
/// THE DESK opens the S9 meta screen. The footer "SAVED ON DEVICE" is now
/// literally true. The seed for the run about to start shows under the keys.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The title screen. [onNewRun] opens a fresh run; [onContinue] (when
/// non-null) resumes the saved one; [onDesk] opens THE DESK.
class TitleScreen extends StatelessWidget {
  /// Builds the title; [seedTag] is the run's №-hex tag.
  const TitleScreen({
    super.key,
    required this.seedTag,
    required this.onNewRun,
    required this.onDesk,
    this.resumeLabel,
    this.onContinue,
    this.onSettings,
    this.onGuidedRun,
    this.onGlossary,
  });

  /// The run seed tag to print (№ 4F2A).
  final String seedTag;

  /// NEW RUN key handler.
  final VoidCallback onNewRun;

  /// THE DESK key handler (opens the S9 meta screen).
  final VoidCallback onDesk;

  /// The CONTINUE slot's `T2 · R3 · #4F2A` subtitle; null hides the slot.
  final String? resumeLabel;

  /// CONTINUE key handler; null (with [resumeLabel] null) hides the slot —
  /// no resumable run on disk.
  final VoidCallback? onContinue;

  /// SETTINGS handler (R20 gear key); null hides the key.
  final VoidCallback? onSettings;

  /// GUIDED RUN handler — starts a run with the first-run tutorial forced on
  /// (intro cards + coachmarks), regardless of the seen flag; null hides it.
  final VoidCallback? onGuidedRun;

  /// TIPS · GLOSSARY handler — opens the glossary screen; null hides the key.
  final VoidCallback? onGlossary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBezel,
      body: SafeArea(
        child: Column(
          children: [
            // The bezel nameplate (a new machine: MK·I).
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2A2E33), Color(0xFF17191C)],
                  ),
                  border: Border.all(color: kBezel),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'MULTIPLES MK·I · №$seedTag',
                  style:
                      labelStyle(color: const Color(0xFF9AA4AD), tracking: 2),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: kBg,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Column(
                          children: [
                            const Spacer(),
                            // Wordmark (Silkscreen 31/tracking 5 + glow).
                            Text(
                              'MULTIPLES',
                              key: const Key('wordmark'),
                              style: const TextStyle(
                                fontFamily: kFontLabel,
                                fontSize: 31,
                                letterSpacing: 5,
                                fontWeight: FontWeight.w700,
                                color: kFg,
                                shadows: [
                                  Shadow(
                                      color: Color(0x59E6EDF3),
                                      blurRadius: 5),
                                  Shadow(
                                      color: Color(0x38E6EDF3),
                                      blurRadius: 36),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "get in. get rich. get out. Wait, that's allowed?!",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: kFontNum,
                                fontSize: 19,
                                letterSpacing: 2,
                                color: kDim,
                              ),
                            ),
                            const SizedBox(height: 26),
                            // The 14× glyph chip (blue budget: one accent).
                            Container(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 8, 18, 10),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: kAccent, width: 2),
                                borderRadius: BorderRadius.circular(4),
                                color: const Color(0x0D4DA3FF),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x8C4DA3FF),
                                      blurRadius: 6),
                                ],
                              ),
                              child: Text('14×',
                                  style: numStyle(46,
                                      color: kAccentHi, glow: kGlowAcc)),
                            ),
                            const SizedBox(height: 40),
                            SizedBox(
                              width: 252,
                              child: Column(
                                children: [
                                  if (onContinue != null) ...[
                                    _ContinueKey(
                                      subtitle: resumeLabel ?? '',
                                      onTap: onContinue!,
                                    ),
                                    const SizedBox(height: 9),
                                  ],
                                  ChunkyKey(
                                    key: const Key('newRun'),
                                    icon: '＋',
                                    label: 'NEW RUN',
                                    variant: onContinue == null
                                        ? ChunkyKeyVariant.primary
                                        : ChunkyKeyVariant.normal,
                                    onTap: onNewRun,
                                  ),
                                  if (onGuidedRun != null) ...[
                                    const SizedBox(height: 9),
                                    ChunkyKey(
                                      key: const Key('guidedRun'),
                                      icon: '◉',
                                      label: 'GUIDED RUN',
                                      onTap: onGuidedRun!,
                                    ),
                                  ],
                                  const SizedBox(height: 9),
                                  ChunkyKey(
                                    key: const Key('theDesk'),
                                    icon: '▤',
                                    label: 'THE DESK',
                                    onTap: onDesk,
                                  ),
                                  if (onSettings != null) ...[
                                    const SizedBox(height: 9),
                                    ChunkyKey(
                                      key: const Key('titleSettings'),
                                      icon: '⚙',
                                      label: 'SETTINGS',
                                      onTap: onSettings,
                                    ),
                                  ],
                                  if (onGlossary != null) ...[
                                    const SizedBox(height: 9),
                                    ChunkyKey(
                                      key: const Key('glossary'),
                                      icon: '?',
                                      label: 'TIPS · GLOSSARY',
                                      onTap: onGlossary!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('№ $seedTag',
                                style: numStyle(15,
                                    color: kDim, glow: const [])),
                            const Spacer(),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                'NO ACCOUNT · OFFLINE · SAVED ON DEVICE',
                                style: labelStyle(
                                    size: 8,
                                    color: kFaint,
                                    tracking: 1.5),
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
          ],
        ),
      ),
    );
  }
}


/// The CONTINUE key (mockup `.fkey.primary` with a `<small>` resume line):
/// a primary chunky key carrying the `T2 · R3 · #4F2A` subtitle ChunkyKey
/// itself does not render. Pulses like the other primary keys.
class _ContinueKey extends StatefulWidget {
  const _ContinueKey({required this.subtitle, required this.onTap});

  /// The resume descriptor line (tier · round · seed).
  final String subtitle;

  /// Resume handler.
  final VoidCallback onTap;

  @override
  State<_ContinueKey> createState() => _ContinueKeyState();
}

class _ContinueKeyState extends State<_ContinueKey>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value * 0.35;
          final cap = Color.lerp(kAccentHi, Colors.white, t)!;
          return Transform.translate(
            offset: Offset(0, _pressed ? 3 : 0),
            child: Container(
              key: const Key('continue'),
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0A3B66), Color(0xFF062845), Color(0xFF03182B)],
                  stops: [0, .6, 1],
                ),
                border: Border.all(color: kBezel),
                borderRadius: BorderRadius.circular(5),
                boxShadow: [
                  BoxShadow(color: kBezel, offset: Offset(0, _pressed ? 1 : 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text('▸',
                            style: TextStyle(
                                fontFamily: kFontNum,
                                fontSize: 18,
                                height: 1,
                                color: cap,
                                shadows: kGlowAcc)),
                      ),
                      Text('CONTINUE',
                          style: TextStyle(
                              fontFamily: kFontLabel,
                              fontSize: 10,
                              letterSpacing: .5,
                              height: 1.2,
                              color: cap,
                              shadows: kGlowAcc)),
                    ],
                  ),
                  if (widget.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(widget.subtitle,
                        key: const Key('continueSub'),
                        style: numStyle(13, color: kAccentHi, glow: const [])),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
