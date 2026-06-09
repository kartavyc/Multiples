/// Integer-width limits for NATIVE targets (VM + AOT), where Dart `int` is a
/// true signed 64-bit and wraps on overflow.
///
/// These are the exact magnitudes the engine has always used. The web variant
/// ([platform_limits_web.dart]) lowers them to stay inside JavaScript's
/// 2^53 exact-integer range; the conditional export in [platform_limits.dart]
/// picks the right one at compile time. The native values here are UNCHANGED
/// so replay and every golden stay byte-identical on mobile/desktop.
library;

/// satMul saturation magnitude (money.dart `kMaxCents`): 2^60 cents
/// (~$1.15e16) — four orders of magnitude above the $1B win bar, far below
/// 2^63-1 so two clamped magnitudes still sum without wrapping int64.
const int kSatMulMaxCents = 1 << 60;

/// The signed-64-bit width sentinel (round.dart endless-bar + compound caps):
/// the largest positive int64, so `nw >= sentinel` never fires.
const int kIntWidthMaxCents = 0x7FFFFFFFFFFFFFFF;
