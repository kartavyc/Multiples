/// Fixed-point money and unit-conversion helpers.
///
/// LOCKED conventions for this package:
/// - All money is integer **cents**. No `double` anywhere.
/// - `multipleMilli` = multiple in milli-units (x1000): 14x is `14000`.
/// - `ownershipBp` = ownership in basis points (x10000): 80% is `8000`.
/// - Integer division truncates toward zero (Dart `~/`).
///
/// Pure and dependency-free (only `dart:core` + the platform-limits shim,
/// itself dependency-free).
library;

import 'platform_limits.dart' show kSatMulMaxCents;

/// Integer division of [a] by [b] truncating toward zero.
///
/// Dart's `~/` already truncates toward zero (unlike floor division), so this
/// is a thin, intention-revealing wrapper:
///   truncDiv(7, 2) == 3, truncDiv(-7, 2) == -3.
int truncDiv(int a, int b) => a ~/ b;

/// The saturating-arithmetic sentinel: the magnitude past which a derived
/// money/EV product is clamped (a derived-getter guard — never a stored
/// value). Chosen as 2^60 cents — about ±$1.15e16, four orders of magnitude
/// above the T4 win bar ($1B) and far enough below 2^63-1 (~9.2e18) that two
/// such clamped magnitudes can still be added/subtracted (the net-worth
/// per-venture sum and the cash term) without the int64 sum overflowing.
///
/// WHY a guard at all (audit 2026-06-09 M3): [GameState.netWorthCents] and
/// [netWorth] multiply `ebitda * multipleMilli` and `equity * ownershipBp`
/// BEFORE the final truncating division. In any bounded run these products
/// stay far inside int64, but T5 endless compounds organic growth every ante
/// without a deadline (L1's escalation bounds the *rate*, not the horizon),
/// so over a marathon the raw products are theoretically unbounded and could
/// silently wrap a signed 64-bit int (wrapping turns a huge positive net
/// worth NEGATIVE — a false bankruptcy/▒death▒, the worst possible silent
/// corruption). [satMul] makes that impossible: the multiply saturates at
/// ±[kMaxCents] instead of wrapping. The cap sits so far above every
/// reachable in-range value that NO in-range golden moves (verified by the
/// replay golden: the seed-42 run's products are ~1e12, nowhere near 2^60).
/// On NATIVE this is 2^60 (the value above); on WEB the platform shim lowers
/// it to 2^52 so a clamped product stays inside JS's 2^53 exact-int range.
/// See platform_limits_web.dart for why web play is unaffected below ~$4.5B.
const int kMaxCents = kSatMulMaxCents;

/// Saturating signed multiply for the fixed-point money getters: returns
/// `a * b` clamped to `[-kMaxCents, kMaxCents]`, never wrapping a signed
/// 64-bit int. Integer-only (no `double`, no `dart:math`).
///
/// Detection without overflowing: a zero operand is 0; otherwise the product
/// would exceed [kMaxCents] in magnitude exactly when `|a| > kMaxCents ~/ |b|`
/// (integer division, the standard non-overflowing saturation test). The
/// result sign is the usual XOR of the operand signs. Used by
/// [GameState.netWorthCents] / [netWorth] for the EV and equity products so a
/// marathon endless run cannot wrap net worth; everywhere else the values are
/// provably in-range and plain `*` is kept (this guard is intentionally
/// scoped to the two unbounded-horizon products, not sprayed across the
/// engine).
int satMul(int a, int b) {
  if (a == 0 || b == 0) return 0;
  final negative = (a < 0) != (b < 0);
  final absLimit = kMaxCents ~/ (b < 0 ? -b : b);
  final absA = a < 0 ? -a : a;
  if (absA > absLimit) return negative ? -kMaxCents : kMaxCents;
  return a * b;
}

/// Formats a [cents] amount as an en-US currency string.
///
/// Rules:
/// - dollars = cents ~/ 100 (truncating toward zero; sub-dollar cents are
///   dropped, matching the integer-dollar display used across the game).
/// - Below $1,000,000: comma-grouped whole dollars with a leading `$`
///   (e.g. `$56,000`).
/// - At/above $1,000,000: abbreviate with one decimal and an `M`/`B` suffix,
///   trimming a trailing `.0` (so $1,500,000 -> `$1.5M`, $2,000,000 -> `$2M`).
/// - Negative values get a leading `-` before the `$` (e.g. `-$56,000`).
///
/// Design choices (documented per spec):
/// - The decimal in abbreviated form truncates toward zero rather than
///   rounding, keeping the package free of rounding ambiguity and consistent
///   with the truncate-toward-zero convention. So $1,990,000 -> `$1.9M`.
/// - Trillions and above are not abbreviated further; they fall through to the
///   `B` suffix (e.g. $2,000,000,000,000 -> `$2000B`), which is outside any
///   realistic in-game range.
String formatMoney(int cents) {
  final dollars = truncDiv(cents, 100);
  final negative = dollars < 0;
  final abs = negative ? -dollars : dollars;
  final sign = negative ? '-' : '';

  if (abs >= 1000000000) {
    return '$sign\$${_abbrev(abs, 1000000000)}B';
  }
  if (abs >= 1000000) {
    return '$sign\$${_abbrev(abs, 1000000)}M';
  }
  return '$sign\$${_groupThousands(abs)}';
}

/// Returns [value] divided by [unit] as a one-decimal string, trimming a
/// trailing `.0`. Truncates toward zero (no rounding).
String _abbrev(int value, int unit) {
  final whole = value ~/ unit;
  final tenths = (value ~/ (unit ~/ 10)) % 10;
  if (tenths == 0) {
    return '$whole';
  }
  return '$whole.$tenths';
}

/// Inserts comma separators every three digits into a non-negative integer.
String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  final firstGroup = digits.length % 3;
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (i - firstGroup) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats [milli] milli-units as a one-decimal multiple string:
/// `formatMultiple(14000) == '14.0x'`, `formatMultiple(2777) == '2.7x'`.
///
/// Rules (the one display shape for multiples — .claude/rules/flutter-app.md
/// requires the app to format multiples through THIS helper, never ad-hoc):
/// - The decimal truncates toward zero (no rounding), matching the package
///   convention and [formatMoney]'s abbreviation rule: `2777 -> '2.7x'`.
/// - The `.0` is kept (a multiple reads `6.0x`, never `6x`).
/// - Negative values (impossible for a stored live multiple, which floors at
///   1000 milli, but legal for raw deltas) get a leading `-`.
String formatMultiple(int milli) {
  final negative = milli < 0;
  final abs = negative ? -milli : milli;
  final sign = negative ? '-' : '';
  return '$sign${abs ~/ 1000}.${(abs % 1000) ~/ 100}x';
}

/// Formats [milli] milli-units as a TWO-decimal multiple string:
/// `formatMultiple2(1340) == '1.34x'`, `formatMultiple2(1305) == '1.30x'`.
///
/// The rate-readout variant of [formatMultiple] for places where one
/// decimal is too coarse — the S7/S8 pace lines compare growth rates that
/// routinely differ only in the hundredths (NEED 1.34x/RD vs AT 1.31x
/// would both collapse to `1.3x`). Same conventions: truncates toward
/// zero, keeps trailing zeros (`14.00x`), leading `-` for negative raw
/// deltas.
String formatMultiple2(int milli) {
  final negative = milli < 0;
  final abs = negative ? -milli : milli;
  final sign = negative ? '-' : '';
  final hundredths = (abs % 1000) ~/ 10;
  final padded = hundredths < 10 ? '0$hundredths' : '$hundredths';
  return '$sign${abs ~/ 1000}.${padded}x';
}

/// Converts a whole multiple [x] to milli-units (x1000): `xToMilli(14) == 14000`.
int xToMilli(int x) => x * 1000;

/// Converts [milli] milli-units back to a whole multiple, truncating toward
/// zero: `milliToXTrunc(14000) == 14`, `milliToXTrunc(14500) == 14`.
int milliToXTrunc(int milli) => truncDiv(milli, 1000);

/// Converts a whole percent [pct] to basis points (x100): `pctToBp(80) == 8000`.
int pctToBp(int pct) => pct * 100;

/// Converts [bp] basis points back to a whole percent, truncating toward zero:
/// `bpToPctTrunc(8000) == 80`, `bpToPctTrunc(8050) == 80`.
int bpToPctTrunc(int bp) => truncDiv(bp, 100);
