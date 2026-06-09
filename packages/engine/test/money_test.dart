import 'package:engine/money.dart';
import 'package:test/test.dart';

void main() {
  group('truncDiv', () {
    test('truncates toward zero for positive operands', () {
      expect(truncDiv(7, 2), 3);
    });

    test('truncates toward zero (not floor) for negative numerator', () {
      expect(truncDiv(-7, 2), -3);
    });

    test('truncates toward zero for negative denominator', () {
      expect(truncDiv(7, -2), -3);
    });

    test('truncates toward zero when both operands negative', () {
      expect(truncDiv(-7, -2), 3);
    });

    test('exact division has no remainder', () {
      expect(truncDiv(8, 2), 4);
    });
  });

  group('formatMoney', () {
    test('comma-groups whole dollars below \$1M', () {
      expect(formatMoney(5600000), r'$56,000');
    });

    test('abbreviates millions with one decimal', () {
      expect(formatMoney(150000000), r'$1.5M');
    });

    test('trims trailing .0 on whole millions', () {
      // 200,000,000 cents = $2,000,000 = $2M
      expect(formatMoney(200000000), r'$2M');
    });

    test('zero formats as \$0', () {
      expect(formatMoney(0), r'$0');
    });

    test('small amounts show comma-grouped dollars', () {
      // 100,000 cents = $1,000
      expect(formatMoney(100000), r'$1,000');
    });

    test('amounts under \$1,000 have no separator', () {
      // 99,900 cents = $999
      expect(formatMoney(99900), r'$999');
    });

    test('negative values get a leading minus before the dollar sign', () {
      expect(formatMoney(-5600000), r'-$56,000');
    });

    test('negative millions abbreviate with leading minus', () {
      expect(formatMoney(-150000000), r'-$1.5M');
    });

    test('billions use a B suffix', () {
      // 1,000,000,000 dollars = 100,000,000,000 cents... use $1.5B
      // $1,500,000,000 = 150,000,000,000 cents
      expect(formatMoney(150000000000), r'$1.5B');
    });

    test('whole billions trim the trailing .0', () {
      // $2,000,000,000 = 200,000,000,000 cents
      expect(formatMoney(200000000000), r'$2B');
    });

    test('exactly \$1,000,000 abbreviates to \$1M', () {
      expect(formatMoney(100000000), r'$1M');
    });
  });

  group('formatMultiple', () {
    test('formats whole multiples with the .0 kept (6000 -> 6.0x)', () {
      expect(formatMultiple(6000), '6.0x');
    });

    test('formats two-digit multiples (14000 -> 14.0x)', () {
      expect(formatMultiple(14000), '14.0x');
    });

    test('keeps one decimal of a fractional multiple (14500 -> 14.5x)', () {
      expect(formatMultiple(14500), '14.5x');
    });

    test('truncates toward zero, never rounds (2777 -> 2.7x — the '
        'ADD_SW_MICRO implied buy multiple)', () {
      expect(formatMultiple(2777), '2.7x');
    });

    test('sub-1.0x values format from 0 (999 -> 0.9x)', () {
      expect(formatMultiple(999), '0.9x');
    });

    test('zero formats as 0.0x', () {
      expect(formatMultiple(0), '0.0x');
    });

    test('a negative raw delta gets a leading minus (-640 -> -0.6x)', () {
      expect(formatMultiple(-640), '-0.6x');
    });
  });

  group('formatMultiple2 (two-decimal rate readout)', () {
    test('keeps two decimals (1340 -> 1.34x)', () {
      expect(formatMultiple2(1340), '1.34x');
    });

    test('distinguishes rates one decimal collapses (1340 vs 1310)', () {
      expect(formatMultiple2(1310), '1.31x');
      expect(formatMultiple2(1340) == formatMultiple2(1310), isFalse);
    });

    test('zero-pads the hundredths (1305 -> 1.30x)', () {
      expect(formatMultiple2(1305), '1.30x');
    });

    test('truncates sub-hundredth milli toward zero (1349 -> 1.34x)', () {
      expect(formatMultiple2(1349), '1.34x');
    });

    test('whole multiples keep .00 (14000 -> 14.00x)', () {
      expect(formatMultiple2(14000), '14.00x');
    });

    test('sub-1.0x values format from 0 (999 -> 0.99x)', () {
      expect(formatMultiple2(999), '0.99x');
    });

    test('zero formats as 0.00x', () {
      expect(formatMultiple2(0), '0.00x');
    });

    test('a negative raw delta gets a leading minus (-640 -> -0.64x)', () {
      expect(formatMultiple2(-640), '-0.64x');
    });
  });

  group('milli-unit round-trip', () {
    test('xToMilli scales by 1000', () {
      expect(xToMilli(14), 14000);
    });

    test('milliToXTrunc divides by 1000 truncating', () {
      expect(milliToXTrunc(14000), 14);
    });

    test('milliToXTrunc truncates partial milli toward zero', () {
      expect(milliToXTrunc(14500), 14);
    });
  });

  group('basis-point round-trip', () {
    test('pctToBp scales by 100', () {
      expect(pctToBp(80), 8000);
    });

    test('bpToPctTrunc divides by 100 truncating', () {
      expect(bpToPctTrunc(8000), 80);
    });

    test('bpToPctTrunc truncates partial percent toward zero', () {
      expect(bpToPctTrunc(8050), 80);
    });
  });

  // ---------------------------------------------------------------------
  // satMul / kMaxCents — the net-worth overflow guard (audit 2026-06-09 M3)
  // ---------------------------------------------------------------------
  group('satMul (saturating signed multiply for the net-worth products)', () {
    test('a zero operand is exactly zero (either side)', () {
      expect(satMul(0, 1 << 40), 0);
      expect(satMul(1 << 40, 0), 0);
      expect(satMul(0, 0), 0);
    });

    test('an in-range product is plain multiplication (no clamp)', () {
      // The seed-42 golden run\'s biggest product is ~1.5e12; nowhere near
      // the cap, so the guard is a no-op for every reachable value.
      expect(satMul(1551560, 8000), 1551560 * 8000);
      expect(satMul(-1551560, 8000), -1551560 * 8000);
      expect(satMul(123456789, 1000), 123456789 * 1000);
    });

    test('the largest exactly-representable product is NOT clamped', () {
      // |a*b| == kMaxCents must pass through unclamped (the boundary is
      // inclusive). 2^30 * 2^30 == 2^60 == kMaxCents.
      const half = 1 << 30;
      expect(satMul(half, half), kMaxCents);
      expect(satMul(-half, half), -kMaxCents);
    });

    test('a positive overflow saturates at +kMaxCents (never wraps)', () {
      // Without the guard, 2^40 * 2^40 == 2^80 wraps a signed int64 to 0;
      // with it, the magnitude is clamped to the sentinel.
      expect(satMul(1 << 40, 1 << 40), kMaxCents);
      expect(satMul(kMaxCents, 1000000), kMaxCents);
    });

    test('a negative overflow saturates at -kMaxCents (sign by XOR)', () {
      expect(satMul(-(1 << 40), 1 << 40), -kMaxCents);
      expect(satMul(1 << 40, -(1 << 40)), -kMaxCents);
      expect(satMul(-(1 << 40), -(1 << 40)), kMaxCents);
    });

    test('two clamped magnitudes still sum without int64 overflow', () {
      // The whole point of the 2^60 choice: a per-venture clamped term plus
      // the cash term (and across ventures) cannot overflow the int64 sum.
      // 2^60 + 2^60 == 2^61, comfortably inside 2^63-1.
      expect(kMaxCents + kMaxCents, 1 << 61);
      expect(kMaxCents + kMaxCents < 0x7FFFFFFFFFFFFFFF, isTrue);
    });
  });
}
