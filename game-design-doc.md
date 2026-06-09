# MULTIPLES — Living Design Doc

*Working title: **MULTIPLES** (tagline: "get in. get rich. get out. Wait, that's allowed?!"). A Balatro-spirit (not Balatro-clone) roguelike where you play an entrepreneur climbing the wealth ladder from broke to billionaire. The hidden curriculum is high finance (valuation, multiples, leverage, dilution, M&A, exits) taught not by lectures but by making the optimal play identical to the correct financial instinct.*

> Status: **design locked, pre-prototype**. The §8 open questions were resolved by a 16-agent design fleet (3 rounds: propose, cross-critique, synthesize). This is a living doc; iterate here instead of rebuilding the idea in chat.
>
> Build context: **single-player, fully offline, no server/accounts**, local on-device saves only. Team is two (Kartavy + Claude Code), indie passion side project. Not GUI-heavy. iOS + Android from one codebase, portrait, touch-first, snackable sessions.

---

## 1. The North Star

**You win at $1,000,000,000 net worth.** Like beating Balatro's final ante, hitting a billion rolls the credits; an **endless mode** continues for score-chasers with escalating modifiers.

The fantasy: start as a scrappy bootstrapper getting diluted by everyone, end as the capital, the one running roll-ups and writing the checks. By the time you're a billionaire you've stood on both sides of every term sheet. That traversal *is* the meta-progression and the pedagogy.

Two commitments borrowed from Balatro's spirit, not its mechanics:
- **Teach by reward, never by lecture.** The player should *feel* a concept (e.g. dilution) by watching a number they care about move, not by reading a tooltip essay.
- **Easy to learn, deep to master.** One core equation anyone grasps in 30 seconds; combinatorial depth that takes 30 runs to plumb.

**Refined pitch:** You start broke and climb the wealth ladder one power-of-ten tier at a time. Each round you draw a hand of deals (a startup to launch, a company to bolt on, a term sheet, a loan, an exit offer) and can only act on a few, so every choice is an underwriting call: the card shows you the EBITDA, the multiple, and the price, but never the answer. Value resolves through one real equation you come to feel in your gut, animated as the game's Balatro-style scoring moment. The signature thrill is multiple arbitrage: buy a cheap company, bolt it onto your expensive platform, watch its earnings instantly revalue ("that's allowed?!"), tempered by the conglomerate discount so it teaches discipline, not free money. Two tensions drive every decision: raising grows the pie but cuts your slice, and your net worth is paper fantasy (rendered in ghosted ink, unspendable) until you exit and convert it to solid cash, if you time the market right. Greed is genuinely tempting and occasionally fatal: over-lever into a credit crunch or hold too long into a cold market and you die with millions on paper and nothing in pocket, the death screen naming the exact instinct that killed you.

---

## 2. The Core Equation (the spine of everything)

```
Enterprise Value (EV) = EBITDA × Multiple
Equity Value          = EV − Net Debt
NET WORTH (score)     = Σ ( Ownership% × Equity Value )  +  Cash in pocket
```

This single identity is the whole game. Map to Balatro intuition:

| Finance term | Balatro analog | What it teaches |
|---|---|---|
| **EBITDA** | Chips (the fundamental size) | Operate well, the earnings base grows |
| **Multiple** | Mult (the premium per unit) | Scale/story/category leadership, revalued without more work |
| **EV = EBITDA × Multiple** | Chips × Mult | Two ways to win: go bigger *or* go higher-quality; it's a product |
| **− Net Debt** | (none) | Leverage is subtracted at the end; it can kill you |
| **Ownership %** | (none) | Dilution: a smaller slice of a bigger pie |
| **Cash in pocket** | (none) | The only truly *safe* number |

A player who internalizes this one line has internalized the core of the industry, and we never have to explain it.

---

## 3. The Two Great Tensions

The emotional engine. Every interesting decision pulls on one of them.

**A. Dilution: a smaller slice of a bigger pie.** Every equity raise grows the company (EBITDA/Multiple) but shaves your Ownership%. The player will feel, in their gut, that you can 10× a company and barely move your own net worth if you sold too much too early, or stay lean, own 80%, and exit smaller but richer. Bootstrap vs raise stops being abstract and becomes a stat ticking down every time you take money.

**B. Paper vs Real: illiquidity and exit timing.** Net worth is mostly locked in ownership you can't easily sell. The on-screen score is a fantasy until you **exit** (acquisition or IPO). The exit multiple, and whether the market is hot or cold that turn, decides whether paper becomes real. The founder who looked richest at hour two but never sold, then ate a downturn, loses to the one who took chips off the table. "Cash in pocket" (secondaries, dividends) is the prudent player's hedge against their own greed.

---

## 4. Structure: The Wealth Ladder = The Ante Track

You don't climb arbitrary score blinds; you climb **orders of magnitude**. Each power-of-ten is a tier you must break through; the bar rising 10× each time *is* the difficulty curve, for free.

| Tier | Net worth band | Who you are | Concepts foregrounded |
|---|---|---|---|
| **1** | $0 → $1M | Scrappy founder, bootstrapped | Unit economics, cash-flow survival, CAC/LTV |
| **2** | $1M → $10M | You raise | VC funding, **dilution**, hiring operating partners, growth |
| **3** | $10M → $100M | The fork opens | **Exit** (serial) *or* start venture #2 (empire); juggling attention |
| **4** | $100M → $1B | You become the money | Roll-ups, LBOs, M&A as the *acquirer*, holding company / portfolio |
| **★** | $1B+ | Endless | Beat the game; modifiers escalate for score-chasers |

Serial + Empire are one continuum, not two modes. Empire is just what "serial" becomes when you stop selling and start holding and compounding. An **action economy** (each active venture consumes attention) forces the juicy "exit and free a slot, or keep juggling?" decisions.

---

## 5. The Core Loop

Within each tier you play a handful of **rounds** (years/quarters) against a tier deadline:

1. **Operate:** your ventures throw off EBITDA / cash; events hit (good and bad).
2. **Act:** make the round's key decisions: raise, take on debt, acquire an add-on, do a dividend recap, exit a holding, start a new venture.
3. **Shop** (between rounds): spend cash on hires (operating partners), assets, add-on acquisitions, financial instruments, one-shot consumables.
4. **Check the deadline:** clear the tier's net-worth bar in time to advance.

**Run ends if** you go **bankrupt** (cash hits zero while servicing debt → margin call / covenant breach) **or** you **miss a tier deadline**.

---

## 6. Card / Asset Taxonomy (the "Jokers" layer)

Permanent engines and modifiers, each secretly a lesson:

- **Operating Partners** → grow EBITDA each round (the slow organic compounder). Some add a fixed cost → teaches **operating leverage** (great at high volume, deadly at low).
- **Add-on Acquisitions** → a *merge* mechanic. Buy a small company at a low multiple, bolt it onto your platform that trades at a high multiple, its earnings are instantly revalued. This is **multiple arbitrage**, the "wait, that's *allowed*?" dopamine hit. Same-sector add-ons throw off **synergies** (bonus EBITDA) = the M&A accretion lesson built into a merge.
- **Financial Engineering** → real PE tricks with real tradeoffs: **dividend recap** (pull cash out early, riskier), **refinancing** (lower interest), **LBO** structures (more debt, magnified equity returns *and* risk).
- **The Market Itself** → multiples drift over the run. **Bubbles** (everything's a 15×, sell don't buy) and **credit crunches** (debt dries up / gets expensive) teach valuation discipline and timing without a word of theory.
- **Consumables (PLAYS)** → one-shot effects (see §8 Q2).

---

## 7. Rigor Dial — LOCKED

**Position: ~70/100.** A thin truly-rigorous spine with gamified magnitudes on top, governed by a three-layer contract.

- **Layer 1 (FROZEN, computed exactly every action):** `EV = EBITDA × Multiple`; `Equity = EV − Net Debt`; `Net Worth = Σ(Ownership% × Equity) + Cash`; real cap-table dilution (`newOwn% = your$ / post-money`); and a **flat** `interest = rate × Net Debt` charged in cash each round, with **bankruptcy when cash < interest due.**
- **Cut entirely:** amortization schedules, covenants, tax shields, IRR, working capital. (These are tuning quicksand for two people and add quiz-friction with no extra lesson.)
- **Layer 2 (tuned integers):** sector multiple bands, interest rates, synergy %, market drift.
- **Layer 3 (free candy):** joker-style card modifiers.

**The hard invariant (enforced by an automated engine test):** every card / consumable / event may ONLY mutate `{EBITDA, Multiple, Net Debt, Ownership%, Cash}` — never a flat `+score`. Magnitudes may be gamified, but **directionality must stay real** (leverage magnifies both ways; arbitrage really is accretive). This is the single cheapest, highest-leverage decision in the design: it is what mathematically welds optimal play to correct instinct (Pillar 2).

*Money stored as integer cents; displayed rounded with k/M/B suffix, forced en-US grouping.*

---

## 8. Resolved Design Decisions (was: Open Questions)

### Q1 — Rigor dial → see §7. ✅

### Q2 — Consumables → **PLAYS** ✅
**One** consumable category in v1 (no two-family Tarot/Planet split). Called **PLAYS**. Hold max 2, scaling to 3 by T4. ~10 one-shots at ship, all routing through the five inputs, all priced in cash/debt/dilution (never free), sellable for ~50% to teach liquidity.

Core set: **Bridge Loan** (cash now, +debt later), **Secondary Sale** (convert some Ownership% to cash now), **Down Round** (cash now, brutal dilution), **Tender / Anti-dilution** (un-dilute with cash), **Dividend Recap** (pull cash = % of EV as new debt; greed, can be fatal, gated T2+), **Hot Window** (force next exit to roll the high market multiple), **Asset Strip** (cash now, −EBITDA), **Spin-off** (split an add-on out, frees a slot, locks its value), **Earn-out** (acquire for $0 now, pay from future EBITDA), **Market-Read** (reveal next round's drift *direction* only, not magnitude).

**Banned in v1:** a second family, AND any permanent sector-multiple buff ("MEMO"). The permanent multiplier was the single most dangerous idea on the table; it teaches "I can manufacture multiple expansion on demand," the exact opposite of the correct instinct (expansion is exogenous market weather you read and ride).

*Build note: Plays are just deck cards with `type='consumable'` and a 2–3 slot held inventory; reuse the same `{deltas}` schema and resolver, so they obey the invariant test automatically. No new screen, a thin card strip above the hand.*

### Q3 — The "deck" → **DEAL FLOW** ✅
**One** primary randomized resource: a **Deal Flow** hand of 3–5 typed cards drawn each round, all sharing one schema `{type, sector, EBITDA, multiple, price, debt, effect}`. Types: venture-to-start, add-on, operating-partner hire, financing instrument, market/event, consumable.

A **plays-per-round cap** forces ranking by ROI; unplayed cards expire (opportunity cost, felt wordlessly). The card **face shows raw inputs only** (EBITDA, Multiple, price, debt, sector), never a net-worth delta; a tap-to-inspect "napkin" overlay reveals the post-deal *mechanical* revaluation only, never the downstream judgment. ("Show the chips, hide the wisdom.")

**The market is NOT a separate deck:** it's a single global state shown as one banner that *reprices* the same hand (bubble = acquisitions cost more / exits pay more; crunch = financing disabled or expensive). Reputation + sector focus bias the draw so the hand feels earned. A guaranteed baseline "reinvest cash into existing EBITDA at floor efficiency" play exists every round so no hand is unwinnable. A cash-priced reroll ("banker fee") makes a bad hand recoverable but costly.

### Q4 — Action economy → **two decoupled scarcities** ✅
- **PLAYS = throughput this round:** T1=2, T2=3, T3=3–4, T4=4.
- **SLOTS = active ventures held across rounds (concurrency):** T1=1, T2=2, T3=2, T4=3, endless cap 4.

Add-ons **merge** into a platform's single slot ("tall not wide" = the roll-up/holdco fantasy with no second slot type). The PLAYS-vs-SLOTS decoupling is the entire "exit to free a slot or keep juggling" emotional engine. T3 deliberately **stays at 2** so the exit fork genuinely bites.

A held venture that gets no action that round **decays** slowly and chunkily (1 neglected round = small dip, 3 = real pain), so holding is never free without per-turn busywork. A "Hire a CEO / Chief of Staff" card converts one venture to passive (lower decay, lower upside) = the delegation / agency-cost lesson, and is how empire-hold scales depth instead of slot count.

**Cut from v1:** the HOLD slot (banking a deal becomes a single "Letter of Intent" consumable) and a separate HOLDCO slot (a T4 slot simply holds a platform; it's a property, not a new counter).

### Q5 — Failure feel → **the AUTOPSY screen** ✅
One death screen, three rows, generated from the **stored action log** (NOT a counterfactual re-sim):
- **Row 1 — CAUSE OF DEATH:** one bold plain-language headline naming the instinct ("GREED. You held too long." / "You ran out of cash paying debt.").
- **Row 2 — THE NUMBER THAT KILLED YOU:** the actual line item, big and red ("Interest due $42k > Cash $11k"; "Net worth $740M, needed $1B").
- **Row 3 — THE ROUND IT BROKE:** the real decision from the log ("Round 6: you took the 8×-leverage loan").

Two distinct copy sets: **Bankruptcy** = liquidity death ("Paper net worth $4.2M. Cash $0. The score was never yours."); **Missed deadline** = growth-rate death ("You grew 1.31×/round; you needed 1.36×. The market won't wait."). A small phrasing library keyed to actual cause means repeat deaths name *different* mistakes, plus an opposite-death callback ("Last run timidity killed you; this run, greed. The skill is the middle."), tracked locally.

**Load-bearing companion rule:** every market/debt death must be **telegraphed a full round ahead** by persistent forward meters (a "debt service next round vs projected cash" runway gauge and a HOT/COLD market temperature gauge), or death-by-market teaches "RNG cheated me" instead of an instinct.

*Cut: the deterministic flip-and-replay counterfactual (weeks of work, can lie because a flipped choice changes downstream RNG). The honest stored-log version teaches ~95% as well at ~10% of the cost.*

### Q6 — Sector / synergy → **4 sectors, one synergy rule** ✅
Ship **4 sectors** in v1, each a 2-axis fingerprint (base-multiple band + steady-vs-spiky volatility) plus one signature behavior/event line:
- **SOFTWARE** (~14×, steady, bubbles hardest)
- **SERVICES** (~5×, spiky / labor-heavy)
- **RETAIL** (~3×, steady, cash-rich but multiple-poor)
- **INDUSTRIAL** (~8×, asset-heavy, slow but crash-resistant)

**One synergy rule governs everything:** a **same-sector** add-on bolts in at the platform multiple AND grants a synergy EBITDA bonus (**flat +20%** of the absorbed unit's EBITDA in v1); a **cross-sector** add-on bolts in at the platform multiple but grants zero synergy and **drags the platform multiple down** (conglomerate discount). The "MULTIPLE ARBITRAGE +$X" flash fires *after* commit, on the compression-applied value, never previewed on the face.

Self-limiting brake: off-sector revenue drags the live "Platform Multiple" number, so infinite junk-drawer roll-ups decay. Concentration risk: sector-specific crashes punish a monoculture, so focus is optimal for the climb (T1–T3) and diversification becomes a defensive holdco play at scale (T4).

*Sectors 5–6 (Consumer Brands, Media/Deep Tech) ship as a post-launch content drop. Build and playtest the arbitrage merge moment FIRST, in isolation.*

### Q7 — Meta-unlocks → **horizontal only, zero power-creep** ✅
Every run starts broke at $0 in T1. **No numeric power-creep, ever.** Persistent currency = **REPUTATION (Track Record)**, earned ONLY by **realized outcomes** (clean exits weighted by exit-quality × Ownership%, secondaries, self-dividends), never paper net worth at death. Exit-quality weighting (`exitMultiple / sectorNorm × Ownership%`) prevents it degenerating into "always sell at first offer."

Reputation buys **access, never advantage**: it unlocks card archetypes, the 2 post-launch sectors, and **Founder Backgrounds** (Bootstrapper: high ownership, no credit access; Operator: free starting operating partner; VC Darling: pre-diluted with more cash; Dealmaker: extra plays). Each Background pairs a perk with a matching constraint and doubles as a difficulty mode; the default is the most forgiving for the first ~5 runs.

Three things carry, nothing else: (1) Reputation total + meta-level, (2) the unlocked card/sector pool, (3) Backgrounds + Hard Modes. Concept-unlocks gate to tier milestones so **unlock order == curriculum order** (reach T2 → raise deck; T3 → exit/empire deck incl. the single attention-slot upgrade; T4 → acquirer/LBO deck; beat game → Endless + Hard Modes). But **every tier stays beatable with only the prior tier's tools**; new decks are expression, never prerequisites. A small "furthest-tier-reached" consolation buys progress even on losing runs. Score-chasers get a cosmetic title ladder + a platform-native (Game Center / Play Games) Endless leaderboard (no backend of ours).

*Content target: ~25–35 cards in v1 as parameterized variants of ~12 archetypes.*

### Q8 — Title → **MULTIPLES** ✅ (pending store/trademark check)
Pick: **MULTIPLES** (four lenses converged). The pun is the thesis: the valuation multiple is the mult, and you are multiplying wealth. One clean word, strong app icon (a bold "×" or "14×" glyph). Risk is SEO-generic, mitigated by tagline "get in. get rich. get out. Wait, that's allowed?!" + distinctive icon.

Backups: **DILUTION** (best fallback if "Multiples" collides), **EXIT MULTIPLE**, **PAPER NET WORTH**, **TEN BAGGER**, **CARRY THE BAG** (note: if used, rename the meta-currency to avoid overloading "Carry").

---

## 9. Still Open (settle by prototype / playtest, not by debate)

- **Tuning constants:** tier deadlines in rounds; the per-round optimal-growth line (~1.5×); reinvestment-efficiency decay (~0.55 → 0.35 curve that forces lever-switching); interest-rate band; multiple-drift rate; Net-Debt/EBITDA danger threshold (~6×). The invariant is the *ratio* (slots scarce, deal size 10×/tier), not the integers. Set in the spreadsheet/headless prototype, validate with per-tier win-rate instrumentation before content lock.
- **Synergy magnitude:** is flat +20% same-sector right vs a self-limiting escalating curve? Needs Monte-Carlo across a full T1→T4 run.
- **Market-cycle model:** exact drift/momentum function and sticky-state durations (bubbles/crunches ~2–3 rounds) so crashes are readable a round ahead and never feel like RNG punishment. Keep it scripted/semi-deterministic, not a hidden stochastic model.
- **Three premise gates (playtest-only):** (a) does the arbitrage merge feel *fun*, not merely clever; (b) do finance-literate players find it non-trivial AND finance-naive players find it non-stressful; (c) do players ever *choose* to hold rather than instant-exit (does Tension B bite on a phone)? If any fails, no downstream system saves the game.
- **Session length:** target 20–30 min; round counts derived backward and verified with a real timed playthrough.
- **Endless (★) calibration:** rising rates / per-ante multiple compression; bound number-formatting past $1B.

---

## 10. Design Pillars (the gut-check)

1. **One equation, felt not explained.** If a mechanic needs a paragraph to justify, redesign it.
2. **The optimal play is the correct financial instinct.** Always. Enforced by the no-`+score` invariant (§7).
3. **Both sides of the table.** The arc from "diluted founder" to "the capital" must be legible in how the game *plays*, not just the numbers.
4. **Greed should be tempting and occasionally fatal.** Paper vs real has to bite.

---

## 11. Documents to Prepare Before Building

The pre-build doc set, right-sized for two people (full rationale in the design-fleet output). Build order:

**P0 — write before any production code**
1. **Economy & Math Spec (the Model)** — one living spreadsheet (named tabs, sim-able formulas in cells, not prose). The game *is* its math; this is where §7 gets proven.
2. **Core Loop & Game State Spec** — the canonical game-state object as a typed schema (paste straight into code) + every legal action with pre/post conditions.
3. **Technical Design Doc / Architecture** — 2–4 pages: stack choice (one codebase iOS+Android), seeded-deterministic RNG, content-as-data pipeline, pure-and-testable rules engine vs UI separation.
4. **Content / Card Database** — same workbook, new tabs; every card's numeric effects, sector tags, rarity, secret lesson. Export to JSON as the build artifact. Start ~15–20 cards, not 100.
5. **UX Flow & Wireframe Set (low-fi)** — grey boxes only; how the five numbers stay legible on a phone. Doubles as the screen build list.
6. **Save / Persistence & Versioning Spec** — local save format, what persists (run + meta), `schemaVersion` + migration hook, mid-run autosave. Can fold into the TDD.
7. **Scope, Milestone Plan & Risk Register** — one page: vertical slice = "prove T1 + the merge mechanic is fun," milestone ladder, explicit cut list, 5-row risk table.

**P1 — soon after**
8. **Balance / Tuning & Simulation Plan** — headless script auto-plays the pure rules engine N times, reports win-rate + strategy distribution; the watchdog for "does a degenerate non-financial strategy win?"
9. **Failure & Onboarding Feel Spec** — first-5-minutes teach-by-play + the death-cause taxonomy (Q5). Can live as a workbook tab.
10. **Playtest Plan** — a Google Form + a "watch 3 friends play T1" ritual; focus on whether lessons land without lecturing.
11. **Store Listing & Platform Compliance Brief** — half a page now answering ONLY the gambling/finance-app review question + "no data collected" privacy labels. Full listing copy near launch.

**P2 — nice-to-have / defer**
12. **Analytics / KPI & Telemetry (local-first)** — a dev-only debug overlay / local JSON dump for your own playtests. No server.
13. **Art & Audio Style Mini-Bible** — one page: 5 colors, 1–2 fonts, SFX shortlist. Readable financial-terminal chic. Defer until the loop is fun.
14. **Live-Ops-Later / Content Drop Plan** — a few bullets in the TDD: "content is versioned JSON, drops ship in the app binary."

**Deliberately NOT writing** (AAA docs that exist to coordinate people we don't have or manage assets/services we won't build): narrative/lore bible, separate vision/pillars deck, art/outsourcing pipeline, monetization/IAP/ad-mediation economy, multiplayer/netcode/backend/accounts/cloud-save/anti-cheat, QA-as-a-department test matrices, standalone localization plan, heavyweight UI-juice/VFX/audio-implementation spec, RACI/stakeholder-comms plan. Rule of thumb: every doc we write must be something one of the two of us actually opens *while coding*.
