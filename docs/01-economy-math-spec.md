# MULTIPLES — Economy & Math Spec (the Model)

> **Status: first-pass. Floor-only smoke test passed (§11).** Single source of truth for every formula, constant, multiple band, curve, and tier bar. Every table here becomes a spreadsheet tab. Numbers are tunable (Layer 2/3); the **Layer-1 formulas and the §7 invariant are frozen**.
>
> Companion: machine-readable mirror at `data/economy-model.json`. Engine state/loop authority: `docs/02-core-loop-game-state.md` (this doc supplies the *numbers*, doc 02 owns the *state shape, round order, and action pre/post-conditions* — where there is overlap, doc 02 wins on structure and this doc wins on constants). Sim harness: `prototype/sim-check.js`. Keep all three in lockstep.

---

## 0. How to read this spec

- All money is **integer cents** internally; tables show dollars rounded with k/M/B suffix (forced en-US grouping).
- **Fixed-point units (authoritative, matches doc 02):** `multiple` is **milli-units ×1000** (14× = `14000`); `ownership` is **basis points ×10000** (80% = `8000`); money is **cents**. There is no ppm anywhere — an earlier draft said ppm; that was wrong.
- **Rounding rule (deterministic):** every fixed-point multiply/divide on currency or ownership uses **truncation toward zero** (`Math.trunc`, i.e. integer floor of the magnitude). No banker's rounding, no float in the rules core. This is what makes iOS/Android byte-identical. Dilution (F5) and synergy/discount on cents all truncate; tiny ownership drift over many raises is accepted and bounded (it only ever rounds *against* the player by <1 bp per op).
- "Round" = one operating turn (a year/quarter). "Tier" = one power-of-ten net-worth band (§4 of the design doc).
- A **delta** is a change to one of the five mutable fields. Per §7, that is the *only* thing any card/consumable/event — **and any engine-applied system event** (drift, decay, organic growth, reseed) — may produce. See §2.1.
- "Floor-checked" means the value was run through `prototype/sim-check.js` (N=5000 seeded runs) and lands the **floor** win-curve in band (§11). The floor models only organic growth + leverage + reinvest + market-ride; it does **not** model arbitrage, synergy, decay, exits, or PLAYS, so it is a *smoke test for winnability*, not a full validation.

---

## 1. Frozen Layer-1 formulas (NEVER change)

These four lines are the spine. They are computed exactly, every action, on integer cents.

| # | Name | Formula | Notes |
|---|------|---------|-------|
| F1 | Enterprise Value | `EV = trunc(EBITDA × Multiple / 1000)` | The product. Two ways to grow: bigger EBITDA or higher Multiple. (`/1000` because Multiple is milli-units.) |
| F2 | Equity Value | `Equity = EV − NetDebt` | Debt is subtracted at the end; it can make Equity negative. |
| F3 | Net Worth (score) | `NetWorth = Σ trunc(Ownership_bp × Equity / 10000) + Cash` | Summed over every held venture, plus pocket cash. Always *derived*, never stored (doc 02). |
| F4 | Interest due (flat) | `Interest = trunc(Rate_bp × Σ NetDebt / 10000)` | Charged in **cash** each round on total net debt. No amortization schedule. |
| F5 | Dilution (post-money) | `newOwn_bp = trunc(oldOwn_bp × preMoney / (preMoney + raise))` <br> the new investor takes `raise / (preMoney + raise)` | `preMoney = current Equity at raise time` (post-money cap-table math). |
| F6 | Bankruptcy rule | **Run ends (bankruptcy) when, after charging interest in OPERATE, `Cash < 0`.** | Liquidity death, not solvency death. Equity can be huge and you still die. See §2.2 for exact timing. |

**Tier-clear rule:** a tier is cleared the first round its **mark-to-market `NetWorth` (F3) ≥ the tier bar**, evaluated in DEADLINE_CHECK on or before the tier deadline. Miss the deadline → growth-rate death (Autopsy "missed deadline").

**Multiple-arbitrage identity (derived, render-only):** when an add-on with `ebitda_a` bought at `price = trunc(ebitda_a × m_buy / 1000)` bolts onto a platform trading at `m_platform`, the instantaneous accretion is `trunc(ebitda_a × (m_platform − m_buy) / 1000)` (before synergy / conglomerate effects in §7). This is the "that's allowed?!" flash. **It is computed for display only and is NEVER written to cash, EV, or any field.** The actual state change is the add-on's deltas (§7.5 / §10); the flash is just F1 recomputed before-vs-after and rendered.

---

## 2. The five mutable fields (resolver inputs)

The hard §7 invariant, made concrete. Every card/consumable/event resolves to a `{deltas}` object touching only these. The resolver applies deltas, then recomputes F1–F4. **There is no `+score` field and the engine test forbids one** (doc 02 §5.1).

| Field | Type | Unit | Sign convention | Clamp |
|-------|------|------|-----------------|-------|
| `ebitda` | int cents | annual earnings base | + grows, − shrinks | `≥ 0` (per venture) |
| `multiple` | fixed-point ×1000 | valuation premium | + expands, − compresses | `≥ 1000` (a live venture floors at 1×) |
| `netDebt` | int cents | borrowings net of cash-on-BS | + leverage up, − pay down | may exceed EV (→ negative equity, allowed) |
| `ownership` | fixed-point ×10000 (bp) | your slice | + un-dilute, − dilute | `0 ≤ own ≤ 10000` |
| `cash` | int cents | pocket cash (the only safe number) | + inflow, − outflow | **not clamped at 0**; `cash < 0` after interest = F6 (see §2.2) |

**Directionality must stay real (§7):** leverage magnifies both ways; arbitrage is genuinely accretive; dilution genuinely shrinks your slice. Magnitudes are gamified; *signs and structure are not*.

### 2.1 `multiple` is STORED, not resampled (architectural lock — resolves the old ambiguity)

A venture's `multiple` is a **stored, mutable field** (doc 02 `Venture.multiple`). It is **never** recomputed from `sectorBase` each round. The market changes it the same way a card does: by **adding a delta**.

- **Card-driven changes** (conglomerate drag, growth) add/subtract milli-units directly and persist.
- **Market drift** (§7.3) is applied in OPERATE as an **additive delta** to each venture's stored `multiple`: `multiple += driftDelta` where `driftDelta = trunc(multiple × (driftFactor − 1))`. It moves the *current* stored value, so card-driven changes are never wiped.
- `sectorBase` (§4) is used **only at venture creation** to seed the starting `multiple`, and as the `sectorNorm` divisor for exit-quality reputation (§7.6). It is a constant, not a per-round source of truth.

There is no `base × (1 + N(0,vol)) × marketDrift` resample anywhere. That formula is deleted.

### 2.2 F6 timing and the cash-deficit rule (exact)

Per doc 02 §2 OPERATE, the order inside a round is fixed (see §6.1). Interest is charged as the **last** economic step of OPERATE:

1. `cash -= interestDue(run)` (F4, on total net debt).
2. **If `cash < 0` → RUN_OVER, cause = BANKRUPTCY.** The autopsy quotes "Interest due $X > Cash $Y" using the pre-charge cash.

The deficit is **not** rolled into `netDebt`, **not** partially paid, and `cash` is **not** clamped to 0 — going negative *is* the death signal. (An earlier draft clamped `cash ≥ 0` and said "hitting 0 = F6"; both were wrong. The trigger is strictly `cash < interest` at charge time, equivalently `cash < 0` after the subtraction — you can die holding $5k against $42k interest.) This death is always telegraphed one round earlier by `meters.runwayOk === false` (doc 02 §1 ForwardMeters, computed against the max-crunch rate).

---

## 3. Global constants (Layer 2 — tuned integers)

Floor-checked first-pass values. Tune in the spreadsheet, re-run `sim-check.js`, keep the floor win-curve in band (§11).

### 3.1 Starting state (T1 seed — required to initialize a run)

A run cannot be seeded without these. They were missing in the first draft.

| Constant | Value | Unit | Role |
|----------|-------|------|------|
| `startCash` | $20,000 | cash (cents) | T1 pocket cash (default Bootstrapper background). |
| `startEbitda` | $6,000 | annual EBITDA (cents) | T1 starting venture earnings. |
| `startSector` | SOFTWARE | sector | Default starting venture sector (Bootstrapper). |
| `startMultiple` | 6000 (= 6×) | milli-units | **Starting venture multiple.** A deliberately *low* seed (well under SOFTWARE's 14× base) so early multiple-expansion via growth/market is felt; not the sector base. |
| `startOwnership` | 10000 (= 100%) | basis points | Founder owns 100% at T1 (Bootstrapper). Other backgrounds (§GDD Q7) pre-dilute this. |
| `startNetDebt` | 0 | cents | Bootstrapper starts debt-free (high ownership, no credit access). |

**Verifiable seed identity:** initial NetWorth = `trunc(10000 × (trunc(600000 × 6000 / 1000) − 0) / 10000) + 2000000` = `trunc(3,600,000 × 1.0) + 2,000,000` = **$56,000** (cents: `5,600,000`). The "50× from ~$20k" line in §6 refers to *pocket cash → tier bar feel*, not seed net worth; the true compounding target is `$1,000,000 / $56,000 ≈ 17.9×` of net worth over 8 rounds ≈ **1.42×/round** required from the seed. §6 is corrected to use this number.

### 3.2 Economy dials

| Constant | Value | Unit | Role |
|----------|-------|------|------|
| `cashYield` | 0.35 | frac of EBITDA/round | EBITDA → deployable cash conversion in OPERATE step 3. This *adds to* the cash pool; it is the same pool you later reinvest (§6.1 fixes ordering). |
| `organicGrowthDefault` | 0.10 | frac/round | EBITDA growth from the **default starting operating partner**, applied as a system event (§2.1 path). NOT free engine drift: it is attributed to the seed partner every run and to any hired partner; a venture with no partner gets 0. (Corrects the old "unconditional baseline drift" leak.) |
| `carrySeedFrac` | 0.24 | frac | On tier-clear, fraction of net worth that reseeds the next tier's base (see §3.3 for the exact delta recipe). |
| `reseedMult` | 8000 (= 8×) | milli-units | Normalized multiple used to size the reseeded EBITDA base (sector-neutral). |
| `interestMin` / `interestMax` | 0.08 / 0.14 | annual rate | Interest band on net debt in a normal market. |
| `targetLeverage` | 3.0 | ×EBITDA | Prudent net-debt/EBITDA the floor strategy carries. |
| `dangerLeverage` | 6.0 | ×EBITDA | Net-debt/EBITDA danger threshold; forward gauge turns red at/above. |
| `reinvestStart` / `reinvestEnd` | 0.55 / 0.35 | EBITDA per $ reinvested | Reinvestment efficiency, decays over a tier (forces lever-switching). |
| `synergySameSector` | 0.20 | frac of absorbed EBITDA | Same-sector add-on synergy bonus (flat, v1). |
| `congDiscountPerAddon` | 0.08 | frac, per cross-sector add-on | Platform multiple drag, applied as `multiple ×= (1 − 0.08)` per cross-sector add-on (see §3.4). **Stored as a positive magnitude.** |
| `recapPct` | 0.30 | frac of EV | Dividend Recap: cash pulled = `recapPct × EV`, added 1:1 to net debt (§7.7). |

### 3.3 Reseed-on-tier-clear, as explicit deltas (closes the invariant leak)

Reseed is a **system event** that emits a normal `{deltas}` object through the same resolver, so it obeys §7 and is auditable in the action log. On clearing tier T (in DEADLINE_CHECK, before advancing):

```
seedEbitda  = trunc( carrySeedFrac × NetWorth × 1000 / reseedMult )   // = 0.24·NW / 8×
deltas = {
  ebitda:    +seedEbitda           // sets the next tier's earnings base from carried net worth
  multiple:  set to reseedMult (8000) on the carried venture (sector-neutral normalization)
  netDebt:   0
  ownership: unchanged (you carry your slice)
  cash:      NetWorth is paper; pocket cash carries as-is (no cash injected here)
}
```

This is **not** manufacturing score: it converts realized net worth into the *next tier's starting EBITDA at a normalized 8× multiple*, which re-derives to a net worth ≤ the net worth you actually had (the haircut is `carrySeedFrac`). It is logged like any other action.

### 3.4 Conglomerate drag — sign and "unit" pinned (fixes the math bug)

- A **"unit"** = **one cross-sector add-on** (not a dollar, not a sector). One BUY_ADDON whose sector ≠ platform sector applies one unit of drag.
- Drag is **multiplicative and stacks per add-on**: after `n` cross-sector add-ons the platform multiple has been multiplied by `(1 − 0.08)^n`. Each BUY_ADDON applies its own `multiple ×= 0.92` at commit (as a stored delta).
- The constant is stored as **positive `0.08`**. The formula is `newMultiple = trunc(multiple × (1 − congDiscountPerAddon))`. (The old draft stored `−0.08` and wrote `× (1 − (−0.08)) = ×1.08`, which *expanded* the multiple — the opposite of intended. Worked example §10 uses `×0.92`, now consistent.)

---

## 4. Sector bands (Layer 2)

Each sector is a 2-axis fingerprint: base-multiple band + volatility (sd as a fraction of base), plus one signature line. `vol` scales the per-round market-drift delta applied on top of the global state (§7.3); it is **not** a resample of the multiple.

| Sector | Base multiple (`sectorBase`, ×1000) | Volatility (sd/base) | Effective band (≈ ±1σ, normal market) | Signature behaviour |
|--------|------------------------------------:|---------------------:|----------------------------------------|---------------------|
| **SOFTWARE**   | 14× (14000) | 0.30 (spiky) | ~10×–18× | Bubbles hardest; highest ceiling, whips most in a crunch. |
| **SERVICES**   |  5× (5000)  | 0.22 (spiky) | ~4×–6× | Labor-heavy; EBITDA spiky round-to-round, modest multiple. |
| **RETAIL**     |  3× (3000)  | 0.10 (steady) | ~2.7×–3.3× | Cash-rich but multiple-poor; high `cashYield` flavour, low ceiling. |
| **INDUSTRIAL** |  8× (8000)  | 0.12 (steady) | ~7×–9× | Asset-heavy, slow, **crash-resistant** (shallow crunch response). |

`sectorBase` is used **only** (a) to seed a new venture's stored `multiple` at creation, and (b) as `sectorNorm` for exit-quality reputation (§7.6). The live `multiple` thereafter is the stored value drifted by §7.3.

---

## 5. Tier bars & deadlines (Layer 2)

The bar rising 10× each tier **is** the difficulty curve (design §4). Deadlines are first-pass, floor-checked.

| Tier | Net-worth bar | Deadline (rounds) | Who you are | Floor median clear round | Floor clear% |
|------|--------------:|------------------:|-------------|-------------------------:|-------------:|
| **T1** | $1,000,000 | 8 | Scrappy founder, bootstrapped | 5 | 77% |
| **T2** | $10,000,000 | 8 | You raise (dilution wall) | 7 | 46% |
| **T3** | $100,000,000 | 9 | The fork: exit serial *or* empire | 7 | 41% |
| **T4** | $1,000,000,000 | 10 | You become the money | 7 | 40% |
| **★ Endless** | $1B+ | — | Score-chase, escalating modifiers | — | — |

Notes: T1 is the gentle on-ramp (high clear%). **T2 is the real squeeze** — the dilution-vs-bootstrap learning wall — where the floor most often dies on the deadline (~32% of floor runs). T3/T4 are survivor-friendly once the player has internalized the levers; the headroom is intentional so skilled arbitrage/timing converts to a comfortable finish rather than a coin-flip.

---

## 6. Per-round optimal-growth line (Layer 2)

To clear a 10× bar inside its deadline you must compound net worth at the per-round line below. This is the number the **Autopsy "missed deadline"** screen quotes ("You grew 1.31×/round; you needed 1.36×"). T1 is corrected to use the true seed net worth ($56k, §3.1), not pocket cash.

| Tier | Net-worth growth needed | Deadline (rounds) | Required avg growth/round | Realistic line (with carried seed) | Floor observed (winners) |
|------|-------------------------|------------------:|---------------------------|------------------------------------|--------------------------|
| T1 | ~17.9× (from $56k seed NW) | 8 | **1.42×** | n/a (cold start) | ~1.45× early, easing |
| T2 | 10× | 8 | 1.33× | ~1.45× early → ~1.25× late | ~1.4× |
| T3 | 10× | 9 | 1.29× | ~1.45× early → ~1.20× late | ~1.4× |
| T4 | 10× | 10 | 1.26× | ~1.40× early → ~1.18× late | ~1.35× |

**Design target: ~1.45× early-tier, decaying toward ~1.2× late-tier.** The decay is *forced* by reinvestment efficiency (§7.1) — you cannot hold the early line by reinvesting alone; you must switch levers (lever up, arbitrage, ride a bubble, exit). That pressure is the gameplay.

---

## 7. Curves & models (Layer 2)

### 6.1 Round order of operations (authoritative — mirrors doc 02 §2 OPERATE)

Every formula below depends on this sequence. One round:

1. **Market drift roll** → update `market.temp`, per-sector `driftFactor`, `roundsInState`.
2. **Apply drift delta** to each venture's stored `multiple` (§2.1): `multiple += trunc(multiple × (driftFactor − 1))`, floored at 1000.
3. **Cash yield in:** `cash += Σ trunc(venture.ebitda × cashYield)` (+ partner engines, incl. `organicGrowthDefault` EBITDA bumps; passive ventures dampened).
4. **Neglect decay** (§7.8) on ventures with `roundsNeglected ≥ 1`; then increment `roundsNeglected`.
5. **Resolve event cards** (sector shocks) as deltas.
6. **Charge interest:** `cash -= interestDue` → if `cash < 0`, BANKRUPTCY (§2.2).
7. Recompute meters → **ACT** (player) → **SHOP** → **DEADLINE_CHECK**.

The cash that `cashYield` produces (step 3) **is** the pool the player reinvests in ACT; the round-trip (0.35 cash-out then reinvest at 0.55→0.35) is intended and now unambiguous about ordering.

### 7.1 Reinvestment-efficiency decay

`reinvestEff(progress) = reinvestStart + (reinvestEnd − reinvestStart) × min(1, progress)`, where `progress = roundInTier / deadline`, **`roundInTier` is zero-indexed** (first round of a tier = 0). So tier-start `progress = 0` (eff 0.55); a round at index = deadline would give `progress = 1.0` (eff 0.35) but is only reachable if the tier is uncleared at the deadline. `min(1, …)` clamps any Endless/edge case past the deadline to eff 0.35.

| Progress through tier | Efficiency ($ new EBITDA / $ reinvested) |
|----------------------:|------------------------------------------:|
| 0.00 (tier start) | 0.55 |
| 0.25 | 0.50 |
| 0.50 | 0.45 |
| 0.75 | 0.40 |
| 1.00 (deadline)   | 0.35 |

Lesson: pure reinvestment hits diminishing returns inside a tier, so the optimal player **switches levers** mid-tier.

### 7.2 Interest band

`rate = (interestMin + (interestMax − interestMin) × U[0,1]) × marketRateMul`, where `U[0,1]` is one mulberry32 draw (§11) normalized to `[0,1)`.

| Market state | rateMul | Effective rate band | Financing availability | Effect |
|--------------|--------:|---------------------|------------------------|--------|
| Normal | 1.0 | 8% – 14% | open | Baseline cost of leverage. |
| Bubble | 0.9 | ~7.2% – 12.6% | open, cheap | Cheap money; tempts over-leverage right before it compresses. |
| Crunch | 1.8 | ~14.4% – 25.2% | **new TAKE_DEBT / financing cards disabled or COLD-priced** (doc 02 §3.3) | Debt expensive *and* hard to get; over-levered players hit F6 here. |

Crunch doesn't just raise the rate — it **gates new debt issuance** (locked GDD §3-Q3). Existing debt still accrues at the spiked rate.

### 7.3 Multiple-drift / market-cycle model

**Sticky, semi-deterministic, readable a round ahead** (design §9 requirement — never a hidden stochastic surprise). Applied as an **additive delta to the stored multiple** (§2.1), never a resample.

| Parameter | Value | Meaning |
|-----------|-------|---------|
| State set | `{normal, bubble, crunch}` | One global market state. |
| State duration | 2–3 rounds (one bounded draw) | Bubbles/crunches persist; they don't flicker. |
| Transition (when a state expires) | P(bubble)=0.18, P(crunch)=0.18, P(normal)=0.64 | Drawn only at state boundaries. |
| `driftBubble` (multiple factor) | 1.35 | Everything reprices up: sell, don't buy. |
| `driftCrunch` (multiple factor) | 0.75 | Everything compresses + rates spike (7.2): danger. |
| Per-venture jitter | `driftFactor = stateFactor × (1 + sectorVol × tri)` where `tri ∈ [−1,1]` is a **triangular** draw (sum of two uniforms − 1) | Sector volatility (§4) widens the swing; deterministic from the RNG cursor. |
| Telegraph | Next-round state direction shown by the HOT/COLD gauge | Death-by-market is always foreshadowed (design §5 companion rule). |

The market is **not a deck** — it's one global banner that reprices the same hand. `Market-Read` PLAY reveals next round's *direction only*, never magnitude.

### 7.4 Net-Debt/EBITDA danger leverage

| `netDebt / EBITDA` | Zone | Forward-gauge state |
|--------------------:|------|---------------------|
| 0 – 3.0 | Safe | green |
| 3.0 – 6.0 | Stretched | amber |
| ≥ 6.0 (`dangerLeverage`) | Danger | red; one crunch round can trigger F6 |

The runway gauge computes `Interest(maxCrunchRate, totalNetDebt)` against `projectedCash` and turns red a full round before a possible bankruptcy.

### 7.5 Synergy & conglomerate discount (with explicit deltas)

| Add-on type | EBITDA effect | Multiple effect | Cash/Debt effect |
|-------------|---------------|-----------------|------------------|
| **Same-sector** | `ebitda += addon.ebitda + trunc(addon.ebitda × synergySameSector)` (absorbed + 20% bonus) | platform `multiple` unchanged (bolts in at platform multiple) | `cash -= price`; `netDebt += addon.faceDebt` |
| **Cross-sector** | `ebitda += addon.ebitda` (no synergy) | `multiple = trunc(multiple × (1 − congDiscountPerAddon))` (×0.92, per add-on, §3.4) | `cash -= price`; `netDebt += addon.faceDebt` |

The add-on's **price is a real cash outflow** (the missing `{deltas}` from the old draft): `price = trunc(addon.ebitda × m_buy / 1000)`, paid `cash -= price` (a portion may be financed as `netDebt += faceDebt` per the card variant). Self-limiting: a junk-drawer roll-up drags the live Platform Multiple toward its floor, so infinite cross-sector bolting decays.

### 7.6 Exit (paper → real) — the missing core conversion

Exit is the single most important conversion (GDD Tension B). Per doc 02 §3.7, an EXIT on venture `v`:

```
exitMultiple = market.hotWindowArmed ? sectorHotMultiple : min(offer.multiple, sectorLiveMultiple)
exitEV       = trunc(v.ebitda × exitMultiple / 1000)
exitEquity   = exitEV − v.netDebt
proceeds     = trunc(exitEquity × v.ownership / 10000)        // your realized slice
deltas: cash += proceeds ; remove venture (frees a SLOT) ; clear hotWindowArmed if used
```

Exit **zeroes the position** (venture removed) and converts your slice to cash at the live (or hot-window-forced) multiple. Reputation records `exitMultiple / sectorNorm × ownership` as a realized outcome.

### 7.7 PLAYS — delta recipes (the consumables that stress the invariant)

Full per-kind PRE/POST lives in doc 02 §3.6; the **economic magnitudes** are here. All route through the five fields; all are paid for in cash/debt/dilution at purchase, never free.

| PLAY | Delta recipe (this doc owns the numbers) |
|------|------------------------------------------|
| **BRIDGE_LOAN** | `cash += X`; `netDebt += trunc(X × 1.15)` (you repay 15% more, as interest later) |
| **SECONDARY_SALE** | `ownership -= Δbp`; `cash += trunc(ventureEquity × Δbp / 10000)` (sell a slice at current marks) |
| **DOWN_ROUND** | `cash += X`; `ownership -= big Δbp` (cash now, brutal dilution) |
| **TENDER** | `cash -= cost`; `ownership += Δbp` (anti-dilute / buy back) |
| **DIVIDEND_RECAP** (T2+) | `cash += trunc(EV × recapPct)` ; `netDebt += trunc(EV × recapPct)` (pull 30% of EV as new debt — **can be fatal**: it raises interest immediately and is the classic F6 setup) |
| **HOT_WINDOW** | no economic delta; arms `market.hotWindowArmed` so the next EXIT uses `sectorHotMultiple` |
| **ASSET_STRIP** | `cash += X`; `ebitda -= Δ` (sell productive assets for cash) |
| **SPIN_OFF** | `cash += lockedEquity` (locks the unit's value at current marks); remove venture (frees a SLOT) |
| **EARN_OUT** | acquire `cash += 0` now; schedule deferred `cash -= trunc(pct × ebitda)` for N rounds |
| **MARKET_READ** | no economic delta; sets `market.marketReadHint` (next-round direction only) |

`recapPct = 0.30` is the first dial flagged for the greed/bankruptcy tune (§8).

### 7.8 Neglect decay (the locked scarcity mechanic — was entirely missing)

GDD §8-Q4: a held venture that receives no Act that round decays "slowly and chunkily." Modeled as deltas in OPERATE step 4, keyed off `roundsNeglected`:

| `roundsNeglected` | EBITDA delta | Multiple delta | Notes |
|------------------:|--------------|----------------|-------|
| 1 | `ebitda -= trunc(ebitda × 0.04)` | 0 | small dip |
| 2 | `ebitda -= trunc(ebitda × 0.08)` | `multiple -= trunc(multiple × 0.03)` | story starts to fade |
| ≥ 3 | `ebitda -= trunc(ebitda × 0.15)` | `multiple -= trunc(multiple × 0.06)` | real pain |

**Passive ventures (Hire-CEO):** decay rates are halved (and organic growth is dampened) — the agency-cost tradeoff. Any Act targeting a venture resets its `roundsNeglected = 0`. `decayRate` per step is a tuning dial (§8).

### 7.9 Out of scope for this doc (flagged, not silent)

- **Reputation accrual math** beyond the exit-quality term (`exitMultiple / sectorNorm × ownership`) lives in the meta layer (doc 02 `MetaState`). This doc only defines `sectorNorm = sectorBase` (§4) so the term is computable. Full reputation curve is deferred to playtest (GDD §Q7).

---

## 8. Tuning knobs (the dials to turn in playtest)

| Knob | First-pass value | If win-rate too LOW, move… | If too HIGH, move… | Note |
|------|------------------|----------------------------|--------------------|------|
| `carrySeedFrac` | 0.24 | up | down | Single biggest difficulty lever. |
| `deadlineRounds` | [8,8,9,10] | up (esp. T2) | down | T2 is the squeeze; loosen here first if floor death-rate >40%. |
| `organicGrowthDefault` | 0.10 | up | down | Affects baseline floor without touching skill ceiling. |
| `reinvestStart/End` | 0.55 / 0.35 | flatten (raise End) | steepen (lower End) | Controls how hard lever-switching is forced. |
| `interestMax` | 0.14 | down | up | Raises/lowers the bankruptcy floor for levered play. |
| `dangerLeverage` | 6.0 | up | down | How greedy a player can get before red. |
| `synergySameSector` | 0.20 | up | down | Reward for focused roll-ups; watch for runaway accretion. |
| `congDiscountPerAddon` | 0.08 | down (less drag) | up (more drag) | Steepness of the conglomerate self-limit. |
| `recapPct` | 0.30 | — | down | Dividend-recap aggression; primary greed-death dial alongside crunch. |
| `decayRate` | [0.04,0.08,0.15] | down (gentler) | up (harsher) | How punishing neglect is; halved for passive ventures. |
| `driftCrunch` / crunch rateMul | 0.75 / 1.8 | soften | harden | Greed-punishment dial; tune so bankruptcy ≈ 8–12% for greedy play. |

---

## 9. Bankruptcy & death-feel hooks (math side)

| Death type | Trigger (math) | Autopsy number it quotes |
|------------|----------------|--------------------------|
| **Bankruptcy** (liquidity) | F6: `cash < 0` after interest charge (§2.2) | "Interest due $X > Cash $Y" |
| **Missed deadline** (growth) | `NetWorth < bar` at deadline round | "You grew A×/round; you needed B×" (from §6) |

Both are generated from the stored action log, never a re-sim (design §5). The greedy sim pass (§11) confirms F6 is reachable — greed is genuinely fatal, not theoretical.

---

## 10. Worked example (the merge moment)

Platform: SOFTWARE, `ebitda = $1.0M`, `multiple = 14000` (14×), `netDebt = $4M`, `ownership = 6000` (60%).
- EV = `trunc(1.0M × 14000 / 1000)` = **$14M**; Equity = 14M − 4M = **$10M**; your stake = `trunc(10M × 6000 / 10000)` = **$6.0M**.

Bolt on a same-sector add-on: `ebitda_a = $200k`, `m_buy = 5000` (5×) → `price = trunc(200k × 5000 / 1000)` = $1.0M.
- **Cash deltas (now explicit):** `cash -= $1.0M`; `netDebt += $0` (this variant is all-cash). The cash outflow is a real state mutation.
- Synergy: absorbed EBITDA = `200k + trunc(200k × 0.20)` = **$240k** → new platform `ebitda` = **$1.24M**.
- Revalued at platform 14×: EV = `trunc(1.24M × 14000 / 1000)` = **$17.36M**. Accretion ≈ $3.36M of EV from a $1.0M outlay.
- That gap is the **"MULTIPLE ARBITRAGE +$3.36M" flash** — pure F1 recomputed before-vs-after, **render-only, written to no field**. The only writes are `ebitda += 240k`, `cash -= $1.0M`.

Cross-sector counter-example: the same $200k add-on from RETAIL gives no synergy and drags the platform `multiple = trunc(14000 × (1 − 0.08))` = **12880** (12.88×), so EV = `trunc(1.2M × 12880 / 1000)` = $15.46M — accretive but visibly worse. The discipline lesson, felt in the number. (Sign is correct: ×0.92 *compresses*.)

---

## 11. Win-curve sanity check (floor-only smoke test)

Harness: `prototype/sim-check.js`, N=5000 seeded runs, **mulberry32** RNG. It models the **math floor**: a competent-but-plain strategy that only organically grows, levers to `targetLeverage`, reinvests at the round's efficiency, rides sector multiples, and clears each tier by mark-to-market.

**Scope honesty:** the floor does **NOT** model arbitrage, synergy, market-timed exits, neglect decay, PLAYS, or crunch-disabled financing. Those are either skill headroom above the floor (arbitrage/synergy/exits) or punishers the floor avoids (decay, recap). So this is a **smoke test for "is the floor winnable and is greed fatal?"**, *not* a validation of the full model. A full Monte-Carlo with §7.5–7.8 modeled is a P1 deliverable (§12).

**Floor strategy algorithm (so §11 is auditable from the doc, not just the JS):** each round — (1) take debt up to `targetLeverage × EBITDA` if market ≠ crunch; (2) reinvest all free cash above a 1-round interest buffer at `reinvestEff(progress)`; (3) never exit, never arbitrage; (4) advance when `NetWorth ≥ bar`. The greedy variant raises step 1 to `5.8× EBITDA` and keeps no buffer.

### 11.1 Floor strategy (the "is it winnable?" check)

```
Overall win rate (T1->T4): 40.2%
Bankruptcy rate          : 0.0%   (prudent leverage never dies)

Tier | deadline | cleared% | avgRoundCleared | medRound
 T1  |    8     |  77.3%   |       5.5       |    5
 T2  |    8     |  45.6%   |       6.5       |    7
 T3  |    9     |  41.0%   |       6.8       |    7
 T4  |   10     |  40.2%   |       6.6       |    7

Missed-deadline deaths by tier: T1=22.7%  T2=31.7%  T3=4.6%  T4=0.8%
VERDICT: WINNABLE-BUT-TIGHT (floor in target band)
```

### 11.2 Greedy over-lever pass (the "is greed fatal?" check)

Same engine, but the strategy levers to ~5.8× (just under `dangerLeverage`) and keeps no interest buffer.

```
Greedy win rate : 73.4%   (higher reward — leverage magnifies the upside)
Greedy bankrupt :  9.0%   (and magnifies the downside — F6 fires in crunches)
```

### 11.3 Reading the result

- **Winnable but tight:** the plain floor wins ~40% and clears a round or two before each deadline. Slack for a skilled player, a real cliff for a sloppy one.
- **T2 is the wall:** the dilution/leverage tier kills the most floor runs on the deadline — the intended learning spike.
- **Greed is tempting and occasionally fatal (Pillar 4):** over-levering lifts the win rate to ~73% **but** introduces a ~9% bankruptcy rate, all in crunch rounds. The death is telegraphed; a prudent player never bankrupts (0.0%).
- **Skill headroom is intact:** since the floor ignores arbitrage/synergy/exit-timing, a skilled player should clear comfortably above 40%.

**Re-run protocol:** any change to §3–§7 constants must re-run `sim-check.js` and keep **floor win-rate in `[25%, 42%]`** and **greedy bankruptcy in `[8%, 12%]`** before content lock. (The band was tightened from the old `[12%, 45%]`, which was so wide it passed almost any tuning — a no-op watchdog. `[25%, 42%]` keeps the floor genuinely tight; the current 40.2% sits near the top, a candidate to pull toward 30% once arbitrage/skill headroom is measured, per §12.)

---

## 12. Open items routed to playtest (design §9)

- **Full-model Monte-Carlo:** rebuild the harness to include arbitrage, synergy, exits, decay, and PLAYS so §11 stops being floor-only. Until then, "validated" claims are scoped to the floor.
- Synergy magnitude: flat +20% vs escalating curve — needs the full-model run above.
- Exact crunch/bubble durations and transition probabilities — tune so death-by-market never reads as RNG.
- T2 deadline (8 rounds) — first candidate to loosen if live playtest floor death-rate exceeds ~40%.
- Whether the 40% floor win-rate should be tightened to ~30% once arbitrage/skill headroom is measured.
- Neglect-decay rates (§7.8) and `recapPct` (§7.7) — first live exposure of the decay/greed punishers the floor sim doesn't touch.
