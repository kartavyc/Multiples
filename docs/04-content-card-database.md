# MULTIPLES — Content / Card Database (P0 #4)

> Status: **draft, design-locked**. Implements GDD §6 (taxonomy), §7 (the hard invariant), §8 Q2 (PLAYS) and Q6 (4 sectors).
> Build artifact: `data/cards.json` (this doc is the human-readable mirror; the JSON is what the engine loads).
> Schema mirror: every row maps 1:1 to a `Card` def in `docs/02-core-loop-game-state.md` §1 and resolves through the same `{deltas}` resolver, so the §7 invariant test covers it automatically.

---

## 0. How to read this database

**Units (from `data/economy-model.json`, do not deviate):**
- `cash`, `netDebt`, `ebitda` are **integer cents**. `$6,000 = 600000`.
- `multiple` is **milli-units** (×1000): a 14× multiple is `14000`.
- `own`(ership) is **basis points** (×10000): 80% is `8000`, a 15% dilution is `-1500`.
- `deltas` keys are a **strict subset of `{ebitda, multiple, netDebt, own, cash}`** — the §7 hard invariant. No card writes anything else, ever. There is no `+score`.
- `cost` is a **human-facing summary** of the up-front price in three currencies (cash / debt / dilution). It is descriptive, not a separate resolver field; the real economic effect is always the `deltas`. For most cards `cost.cash` mirrors the negative `deltas.cash`; for financing/event cards the relationship is annotated below.

**Directionality is real (GDD §7, even where magnitudes are gamified):**
- Leverage adds `+cash` AND `+netDebt` (interest bites later, both ways).
- Dilution is always `-own`; a raise pairs `+cash`/`+ebitda`/`+multiple` with a *separate* engine-computed ownership cut (real cap-table math in `RAISE`, §3.2 of doc 02) — for **financing raise cards the `cost.dilution` is the nominal slice surrendered**, shown so the player feels the trade; the precise post-money recompute is the engine's job.
- Same-sector add-ons are accretive (synergy +20%, no drag); cross-sector add-ons carry **zero synergy and a −8% multiple drag** (`multiple: -640` on a 8000 platform ≈ 0.92×, the conglomerate discount). The drag magnitude in a card row is illustrative; the engine applies `multiple *= (1 - congDiscountPerAddon)` against the *live* platform multiple at merge (doc 02 §3.4).

**Sector multiple bands (seed values, GDD §8 Q6):** SOFTWARE 14× (`14000`, vol 0.30), SERVICES 5× (`5000`, vol 0.22), RETAIL 3× (`3000`, vol 0.10), INDUSTRIAL 8× (`8000`, vol 0.12). Venture face multiples below are seeded to band.

**Tier gates map to the curriculum (GDD §4, unlock order == curriculum order):** T1 unit-economics & survival, T2 raise/dilution & operating partners, T3 exit/empire & spin-off, T4 acquirer/LBO. **Every tier stays beatable with only the prior tier's tools** (GDD §7 Q7); higher-gate cards are expression, never prerequisites.

**Add-ons & partners are ACT cards** (cost a PLAY when played onto a venture). **Financing instruments and consumables (PLAYS)** are bought in SHOP for cash, then PLAYS resolve in ACT from the held inventory. **Events** auto-resolve in OPERATE. (doc 02 §2–§3.)

---

## 1. The card table (33 cards)

Legend: **VS** = in the v1 vertical-slice subset. Rarity ∈ {common, uncommon, rare}. Deltas shown in raw engine units.

### Ventures (start a company, consume a SLOT, you begin at 100% own = `10000`)

| id | name | sector | rar | gate | cost (cash/debt/dil) | deltas | secret lesson | flavor | VS |
|---|---|---|---|---|---|---|---|---|---|
| VEN_SW_GARAGE | Garage SaaS | SOFTWARE | common | 1 | 1.2M / 0 / 0 | cash −1.2M, ebitda +400k, multiple 14×, own 100% | Founding = 100% of a tiny base; the multiple does the heavy lifting later. | Two laptops, one couch, infinite confidence. | ✅ |
| VEN_SVC_AGENCY | Boutique Consultancy | SERVICES | common | 1 | 0.8M / 0 / 0 | cash −0.8M, ebitda +550k, multiple 5×, own 100% | Services convert effort to cash fast but trade at a low multiple. Earnings, not story. | You ARE the product. Pray nobody quits. | ✅ |
| VEN_RET_KIOSK | Mall Kiosk Chain | RETAIL | common | 1 | 0.7M / 0 / 0 | cash −0.7M, ebitda +500k, multiple 3×, own 100% | Retail is cash-rich, multiple-poor: spits out pocket cash but the market won't pay up. | Sunglasses and phone cases never sleep. | ✅ |
| VEN_IND_WORKSHOP | Machine Shop | INDUSTRIAL | common | 1 | 1.0M / 0 / 0 | cash −1.0M, ebitda +450k, multiple 8×, own 100% | Industrial is the defensive anchor: solid mid multiple that barely moves in a crash. | Steel doesn't care about the hype cycle. | ✅ |
| VEN_SW_PLATFORM | Vertical SaaS Platform | SOFTWARE | uncommon | 2 | 6.0M / 0 / 0 | cash −6.0M, ebitda +1.8M, multiple 14×, own 100% | The ideal roll-up base: a high multiple means every cheap add-on revalues up. | It's not a feature, it's a category. | — |

### Add-on acquisitions (merge into a platform slot — the arbitrage move)

| id | name | sector | rar | gate | cost (cash/debt/dil) | deltas | secret lesson | flavor | VS |
|---|---|---|---|---|---|---|---|---|---|
| ADD_SW_PLUGIN | Bolt-on Plugin Co | SOFTWARE | common | 1 | 0.9M / 0 / 0 | cash −0.9M, ebitda +300k | MULTIPLE ARBITRAGE: bought cheap, revalues at the platform multiple; same-sector adds +20% synergy. | Why build it when you can buy the team that did? | ✅ |
| ADD_SW_MICRO | Micro-SaaS Tuck-in | SOFTWARE | common | 1 | 0.5M / 0 / 0 | cash −0.5M, ebitda +180k | Small same-sector tuck-ins are the cleanest accretion: tiny price, instant revaluation, synergy. | One founder, one product, one tired Stripe account. | ✅ |
| ADD_SVC_TEAM | Implementation Team | SERVICES | common | 2 | 0.7M / 0 / 0 | cash −0.7M, ebitda +350k, multiple −0.64× | Cross-sector bolt-ons earn ZERO synergy and DRAG the platform multiple −8%. Junk roll-ups self-limit. | Bolt the consultants onto the software co. What could go wrong? | ✅ |
| ADD_RET_STORES | Regional Store Group | RETAIL | uncommon | 2 | 1.1M / 0.4M / 0 | cash −1.1M, ebitda +600k, netDebt +0.4M, multiple −0.64× | A cheap cash-rich target hides multiple drag + inherited debt. Cross-sector accretion is a trap. | Lots of revenue, lots of leases, lots of regret. | — |
| ADD_IND_SUPPLIER | Upstream Supplier | INDUSTRIAL | uncommon | 3 | 2.2M / 0.8M / 0 | cash −2.2M, ebitda +900k, netDebt +0.8M | Same-sector vertical integration: synergy fires, multiple holds. Owning your supply is accretive in-sector. | Own the bottleneck, own the margin. | — |

### Operating partners (permanent organic-growth engines — the Jokers layer)

| id | name | sector | rar | gate | cost (cash/debt/dil) | deltas | secret lesson | flavor | VS |
|---|---|---|---|---|---|---|---|---|---|
| PRT_SALES_LEAD | VP of Sales | — | common | 1 | 0.6M / 0 / 0 | cash −0.6M, ebitda +150k/rd | The slow organic compounder: a permanent +EBITDA engine. No leverage, no dilution, just grind. | She closes deals you didn't know existed. | ✅ |
| PRT_COO_FIXED | COO (fixed cost) | — | uncommon | 2 | 0.9M / 0 / 0 | cash −0.9M, ebitda +450k/rd (+ recurring fixed salary) | OPERATING LEVERAGE: big +EBITDA but a recurring fixed cost. Great at scale, lethal when thin. | Worth every penny. Until the quarter you can't pay him. | — |
| PRT_GROWTH_HACKER | Growth Lead | SOFTWARE | uncommon | 2 | 0.75M / 0 / 0 | cash −0.75M, ebitda +120k/rd, multiple +0.5× | Some hires buy a sliver of story too. Software rewards narrative more than any sector. | Half growth, half vibes, fully expensive. | — |

### Financing instruments (raises, loans, refi — bought in SHOP for cash, no PLAY)

| id | name | sector | rar | gate | cost (cash/debt/dil) | deltas | secret lesson | flavor | VS |
|---|---|---|---|---|---|---|---|---|---|
| FIN_SEED_RAISE | Seed Round | — | common | 2 | 0 / 0 / 15% | cash +3.0M, ebitda +200k, multiple +1× (own cut by engine) | DILUTION (Tension A): the pie grows, your slice shrinks on real cap-table math. | Congratulations on your new bosses. | ✅ |
| FIN_GROWTH_RAISE | Series A | — | uncommon | 2 | 0 / 0 / 20% | cash +8.0M, ebitda +500k, multiple +2× (own cut by engine) | Bigger raises buy more growth and story but cut deeper. The over-diluted founder is the cautionary tale. | Up and to the right. Down and to the left for your cap table. | — |
| FIN_TERM_LOAN | Term Loan | — | common | 1 | 0 / 1.5M / 0 | cash +1.5M, netDebt +1.5M | LEVERAGE both ways: cash now, a flat interest bill every round forever. No dilution. | The bank believes in you. The bank always does. | ✅ |
| FIN_LBO_LOAN | Acquisition Facility | — | rare | 4 | 0 / 20M / 0 | cash +20M, netDebt +20M | The LBO lever: huge debt-funded firepower as the acquirer. Magnified returns AND magnified risk. | You write the checks now. Try not to bounce them. | — |
| FIN_REFI | Refinancing | — | uncommon | 3 | 0.3M / 0 / 0 | cash −0.3M, netDebt −2.5M | A fee now retires debt and shrinks the interest bill. The unsexy move that keeps a levered run alive. | Boring. Survival usually is. | — |

### Market / events (auto-resolve in OPERATE; magnitudes route through the five inputs)

| id | name | sector | rar | gate | cost | deltas | secret lesson | flavor | VS |
|---|---|---|---|---|---|---|---|---|---|
| EVT_SECTOR_BUBBLE | Sector Bubble | SOFTWARE | uncommon | 1 | — | multiple +4.2× | Multiple expansion is exogenous weather you ride, not manufacture. Sell, don't buy. | Everything is a 15×. Nothing is real. Get out. | ✅ |
| EVT_CREDIT_CRUNCH | Credit Crunch | — | uncommon | 1 | — | multiple −2.8× | Crunches compress multiples, spike interest, disable financing. The over-levered die here. | The music stopped. Hope you have a chair. | ✅ |
| EVT_KEY_CLIENT_LOSS | Lost a Whale Client | SERVICES | common | 1 | — | ebitda −250k | Concentration risk: spiky sectors lose earnings in chunks. A monoculture is fragile. | They went "in a different direction." | ✅ |
| EVT_VIRAL_QUARTER | Viral Quarter | RETAIL | common | 1 | — | cash +600k, ebitda +100k | Good events still route through the five inputs, never a flat +score. The multiple shrugs. | TikTok found you. Enjoy it while it lasts. | — |
| EVT_SUPPLY_SHOCK | Supply Shock | INDUSTRIAL | common | 2 | — | ebitda −180k, multiple −0.4× | Even crash-resistant industrials wobble mildly on input costs. Low vol = small deltas both ways. | The price of steel did a thing. | — |

### PLAYS — consumables (held inventory, max 2→3; sellable ~50%; GDD §8 Q2). All 10 ship in v1.

| id | name | rar | gate | cost (cash/debt/dil) | deltas | secret lesson | flavor | VS |
|---|---|---|---|---|---|---|---|---|
| PLY_BRIDGE_LOAN | Bridge Loan | common | 1 | 0.2M / 0 / 0 | cash +1.0M, netDebt +1.15M | Cash now at a premium later (take 1.0, owe 1.15 in debt). Liquidity has a price. | It's only temporary. They all say that. | ✅ |
| PLY_SECONDARY_SALE | Secondary Sale | common | 1 | 0.15M / 0 / 0 | own −10%, cash + (equity at live mark, engine-computed) | PAPER→REAL (Tension B): sell a slice at the live mark for guaranteed cash. The hedge vs your own greed. | Take chips off the table. You earned them. Probably. | ✅ |
| PLY_DOWN_ROUND | Down Round | uncommon | 1 | 0 / 0 / 40% | cash +2.5M, own −40% | Desperation financing: cash now at brutal dilution. The sharpest lesson in selling too cheap. | Survival is a kind of victory. A small, sad kind. | ✅ |
| PLY_TENDER | Tender / Anti-dilution | uncommon | 2 | 2.0M / 0 / 0 | cash −2.0M, own +15% | Buy your ownership back: spend cash to widen your slice when you believe more than the market. | Mine. All of it. More of it. | — |
| PLY_DIVIDEND_RECAP | Dividend Recap | rare | 2 | 0 / 0 / 0 | cash +3.0M, netDebt +3.0M | GREED weaponized: pull cash out as new debt (a share of EV). Classic PE move, classic bankruptcy setup. | Pay yourself first. The covenants can wait. | ✅ |
| PLY_HOT_WINDOW | Hot Window | uncommon | 2 | 0.5M / 0 / 0 | cash −0.5M (arms next exit to the high market multiple) | Exit timing made manual. Reading and riding the window is the whole exit game. | Strike while the market is dumb and rich. | ✅ |
| PLY_ASSET_STRIP | Asset Strip | uncommon | 2 | 0 / 0 / 0 | cash +1.8M, ebitda −300k | Sell the productive guts for cash: instant liquidity at permanent earnings cost. | Sell the copper out of your own walls. | — |
| PLY_SPIN_OFF | Spin-off | uncommon | 3 | 0.3M / 0 / 0 | cash −0.3M (then bank add-on share, re-marked; frees a SLOT) | Split a unit back out at the current multiple and lock its value. Unbundle when parts > whole. | Unbundle the empire when the parts are worth more. | — |
| PLY_EARN_OUT | Earn-out | rare | 3 | 0 / 0 / 0 | ebitda +500k (seller paid from future EBITDA via scheduled drag) | Acquire for $0 down; the bill is a scheduled cash drag over N rounds. Buy now, sweat later. | Zero down. The catch is in the fine print's fine print. | — |
| PLY_MARKET_READ | Market Read | common | 1 | 0.1M / 0 / 0 | cash −0.1M (reveals next round's drift direction) | Information has a price. Direction only, never magnitude, so timing stops being a blind guess. | A little birdie. The little birdie charges a fee. | ✅ |

---

## 2. Coverage check (against the brief)

| Requirement | Status |
|---|---|
| ~30 cards | 33 total |
| All 6 card types | venture 5, addon 5, partner 3, financing 5, event 5, consumable 10 |
| All 10 PLAYS from §8 Q2 | Bridge, Secondary, Down Round, Tender, Dividend Recap, Hot Window, Asset Strip, Spin-off, Earn-out, Market Read — all present |
| Spread across 4 sectors | SOFTWARE 6, SERVICES 3, RETAIL 3, INDUSTRIAL 3, sector-agnostic 18 |
| Spread across 4 tiers | gate T1 ×16, T2 ×12, T3 ×4, T4 ×1 (front-loaded by design: lower tiers carry the curriculum core; higher tiers are expression) |
| §7 invariant (deltas ⊆ 5 inputs, no +score) | verified by script: 0 cards write any key outside `{ebitda, multiple, netDebt, own, cash}` |
| Directionality real | leverage = +cash/+netDebt; dilution = −own; same-sector accretive vs cross-sector drag; recap = +cash/+netDebt |

## 3. The v1 vertical-slice subset (19 cards)

Goal (GDD §11): **prove "T1 + the merge mechanic is fun."** The slice is deliberately T1/early-T2 heavy and contains exactly the cards needed to feel arbitrage, dilution, leverage, and exit timing once each.

**Ventures (4):** all four starter ventures (one per sector) — `VEN_SW_GARAGE`, `VEN_SVC_AGENCY`, `VEN_RET_KIOSK`, `VEN_IND_WORKSHOP`.
**Add-ons (3):** `ADD_SW_PLUGIN`, `ADD_SW_MICRO` (same-sector, to feel synergy + the revaluation flash), `ADD_SVC_TEAM` (cross-sector, to feel the conglomerate drag self-limit).
**Partner (1):** `PRT_SALES_LEAD` (the clean organic compounder).
**Financing (2):** `FIN_SEED_RAISE` (dilution), `FIN_TERM_LOAN` (leverage).
**Events (3):** `EVT_SECTOR_BUBBLE`, `EVT_CREDIT_CRUNCH` (the timing/temperature pair), `EVT_KEY_CLIENT_LOSS` (a real downside hit).
**PLAYS (6):** `PLY_BRIDGE_LOAN`, `PLY_SECONDARY_SALE`, `PLY_DOWN_ROUND`, `PLY_DIVIDEND_RECAP`, `PLY_HOT_WINDOW`, `PLY_MARKET_READ`.

Held out of the slice (T2+ depth, ship after the merge moment validates): `VEN_SW_PLATFORM`, `ADD_RET_STORES`, `ADD_IND_SUPPLIER`, `PRT_COO_FIXED`, `PRT_GROWTH_HACKER`, `FIN_GROWTH_RAISE`, `FIN_LBO_LOAN`, `FIN_REFI`, `EVT_VIRAL_QUARTER`, `EVT_SUPPLY_SHOCK`, `PLY_TENDER`, `PLY_ASSET_STRIP`, `PLY_SPIN_OFF`, `PLY_EARN_OUT`.

> The `inVerticalSlice` boolean in `data/cards.json` is the machine-readable source of truth for this subset.

## 4. Notes for tuning (GDD §9 — these magnitudes are not locked)

- Card magnitudes are first-pass and meant to be swept in the headless sim (P1, `prototype/sim-check.js`). What is locked is **directionality and which inputs each card touches**, never the integers.
- `ADD_*` cross-sector `multiple` drag is shown as a fixed `−0.64×` for readability; the engine applies `multiple *= 0.92` against the live platform multiple at merge (`congDiscountPerAddon` = 0.08), so the realized drag scales with the platform.
- `FIN_SEED_RAISE` / `FIN_GROWTH_RAISE` show a nominal `cost.dilution`; the actual ownership cut is the engine's post-money recompute (`newOwn = oldOwn * preMoney/(preMoney+raise)`), so the felt dilution depends on the venture's current equity.
- `PLY_SECONDARY_SALE` / `PLY_DIVIDEND_RECAP` / `PLY_SPIN_OFF` / `PLY_EARN_OUT` carry placeholder literal deltas in the JSON; their *true* proceeds are computed at resolve time from live venture equity/EV (doc 02 §3.6 per-kind table). The JSON deltas exist so the invariant test has a fixture and the card reads sensibly; the resolver overrides with the live-mark math.
