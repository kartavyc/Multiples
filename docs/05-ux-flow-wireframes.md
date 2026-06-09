# MULTIPLES — UX Flow & Low-Fi Wireframe Set (P0 #5)

> Status: **draft, design-locked structure**. Implements the UI surface of `game-design-doc.md` (§1–§10) and `docs/02-core-loop-game-state.md` (the four-phase state machine + every legal action).
> Scope: this doc defines (1) the **screen inventory** (= the build list), (2) the **per-round tap flow**, (3) low-fi grey-box wireframes for every key screen. It is layout + interaction only. **No color, no visual design, no animation spec** — those now live in `docs/07-art-style-bible.md` ("THE TERMINAL" direction, locked 2026-06-06) with canonical mockups at `docs/mockups/layout-a-v4.html` and `docs/mockups/ui-v4-all-screens.html`. This doc still owns layout + interaction; the bible owns skin + juice.
> Hard constraint inherited from §7: the UI may render only the five mutable inputs `{EBITDA, Multiple, Net Debt, Ownership%, Cash}` plus the derived `Net Worth`. There is **no `+score` to show** because there is none to store. The HUD reads `netWorth(run)` live; it never displays a points value the engine wrote.

---

## 0. Design constraints this doc must obey

These bound every screen below.

1. **Portrait, one-thumb.** Single 9:19.5-ish column. All primary actions sit in the bottom ~40% of the screen (thumb zone). The top ~25% is glanceable read-only state. Nothing load-bearing in the top corners.
2. **No animation crutches.** The §Q5 "telegraph death a round ahead" rule means the player must understand the run from **static state**, not from a motion they might miss. Every meter has a text label and a discrete fill; if all animation were removed the game would still be fully legible and playable. Animation, when added later, is garnish on an already-readable frame.
3. **Five numbers + Net Worth stay glanceable, always.** They live in a fixed HUD that is present (in full or condensed form) on every in-run screen. Same order, same place, every screen: **CASH · EBITDA · MULTIPLE · NET DEBT · OWN% → NET WORTH**. Muscle memory beats labels.
4. **Show the chips, hide the wisdom (§Q3).** A card face shows raw inputs only (EBITDA, Multiple, price, debt, sector). The post-deal mechanical revaluation is one tap away (the "napkin"). The downstream *judgment* (is this a good deal?) is never shown, ever.
5. **Paper vs real is a visual rule, not a number (§3 Tension B).** Net Worth is "ghosted ink / unspendable" framing; Cash is "solid." We encode this with weight/border treatment (a ghost-outline box vs a solid box), legible in pure greyscale. No color dependency.
6. **Right-sized for two people.** ~9 reusable screens, not 30. Card face, napkin overlay, HUD, and meter widgets are **shared components** reused across phases. A "screen" here is mostly a re-arrangement of the same parts.
7. **Tap, not drag, is the primary verb.** Drag is allowed as an *optional* accelerator (flick a card to play) but every drag has a tap equivalent. The game is fully playable tap-only. No gesture is the only way to do anything.
8. **Confirmation only where it bites.** Irreversible / fatal-adjacent actions (EXIT, DIVIDEND_RECAP, big TAKE_DEBT, advancing past the deadline) get a one-line confirm. Cheap reversible-feel actions (REINVEST, REROLL) commit on tap.

---

## 1. Screen inventory (the build list)

Nine screens + four shared components. Numbered as build tickets. "Phase" maps to `PhaseId` in the state machine.

| # | Screen | Maps to phase / state | Purpose | Priority |
|---|--------|----------------------|---------|----------|
| **S0** | **Title / Continue** | pre-run (`run === null` or resumable) | New run, continue autosave, go to Desk. Dead simple. | P0 |
| **S1** | **Run HUD (the frame)** | every in-run phase | The persistent shell: 5 numbers + Net Worth + 2 forward meters + market banner. All other in-run screens render *inside* this frame. | P0 — build first |
| **S2** | **Operate digest** | `OPERATE` (auto) | A brief read-only "what just happened" beat: cash in, interest charged, drift, decay. No input. Dismiss to ACT. | P0 |
| **S3** | **Deal-Flow Hand (ACT)** | `ACT` | The core decision screen. The 3–5 card hand + plays strip + venture rail + END TURN. Where the game is *played*. | P0 — core |
| **S4** | **Card Face + Napkin** (overlay) | invoked from S3/S5 | Tap a card → enlarged face (raw inputs) → tap again → napkin (post-deal mechanical preview). Targeting + confirm live here. | P0 — core |
| **S5** | **Shop** | `SHOP` | Cash-only buys: consumables (PLAYS) + financing instruments. Reroll. Advance. | P0 |
| **S6** | **Valuation / Scoring Moment** (overlay) | fires on BUY_ADDON / EXIT / RAISE | The Balatro-style "watch the number move" beat. Renders the realized deltas on the five inputs. Static-legible version first. | P0 — the dopamine |
| **S7** | **Deadline Check / Tier Clear** | `DEADLINE_CHECK` | "Did you clear the bar?" Net Worth vs Tier Bar, rounds left, advance or fail. | P0 |
| **S8** | **Autopsy (death)** | `RUN_OVER` (death) | The three-row death screen from the action log (§Q5). | P0 |
| **S9** | **The Desk (meta / unlock)** | meta, between runs | Reputation, unlocks, Founder Background pick, titles. The "between runs" home. | P0 |
| **(S10)** | **Victory / Endless toggle** | `RUN_OVER` (won) | Reuses S8 layout inverted: you hit $1B. Offer Endless. | P1 (skin of S8) |

**Shared components (build once, reuse everywhere):**
- **C-HUD** — the 5-number + Net Worth strip (S1).
- **C-METERS** — the two forward gauges: debt-runway + market temp.
- **C-CARD** — one deal/play card face (raw inputs, type glyph, sector tag).
- **C-NAPKIN** — the tap-to-inspect overlay body (mechanical preview math).

---

## 2. Per-round tap flow

One round = OPERATE → ACT → SHOP → DEADLINE_CHECK. Taps below are the *minimum* to advance; a greedy player taps more in ACT/SHOP.

```
ROUND START
  │
  ▼
[S2 OPERATE digest]  ← auto-computed, read-only
  • shows: cash in, interest charged, market drift, any decay/event
  • TAP "Continue"  ───────────────────────────────────┐ (1 tap)
                                                        ▼
[S3 ACT — Deal-Flow Hand]   playsRemaining = playsMax(tier)
  │  loop while plays remain & player wants to act:
  │    TAP a card ──▶ [S4 face] ──▶ TAP "inspect" ──▶ [S4 napkin]
  │                                   │
  │                                   ├─ targeted? TAP a venture in the rail to aim
  │                                   └─ TAP "PLAY" (confirm if fatal-adjacent)
  │                                        │
  │                                        ├─ BUY_ADDON / EXIT / RAISE ──▶ [S6 scoring moment] ──▶ back to S3
  │                                        └─ other ──▶ delta lands in HUD ──▶ back to S3
  │    (optional) TAP a play in the strip ──▶ [S4] ──▶ PLAY   (does NOT cost throughput)
  │    (optional) TAP "Reroll (banker fee)" ──▶ new hand
  │
  └─ TAP "END TURN"  ───────────────────────────────────┐ (1 tap; auto-prompted when plays hit 0)
                                                         ▼
[S5 SHOP]   cash only, no throughput
  • browse consumables + financing offers
  • (optional) TAP buy ; (optional) TAP reroll ; (optional) sell a held play
  • TAP "Advance" (confirm) ───────────────────────────┐ (1 tap)
                                                        ▼
[S7 DEADLINE_CHECK]
  • netWorth vs TIER_BAR ; rounds left
  • cleared & tier<4 ──▶ TIER CLEAR card ──▶ TAP "Next Tier" ──▶ next OPERATE
  • cleared & tier==4 ──▶ [S10 Victory]
  • not cleared, rounds remain ──▶ TAP "Next Round" ──▶ next OPERATE
  • out of rounds ──▶ [S8 Autopsy: MISSED_DEADLINE]
  (bankruptcy can also fire inside S2 OPERATE step 8 ──▶ [S8 Autopsy: BANKRUPTCY])
```

**Minimum taps for a fast round** (operate-only, no acts wanted, just survive): `Continue → End Turn → Advance → Next Round` = **4 taps**. A snackable round with one real decision is ~6–8 taps. This keeps sessions in the §9 20–30 min target.

**Tap-count budget per surface** (design ceiling, keeps it un-fiddly):
- Play one card start-to-commit: **3 taps** (select → inspect/aim → play). 2 if untargeted and you skip the napkin.
- End a passive round: **4 taps** (above).
- Reach a decision from cold-open: title → continue → (operate) continue → in ACT = **3 taps**.

---

## 3. Wireframes

ASCII grey boxes. `=` / `#` = heavier weight (solid, "real": Cash, primary buttons). `.` / single-line `─ │` = lighter weight (ghosted, "paper": Net Worth, secondary). `▓ ░` used for discrete meter fills. Phone frame is ~`[ 40 cols ]` wide to stand in for portrait.

---

### S1 — Run HUD (the persistent frame) · component C-HUD + C-METERS

Always on screen during a run. Top zone = read-only state. The five numbers in fixed order; Net Worth derived and ghost-boxed; Cash solid-boxed. Below them, the two forward meters and the market banner. The bottom ~60% is the "stage" where S2/S3/S5 content renders.

```
┌──────────────────────────────────────┐
│ T2 · ROUND 3/6        seed#4F2A   ⚙   │  tier · round/deadline · run id · settings
├──────────────────────────────────────┤
│  ╔══════════════╗   .................. │
│  ║ CASH         ║   : NET WORTH      : │  CASH = solid box (real)
│  ║  $182k       ║   :   $4.21M  ⌜p⌟  : │  NET WORTH = dotted box (paper/ghost),
│  ╚══════════════╝   .................. │     'p' tag = "paper, unspendable"
│  ┌──────┬──────┬──────────┬─────────┐  │
│  │EBITDA│MULT  │ NET DEBT │  OWN%   │  │  the 4 supporting inputs, one row,
│  │ $310k│ 11.0×│  $1.20M  │   64%   │  │  same order forever
│  └──────┴──────┴──────────┴─────────┘  │
│  RUNWAY  ▓▓▓▓▓▓░░░  OK   next: $48k/$96k│  debt-service-next vs projected-cash
│  MARKET  ░░░|██|░░  NEUTRAL  (read: —) │  HOT/COLD temp gauge + market-read hint
│  ┌────────────────────────────────┐    │
│  │  〔 SOFTWARE bubble forming 〕  │    │  one-line market banner (the global state)
│  └────────────────────────────────┘    │
├──────────────────────────────────────┤
│                                        │
│         << STAGE: S2 / S3 / S5 >>      │  phase content renders here
│                                        │
└──────────────────────────────────────┘
```

Notes:
- **Order is law.** CASH first (it is the only safe number), then NET WORTH (the goal, ghosted), then the four levers. Never reorder per screen.
- **RUNWAY meter** (= `meters.runwayOk` + `debtServiceNextRound` / `projectedCashNextRound`): discrete fill + the literal two numbers `next: $48k/$96k` (debt due / projected cash). When `runwayOk === false`, the fill empties past the line and the label flips to `LOW` (this is the bankruptcy telegraph — must be readable with zero motion).
- **MARKET meter** (= `meters.marketTempGauge`): a three-zone bar with a marker; `(read: —)` shows the MARKET_READ hint when one is armed (`(read: HOT↑)`), else `—`.
- Tapping any of the five numbers opens a one-line plain-language tooltip ("MULTIPLE: what the market pays per $1 of earnings"). Teaching-by-tap, never a forced essay.

---

### S2 — Operate digest (auto, read-only)

The "what just happened while you weren't deciding" beat. Pure summary of OPERATE steps 2–8. No input except dismiss. Keeps the auto-phase legible so market death never feels like RNG.

```
┌──────────────────────────────────────┐
│ [ C-HUD condensed: CASH $182k  NW $4.21M ]
├──────────────────────────────────────┤
│              THE YEAR PASSED            │
│                                        │
│   Operations                +$96k cash │  Σ ventureCashYield
│   Interest on debt          −$48k cash │  interestDue — shown even if 0
│   Market drift     SOFTWARE  +0.4×     │  sectorDrift on your sectors
│   Neglect (Venture B, 2rd)  −$12k EBITDA│ only if any venture decayed
│   Event: —                              │  surfaced event card, if any
│   ────────────────────────────────────  │
│   Net cash this round       +$48k       │
│                                        │
│   〔 RUNWAY still OK next round 〕      │  restates the telegraph in words
│                                        │
│        ╔════════════════════════╗      │
│        ║      C O N T I N U E    ║      │  single solid button → ACT
│        ╚════════════════════════╝      │
└──────────────────────────────────────┘
```

Notes:
- Each line is a delta on exactly one of the five inputs, labeled in plain words. This screen *is* the §7 invariant made visible: every change traces to a lever.
- If a death is imminent next round, the RUNWAY line reads `〔 WARNING: interest next round $96k > projected cash $61k 〕` here — telegraph #1, a full round ahead.

---

### S3 — Deal-Flow Hand (ACT) · the core screen

The hand (3–5 cards) + plays strip + venture rail + throughput counter + END TURN. This is where most taps happen. Bottom-anchored cards = thumb-reachable.

```
┌──────────────────────────────────────┐
│ [ C-HUD full (S1 top zone) ]           │
├──────────────────────────────────────┤
│ VENTURES (slots 2/2)                   │  the venture rail (held companies)
│ ┌───────────┐ ┌───────────┐            │
│ │�#A SOFTWARE│ │ B SERVICES│            │  tap to select as target;
│ │$310k 11.0×│ │$140k  5.0×│  zz(2rd)   │  'zz' = neglected, '#' = selected
│ │own 64%    │ │own 100%   │  ⚠decay    │
│ └───────────┘ └───────────┘            │
├──────────────────────────────────────┤
│ PLAYS  [ Bridge ] [ + ]      held 1/2  │  consumables strip (does NOT cost throughput)
├──────────────────────────────────────┤
│ THIS ROUND'S DEALS         PLAYS 2/3 ◀ │  throughput remaining this round
│ ┌────────┐┌────────┐┌────────┐┌──────┐ │
│ │ ADD-ON ││ RAISE  ││PARTNER ││ EXIT │ │  the hand — horizontally scrollable
│ │SERVICES││  —     ││SOFTWARE││ OFFER│ │  if 5 cards
│ │EB $40k ││+$250k  ││+EB/rd  ││ B @  │ │  FACE = raw inputs only
│ │ 4.5×   ││ −own   ││ $30k   ││ 6.0× │ │
│ │buy $90k││        ││        ││      │ │
│ └────────┘└────────┘└────────┘└──────┘ │
│  REINVEST (baseline) ▸  always here     │  the guaranteed no-unwinnable-hand play
│ ┌──────────────┐      ╔═══════════════╗ │
│ │ Reroll  $15k │      ║   END  TURN    ║ │  banker fee │ solid advance
│ └──────────────┘      ╚═══════════════╝ │
└──────────────────────────────────────┘
```

Notes:
- **PLAYS X/Y** (top-right of the hand) is the throughput meter (`playsRemaining`/`playsMax`). When it hits 0, END TURN auto-pulses and remaining unplayed cards dim (opportunity cost felt, no words).
- **Venture rail** doubles as the target picker: a targeted card (ADD-ON, RAISE, PARTNER, EXIT, REINVEST) lights the rail and you tap the venture to aim. A neglected venture shows `zz(Nrd)` + `⚠decay`.
- **PLAYS strip** is visually separate from the hand and labeled `held 1/2` so the two scarcities never blur (the §Q4 decoupling, made spatial). `[ + ]` is empty inventory slots.
- Card faces never show a net-worth delta. `ADD-ON … buy $90k / 4.5×` is all raw. The accretion is hidden until S6 fires post-commit.
- Tapping a card → **S4**.

---

### S4 — Card Face + Napkin (overlay) · components C-CARD + C-NAPKIN

Two-stage overlay. Stage 1 = enlarged face (still raw inputs). Stage 2 = napkin (mechanical post-deal preview — the math, not the judgment). Targeting + the commit button live here.

**Stage 1 — Face (raw):**
```
┌──────────────────────────────────────┐
│  ✕                          ADD-ON     │  dismiss · card type
│ ┌────────────────────────────────────┐ │
│ │            SERVICES add-on          │ │
│ │                                     │ │
│ │   EBITDA on offer        $40k /rd   │ │  raw face values only
│ │   Multiple               4.5×       │ │
│ │   Price (cash)           $90k       │ │
│ │   Debt it brings         $0         │ │
│ │                                     │ │
│ └────────────────────────────────────┘ │
│   Target:  〔 tap a venture ▸ 〕        │  targeted card → pick from rail
│ ┌────────────────┐ ┌─────────────────┐ │
│ │  INSPECT (napkin)│ │     PLAY  ▸      │ │  inspect → stage 2 │ commit
│ └────────────────┘ └─────────────────┘ │
└──────────────────────────────────────┘
```

**Stage 2 — Napkin (mechanical preview, after INSPECT):**
```
┌──────────────────────────────────────┐
│  ✕                      THE NAPKIN  ✎  │  the back-of-envelope
│   Buy SERVICES add-on → Platform #A    │
│  ────────────────────────────────────  │
│   You pay              − $90k cash      │  what leaves
│   Platform absorbs      + $40k EBITDA   │  what merges
│   Same sector?           NO (cross)     │  ← drives synergy vs drag
│   Synergy bonus          + $0           │  cross-sector = zero
│   Platform multiple      11.0× → 10.6×  │  conglomerate DRAG shown
│  ────────────────────────────────────  │
│   After commit, EBITDA folds in at the  │  plain-language mechanic,
│   platform's multiple. Off-sector       │  NOT "good/bad deal" judgment
│   earnings drag the platform down.      │
│  ────────────────────────────────────  │
│       ╔══════════════════════════╗     │
│       ║      PLAY  THIS  DEAL      ║     │  commit → S6 scoring moment
│       ╚══════════════════════════╝     │
└──────────────────────────────────────┘
```

Notes:
- The napkin shows the **mechanical** before/after of the five inputs (`11.0× → 10.6×`), never "this is +$X net worth" and never "this is a good idea." It surfaces the *rule* (cross-sector drags), so the lesson is felt on the next deal.
- For a **same-sector** add-on the napkin reads `Synergy bonus +$8k EBITDA` and `Platform multiple 11.0× → 11.0× (held)` — the arbitrage setup, still without the final number, which only flashes in S6.
- For RAISE the napkin shows `Ownership 64% → 57%` + `Cash +$250k` (dilution made concrete pre-commit). For EXIT it shows the exit multiple it will roll and the resulting `proceeds → cash`, with a `〔 HOT WINDOW armed: will roll 14× 〕` line if applicable.
- INSPECT is optional. A confident player taps PLAY from stage 1. The napkin is the teaching ramp, not a toll.

---

### S5 — Shop (between rounds, cash only)

Consumables (PLAYS) + financing instruments. No throughput cost. Reroll + sell-a-play live here. Add-ons/partners are NOT here (they are ACT cards) — this keeps one canonical path per card type.

```
┌──────────────────────────────────────┐
│ [ C-HUD condensed: CASH $134k  held 1/2 ]
├──────────────────────────────────────┤
│           SHOP  ·  cash only           │
│ ┌────────┐┌────────┐┌────────┐         │
│ │ PLAY   ││ PLAY   ││FINANCE │         │
│ │Secondary││Hot     ││Refi    │         │
│ │ Sale   ││Window  ││ −rate  │         │
│ │ $0*    ││ $45k   ││ $60k   │         │  * Secondary nets cash, not costs
│ │ buy ▸  ││ buy ▸  ││ buy ▸  │         │
│ └────────┘└────────┘└────────┘         │
│                                        │
│ YOUR PLAYS (sell for ~50%)             │
│ ┌────────────┐                          │
│ │ Bridge Loan │  [ sell $7k ]           │  liquidity lesson: dump a held play
│ └────────────┘                          │
│                                        │
│ ┌──────────────┐      ╔═══════════════╗ │
│ │ Reroll  $20k │      ║   ADVANCE  ▸   ║ │  refresh offers │ → DEADLINE_CHECK
│ └──────────────┘      ╚═══════════════╝ │
└──────────────────────────────────────┘
```

Notes:
- `held 1/2` in the condensed HUD makes the inventory cap visible before you buy (a buy is rejected at cap; the UI greys "buy" when full rather than letting you tap into a rejection).
- ADVANCE asks a one-line confirm only if RUNWAY is `LOW` ("Advance with interest underfunded next round?") — the last telegraph before a possible bankruptcy.

---

### S6 — Valuation / Scoring Moment (overlay) · the dopamine beat

Fires *after commit* on the value-moving actions (BUY_ADDON, EXIT, RAISE). The Balatro "watch the number move" beat — but **static-legible first**: even with all animation stripped, the player reads exactly which of the five inputs moved and the realized headline. Animation later just sequences these same rows.

**BUY_ADDON (same-sector arbitrage) — the signature "that's allowed?!":**
```
┌──────────────────────────────────────┐
│                                        │
│            MULTIPLE  ARBITRAGE          │  the §6 flash, post-commit only
│                                        │
│     $40k earnings  ×  bought at 4.5×    │  what you paid for
│            ▼  bolted onto              │
│     Platform #A    @  11.0×             │  where it landed
│  ────────────────────────────────────  │
│     EBITDA   $310k  →  $356k            │  +40k absorbed +8k synergy
│     Multiple 11.0×  →  11.0×  (held)    │  same-sector: no drag
│  ────────────────────────────────────  │
│        ┌──────────────────────┐         │
│        │  + $506k  EQUITY VALUE │        │  the realized accretion headline
│        └──────────────────────┘         │     (derived; NOT a stored score)
│                                        │
│            ╔════════════════╗           │
│            ║      NICE.      ║           │  dismiss → back to S3
│            ╚════════════════╝           │
└──────────────────────────────────────┘
```

**EXIT (paper → real):**
```
┌──────────────────────────────────────┐
│                EXIT                    │
│   Venture B  ·  SERVICES  ·  IPO        │
│  ────────────────────────────────────  │
│   Exit multiple rolled      6.0×        │  HOT WINDOW shows 14× here if armed
│   Equity at exit            $640k       │
│   Your ownership            100%        │
│  ────────────────────────────────────  │
│   ░ paper  $640k  ══▶  ╔═══════════╗    │  ghost → solid: the whole thesis
│                        ║ +$640k    ║    │  cash box is heavy/solid
│                        ║ CASH      ║    │
│                        ╚═══════════╝    │
│   Slot freed (1/2)  ·  clean exit ✓     │  frees a slot; reputation flag
│            ╔════════════════╗           │
│            ║   CASHED  OUT   ║           │
│            ╚════════════════╝           │
└──────────────────────────────────────┘
```

Notes:
- The headline (`+$506k EQUITY VALUE`, `+$640k CASH`) is computed from the committed deltas, never read from a score field. S6 is the single place the player *sees* the arbitrage pay off — it is deliberately withheld from the card face and napkin (§Q3) so the reveal lands.
- The EXIT panel's `paper → solid` row is the §3 Tension-B visual: ghost box collapsing into a solid Cash box. Works in pure greyscale via border weight.
- This overlay is **reused** for all three triggers; only the header + the headline rows differ. One component, three skins.

---

### S7 — Deadline Check / Tier Clear

The bar moment. Net Worth vs the tier bar, rounds left. Two outcomes shown; a third (fail) routes to S8.

**Cleared (tier < 4):**
```
┌──────────────────────────────────────┐
│             TIER  CLEARED              │
│                                        │
│   NET WORTH   ░ $11.4M                  │  ghost number (the goal)
│   TIER 2 BAR  ═ $10.0M   ✓ CLEARED      │  solid bar line
│                                        │
│   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒  114%                  │  discrete progress bar past the line
│                                        │
│   Rounds used   4 / 6                   │  beat the deadline with room
│  ────────────────────────────────────  │
│   You are now: TIER 3 — "The Fork"      │  who you become (curriculum cue)
│   Unlocks: EXIT / EMPIRE deck           │  unlock == curriculum order (§Q7)
│            ╔════════════════╗           │
│            ║   NEXT  TIER ▸  ║           │
│            ╚════════════════╝           │
└──────────────────────────────────────┘
```

**Not cleared, rounds remain:**
```
┌──────────────────────────────────────┐
│           DEADLINE  CHECK              │
│   NET WORTH   ░ $6.8M                   │
│   TIER 2 BAR  ═ $10.0M    not yet       │
│   ▓▓▓▓▓▓▓▓▓░░░░░░  68%                   │
│   Rounds left   2 / 6                   │  pressure, stated plainly
│   You need ~1.36×/round; you're at 1.31×│  the growth-rate telegraph (#2)
│            ╔════════════════╗           │  ← this line IS the missed-deadline
│            ║  NEXT  ROUND ▸  ║           │     warning, a full tier ahead
│            ╚════════════════╝           │
└──────────────────────────────────────┘
```

Notes:
- The `1.36×/round needed vs 1.31× actual` line (= `meters.growthRateNeeded` vs `growthRateThisTier`) is telegraph #2: missed-deadline death never surprises you. It appears every round once you're behind pace, not only at the end.

---

### S8 — Autopsy (death) · §Q5, three rows from the action log

One screen, three rows, built from `run.log` (never a counterfactual re-sim). Cause → the number → the round it broke. Two copy sets: BANKRUPTCY vs MISSED_DEADLINE.

**Bankruptcy (liquidity death):**
```
┌──────────────────────────────────────┐
│                                        │
│              A U T O P S Y             │
│  ════════════════════════════════════  │
│  CAUSE OF DEATH                         │
│  ┌────────────────────────────────┐    │  Row 1 — the instinct, plain words
│  │  GREED.                          │    │     (heavy, unmissable)
│  │  You ran out of cash paying debt.│    │
│  └────────────────────────────────┘    │
│                                        │
│  THE NUMBER THAT KILLED YOU             │  Row 2 — the literal line item
│  ┌────────────────────────────────┐    │
│  │  Interest due $96k  >  Cash $61k │    │
│  └────────────────────────────────┘    │
│                                        │
│  THE ROUND IT BROKE                     │  Row 3 — the real logged decision
│  ┌────────────────────────────────┐    │
│  │  Round 6: you took the 8×        │    │
│  │  leverage loan.                  │    │
│  └────────────────────────────────┘    │
│  ────────────────────────────────────  │
│  Paper net worth $4.2M. Cash $0.        │  the gut-punch line (§Q5 copy)
│  The score was never yours.             │
│                                        │
│  〔 Last run: timidity. This run: greed.│  opposite-death callback (local)
│     The skill is the middle. 〕         │
│                                        │
│  Furthest tier reached: 2 (+rep small)  │  consolation progress
│   ╔═══════════╗     ╔════════════════╗ │
│   ║  RETRY  ▸  ║     ║   THE  DESK  ▸  ║ │  new run │ meta screen
│   ╚═══════════╝     ╚════════════════╝ │
└──────────────────────────────────────┘
```

**Missed deadline (growth-rate death) — same layout, swapped copy:**
```
  CAUSE: "TOO SLOW. The market won't wait."
  NUMBER: "Net worth $740M, needed $1B."
  ROUND: "Round 8: you held Venture A instead of exiting."
  TAIL:  "You grew 1.31×/round; you needed 1.36×."
```

Notes:
- All three rows are string lookups against logged actions + a small phrasing library keyed to `LoggedAction.note` and `death.cause`. Repeat deaths name *different* mistakes because they pull from different log entries (§Q5). No re-sim, no engine cost.
- The opposite-death callback reads `meta.lastDeathCause` — pure local state.

---

### S9 — The Desk (meta / unlock home)

Between-runs home. Reputation total, unlock pool, Founder Background picker (each a difficulty mode), title ladder. Horizontal-only progress (§Q7): **access, never advantage.** No power-creep stat anywhere on this screen.

```
┌──────────────────────────────────────┐
│   THE DESK                       ⚙     │
│  ════════════════════════════════════  │
│   TRACK RECORD (Reputation)            │
│   ▓▓▓▓▓▓▓▓▓▓░░░░░  Lv 4   1,820 rep    │  realized-outcomes currency only
│   Next unlock at 2,000: LBO deck        │  what access the next level buys
│  ────────────────────────────────────  │
│   START AS  (pick a Founder Background) │  each = perk + matching constraint
│   ┌──────────────┐ ┌──────────────┐    │
│   │ BOOTSTRAPPER  │ │  OPERATOR     │    │
│   │ +high own%    │ │ free partner  │    │
│   │ −no credit    │ │ −             │    │  default highlighted for first ~5 runs
│   └──────────────┘ └──────────────┘    │
│   ┌──────────────┐ ┌──────────────┐    │
│   │ VC DARLING    │ │  DEALMAKER    │    │
│   │ +cash, −own   │ │ +extra play   │    │
│   └──────────────┘ └──── 🔒 ─────┘    │  locked = needs more rep (access gate)
│  ────────────────────────────────────  │
│   UNLOCKED   cards 22/35 · sectors 4/6  │  the pool, as a count not a buff
│   TITLE   "Bagholder"  ▾   (cosmetic)   │  score-chaser cosmetics
│   ╔══════════════════════════════════╗ │
│   ║         START  RUN  ▸             ║ │  → S0 background-confirmed → run
│   ╚══════════════════════════════════╝ │
└──────────────────────────────────────┘
```

Notes:
- Every unlock is phrased as **access** ("LBO deck", "sectors 4/6"), never a number that makes you stronger. The reputation bar is the only persistent meter and it buys *options*, not power.
- Backgrounds show perk **and** constraint on the face so the difficulty-mode framing is honest at pick time.

---

### S0 — Title / Continue (the front door, minimal)

```
┌──────────────────────────────────────┐
│                                        │
│              M U L T I P L E S           │
│            get in · get rich · get out         │
│                  〔 14× 〕              │  the icon glyph
│                                        │
│      ╔══════════════════════════╗      │
│      ║   CONTINUE  (T2 · R3)     ║      │  only if resumable autosave exists
│      ╚══════════════════════════╝      │
│      ┌──────────────────────────┐      │
│      │       NEW  RUN  ▸          │      │  → S9 The Desk
│      └──────────────────────────┘      │
│      ┌──────────────────────────┐      │
│      │       THE  DESK  ▸         │      │  meta without starting a run
│      └──────────────────────────┘      │
│                                        │
│   no account · offline · saved on device│  the §7-build-context promise, stated
└──────────────────────────────────────┘
```

---

## 4. Component reuse map (keeps the build at two-person scale)

| Component | Built in | Reused by |
|-----------|----------|-----------|
| **C-HUD** (5 numbers + Net Worth) | S1 | S2 (condensed), S3 (full), S5 (condensed), S7 (line form) |
| **C-METERS** (runway + market) | S1 | S2 (restated in words), S7 (growth-rate variant) |
| **C-CARD** (raw-input face) | C-CARD | S3 hand, S3 plays strip, S5 shop, S4 stage 1 |
| **C-NAPKIN** (mechanical preview) | S4 | S4 only (but parameterized per card type) |
| **Scoring overlay** | S6 | BUY_ADDON / EXIT / RAISE (3 skins, 1 component) |
| **Confirm strip** (one-line) | shared | EXIT, RECAP, big TAKE_DEBT, ADVANCE-when-LOW, Next Tier |
| **Three-row result panel** | S8 | S8 (death) + S10 (victory, inverted copy) |

Net new screens to actually build: **S0, S1, S2, S3, S4, S5, S6, S7, S8, S9** (S10 = S8 re-skin). Roughly **9 screens, 4 shared parts** — buildable by two people without an art pipeline, all rendered as greyscale boxes + text until the loop proves fun (per §11/§P2 #13).

---

## 5. Glanceability rules (the one hard test for every screen)

A screen passes only if all of the following hold with **zero animation**:

1. The five numbers + Net Worth are visible (full or condensed) and in the canonical order.
2. Cash reads as "solid/real" and Net Worth reads as "ghost/paper" by border weight alone — no color needed.
3. Both forward meters (runway, market) are present on any screen where a death could be telegraphed (S1/S2/S3/S5/S7), each with a discrete fill **and** a literal number.
4. A card face never shows a net-worth delta; the mechanical preview is exactly one tap away; the judgment is never shown.
5. The most dangerous actio