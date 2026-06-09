# MULTIPLES — Core Loop & Game State Spec (P0 #2)

> Status: **draft, design-locked**. Implements §4–§7 of `game-design-doc.md`. Paste the schema straight into code.
> Scope: this doc defines (1) the canonical game-state object, (2) the core-loop state machine, (3) every legal player action with pre/postconditions. It does NOT set tuning constants (those live in the Economy & Math Spec / spreadsheet, see §9 of the design doc); constants are referenced here by symbolic name.

---

## 0. Ground rules this spec must obey

These come straight from the locked design doc and constrain every line below.

1. **The §7 hard invariant.** Every card, consumable, and event resolves as a set of *deltas* over exactly five mutable inputs:
   `{ EBITDA, Multiple, NetDebt, Ownership%, Cash }`. There is **no `+score` field anywhere** in the state. Net worth is always a *derived* read, never stored as a writable value. The autopsy, the deadline check, the tier bar all read the same derived function.
2. **Money is integer cents.** All currency fields (`cash`, `netDebt`, `ebitda`, prices) are `int` cents. Display formatting (k/M/B, en-US grouping) is a UI concern, never stored.
3. **Multiple and Ownership are fixed-point integers**, not floats, so the engine is byte-for-byte deterministic across iOS/Android. `multiple` is stored in **milli-units** (×1000: a 14× multiple is `14000`). `ownership` is stored in **basis points** (×10000: 80% is `8000`). Helpers convert at the edges.
4. **Determinism.** Given `(seed, action log)` the entire run replays bit-identically. No `Math.random()`, no wall-clock, no float in the rules core. The RNG cursor advances only through the named draw functions. **All scaling factors are fixed-point integers (basis points) applied with `trunc`; there is never a float multiply on a currency value** (§0.7 below).
5. **Two scarcities, decoupled (§Q4).** `PLAYS` = throughput this round (T1→T4: 2/3/3/4 — see §3 note on T3). `SLOTS` = concurrent held ventures (T1→T4: 1/2/2/3, endless cap 4). They never share a counter.
6. **Pure core / dumb UI.** Everything in this doc is the pure rules engine. The UI calls `applyAction(state, action) -> {state, events[]}` and renders. No game logic in widgets.
7. **Fixed-point money multiply convention.** Any "× a factor" on a currency value uses a **basis-point integer** and truncates:
   `mulBp(amountCents, factorBp) = trunc(amountCents * factorBp / 10000)`. A factor of `12000` means 1.2×. This is the ONLY way the core scales money. `marketPriceMul`, `SYNERGY_BP`, `REINVEST_EFFICIENCY`, recap %, earn-out %, exit pricing all go through `mulBp`. The determinism lint (§5.3) bans any bare `*`/`/` on a currency field that is not wrapped in `mulBp`/`trunc`.

---

## 1. Canonical game state — typed schema

TypeScript is used as the language-neutral schema language. Treat every `number` as an integer (cents / milli-units / basis points as annotated). `readonly` marks fields the rules engine never mutates after creation.

```ts
// ============================================================
// MULTIPLES — canonical game state
// All currency: integer CENTS. multiple: milli-units (x1000).
// ownership: basis points (x10000). No floats in the core.
// ============================================================

// ---------- enums / unions ----------

type Sector = 'SOFTWARE' | 'SERVICES' | 'RETAIL' | 'INDUSTRIAL';
// post-launch: 'CONSUMER' | 'MEDIA' — gated behind reputation, not in v1 pool.

type Tier = 1 | 2 | 3 | 4 | 5; // 5 == endless (★)

type CardType =
  | 'venture'        // start a new venture (consumes a SLOT)
  | 'addon'          // bolt-on acquisition (merges into a platform slot)
  | 'partner'        // operating-partner hire (engine on a venture)
  | 'financing'      // debt / refi / recap instrument
  | 'event'          // market / sector shock (auto-resolves in Operate)
  | 'consumable';    // a PLAY (held in plays inventory)

type MarketTemp = 'COLD' | 'NEUTRAL' | 'HOT';
// HOT == bubble (acquisitions cost more, exits pay more);
// COLD == credit crunch (financing disabled/expensive).

type PhaseId = 'OPERATE' | 'ACT' | 'SHOP' | 'DEADLINE_CHECK' | 'RUN_OVER';

type DeathCause =
  | 'BANKRUPTCY'        // cash < interest due (liquidity death)
  | 'MISSED_DEADLINE';  // tier bar not cleared in time (growth-rate death)

// ---------- the 5 mutable inputs (the ONLY writable economic fields) ----------

interface Deltas {
  // Every card/consumable/event effect is expressed as one of these.
  // Absent field == 0 / no change. Signs carry the real directionality.
  ebitda?: number;       // cents/round, additive
  multiple?: number;     // milli-units, additive (can be negative: conglomerate drag)
  netDebt?: number;      // cents, additive (positive = took on debt)
  ownership?: number;    // basis points, additive (negative = dilution)
  cash?: number;         // cents, additive (negative = spend)
}
// HARD INVARIANT: a Deltas object is the ONLY shape any effect may produce.
// The automated engine test asserts no effect path writes outside these keys
// and that no field listed in SCORE_BANNED_FIELDS is ever writable. (§7, §5.3)

// ---------- a scheduled (deferred) delta — the "later bill" machinery ----------
// Home for EARN_OUT installments, partner fixed costs, recap follow-ons, etc.
// Resolved in OPERATE step 5 (see §2). This is the only deferred-effect channel;
// it keeps the five-input invariant (each entry IS a Deltas) while letting an
// action commit an effect that lands in a future round.

interface ScheduledEffect {
  readonly id: string;             // seeded uuid
  readonly targetVentureId: string | null; // null == applies to run-level cash
  roundsLeft: number;              // ticked down each OPERATE; removed at 0
  recurring: boolean;              // true = fixed cost every OPERATE (partner); false = countdown installment
  // The delta may be RELATIVE to a live value (pct of EBITDA/EV) so it is stored
  // as a basis-point spec, resolved at apply-time via mulBp against the named base:
  readonly basis: 'FIXED' | 'PCT_EBITDA' | 'PCT_EV'; // what the bp multiplies
  readonly bp: number;             // basis points (for PCT_*) — ignored if FIXED
  readonly fixed: Deltas;          // literal cents/milli/bp deltas (for FIXED, or in addition)
  readonly source: 'EARN_OUT' | 'PARTNER_FIXED_COST' | 'RECAP_FOLLOWON';
}

// ---------- an operating-partner engine attached to a venture (the Jokers layer, §6) ----------
// "Permanent engines" live HERE, on the venture, so they have a storable home and
// resolve every OPERATE. A partner is not a separate top-level entity; it is a
// modifier list on the venture it was hired onto.

interface PartnerEngine {
  readonly id: string;             // seeded uuid
  readonly defId: string;          // content-DB archetype
  perRound: Deltas;                // applied to the venture each OPERATE (e.g. +ebitda)
  // fixed cost, if any, is registered as a recurring ScheduledEffect at hire time
  // (PARTNER_FIXED_COST) so all deferred/recurring money flows through ONE channel.
}

// ---------- a venture (a held company; lives across rounds, costs a SLOT) ----------

interface Venture {
  readonly id: string;            // stable uuid (seeded, see RNG)
  readonly sector: Sector;        // the platform's home sector
  ebitda: number;                 // cents/round, the earnings base
  multiple: number;               // milli-units, the LIVE platform multiple
                                  //   (drifts with market + dragged by cross-sector add-ons)
  netDebt: number;                // cents attributed to this venture
  ownership: number;              // basis points YOU own of this venture
  passive: boolean;               // true after Hire-CEO: lower decay, lower upside
  roundsNeglected: number;        // rounds since this venture received any action; drives decay
  absorbedSectors: Sector[];      // sectors of bolted-on add-ons (for conglomerate-drag calc)
                                  //   NOT readonly: BUY_ADDON cross-sector pushes here.
  partners: PartnerEngine[];      // permanent engines hired onto this venture (§3.5)
  // per-add-on value ledger — lets SPIN_OFF return a defensible share without
  // a destructive merge. Each add-on records the equity value it contributed at
  // merge time (its standalone marks), so a spin-off returns that contribution
  // re-marked to the platform's CURRENT multiple. See §3.6 SPIN_OFF.
  addOns: AddOnRecord[];
  get addOnCount(): number;       // == addOns.length (display + synergy bookkeeping)
}

interface AddOnRecord {
  readonly id: string;            // seeded uuid
  readonly sector: Sector;        // the add-on's home sector (cross- vs same-sector)
  readonly ebitdaContributed: number;     // cents/round folded into the platform at merge
  readonly netDebtContributed: number;    // cents of debt folded in
  readonly mergeMultiple: number;         // platform multiple (milli) at merge time
}

// ---------- a card in the deal-flow hand (§Q3) ----------

interface Card {
  readonly id: string;            // unique instance id this round
  readonly defId: string;         // points into the content DB (the archetype + variant)
  readonly type: CardType;
  readonly sector: Sector | null; // null for type-agnostic cards (some financing/consumables)
  // FACE values — raw inputs only, shown to the player (§Q3 "show the chips, hide the wisdom").
  // The content DB GUARANTEES every venture/addon face is generated within its
  // SECTOR_BAND (§4). The engine therefore NEVER clamps a face the player saw —
  // doing so would make the displayed chip lie (§Q3). The band is a content-gen
  // constraint, asserted by a content-lint test, NOT an engine-time clamp.
  readonly faceEbitda: number | null;   // cents/round on offer (venture/addon/partner)
  readonly faceMultiple: number | null; // milli-units on offer (already in-band by content guarantee)
  readonly facePrice: number;           // cents. SIGN CONVENTION below.
  readonly faceDebt: number;            // cents debt this card adds/enables
  readonly defaults: Deltas;            // the BASE deltas this card applies on play
  readonly targeted: boolean;           // true if it must target an existing venture
  readonly consumableKind?: ConsumableKind; // present iff type==='consumable'
}
// facePrice SIGN CONVENTION (resolves the inflow/outflow ambiguity):
//   facePrice is ALWAYS a non-negative magnitude in cents.
//   Its direction is fixed BY CARD TYPE, never by sign:
//     venture / addon / partner  -> facePrice is a COST   (cash -= mulBp(facePrice, marketPriceMul))
//     financing RAISE            -> facePrice is NEW MONEY (cash += facePrice)  [the "m" in dilution]
//     financing TAKE_DEBT        -> facePrice is PROCEEDS  (cash += facePrice)
//   Consumables carry their economic effect in `defaults` / per-kind table, not facePrice.

type ConsumableKind =
  | 'BRIDGE_LOAN' | 'SECONDARY_SALE' | 'DOWN_ROUND' | 'TENDER'
  | 'DIVIDEND_RECAP' | 'HOT_WINDOW' | 'ASSET_STRIP' | 'SPIN_OFF'
  | 'EARN_OUT' | 'MARKET_READ';

// ---------- UI event contract (returned from applyAction, never persisted) ----------

type GameEventType =
  | 'MULTIPLE_ARBITRAGE'   // BUY_ADDON committed; carries realized accretion
  | 'DILUTION'             // RAISE/DOWN_ROUND cut ownership
  | 'EXIT_REALIZED'        // EXIT paid out
  | 'HOT_WINDOW_ARMED' | 'HOT_WINDOW_FIRED' | 'HOT_WINDOW_EXPIRED'
  | 'MARKET_READ_REVEALED'
  | 'NEGLECT_DECAY' | 'INTEREST_CHARGED'
  | 'SCHEDULED_EFFECT_FIRED'
  | 'ACTION_REJECTED'      // PRE failed; carries reason
  | 'BANKRUPTCY' | 'MISSED_DEADLINE' | 'TIER_CLEARED' | 'WON';

interface GameEvent {
  readonly type: GameEventType;
  readonly ventureId?: string;
  readonly deltas?: Deltas;        // what hit the five inputs, for animation
  readonly amount?: number;        // headline number (cents/milli/bp per type)
  readonly reason?: string;        // phrasing key (rejections, autopsy flavor)
}

// ---------- market state (single global banner, NOT a deck) (§Q3) ----------

interface MarketState {
  temp: MarketTemp;               // current weather
  roundsInState: number;          // how long we've been HOT/COLD (sticky 2–3 rounds)
  // per-sector multiple drift, milli-units, applied to ventures each Operate:
  sectorDrift: Record<Sector, number>;
  // HOT_WINDOW: armed by the play, forces the NEXT exit to roll the high multiple.
  // It has a one-window LIFETIME (§Q2 "force next exit"): cleared when an EXIT
  // fires it, OR auto-expires at the start of OPERATE if it has been armed for a
  // full round without an exit (hotWindowExpiresRound). It never persists silently.
  hotWindowArmed: boolean;
  hotWindowExpiresRound: number | null; // absolute (tier,round) flattened counter; null if disarmed
  // MARKET_READ: reveals NEXT round's direction only. Lifetime = exactly one round.
  // Set during ACT, consumed/cleared at the start of the next OPERATE after it is
  // surfaced to the UI (marketReadExpiresRound). Never a stale flag.
  marketReadHint: MarketTemp | null;
  marketReadExpiresRound: number | null;
}

// ---------- RNG (seeded, deterministic) ----------

interface RngState {
  readonly seed: number;          // run seed (also used to derive run id)
  cursor: number;                 // monotonically increasing draw counter; never rewinds
  // The PRNG is a pure function f(seed, cursor) -> uint32. Every draw
  // increments cursor by a fixed amount per named draw call, so replay is exact.
}

// ---------- action log (drives the autopsy; NOT a re-sim) (§Q5) ----------

interface LoggedAction {
  readonly round: number;
  readonly tier: Tier;
  readonly type: ActionType;       // see §3
  readonly cardDefId?: string;
  readonly targetVentureId?: string;
  readonly appliedDeltas: Deltas;  // exactly what hit the 5 inputs
  readonly cashAfter: number;
  // derived snapshot, logged for the autopsy headline. NOT game state the engine
  // reads back to simulate (§Q5). Explicitly whitelisted by the §7 invariant test
  // (see SCORE_BANNED_FIELDS note) because it is log-only and write-once.
  readonly netWorthAfterSnapshot: number;
  readonly note?: string;          // pre-baked phrasing key for the death library
}

// ---------- forward meters (telegraph death a round ahead) (§Q5 companion rule) ----------

interface ForwardMeters {
  projectedCashNextRound: number;   // cents, after expected EBITDA inflow & scheduled effects
  debtServiceNextRound: number;     // cents = interestDue(run) next OPERATE
  runwayOk: boolean;                // projectedCash >= debtService
  // growthRate is realized: netWorth(now) vs the baseline captured at tier entry,
  // expressed as milli-units (1.31x == 1310). Requires the snapshot below.
  growthRateThisTier: number;       // milli-units, realized
  growthRateNeeded: number;         // milli-units required to clear the bar in time
  marketTempGauge: MarketTemp;      // mirrors market.temp for the HOT/COLD gauge
}

// ---------- RUN STATE (one playthrough; wiped on death/win) ----------

interface RunState {
  readonly runId: string;
  readonly backgroundId: string;    // founder background chosen at run start (§Q7)
  tier: Tier;
  round: number;                    // round within the current tier (1-based)
  phase: PhaseId;

  cash: number;                     // cents in pocket — the only truly safe number

  ventures: Venture[];              // held companies; length <= slotsMax(tier)
  hand: Card[];                     // the deal-flow hand drawn this round
  handSize: number;                 // how many cards were drawn this round (3–5, §Q3)
  plays: Card[];                    // held consumable inventory (max = playsHeldMax(tier))
  shopOffers: Card[];               // offers presented in SHOP this round (rerollable)
  scheduled: ScheduledEffect[];     // deferred/recurring effects (earn-outs, partner costs)

  // economy budgets for the CURRENT round:
  playsRemaining: number;           // throughput left this round (decrements per Act)
  rerollsUsed: number;              // banker-fee rerolls taken this round (cost scales)

  // baselines for derived meters (snapshots, NOT score — never read by effects):
  netWorthAtTierEntry: number;      // captured when a tier begins; feeds growthRateThisTier
  netWorthLastRound: number;        // captured at end of each round; per-round growth read

  market: MarketState;
  rng: RngState;
  log: LoggedAction[];
  meters: ForwardMeters;

  // derived caches (recomputed, never authored — kept for cheap UI reads):
  readonly slotsMax: number;        // = slotsMax(tier)
  readonly playsMax: number;        // = playsPerRound(tier)
  readonly playsHeldMax: number;    // = playsHeldMax(tier)

  // end-of-run:
  death: { cause: DeathCause; round: number; tier: Tier } | null;
  won: boolean;                     // reached the $1B win bar
}

// ---------- META STATE (persists across runs; horizontal only, §Q7) ----------

interface MetaState {
  readonly schemaVersion: number;       // for save migration
  reputation: number;                   // Track Record total (realized outcomes only)
  metaLevel: number;                    // derived tier of reputation, gates unlocks
  furthestTierReached: Tier;            // consolation progress even on losses
  unlockedCards: string[];              // archetype/variant defIds available to the deal-flow pool
  unlockedSectors: Sector[];            // base 4 always; CONSUMER/MEDIA unlock here
  unlockedBackgrounds: string[];        // founder backgrounds (each = a difficulty mode)
  hardModes: string[];                  // unlocked hard-mode ids
  cosmetics: {
    titles: string[];                   // cosmetic title ladder (score-chasers)
    activeTitle: string | null;
    iconSkins: string[];
  };
  // local-only stats (no server):
  lastDeathCause: DeathCause | null;    // for the opposite-death callback ("timidity → greed")
  runsPlayed: number;
  cleanExits: number;                   // count of exits that met the CLEAN_EXIT rule (§3.7)
}

// ---------- the whole persisted blob ----------

interface SaveFile {
  readonly schemaVersion: number;
  meta: MetaState;
  run: RunState | null;                 // null between runs; non-null == resumable autosave
}
```

### Derived reads (never stored)

```ts
// EV = EBITDA * Multiple ; Equity = EV - NetDebt ; NetWorth = Σ(Own% * Equity) + Cash
// All fixed-point: multiple is /1000, ownership is /10000.

function ventureEV(v: Venture): number {        // cents
  return Math.trunc(v.ebitda * v.multiple / 1000);
}
function ventureEquity(v: Venture): number {     // cents (can be negative)
  return ventureEV(v) - v.netDebt;
}
function ventureNetWorth(v: Venture): number {   // your share, cents
  return Math.trunc(ventureEquity(v) * v.ownership / 10000);
}
function netWorth(run: RunState): number {       // THE SCORE — always derived
  return run.ventures.reduce((s, v) => s + ventureNetWorth(v), 0) + run.cash;
}
function totalNetDebt(run: RunState): number {
  return run.ventures.reduce((s, v) => s + v.netDebt, 0);
}
function interestDue(run: RunState): number {     // flat rate * net debt (§7)
  return Math.trunc(totalNetDebt(run) * INTEREST_RATE_BP / 10000);
}
// canonical fixed-point money scaler (§0.7) — the ONLY way money is multiplied:
function mulBp(amountCents: number, factorBp: number): number {
  return Math.trunc(amountCents * factorBp / 10000);
}
```

There is intentionally **no `score`, `netWorth`, or `points` field in `RunState`** that any effect can write. Anything that wants the score calls `netWorth(run)`. The only persisted snapshots (`netWorthAtTierEntry`, `netWorthLastRound`, `log[].netWorthAfterSnapshot`) are write-once meter/log baselines, never read by any card/consumable/event resolution path; they are named with the `…Snapshot`/`…AtTierEntry`/`…LastRound` suffixes precisely so the §7 lint can whitelist them by exact name (see §5.3).

---

## 2. The core loop as a state machine

Four phases per round, plus a terminal state. The loop runs inside one tier; clearing the deadline advances the tier and resets `round` to 1.

```
        ┌─────────────────────────────────────────────────────────┐
        │                      (start of round)                    │
        ▼                                                          │
   ┌─────────┐  auto-resolve   ┌──────┐  player done   ┌──────┐    │
   │ OPERATE │ ───────────────▶│ ACT  │ ──────────────▶│ SHOP │    │
   └─────────┘                 └──────┘                 └──────┘    │
        ▲                         │  bankruptcy            │       │
        │                         │  during Act            │ done  │
        │                         ▼                        ▼       │
        │                    ┌──────────┐  pass    ┌────────────────┐
        │   bar not cleared, │ RUN_OVER │◀─────────│ DEADLINE_CHECK │
        └────────────────────┤          │   fail   └────────────────┘
          rounds remain      └──────────┘                 │ cleared tier
                                  ▲                        ▼
                                  │                  advance tier OR
                                  └──────────────────  WIN ($1B at T4)
```

### Phase definitions and transitions

**OPERATE** — fully automatic, no player input.
1. Expire stale market flags FIRST: if `market.hotWindowExpiresRound` has passed, clear `hotWindowArmed` (emit `HOT_WINDOW_EXPIRED`); if `market.marketReadExpiresRound` has passed, clear `marketReadHint`. This is what guarantees no flag persists across rounds (resolves the armed-flag-forever bug).
2. Roll market drift; update `market.temp`, `sectorDrift`, `roundsInState` (sticky 2–3 rounds; semi-scripted per §9, never a hidden stochastic model).
3. Apply `sectorDrift` to each venture's `multiple` (Layer-2 market weather; obeys invariant — only touches `Multiple`).
4. Each venture throws off EBITDA into cash, plus partner engines: `cash += Σ ventureCashYield(v)` where `ventureCashYield(v)` is defined below. Partner `perRound` deltas and the `passive` damping resolve here.
5. Resolve **scheduled effects** (`run.scheduled`): for each entry, compute its delta (`FIXED` → `fixed`; `PCT_EBITDA`/`PCT_EV` → `mulBp(base, bp)` plus `fixed`), apply to target venture or run cash, tick `roundsLeft`. Non-recurring entries at `roundsLeft === 0` are removed; recurring entries (partner fixed costs) persist while the partner exists. Emit `SCHEDULED_EFFECT_FIRED`.
6. Apply **neglect decay**: for any venture with `roundsNeglected >= 1`, apply chunky decay deltas to **EBITDA only** (the earnings base erodes; multiple is left to the market). 1 round = small `-EBITDA` (`NEGLECT_DECAY_BP_R1`); 3 = real pain (`NEGLECT_DECAY_BP_R3`); see §4. Passive ventures use the reduced curve (`NEGLECT_DECAY_BP_PASSIVE_*`). Then increment `roundsNeglected` for all (reset to 0 by any Act that targets the venture).
7. Resolve any `event` cards surfaced this round (sector shocks, crashes) as Deltas.
8. **Charge interest:** `cash -= interestDue(run)` (emit `INTEREST_CHARGED`).
   - **If `cash < 0` after interest → transition to RUN_OVER with `cause = BANKRUPTCY`.** (Liquidity death. It was telegraphed last round by `meters.runwayOk === false`.)
9. Snapshot `netWorthLastRound = netWorth(run)` AFTER all the above (used next round for per-round growth). Recompute `meters`. Transition to **ACT**.

```ts
// EBITDA inflow + partner engines, dampened if passive. Pure, no RNG.
function ventureCashYield(v: Venture): number { // cents into pocket this OPERATE
  const partnerEbitda = v.partners.reduce((s, p) => s + (p.perRound.ebitda ?? 0), 0);
  const grossEbitda = v.ebitda + partnerEbitda;
  // 'yield' is the earnings that convert to pocket cash this round; passive
  // ventures convert at the dampened rate (agency cost) per §Q4.
  const bp = v.passive ? CASH_YIELD_BP_PASSIVE : CASH_YIELD_BP_ACTIVE;
  return mulBp(grossEbitda, bp);
}
```

**ACT** — the decision phase. Player spends `playsRemaining` on legal actions (§3).
- Each action that costs throughput decrements `playsRemaining`.
- Targeting a venture resets that venture's `roundsNeglected = 0`.
- Player may issue actions until `playsRemaining === 0` or they choose "end turn".
- If any action would drive `cash < 0` → the action is **rejected at precondition** (actions never push you bankrupt mid-Act; bankruptcy only happens via interest in OPERATE, the telegraphed death). Deferred negatives (EARN_OUT installments, partner fixed costs) are NOT mid-Act spends — they enter `run.scheduled` and only ever land in OPERATE step 5, where bankruptcy is a legal telegraphed outcome.
- Transition to **SHOP** when the player ends the turn or runs out of plays.

**SHOP** — between-round spend (§5.3). Uses **cash only**, does **not** consume `playsRemaining`. Available offers live in `run.shopOffers`: financial instruments, one-shot consumables (PLAYS), and cosmetic/meta items. Add-on acquisitions and operating-partner hires are **deal-flow cards** played in ACT (they cost a PLAY); they are NOT bought in SHOP. SHOP is the consumable/financing counter only — this removes the buy-vs-play contradiction. A **reroll** (banker fee) refreshes `run.shopOffers` here at scaling cost; in ACT the same reroll refreshes `run.hand`.
- Buying a consumable adds it to `plays[]` (rejected if `plays.length === playsHeldMax`).
- Player confirms "advance" → transition to **DEADLINE_CHECK**.

**DEADLINE_CHECK** — evaluate the tier bar.
- Compute `nw = netWorth(run)`. Note this runs AFTER ACT, so a tier-clearing EXIT made this round is already reflected; the prior-round telegraph (`growthRateThisTier < needed`) is a forecast, and a final-round winning move legitimately overrides it (the telegraph is a warning, not a verdict — see §5.3 telegraph test wording).
- **If `nw >= TIER_BAR[tier]`:**
  - **Win is defined as clearing the T4 bar, and `TIER_BAR[4]` IS the $1B win bar** (`1_000_000_000_00` cents). So at `tier === 4`, clearing the bar IS the win: set `won = true`, transition to **RUN_OVER** (victory; offer Endless). There is no separate nested billion check — the outer threshold and the win threshold are the same number by definition.
  - Else (`tier < 4`) advance: `tier += 1`, `round = 1`, recompute `slotsMax/playsMax/playsHeldMax`, set `netWorthAtTierEntry = nw`, draw a fresh hand, transition to **OPERATE**.
- **Else (bar not cleared):**
  - If `round < TIER_DEADLINE_ROUNDS[tier]` → `round += 1`, reset `playsRemaining = playsMax`, `rerollsUsed = 0`, draw a fresh hand, transition to **OPERATE**.
  - Else (out of rounds) → transition to **RUN_OVER** with `cause = MISSED_DEADLINE`. (Growth-rate death; telegraphed by `meters.growthRateThisTier < growthRateNeeded`.)
- Tier 5 (Endless) has no win path: `TIER_BAR[5]` is treated as unreachable (`Infinity` sentinel in the bar map's intent), so DEADLINE_CHECK in endless only ever fails-out on the deadline; `won` is never set in T5.

**RUN_OVER** — terminal.
- Read final outcome data from `run` **before** wiping it. Sequence is strict: (1) build the **Autopsy** from `log` (§Q5) — three rows pulled from the stored action log, never a counterfactual re-sim; (2) settle **reputation** from realized outcomes only (see formula below); (3) `meta.furthestTierReached = max(meta.furthestTierReached, run.tier)`; (4) `meta.lastDeathCause = run.death?.cause ?? null`; `meta.runsPlayed += 1`; (5) ONLY THEN `run = null`.
- **Reputation settlement (§Q7), realized outcomes only — paper net worth never counts:**
  ```
  repFromExit      = mulBp(exitProceeds, trunc(exitMultiple * 10000 / sectorNorm))  scaled by ownership-at-exit
  repFromSecondary = a fraction REP_SECONDARY_BP of secondary-sale proceeds
  repFromDividend  = a fraction REP_DIVIDEND_BP of dividend-recap cash actually banked
  reputation += repFromExit (per clean exit) + repFromSecondary + repFromDividend
  ```
  Exits, secondaries, and dividends are the ONLY three contributors, matching the "realized outcomes only" rule. These accrue to a run-local tally as they happen (so the data exists at RUN_OVER without a re-sim) and are committed to `meta.reputation` in step (2).

### Phase invariants
- `phase` only ever advances along the arrows above; there is no free jump.
- The RNG cursor advances **only** in OPERATE (market/event/decay rolls) and in the named draw functions (hand draw, shop-offer draw, reroll). No other path touches `rng`.
- Every transition is a pure function `step(state) -> state`; the UI never mutates `phase` directly.

---

## 3. Every legal player action (preconditions + postconditions)

All actions go through one dispatcher:

```ts
type ActionType =
  | 'START_VENTURE' | 'RAISE' | 'TAKE_DEBT' | 'BUY_ADDON'
  | 'HIRE_PARTNER' | 'PLAY_CONSUMABLE' | 'EXIT' | 'REROLL'
  | 'REINVEST' | 'HIRE_CEO' | 'END_TURN';

interface Action {
  type: ActionType;
  cardId?: string;          // hand/shop card this action consumes
  targetVentureId?: string; // for targeted actions
  targetAddOnId?: string;   // for SPIN_OFF of a specific bolted-on unit
  consumableId?: string;    // for PLAY_CONSUMABLE (from plays[])
  sell?: boolean;           // PLAY_CONSUMABLE sell-a-play variant
}

function applyAction(run: RunState, a: Action): { run: RunState; events: GameEvent[] };
```

Notation below: **PRE** = precondition (else action is rejected, no state change, emit `ACTION_REJECTED`), **POST** = postcondition (Deltas applied + bookkeeping). Every POST is expressible purely as `Deltas` on the five inputs plus whitelisted bookkeeping (ventures add/remove, scheduled-effect add/remove, slot/play counters, neglect reset, log). "costs 1 play" = `playsRemaining -= 1`.

> **Venture add/remove and the §7 invariant.** Adding a venture (START_VENTURE), removing one (EXIT, SPIN_OFF), and merging an add-on (BUY_ADDON) DO change `netWorth(run)`, but they are structural array operations, not writes to a banned score field. The §5.3 invariant test whitelists `ventures[]` membership changes explicitly: it asserts that the *economic* effect of each structural op equals a sum of Deltas (e.g. a START_VENTURE's net-worth change equals the new venture's `ventureNetWorth` minus the cash spent), so no value is conjured outside the five inputs.

---

### 3.1 START_VENTURE  (begin a new company; consumes a SLOT)
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; `ventures.length < slotsMax`; selected `card.type === 'venture'`; `cash >= mulBp(card.facePrice, marketPriceMul(market))`.
- **POST:**
  - `cash -= mulBp(facePrice, marketPriceMul(market))` (HOT raises price; COLD lowers it).
  - Create `Venture { sector, ebitda: faceEbitda, multiple: faceMultiple (used AS-SHOWN — content DB already guarantees it is in SECTOR_BAND; no clamp), netDebt: card.faceDebt, ownership: 10000, passive: false, roundsNeglected: 0, absorbedSectors: [], partners: [], addOns: [] }`.
  - `playsRemaining -= 1`; log it.
- **Lesson:** founding = 100% ownership, small base. The climb starts lean.

### 3.2 RAISE  (equity raise: grow the pie, cut your slice — Tension A)
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; target venture exists; card is a `financing` raise; **`ventureEquity(target) > 0`** (you cannot price a raise into an over-levered venture with non-positive equity — that path is rejected with reason `"raise_blocked_negative_equity"`; use TAKE_DEBT or EXIT instead); raises allowed in COLD but at worse terms via the card variant.
- **POST (real cap-table dilution, §7 Layer 1):**
  - New money `m = card.facePrice` (facePrice is NEW MONEY for a RAISE, per the sign convention). `cash += m` (v1 default routes raise cash to pocket).
  - Dilution computed on **whole-venture pre-money equity**, defined precisely as `preMoneyEquity = ventureEquity(target)` (EV − netDebt, the value confirmed positive in PRE):
    `postMoney = preMoneyEquity + m`; `target.ownership = trunc(target.ownership * preMoneyEquity / postMoney)`. This is the multiplicative form of "newOwn% = (your stake value) / post-money"; with positive `preMoneyEquity` the two formulations agree.
  - Apply card `defaults` (e.g. `+EBITDA`, `+Multiple` growth from the round).
  - reset `target.roundsNeglected = 0`; `playsRemaining -= 1`; log it; emit `DILUTION`.
- **Lesson:** the pie grows, your slice shrinks. Felt as `ownership` ticking down.

### 3.3 TAKE_DEBT  (leverage: magnifies both ways)
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; target venture exists; `market.temp !== 'COLD'` OR card is a COLD-priced variant; resulting `netDebt/EBITDA` may exceed the danger threshold but is **allowed** (rope to hang yourself — death is via interest, telegraphed).
- **POST:**
  - `cash += card.facePrice` (proceeds — facePrice is PROCEEDS for TAKE_DEBT); `target.netDebt += card.faceDebt`.
  - No interest charged now; interest is the flat `mulBp(totalNetDebt, INTEREST_RATE_BP)` charged every OPERATE.
  - reset neglect; `playsRemaining -= 1`; log it (note key `"took_leverage"` for autopsy row 3).
- **Lesson:** cash now, a recurring bill forever. Over-lever into a crunch and you die.

### 3.4 BUY_ADDON  (the merge — multiple arbitrage, §6)  — ACT action, costs a PLAY
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; a **platform** target venture exists; `card.type === 'addon'`; `cash >= mulBp(facePrice, marketPriceMul(market))`.
- **POST (the signature move):**
  - `cash -= mulBp(facePrice, marketPriceMul(market))` (buy the add-on at its **low** face multiple).
  - Record the unit for later spin-off (non-destructive ledger): push `AddOnRecord { sector: addon.sector, ebitdaContributed: addon.faceEbitda, netDebtContributed: addon.faceDebt, mergeMultiple: platform.multiple }` onto `platform.addOns`.
  - Absorb earnings: `platform.ebitda += addon.faceEbitda`; `platform.netDebt += addon.faceDebt`.
  - **Same-sector** (`addon.sector === platform.sector`): synergy `platform.ebitda += mulBp(addon.faceEbitda, SYNERGY_BP)` (+20% v1); platform `multiple` unchanged → absorbed earnings instantly revalue at the high platform multiple.
  - **Cross-sector:** zero synergy; push `addon.sector` into `platform.absorbedSectors`; apply **conglomerate drag** `platform.multiple += CONGLOMERATE_DRAG` (negative milli-units, scaled by off-sector share).
  - reset neglect; `playsRemaining -= 1`; log it.
  - Emit `MULTIPLE_ARBITRAGE` with the realized accretion delta **after commit** (never previewed on the face).
- **Lesson:** cheap earnings bolted onto an expensive platform revalue up; junk-drawer roll-ups self-limit via drag.

### 3.5 HIRE_PARTNER  (operating partner: organic compounder — the permanent-engine / Jokers layer, §6)  — ACT action, costs a PLAY
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; target venture exists; `cash >= facePrice` (partner is a cost; facePrice is a COST for type `partner`).
- **POST:**
  - `cash -= facePrice`.
  - Attach the engine to the venture: push `PartnerEngine { defId, perRound: card.defaults }` onto `target.partners`. The per-round `+EBITDA` resolves in OPERATE step 4 via `ventureCashYield`.
  - If the variant carries a fixed cost, register it as a **recurring** `ScheduledEffect { source: 'PARTNER_FIXED_COST', recurring: true, targetVentureId: null, basis: 'FIXED', fixed: { cash: -fixedCost }, roundsLeft: -1 }` (negative `roundsLeft` = lives until the partner is removed). This is the operating-leverage knife: great at volume, deadly at thinness.
  - reset neglect; `playsRemaining -= 1`; log it.
- **Lesson:** slow organic EBITDA growth; fixed-cost variants reward scale and punish thinness.

### 3.6 PLAY_CONSUMABLE  (a PLAY from inventory; one-shot)
- **PRE:** `phase === ACT`; consumable is in `plays[]`; its own per-kind PRE holds (below); if `targeted`, target venture exists. **Does NOT consume `playsRemaining`** unless the kind specifies it — PLAYS are a separate held resource (§Q2). *(Tuning note: if playtests show this is too strong, gate big plays behind 1 throughput; flagged in §6, not locked.)*
- **POST:** apply the kind's Deltas (and/or push a `ScheduledEffect` for deferred kinds); remove from `plays[]`; log it.

Per-kind PRE/POST. All money scaling uses `mulBp` against a **defined base**; no naked floats.
| Kind | PRE | POST |
|---|---|---|
| **BRIDGE_LOAN** | — | `cash += X` now; `target.netDebt += Y` (Y>X), cost lands later as interest |
| **SECONDARY_SALE** | target venture; `target.ownership > 0` | sell `Δbp` of your stake: `proceeds = trunc(ventureEquity(target) * Δbp / 10000)`; `cash += proceeds`; `target.ownership -= Δbp`. `Δbp` is the card's `defaults.ownership` magnitude. (Converts paper → real at the live mark; tallies to reputation as a secondary.) |
| **DOWN_ROUND** | target venture | `cash += X`; `target.ownership -= big` (brutal dilution); emit `DILUTION` |
| **TENDER** | target venture; `cash >= cost` | `cash -= cost`; `target.ownership += Δbp` (buy back / anti-dilute) |
| **DIVIDEND_RECAP** | `tier >= 2`; target venture | `pull = mulBp(ventureEV(target), RECAP_PCT_BP)`; `cash += pull`; `target.netDebt += pull` (greed; can be fatal). `RECAP_PCT_BP` defined in §4. |
| **HOT_WINDOW** | — | `market.hotWindowArmed = true`; set `market.hotWindowExpiresRound = flatRound(run) + 1` (one-window lifetime, §Q2); emit `HOT_WINDOW_ARMED`. No economic delta until exit. |
| **ASSET_STRIP** | target venture | `cash += X`; `target.ebitda -= Δ` (sell productive assets for cash) |
| **SPIN_OFF** | target add-on (`targetAddOnId` ∈ `target.addOns`) OR a whole venture | If an `AddOnRecord`: re-mark its contribution to the platform's CURRENT multiple and return your share: `unitEquity = trunc(rec.ebitdaContributed * platform.multiple / 1000) - rec.netDebtContributed`; `proceeds = trunc(unitEquity * platform.ownership / 10000)`; `cash += proceeds`; subtract `rec.ebitdaContributed`/`rec.netDebtContributed` from the platform; remove the record. (Per-add-on ledger makes this defensible — no destructive merge.) If a whole venture: `cash += ventureNetWorth(v)`; remove from `ventures[]` (frees a SLOT). |
| **EARN_OUT** | target/new acquisition | acquire with `cash += 0` now; push `ScheduledEffect { source:'EARN_OUT', recurring:false, basis:'PCT_EBITDA', bp: EARN_OUT_PCT_BP, fixed:{}, roundsLeft: EARN_OUT_ROUNDS, targetVentureId: <acq> }` → each OPERATE pays `cash -= mulBp(target.ebitda, EARN_OUT_PCT_BP)` for N rounds |
| **MARKET_READ** | — | `market.marketReadHint = nextTempDirection`; set `market.marketReadExpiresRound = flatRound(run) + 1` (one-round lifetime); emit `MARKET_READ_REVEALED` next time UI reads it. Direction only, never magnitude. |

- **Sell-a-play** (`sell: true`): any held consumable sells for ~50% of purchase price (`cash += trunc(price/2)`; remove from `plays[]`). Does not consume throughput. Teaches liquidity.

`flatRound(run)` = a monotonically increasing round counter across tiers (e.g. `run.tier * 100 + run.round`) used only to date the one-window flag expiries; it is bookkeeping, not economy.

### 3.7 EXIT  (acquisition / IPO — convert paper to real, Tension B)
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; target venture exists; an exit offer card is present (or the always-available baseline exit at market terms).
- **POST:**
  - Determine exit multiple: base `min(offer.multiple, sectorMarketMultiple)`; if `market.hotWindowArmed` → use the **high** market multiple, then clear the flag and `hotWindowExpiresRound` (emit `HOT_WINDOW_FIRED`).
  - Compute equity at the exit multiple: `evAtExit = trunc(v.ebitda * exitMultiple / 1000)`; `equityAtExit = evAtExit - v.netDebt`; `proceeds = trunc(equityAtExit * v.ownership / 10000)`.
  - `cash += proceeds`; remove venture from `ventures[]` (frees a SLOT); emit `EXIT_REALIZED`.
  - **CLEAN_EXIT rule:** an exit is "clean" iff `equityAtExit > 0` AND `exitMultiple >= CLEAN_EXIT_MIN_MULTIPLE` (§4). Clean exits increment `meta.cleanExits` at RUN_OVER and feed reputation; a fire-sale (non-positive equity) banks cash but earns no reputation.
  - Record realized-outcome metadata for reputation (the `repFromExit` term in §2).
  - `playsRemaining -= 1`; log it with note `"exit"` (and `"held_too_long"` flavor if market was COLD).
- **Lesson:** paper becomes real only on exit; timing the market (HOT vs COLD) is the whole game.

### 3.8 REROLL  (banker fee — recover a bad hand)
- **PRE:** `phase === ACT || phase === SHOP`; `cash >= rerollCost(rerollsUsed)`.
- **POST:** `cash -= rerollCost(rerollsUsed)`; `rerollsUsed += 1`; redraw the **target deck for the current phase** — `run.hand` in ACT, `run.shopOffers` in SHOP — via the named RNG draw (advances `rng.cursor`). Does **not** consume `playsRemaining`.
- **Lesson:** opportunity cost has a price; a bad hand is recoverable but never free.

### 3.9 REINVEST  (always-available baseline; no hand unwinnable, §Q3)
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; at least one venture exists; `cash >= reinvestAmount`.
- **POST:**
  - `cash -= amount`; `target.ebitda += mulBp(amount, reinvestEfficiencyBp(run, target))`.
  - reset neglect; `playsRemaining -= 1`; log it.
- **Lesson:** brute-force growth always exists but at diminishing efficiency, so smarter plays beat it.

```ts
// Efficiency is a DECAY CURVE, not a scalar: it falls with cumulative reinvest into
// the same venture, so spamming reinvest self-limits (§9). Keyed off reinvestCount,
// a small per-venture counter (bookkeeping, not economy). Returns basis points.
//   reinvestEfficiencyBp: starts at REINVEST_EFF_START_BP (~5500 = 0.55),
//   decays toward REINVEST_EFF_FLOOR_BP (~3500 = 0.35) by REINVEST_EFF_STEP_BP per prior reinvest.
function reinvestEfficiencyBp(run: RunState, v: Venture): number {
  const eff = REINVEST_EFF_START_BP - v.reinvestCount * REINVEST_EFF_STEP_BP;
  return Math.max(REINVEST_EFF_FLOOR_BP, eff);
}
// (Venture gains: `reinvestCount: number` — increment after each REINVEST on it.)
```

### 3.10 HIRE_CEO  (delegation: convert a venture to passive — agency cost, §Q4)
- **PRE:** `phase === ACT`; `playsRemaining >= 1`; target venture exists; `venture.passive === false`; `cash >= ceoCost`.
- **POST:**
  - `cash -= ceoCost`; `venture.passive = true`.
  - Passive ventures: reduced neglect-decay curve and dampened cash yield (`CASH_YIELD_BP_PASSIVE`). This is how **empire-hold scales depth instead of slot count**.
  - reset neglect; `playsRemaining -= 1`; log it.
- **Lesson:** delegation lets you hold more without busywork, at the price of lower returns (agency cost).

### 3.11 END_TURN  (leave ACT)
- **PRE:** `phase === ACT`.
- **POST:** transition `phase = SHOP`. No economic delta.

---

### Action ↔ economy-budget matrix

| Action | Costs a PLAY (throughput) | Touches a SLOT | Phase |
|---|---|---|---|
| START_VENTURE | yes | +1 (new) | ACT |
| RAISE | yes | — | ACT |
| TAKE_DEBT | yes | — | ACT |
| BUY_ADDON | yes | merges (no new slot) | ACT |
| HIRE_PARTNER | yes | — | ACT |
| PLAY_CONSUMABLE | no (held resource) | SPIN_OFF frees one | ACT |
| EXIT | yes | −1 (frees) | ACT |
| REROLL | no | — | ACT/SHOP |
| REINVEST | yes | — | ACT |
| HIRE_CEO | yes | — | ACT |
| END_TURN | no | — | ACT |

> SHOP buys (consumables, financing instruments) cost **cash only, never a PLAY**. Add-ons and partners are ACT cards (they cost a PLAY) and are not sold in SHOP — this is the single canonical path for each card type.

**PLAYS vs SLOTS, restated for the engine:**
- `playsMax` (throughput / round): T1 **2**, T2 **3**, T3 **3** (v1 ships 3; the 3-vs-4 question is OPEN, see §6), T4 **4**.
- `playsHeldMax` (consumable inventory): T1 **2**, T2 **2**, T3 **2**, T4 **3** (scales toward 3 by T4 per §Q2).
- `slotsMax` (concurrent ventures): T1 **1**, T2 **2**, T3 **2** (deliberately stays at 2 so the exit fork bites), T4 **3**, endless cap **4**.

```ts
// T3 plays-per-round: v1 default is 3. This is NOT design-locked (§6, §Q4).
// The single source of truth is T3_PLAYS_PER_ROUND so the prototype can flip
// 3<->4 in one place without editing the literal below.
const T3_PLAYS_PER_ROUND = 3; // OPEN: tune 3 vs 4 in prototype (§6)
function playsPerRound(t: Tier): number  { return ({1:2,2:3,3:T3_PLAYS_PER_ROUND,4:4,5:4})[t]; }
function playsHeldMax(t: Tier): number   { return ({1:2,2:2,3:2,4:3,5:3})[t]; }
function slotsMax(t: Tier): number       { return ({1:1,2:2,3:2,4:3,5:4})[t]; }
```

---

## 4. Symbolic constants (values live in the Economy & Math Spec)

Referenced above by name; the spreadsheet/headless prototype owns the integers (§9). Listed so the engine compiles against named imports, not magic numbers. **Every "%/×" constant is basis points (×10000) so it is consumed by `mulBp` with no float.**

```ts
const TIER_BAR: Record<Tier, number>;            // net-worth cents to clear each tier; TIER_BAR[4] === 1_000_000_000_00 (the win bar); TIER_BAR[5] = unreachable sentinel (endless)
const TIER_DEADLINE_ROUNDS: Record<Tier, number>;// rounds allowed per tier
const INTEREST_RATE_BP: number;                  // flat interest, basis points of net debt
const SYNERGY_BP: number;                         // 2000 == +20% same-sector synergy (v1)
const CONGLOMERATE_DRAG: number;                  // negative milli-units per off-sector unit
const NET_DEBT_DANGER_BP: number;                 // ~6x EBITDA warning threshold

// reinvest decay curve (§3.9), basis points:
const REINVEST_EFF_START_BP: number;             // ~5500 (0.55)
const REINVEST_EFF_FLOOR_BP: number;             // ~3500 (0.35)
const REINVEST_EFF_STEP_BP: number;              // decay per prior reinvest into same venture

// cash-yield (OPERATE step 4), basis points of EBITDA converted to pocket cash:
const CASH_YIELD_BP_ACTIVE: number;
const CASH_YIELD_BP_PASSIVE: number;             // lower (agency cost)

// neglect decay (OPERATE step 6), basis points of EBITDA lost:
const NEGLECT_DECAY_BP_R1: number;               // 1 round neglected (small)
const NEGLECT_DECAY_BP_R3: number;               // 3 rounds (real pain)
const NEGLECT_DECAY_BP_PASSIVE_R1: number;
const NEGLECT_DECAY_BP_PASSIVE_R3: number;

// consumable %s (§3.6), basis points:
const RECAP_PCT_BP: number;                      // dividend-recap pull as % of EV
const EARN_OUT_PCT_BP: number;                   // earn-out installment as % of EBITDA
const EARN_OUT_ROUNDS: number;                   // number of installments

// exit / reputation (§3.7, §2):
const CLEAN_EXIT_MIN_MULTIPLE: number;           // milli-units; below this an exit is not "clean"
const REP_SECONDARY_BP: number;                  // reputation per cent of secondary proceeds
const REP_DIVIDEND_BP: number;                   // reputation per cent of dividend banked

function marketPriceMul(m: MarketState): number; // RETURNS BASIS POINTS (HOT >10000, COLD <10000); consumed only via mulBp
function rerollCost(used: number): number;        // scaling banker fee, cents
const SECTOR_BAND: Record<Sector, {lo:number; hi:number}>; // multiple bands, milli-units — a CONTENT-GEN constraint (face values are generated in-band), not an engine clamp
```

---

## 5. Engine test hooks (enforce the locks)

### 5.1 Whitelists the invariant test depends on

```ts
// Fields that look score-ish but are legitimate write-once snapshots / logs.
// The §7 invariant test allows writes ONLY to these named fields (exact match),
// and bans any OTHER field whose name matches /score|networth|points/i.
const SCORE_SNAPSHOT_WHITELIST = [
  'netWorthAtTierEntry',
  'netWorthLastRound',
  'netWorthAfterSnapshot', // on LoggedAction
];
// Structural ops the invariant test treats as legal (not "outside the five inputs"),
// provided their economic effect reconciles to a sum of Deltas:
const STRUCTURAL_OPS_WHITELIST = ['ventures.add', 'ventures.remove', 'addons.merge', 'scheduled.add', 'scheduled.remove'];
```

### 5.2 The checks

1. **Invariant test (§7):** for every card/consumable/event def, run `applyAction` against a fixture and assert the diff touches **only** `Deltas` keys (`ebitda|multiple|netDebt|ownership|cash`) plus whitelisted bookkeeping (`roundsNeglected`, `reinvestCount`, slot/play counters, `ventures[]`/`scheduled[]`/`addOns[]`/`partners[]` membership, log). Any write to a field whose name matches `/score|networth|points/i` and is **not** in `SCORE_SNAPSHOT_WHITELIST` fails the build. (This is a machine-checkable name rule — "semantically named" is dropped in favor of an exact regex + explicit whitelist.)
2. **Reconciliation test (structural ops):** for START_VENTURE / EXIT / SPIN_OFF / BUY_ADDON, assert `Δnetworth == (sum of the action's cash/equity Deltas)` so adding/removing a venture never conjures value outside the five inputs.
3. **Directionality test:** leverage increases both upside and downside; same-sector add-on is strictly accretive vs cross-sector. Assert signs, not magnitudes.
4. **Determinism test:** replay `(seed, log)` twice → byte-identical `RunState`. Lint rule bans any bare `*`/`/` on a currency-typed value not wrapped in `mulBp`/`trunc` (catches `marketPriceMul` float multiplies, recap %, earn-out %).
5. **No-unwinnable-hand test:** every drawn hand contains a legal REINVEST path within current cash, or the baseline reinvest is injected.
6. **Telegraph test (§Q5 companion rule):** any state that *enters* RUN_OVER via BANKRUPTCY or MISSED_DEADLINE must have had `meters.runwayOk === false` (bankruptcy) or `meters.growthRateThisTier < growthRateNeeded` (deadline) set at the END of the prior round. The telegraph is a *forecast surfaced before ACT*; a player who clears the bar with a final-round EXIT legitimately escapes a flagged meter — that is the meter doing its job (a warning, not a false alarm), and the test only asserts the flag was raised, not that death was unavoidable.
7. **Flag-lifetime test:** assert `hotWindowArmed` and `marketReadHint` are always cleared within one round of being set (by firing or by OPERATE step 1 expiry) — no flag survives two OPERATE passes unconsumed.

### 5.3 Determinism lint
No `Math.random`, no `Date.now`, no float literal in the rules core. Currency multiply must route through `mulBp`. RNG only via named draw functions.

---

## 6. Open hooks (defer to prototype, not debate — §9)

- Exact tuning integers for all §4 constants (spreadsheet owns them).
- Whether PLAY_CONSUMABLE should cost 1 throughput for the heavy plays (flagged in §3.6).
- **T3 plays-per-round final value (3 vs 4).** v1 ships **3** via `T3_PLAYS_PER_ROUND`; flip in one place after Monte-Carlo.
- Market drift/momentum function and sticky-state durations (kept scripted/semi-deterministic).
- Synergy flat +20% vs escalating curve (needs Monte-Carlo).
- Conglomerate-drag scaling shape (flat per off-sector unit vs share-weighted).

*Everything above the §6 line is design-locked structure; the integers below it are the only things still moving.*
