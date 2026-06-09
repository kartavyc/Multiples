// MULTIPLES — headless rules resolver (prototype)
//
// Layer-1 FROZEN formulas from docs/01-economy-math-spec.md, §7 of the GDD.
// Pure, deterministic, integer fixed-point. NO float in the rules core.
// This is the testable core that the Flutter UI sits on top of (see docs/03).
//
// Fixed-point units:
//   money     : integer CENTS              ($1.00 = 100)
//   multiple  : milli-units  x1000         (14.0x  = 14000)
//   ownership : basis points x10000        (80%    = 8000)
// Rounding: truncate toward zero on every fixed-point multiply/divide.

int _trunc(int a, int b) => (a ~/ b); // Dart ~/ already truncates toward zero for ints

class Venture {
  int ebitda;     // cents/round
  int multiple;   // milli-units
  int netDebt;    // cents
  int ownership;  // basis points
  bool passive;
  int roundsNeglected;
  final String sector;
  Venture({
    required this.ebitda,
    required this.multiple,
    required this.netDebt,
    required this.ownership,
    required this.sector,
    this.passive = false,
    this.roundsNeglected = 0,
  });
}

// F1: EV = trunc(EBITDA * Multiple / 1000)
int enterpriseValue(int ebitda, int multiple) => _trunc(ebitda * multiple, 1000);

// F2: Equity = EV - NetDebt   (may go negative)
int equityValue(int ebitda, int multiple, int netDebt) =>
    enterpriseValue(ebitda, multiple) - netDebt;

// F3: NetWorth = SUM(trunc(own_bp * Equity / 10000)) + Cash
int netWorth(List<Venture> ventures, int cash) {
  var sum = cash;
  for (final v in ventures) {
    final eq = equityValue(v.ebitda, v.multiple, v.netDebt);
    sum += _trunc(v.ownership * eq, 10000);
  }
  return sum;
}

// F4: Interest = trunc(rate_bp * totalNetDebt / 10000), charged in cash each OPERATE
int interestDue(int rateBp, int totalNetDebt) => _trunc(rateBp * totalNetDebt, 10000);

// F5: dilution. preMoney = current Equity. newOwn = trunc(oldOwn * preMoney / (preMoney + raise))
int diluteOwnership(int oldOwnBp, int preMoney, int raise) =>
    _trunc(oldOwnBp * preMoney, preMoney + raise);

// F6: bankruptcy when cash < 0 after interest is charged (cash is NOT clamped).
bool isBankrupt(int cashAfterInterest) => cashAfterInterest < 0;

// RENDER-ONLY arbitrage flash (written to NO field — display only).
int arbitrageAccretion(int addonEbitda, int platformMultiple, int buyMultiple) =>
    _trunc(addonEbitda * (platformMultiple - buyMultiple), 1000);

// The §7 invariant, as code: a delta may only carry these five keys.
const Set<String> kMutableInputs = {'ebitda', 'multiple', 'netDebt', 'own', 'cash'};
bool deltaObeysInvariant(Map<String, num> delta) =>
    delta.keys.every(kMutableInputs.contains);
