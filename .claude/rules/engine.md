---
paths:
  - "packages/engine/**"
  - "prototype/**"
---

# Engine rules (pure Dart)

Loaded only when working in `packages/engine/` or `prototype/`. The core conventions are in the
root CLAUDE.md; this file holds engine-specific detail.

## Hard rules
- **No `double`, ever.** Express JSON fractions as integer numerator/denominator (e.g. synergy 0.20
  -> `* 20 ~/ 100`; conglomerate drag 0.08 -> keep 92%: `* 92 ~/ 100`). Add a const + comment citing
  the JSON source value.
- **No Flutter import.** The engine must run under bare `dart test`.
- Immutable model. `Venture` and `GameState` are value types with `copyWith` + value equality.
- `netWorthCents` is a getter only. Canonical per-venture order (match exactly for byte-identical ports):
  `ev = ebitdaCents*multipleMilli ~/ 1000; equity = ev - netDebtCents; mine = equity*ownershipBp ~/ 10000;`
  then `sum(mine) + cashCents`. Divisions LAST.

## Layers
- **Layer 1 (frozen formulas)** in `lib/resolver.dart`: `enterpriseValue`, `equityValue`, `interestDue`
  (rate-parameterized: economy defines an 8-14% / 800-1400bp band, NOT a fixed rate; live per-round rate
  belongs to the drift/Operate layer), `diluteOwnership`, arbitrage accretion (same-sector +20% synergy
  at platform multiple; cross-sector zero synergy + 0.92 multiple drag, may be net-dilutive = legal).
- **`apply(state, action)`**: closed union of 11 actions (see doc 03 §4.1). Build `AcquireAddOn` FIRST
  (the signature merge, §Q6) - accretion is RESOLVER-COMPUTED from live platform state, not card deltas.
- Each action is unit-tested for its doc-02 pre/post-conditions, one test file per action.

## Testing
- Strict TDD: write the failing test first, confirm red, then green, then refactor.
- Run: `cd packages/engine && dart test test/<file>` for one file, `dart test` for all.
- The §7 invariant test and the golden draw-order test are the two guardrails - never weaken them to
  make something pass. If reality differs from the docs, reconcile against the docs, don't patch the test.
- Sectors: `software, retail, services, industrial` (JSON spellings uppercase).
