/// THE TERMINAL — docs/07 art-bible tokens + the shared retro widgets.
///
/// Canon: the `:root` block of docs/mockups/layout-a-v4.html is the source
/// of truth for every hex, size, and animation timing here; docs/07 owns
/// the usage rules (blue is a budget, label-over-number, everything legible
/// static). This file is SKIN ONLY: nothing in it reads GameState or does
/// money math — the one helper that touches integers ([chipText]) does a
/// presentation sign split and delegates every magnitude to an engine
/// formatter passed in by the caller.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Palette tokens (layout-a-v4.html :root; docs/07 table)
// ---------------------------------------------------------------------------

/// Machine bezel + room: pure black (`--bg-0`).
const Color kBezel = Color(0xFF000000);

/// Screen glass: neutral near-black, never blue-tinted (`--bg-1`).
const Color kBg = Color(0xFF07090C);

/// Raised panel (ticket bodies) (`--bg-2`).
const Color kPanel = Color(0xFF10151B);

/// White phosphor: all primary numbers (`--fg`).
const Color kFg = Color(0xFFE6EDF3);

/// Dimmed labels (`--fg-dim`).
const Color kDim = Color(0xFF76828D);

/// Faint rules / flat chips (`--fg-faint`).
const Color kFaint = Color(0xFF3A434C);

/// Ghost ink: fg at 36% alpha — the PAPER treatment (`--fg-ghost`).
const Color kGhost = Color(0x5CE6EDF3);

/// Blue accent — a budget, not a wallpaper (`--acc`).
const Color kAccent = Color(0xFF4DA3FF);

/// Bright accent for glowing blue text (`--acc-hi`).
const Color kAccentHi = Color(0xFF8CC7FF);

/// Gains / synergy / EXECUTE green (`--grn`).
const Color kGain = Color(0xFF4DFF8A);

/// Losses / danger / EXIT red (`--red`).
const Color kLoss = Color(0xFFFF5566);

/// Raise/equity purple — the lone semantic extra (docs/07 palette note).
const Color kRaise = Color(0xFFB48CFF);

/// Hairline dividers, neutral (`--line`).
const Color kLine = Color(0xFF1A2026);

/// Unlit LED segment fill (mockup `.segbar i`).
const Color kSegOff = Color(0xFF11161C);

/// COLD zone LED blue (mockup `.segbar i.on.cold`).
const Color kCold = Color(0xFF3A6C9F);

/// Dark ink printed on bright badges/chips (mockup `.tbadge` color).
const Color kBadgeInk = Color(0xFF0A0D10);

// --- Glows (mockup --glow* vars; alphas baked in for const-ness) ---

/// White phosphor glow (`--glow`).
const List<Shadow> kGlowFg = [Shadow(color: Color(0x59E6EDF3), blurRadius: 5)];

/// Blue accent glow (`--glow-acc`).
const List<Shadow> kGlowAcc = [
  Shadow(color: Color(0x8C4DA3FF), blurRadius: 6),
  Shadow(color: Color(0x294DA3FF), blurRadius: 18),
];

/// Gain green glow (`--glow-grn`).
const List<Shadow> kGlowGain = [
  Shadow(color: Color(0x8C4DFF8A), blurRadius: 6),
  Shadow(color: Color(0x384DFF8A), blurRadius: 16),
];

/// Loss red glow (`--glow-red`).
const List<Shadow> kGlowLoss = [Shadow(color: Color(0x80FF5566), blurRadius: 6)];

// ---------------------------------------------------------------------------
// Type (docs/07 "3 faces, fixed jobs"; bundled in assets/fonts, no runtime
// fetching — the game is offline)
// ---------------------------------------------------------------------------

/// VT323 — every big number (numbers are the heroes).
const String kFontNum = 'VT323';

/// Silkscreen — tiny letterspaced small-caps labels, section heads, keys.
const String kFontLabel = 'Silkscreen';

/// IBM Plex Mono — body rows where pixel fonts would tire.
const String kFontBody = 'IBMPlexMono';

/// A hero number style (VT323). Glow defaults to white phosphor; pass
/// `glow: const []` for ghosted values.
TextStyle numStyle(double size,
        {Color color = kFg, List<Shadow> glow = kGlowFg}) =>
    TextStyle(
      fontFamily: kFontNum,
      fontSize: size,
      color: color,
      height: 1.0,
      shadows: glow,
    );

/// A tiny letterspaced label style (Silkscreen, 8-10px per the bible).
TextStyle labelStyle(
        {double size = 9, Color color = kDim, double tracking = 1.5}) =>
    TextStyle(
      fontFamily: kFontLabel,
      fontSize: size,
      color: color,
      letterSpacing: tracking,
      height: 1.0,
    );

/// A body/row style (IBM Plex Mono).
TextStyle bodyStyle({double size = 12, Color color = kFg}) =>
    TextStyle(fontFamily: kFontBody, fontSize: size, color: color);

// ---------------------------------------------------------------------------
// Change chips (the lever `.lc` row)
// ---------------------------------------------------------------------------

/// Renders a signed lever delta as a change-chip string: `▲` + magnitude
/// for gains, `▼` + magnitude for losses, the mockup's flat glyph for
/// zero/underivable. [fmt] must be an ENGINE formatter (formatMoney /
/// formatMultiple / a bp-percent wrapper); the only arithmetic here is the
/// presentation sign split.
String chipText(int? signedDelta, String Function(int) fmt) {
  if (signedDelta == null || signedDelta == 0) return '—';
  return signedDelta > 0 ? '▲${fmt(signedDelta)}' : '▼${fmt(-signedDelta)}';
}

/// The chip color for a signed delta (gain green / loss red / faint flat).
Color chipColor(int? signedDelta) {
  if (signedDelta == null || signedDelta == 0) return kFaint;
  return signedDelta > 0 ? kGain : kLoss;
}

/// The chip glow for a signed delta (none when flat).
List<Shadow> chipGlow(int? signedDelta) {
  if (signedDelta == null || signedDelta == 0) return const [];
  return signedDelta > 0 ? kGlowGain : kGlowLoss;
}

// ---------------------------------------------------------------------------
// ChunkyKey — the 3D-press function key (mockup .fkey)
// ---------------------------------------------------------------------------

/// The three key skins: gunmetal, the one blue primary per screen, and the
/// green EXECUTE.
enum ChunkyKeyVariant { normal, primary, exec }

/// A chunky terminal function key: 1px black border, 4px black drop edge,
/// translates down 3px on press (mockup `.fkey`). [ChunkyKeyVariant.primary]
/// and [ChunkyKeyVariant.exec] pulse (mockup `keypulse`).
class ChunkyKey extends StatefulWidget {
  /// Builds a key. [icon] renders in VT323 ahead of the Silkscreen [label].
  const ChunkyKey({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.variant = ChunkyKeyVariant.normal,
    this.dense = false,
  });

  /// Silkscreen key cap text.
  final String label;

  /// Optional VT323 glyph prefix (`▶`, `⟳`, `↻`, `✕`).
  final String? icon;

  /// Tap handler; null renders the key dimmed and inert.
  final VoidCallback? onTap;

  /// Which skin (see [ChunkyKeyVariant]).
  final ChunkyKeyVariant variant;

  /// Tighter padding for inline keys (shop BUY).
  final bool dense;

  @override
  State<ChunkyKey> createState() => _ChunkyKeyState();
}

class _ChunkyKeyState extends State<ChunkyKey>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _pulses =>
      widget.variant != ChunkyKeyVariant.normal && widget.onTap != null;

  @override
  void initState() {
    super.initState();
    if (_pulses) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ChunkyKey oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pulses && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!_pulses && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static const Map<ChunkyKeyVariant, List<Color>> _gradients = {
    ChunkyKeyVariant.normal: [
      Color(0xFF1C2127),
      Color(0xFF11151A),
      Color(0xFF090C0F),
    ],
    ChunkyKeyVariant.primary: [
      Color(0xFF0A3B66),
      Color(0xFF062845),
      Color(0xFF03182B),
    ],
    ChunkyKeyVariant.exec: [
      Color(0xFF0D4D2C),
      Color(0xFF07301C),
      Color(0xFF041D11),
    ],
  };

  Color get _capColor {
    if (widget.onTap == null) return kFaint;
    switch (widget.variant) {
      case ChunkyKeyVariant.normal:
        return kDim;
      case ChunkyKeyVariant.primary:
        return kAccentHi;
      case ChunkyKeyVariant.exec:
        return kGain;
    }
  }

  List<Shadow> get _capGlow {
    if (widget.onTap == null) return const [];
    switch (widget.variant) {
      case ChunkyKeyVariant.normal:
        return const [];
      case ChunkyKeyVariant.primary:
        return kGlowAcc;
      case ChunkyKeyVariant.exec:
        return kGlowGain;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap!();
            },
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          // keypulse: brightness 1 -> 1.35 -> 1; lerp the cap toward white.
          final t = _pulses ? _pulse.value * 0.35 : 0.0;
          final cap = Color.lerp(_capColor, Colors.white, t)!;
          return Transform.translate(
            offset: Offset(0, _pressed ? 3 : 0),
            child: Container(
              padding: widget.dense
                  ? const EdgeInsets.symmetric(vertical: 6, horizontal: 8)
                  : const EdgeInsets.fromLTRB(4, 10, 4, 11),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _gradients[widget.variant]!,
                  stops: const [0, .6, 1],
                ),
                border: Border.all(color: kBezel),
                borderRadius: BorderRadius.circular(5),
                boxShadow: [
                  BoxShadow(
                    color: kBezel,
                    offset: Offset(0, _pressed ? 1 : 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        widget.icon!,
                        style: TextStyle(
                          fontFamily: kFontNum,
                          fontSize: 16,
                          height: 1.0,
                          color: cap,
                          shadows: _capGlow,
                        ),
                      ),
                    ),
                  Flexible(
                    // scaleDown, never clip: long caps (REROLL $15,000)
                    // must stay whole on the narrow three-key row.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: kFontLabel,
                          fontSize: 10,
                          letterSpacing: .5,
                          height: 1.2,
                          color: cap,
                          shadows: _capGlow,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SegBar — the segmented LED meter (mockup .segbar)
// ---------------------------------------------------------------------------

/// One LED's state in a [SegBar].
enum SegState {
  /// Unlit.
  off,

  /// Lit gain green.
  on,

  /// Lit dim white.
  onWhite,

  /// Lit cold blue.
  onCold,

  /// Lit hot red.
  onHot,

  /// Lit hot red, dimmed to 25% (the inactive far zone).
  onHotDim,

  /// Lit cold blue, dimmed to 25%.
  onColdDim,

  /// Lit loss red (danger fill on the runway).
  onLoss,
}

/// A segmented LED meter: discrete fill, 2px gaps, optional `▼` needle
/// marker above one segment (mockup `.segbar` + `.mk`). Static-legible:
/// nothing here animates.
class SegBar extends StatelessWidget {
  /// Builds the bar from per-segment states.
  const SegBar({super.key, required this.segs, this.markerIndex});

  /// The LED states, left to right.
  final List<SegState> segs;

  /// Index of the segment carrying the `▼` needle, if any.
  final int? markerIndex;

  static const Map<SegState, Color> _fill = {
    SegState.off: kSegOff,
    SegState.on: kGain,
    SegState.onWhite: kDim,
    SegState.onCold: kCold,
    SegState.onHot: kLoss,
    SegState.onHotDim: Color(0x40FF5566),
    SegState.onColdDim: Color(0x403A6C9F),
    SegState.onLoss: kLoss,
  };

  static const Map<SegState, List<BoxShadow>> _glow = {
    SegState.on: [BoxShadow(color: Color(0x994DFF8A), blurRadius: 5)],
    SegState.onWhite: [BoxShadow(color: Color(0x4DE6EDF3), blurRadius: 4)],
    SegState.onCold: [BoxShadow(color: Color(0x803A6C9F), blurRadius: 5)],
    SegState.onHot: [BoxShadow(color: Color(0x99FF5566), blurRadius: 5)],
    SegState.onLoss: [BoxShadow(color: Color(0x99FF5566), blurRadius: 5)],
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              for (var i = 0; i < segs.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _fill[segs[i]],
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: _glow[segs[i]],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (markerIndex != null)
            Positioned(
              top: -10,
              left: 0,
              right: 0,
              child: Align(
                // Center of segment markerIndex among segs.length equal
                // cells: pure layout fraction, no game math.
                alignment: Alignment(
                  segs.length <= 1
                      ? 0
                      : ((markerIndex! + 0.5) / segs.length) * 2 - 1,
                  0,
                ),
                child: Text(
                  '▼',
                  style: TextStyle(
                    fontSize: 8,
                    height: 1.0,
                    color: kAccentHi,
                    shadows: kGlowAcc,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SolidBox / GhostBox — the paper-vs-real money treatments (mockup #q-cash /
// #q-nw; docs/07 "two sacred treatments" #1)
// ---------------------------------------------------------------------------

/// The REAL treatment: solid 2px blue border, blue-tinted fill, glow.
/// CASH lives here and nowhere else (the blue budget).
class SolidBox extends StatelessWidget {
  /// Builds the solid quote box.
  const SolidBox({
    super.key,
    required this.label,
    required this.value,
    required this.tag,
    this.valueKey,
  });

  /// Silkscreen label (CASH).
  final String label;

  /// Engine-formatted value string.
  final String value;

  /// Top-right corner tag (REAL).
  final String tag;

  /// Test key for the value text.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
      decoration: BoxDecoration(
        border: Border.all(color: kAccent, width: 2),
        color: const Color(0x0F4DA3FF),
        boxShadow: const [
          BoxShadow(color: Color(0x8C4DA3FF), blurRadius: 6),
          BoxShadow(color: Color(0x294DA3FF), blurRadius: 18),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle(color: kAccent)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  key: valueKey,
                  style: numStyle(38, color: kAccentHi, glow: kGlowAcc),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Text(label == tag ? '' : tag,
                style: labelStyle(size: 8, color: kAccent, tracking: 1)),
          ),
        ],
      ),
    );
  }
}

/// The PAPER treatment: 1px dashed ghost border, ghost ink, no glow.
/// NET WORTH lives here — unspendable until exited.
class GhostBox extends StatelessWidget {
  /// Builds the ghost quote box.
  const GhostBox({
    super.key,
    required this.label,
    required this.value,
    required this.tag,
    this.valueKey,
  });

  /// Silkscreen label (NET WORTH).
  final String label;

  /// Engine-formatted value string.
  final String value;

  /// Top-right dashed tag (PAPER).
  final String tag;

  /// Test key for the value text.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: DashedRectPainter(color: kGhost),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle(color: kGhost)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    key: valueKey,
                    style: numStyle(38, color: kGhost, glow: const []),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: CustomPaint(
                painter: DashedRectPainter(color: kGhost),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(tag,
                      style: bodyStyle(size: 9, color: kGhost)
                          .copyWith(letterSpacing: 1)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a 1px dashed rectangle border (Flutter has no native dashed
/// border; mockup `border: 1px dashed`).
class DashedRectPainter extends CustomPainter {
  /// Builds the painter.
  const DashedRectPainter(
      {required this.color, this.dash = 4, this.gap = 3});

  /// Dash color.
  final Color color;

  /// Dash length in px.
  final double dash;

  /// Gap length in px.
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var d = 0.0;
      while (d < total) {
        final end = (d + dash) > total ? total : d + dash;
        canvas.drawLine(a + dir * d, a + dir * end, paint);
        d = end + gap;
      }
    }

    line(Offset.zero, Offset(size.width, 0));
    line(Offset(size.width, 0), Offset(size.width, size.height));
    line(Offset(size.width, size.height), Offset(0, size.height));
    line(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(DashedRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}

// ---------------------------------------------------------------------------
// CRT overlay — scanlines + vignette + the 4.2s flicker (mockup #crt)
// ---------------------------------------------------------------------------

/// The CRT glass: repeating scanlines, an edge vignette, and a faint
/// stepped flicker on a 4.2s loop. [IgnorePointer] so taps pass through;
/// everything beneath stays fully legible (docs/05 §0.2 — this is garnish).
class CrtOverlay extends StatefulWidget {
  /// Builds the overlay.
  const CrtOverlay({super.key});

  @override
  State<CrtOverlay> createState() => _CrtOverlayState();
}

class _CrtOverlayState extends State<CrtOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flick = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  @override
  void dispose() {
    _flick.dispose();
    super.dispose();
  }

  /// The mockup `flick` keyframes as a step function over t in [0,1).
  static double _flickerOpacity(double t) {
    if (t >= 0.07 && t < 0.09) return 0;
    if (t >= 0.44 && t < 0.45) return 0;
    if (t >= 0.81 && t < 0.82) return 0.4;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(painter: _ScanlinePainter()),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.1),
                radius: 1.25,
                colors: [
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x80000000),
                ],
                stops: [0, .58, 1],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _flick,
            builder: (context, _) => Opacity(
              opacity: _flickerOpacity(_flick.value),
              child: const ColoredBox(color: Color(0x05DCEBFA)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1px black scanlines every 3px at 22% (mockup #crt repeating gradient).
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x38000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// BlinkingCursor — the statline block cursor (mockup #cursor)
// ---------------------------------------------------------------------------

/// A 7x13 blue block cursor blinking on the mockup's 1.05s step cycle
/// (visible 60%, hidden 40%).
class BlinkingCursor extends StatefulWidget {
  /// Builds the cursor.
  const BlinkingCursor({super.key});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) => Opacity(
        opacity: _blink.value < 0.6 ? 1 : 0,
        child: Container(
          width: 7,
          height: 13,
          margin: const EdgeInsets.only(left: 4),
          decoration: const BoxDecoration(
            color: kAccent,
            boxShadow: [BoxShadow(color: Color(0x8C4DA3FF), blurRadius: 6)],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NewsTape — the scrolling marquee (mockup #tape, 14s linear loop)
// ---------------------------------------------------------------------------

/// The one-line scrolling news tape. Pure idle motion; the same text is
/// market state the HUD already shows statically (docs/05 §0.2).
class NewsTape extends StatefulWidget {
  /// Builds the tape with the line to scroll.
  const NewsTape({super.key, required this.text});

  /// The tape line (already formatted upstream).
  final String text;

  @override
  State<NewsTape> createState() => _NewsTapeState();
}

class _NewsTapeState extends State<NewsTape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = bodyStyle(size: 13, color: kDim);
    return Container(
      height: 21,
      decoration: const BoxDecoration(
        color: Color(0x4D000000),
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: widget.text, style: style),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout();
            final textWidth = painter.width;
            return AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final dx = constraints.maxWidth -
                    _t.value * (constraints.maxWidth + textWidth);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: dx,
                      top: 0,
                      child: SizedBox(
                        height: 21,
                        child: Center(
                          child: Text(
                            widget.text,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: style,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// CrtScreenSwitcher — terminal-flavored top-level screen transition
// (docs/07: "THE TERMINAL"; replaces the shell's hard title↔desk↔run cuts
// with a quick CRT channel-change: fade-through-black + a scanline sweep)
// ---------------------------------------------------------------------------

/// Swaps top-level screens with a ~300ms CRT power-cycle: the outgoing screen
/// fades to black as a bright scanline sweeps down, the incoming screen fades
/// up under a sweep that lifts off — like flipping channels on the machine.
/// Snappy (snackable sessions) and legible the instant it settles. Built on
/// [AnimatedSwitcher] (one finite controller per swap, auto-disposed), so
/// `pump(Duration)` steps it and no real timer leaks; the incoming screen is
/// in the tree from frame one (finders resolve immediately).
class CrtScreenSwitcher extends StatelessWidget {
  /// Builds the switcher around [child]; give each distinct screen a unique
  /// [ValueKey] so a change triggers the sweep.
  const CrtScreenSwitcher({super.key, required this.child});

  /// The current screen (keyed).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          _CrtSweep(animation: animation, child: child),
      // Lay the incoming screen over the outgoing one (default stacks both),
      // so the sweep reads as one continuous channel-change.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

/// One screen's half of the CRT sweep: fade + a bright scanline band that
/// rides across as the screen enters (band lifts up) or leaves (band drops
/// in). [animation] runs 0→1 for the incoming child and 1→0 for the
/// outgoing one (AnimatedSwitcher drives both).
class _CrtSweep extends StatelessWidget {
  const _CrtSweep({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Fade-through-black: the screen darkens hard near the swap.
            Opacity(
              opacity: (t * 1.4).clamp(0.0, 1.0),
              child: child,
            ),
            // The sweep band: a thin bright scanline that crosses the screen
            // during the transition, fading as it nears the edges.
            if (t > 0 && t < 1)
              IgnorePointer(
                child: CustomPaint(
                  painter: _SweepPainter(t),
                  size: Size.infinite,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SweepPainter extends CustomPainter {
  const _SweepPainter(this.t);

  /// 0..1 transition progress for this screen.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // The band rides from just below the top to just past the bottom as the
    // screen enters; brightness peaks mid-cross.
    final y = size.height * (1.15 * t - 0.075);
    final glow = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = kAccentHi.withValues(alpha: 0.55 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRect(Rect.fromLTWH(0, y - 2, size.width, 4), paint);
    // A fainter trailing wash so the sweep has body, not a hairline.
    final wash = Paint()
      ..color = kAccent.withValues(alpha: 0.10 * glow);
    canvas.drawRect(Rect.fromLTWH(0, y - 14, size.width, 28), wash);
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t;
}
