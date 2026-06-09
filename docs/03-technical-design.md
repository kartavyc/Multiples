# MULTIPLES — Technical Design Doc

*Companion to `game-design-doc.md` (§7 hard invariant, §11 doc #3). Audience: the two people building this. Scope: stack choice, deterministic RNG, the per-venture data model, the resolver and its action set, the content-as-data pipeline, engine/UI separation, the invariant test, saves, and store builds. Opinionated on purpose, and corrected against the GDD where an earlier draft drifted.*

Status: **stack LOCKED — Flutter + Dart.** Everything below flows from that decision. Stack scoring lives in `data/stack-decision.json`; this doc states the consequences, not the beauty contest.

---

## 1. What this game actually is, technically

Strip the theme and MULTIPLES is a **deterministic state machine over a small set of integer-cents quantities, held per venture, with one global Cash pot**, plus a thin animated front end. Per §7, every action mutates only `{EBITDA, Multiple, Net Debt, Ownership%, Cash}`. There is no physics, no real-time loop, no 3D, no shader work, no networking, no accounts, no server. The hard parts are:

1. **Numerical correctness** — money is integer cents (§7), the core equation must compute identically every time, and a balance sim has to replay thousands of headless runs. **No floating-point anywhere below the UI boundary** (see §3).
2. **Reproducibility** — a run must be byte-for-byte replayable from a seed, or the AUTOPSY screen (§Q5) and the balance harness both lie.
3. **Content velocity** — ship ~25–35 cards as parameterized variants of ~12 archetypes (§Q7), but the **vertical slice starts far smaller** (§9): ~6–10 cards that prove T1 + the arbitrage merge. Cards are authored as data, hot-iterable without recompiling logic.
4. **Two-store shipping from one codebase** for two people who cannot afford a per-platform UI rewrite.

That profile is a **data-and-rules problem with a modest 2D card UI**, not a game-engine problem. The stack choice follows directly: pick the toolchain that makes pure logic, fast tests, and dual-store builds cheapest — not the one with the best particle system.

---

## 2. Stack choice (summary; full scoring in `data/stack-decision.json`)

**Chosen: Flutter + Dart.** It wins the two decisive ×3 axes — a *pure, headless, Flutter-free resolver* run by `dart test`, and a *single-toolchain dual-store build* — and ties or wins everywhere else, all in one language for two people.

- Runner-up was React Native + TS (clean pure-function resolver and Jest, but a native-module / Metro / CocoaPods / Gradle maintenance tax that bites a two-person team on every upgrade).
- Godot 4 scored lowest for *this* game: its headless-test story leans on engine-context addons (GUT), which is exactly the axis where the tests are the product.

**Honest cost we are NOT pretending is free:** Dart `build_runner` codegen (`json_serializable`) is a real maintenance step — it must be re-run on every schema change and wired as a CI step. We accept it because it buys compile-checked content; see §5. iOS release still requires a Mac + Xcode for signing/upload — unavoidable on any stack.

---

## 3. Seeded-deterministic RNG (single stream + explicit cursor)

### Why determinism is load-bearing *here* specifically
Determinism is not a nicety in MULTIPLES; three locked design decisions depend on it:

1. **The AUTOPSY screen (§Q5)** is generated from the **stored action log**, explicitly *not* a counterfactual re-sim. For the log to faithfully reconstruct "Round 6: you took the 8×-leverage loan," replaying `seed + action log` must reproduce the exact same run.
2. **The balance harness (§11 #8)** auto-plays the pure engine N thousand times and asks "does a degenerate non-financial strategy win?" That's only meaningful if `(seed, policy)` → identical run every time, so a tuning regression is a diff, not noise.
3. **Bug reproduction for a two-person team:** a single `seed` string reproduces any reported bad run exactly. No telemetry server (we have none) — the seed *is* the bug report.

### The model: one stream, one explicit cursor, one pinned algorithm
We use **a single named RNG stream per run**, advanced by an **explicit integer cursor**, never by ambient global state. The algorithm is **pinned to SplitMix64** (no "or a PCG" — a determinism contract cannot have an "or").

```
RunRng {
  final int seed;        // 64-bit, derived from run start
  int cursor = 0;        // monotonically increasing draw index
  // draw N is: state = mix(seed, N); see exact algorithm below
  int nextInt(int bound) // pure: f(seed, cursor++) -> [0, bound)
  int nextScaled(int n)  // pure: f(seed, cursor++) -> [0, n) integer; used by all gameplay
}
```

**Exact algorithm (the contract). Pin this; do not "improve" it post-launch.**

```
// 64-bit unsigned arithmetic throughout (Dart int is 64-bit on mobile;
// mask with 0xFFFFFFFFFFFFFFFF to stay defined).
int _splitmix64(int x) {
  x = (x + 0x9E3779B97F4A7C15);
  x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9;
  x = (x ^ (x >>> 27)) * 0x94D098432DEDEC1F;
  return x ^ (x >>> 31);
}
// draw #N for a run = _splitmix64(seed + N * 0x9E3779B97F4A7C15)
// nextInt(bound): take the draw, then unbiased modulo-reduction by rejection.
```

This is **not** `seed ^ cursor` (an earlier draft said that; it is wrong — XOR-ing the cursor into the seed correlates nearby streams). Each draw is `_splitmix64(seed + cursor * GOLDEN)`, so the Nth draw is a pure function of `(seed, N)`: independently computable, jumpable, testable.

**Determinism rules, non-negotiable:**

- **No floats in the engine, ever.** `nextInt`/`nextScaled` return integers. All probabilities are expressed as integer numerators over a fixed denominator (e.g. "drift up if `nextInt(100) < 35`"). Money is integer cents. Net-worth math is integer arithmetic only (EBITDA, Multiple, Net Debt all integers; products fit in 64-bit at our scales — guard the endless-mode ceiling, §9). A double anywhere below the UI boundary breaks byte-for-byte replay across ABIs, so it is banned by test (see §4 grep test).
- **One stream for the whole run.** Persist `{seed, cursor}` and you can resume mid-run bit-perfectly.
- **Draw order is a written, golden-tested contract (§3.1).**
- **Never call `dart:math Random()`, `DateTime.now()`, or any `double`-returning RNG inside the engine.**

### 3.1 The canonical draw order (the golden contract)

Every per-round resolution draws from the one cursor in **exactly this order**. This sequence is the spec; a golden test file (`test/golden/draw_order_v1.json`) pins the first ~200 draws of a fixed seed so any reordering fails CI.

Per round, in order:
1. **Deal Flow draw** — the 3–5 hand cards (§Q3), including the guaranteed baseline "reinvest" play and reputation/sector draw bias.
2. **Market drift** — global Multiple/credit state update (§Q3, exogenous; see §5 on why this is legal vs. the banned permanent buff).
3. **Event roll** — the round's good/bad event (§5).
4. **Resolution of player actions**, in the order the player committed them. Player-triggered draws live *here*, after the deterministic above:
   - **Reroll ("banker fee", §Q3)** advances the cursor and **re-runs steps 1–3 of the draw order** for the new hand. Its cursor position is therefore fully determined by *when* the player rerolls. This is part of the contract.
   - **Decay (§Q4)** for any venture that got no action: a chunky deterministic dip; draws only if a decay variant uses RNG (v1 decay is deterministic, so 0 draws).
   - **Flat interest charge** `interest = rate × NetDebt` per venture, paid from Cash; bankruptcy if `Cash < interest due` (§7). Deterministic, 0 draws.

Result: a run is fully described by `{seed, schemaVersion, startConfig, actionLog}`. Replay = re-feed the action log into a fresh engine seeded the same way. **If draw order or the schema changes, that is a `schemaVersion` bump and in-progress runs from older versions are abandoned, not migrated** (§6 — a migration cannot un-break a seed whose stream moved).

---

## 4. Hard separation: pure resolver vs UI

The architectural spine, enforced by **package boundaries**, not discipline.

```
multiple/                      (Flutter app — monorepo / Dart workspace)
├── packages/
│   └── engine/                ← PURE DART. No flutter import. Ever.
│       ├── lib/
│       │   ├── model/         GameState, Venture, Card, Deltas, Action (§4.1)
│       │   ├── rng/           RunRng (SplitMix64, single stream + cursor, §3)
│       │   ├── content/       JSON loader → typed card/economy objects (§5)
│       │   ├── resolver.dart  apply(GameState, Action, RunRng) -> GameState
│       │   └── invariant.dart the 5-input contract checker (§5)
│       └── test/              dart test — NO device, NO widgets
└── app/                       ← Flutter UI. Depends on engine. One-way.
    ├── lib/ widgets, screens, animation (card flip, arbitrage flash)
    └── ...                    UI may READ state and DISPATCH actions only
```

The contract:

- **The engine is a pure, headless library.** `packages/engine/pubspec.yaml` declares **no Flutter dependency**; it cannot import `package:flutter/*`. Runs under plain `dart test`.
- **The resolver is a pure function:** `GameState apply(GameState s, Action a, RunRng rng)`. Same inputs → same output. No I/O, no clock, no global mutation, no float. Immutable state; `apply` returns a copy-with.
- **The UI is a dumb renderer.** Widgets take a `GameState`, draw the numbers and the hand, emit `Action` values. The UI never computes net worth, never mutates a field, never owns rules. The "+$X arbitrage flash" animates a delta the engine *already* computed.
- **Dependency direction is one-way:** `app → engine`. The CLI balance harness uses the engine with no UI at all.
- **Two static guard tests** in the engine package:
  - greps engine source for `Random(`, `DateTime.now`, and `double ` / `.toDouble()` — fails the build if found (float + clock ban, §3).
  - asserts the engine `pubspec.yaml` has no `flutter` dependency.

### 4.1 The state model and the action set (this is where the earlier draft was wrong)

**The five inputs are PER VENTURE, except Cash, which is global.** The GDD holds 1–4 ventures (§Q4), each its own cap table and live Platform Multiple (§Q6). The earlier draft treated all five as flat scalars on `GameState`; that cannot express "a card mutated venture[2].ownership" and made the invariant test diff the wrong shape. Corrected model:

```dart
class Venture {
  final String id;
  final Sector sector;
  final int ebitdaCents;        // per venture
  final int multipleMilli;      // multiple in milli-units (×1000: 14x = 14000), integer
  final int netDebtCents;       // per venture
  final int ownershipBp;        // your % in basis points (×10000), integer 0..10000
  // platform-multiple drag from cross-sector add-ons is recomputed from
  // absorbed units, not stored as a separate score (§Q6)
}

class GameState {
  final List<Venture> ventures; // 1..4 (SLOTS, §Q4)
  final int cashCents;          // the ONLY global money quantity
  // bookkeeping (NOT gameplay fields, explicitly excluded from the invariant):
  final int rngCursor;
  final List<LoggedAction> actionLog;
  final int round, tier, schemaVersion;
}
```

**Canonical net-worth formula — distributes over ventures (corrected):**

```
netWorthCents(s) =
   Σ_v ( ownershipBp_v/10000 × ( ebitdaCents_v × multipleMilli_v/1000 − netDebtCents_v ) )
   + cashCents
```

i.e. `Equity_v = EV_v − NetDebt_v` *inside* each venture, then ownership-weighted and summed, then add global Cash. This matches GDD §2/§7. Net worth is a **derived pure getter, never a stored settable field**, so no card can write to it. (Implementation note: do the basis-point divisions last and in integer arithmetic with explicit rounding to cents; never introduce a double.)

**The `Action` set (imported from GDD doc #2, §5 core loop, §Q2–Q4).** The resolver's domain is a closed union. Each action carries the target venture/slot where relevant (the flat `PlayCard(card)` shape only worked for context-free consumables — most actions need a target):

| Action | Payload | Touches | Notes |
|---|---|---|---|
| `StartVenture` | card, sector | new Venture, Cash | consumes a SLOT |
| `RaiseEquity` | venture, amount | EBITDA/Multiple↑, Ownership%↓, Cash↑ | dilution: `newOwn = your$/post-money` |
| `TakeDebt` | venture, amount | NetDebt↑, Cash↑ | |
| `AcquireAddOn` | platform venture, target card | platform EBITDA/Multiple, Cash | the merge — resolver-computed, see below |
| `DividendRecap` | venture, pct | NetDebt↑, Cash↑ | gated T2+ |
| `ExitVenture` | venture | frees SLOT, Cash↑, ownership→0 | rolls live market multiple |
| `HireCEO` | venture | venture flagged passive | lower decay/upside |
| `SellPlay` | play card | Cash↑ (~50%) | liquidity lesson |
| `Reroll` | — | Cash↓, redraws hand | advances cursor (§3.1) |
| `PlayConsumable` | play card (+ optional target) | per the play's deltas | context-free plays need no target |
| `ReinvestBaseline` | venture | EBITDA↑ at floor efficiency, Cash↓ | the guaranteed always-available play |

Pre/post-conditions for each live in GDD doc #2; the resolver asserts them and is unit-tested per action.

### 4.2 The arbitrage merge is a RESOLVER COMPUTATION, not card deltas (signature mechanic)

This is the game's signature moment (§Q6: "build the merge FIRST") and it **cannot be encoded as fixed `{deltas}` on a card.** Accretion depends on *live* platform state at commit time:

- A same-sector add-on bolts the absorbed EBITDA in **at the platform's live multiple**, plus a **flat +20% synergy** on absorbed EBITDA (§Q6).
- A cross-sector add-on bolts in at the platform multiple, **zero synergy**, and **drags the live Platform Multiple down** (conglomerate discount). This can be *net-dilutive* on the blended multiple — which is legal and intended.

So the add-on card carries the *target's* raw inputs (`ebitda, multiple, price, debt, sector`), and `AcquireAddOn` *computes* the post-merge platform state from `(platform, target, synergyRule, discountRule)`. The "MULTIPLE ARBITRAGE +$X" flash fires after commit on the realized revaluation, never previewed (§Q6 "show the chips, hide the wisdom"). The card schema's `{deltas}` block is for context-free plays/cards; merges, raises, and exits resolve through dedicated `apply` branches.

---

## 5. Content-as-data pipeline + the invariant test

### Pipeline: spreadsheet → JSON → typed runtime objects

```
[ Authoring workbook ]            humans tune numbers here (§11 #1/#4)
        │  export
        ▼
[ cards.json / economy.json ]     build artifact, versioned in git
        │  loaded at runtime + json_serializable codegen at build (build_runner; CI step)
        ▼
[ typed Dart: Card, EconomyConfig ]  compile-checked
        │
        ▼
[ engine/content loader ]         validates schema, feeds resolver
```

- **Cards and economy are pure data.** Card schema (§Q3): `{id, type, sector, ebitdaCents, multipleBp, priceCents, debtCents, effect}`. A "PLAY" consumable (§Q2) is just `type:'consumable'` reusing the same schema.
- **`effect` is `Deltas` over the five inputs ONLY.** Canonical field names, pinned once so schema and test agree: **`ebitda, multiple, netDebt, ownershipPct, cash`** (these map to the integer fields above; `ebitda→ebitdaCents`, `multiple→multipleBp`, `ownershipPct→ownershipBp`). There is no `score`/`netWorth` key; JSON with any other key fails deserialization.
- **JSON ships inside the app binary** (asset bundle). Content drops are app updates (no server; fully offline).
- A startup validation pass rejects malformed/unknown-key cards loudly.

### The automated invariant test (§7 — the single most important test in the project)

The §7 hard invariant — *every card / consumable / **event** may ONLY mutate the five inputs, never a flat +score* — is enforced executably in the engine package, in CI on every commit.

**Three layers:**

**1. Schema-level (static):** `effect` is a `Deltas` with only `{ebitda, multiple, netDebt, ownershipPct, cash}`. No field exists to hold a raw score. Illegal state is largely unrepresentable.

**2. Behavioral — the real test.** It diffs *paths* over the nested per-venture state, and the "what's allowed" / "what's bookkeeping" predicates are **defined, not hand-waved** (the earlier draft left `isGameplayField` undefined — the whole test rested on it):

- `ALLOWED_GAMEPLAY_PATHS` = the per-venture set `{venture[*].ebitdaCents, venture[*].multipleBp, venture[*].netDebtCents, venture[*].ownershipBp}` ∪ `{cashCents}`. **This explicit constant IS the definition of a gameplay field.** A path not in this set and not in the bookkeeping set is forbidden.
- `BOOKKEEPING_PATHS` = `{rngCursor, actionLog, round, tier, schemaVersion, ventures[*].id, ventures[*].sector}` plus list-length changes from `StartVenture`/`ExitVenture`. Adding/removing a venture is allowed; mutating a non-allowed field on one is not.
- **Diff mechanism (Dart has no AOT reflection — this must be explicit, not magic).** `GameState` exposes a hand-written `Map<String,int> flatten()` that walks itself to a canonical map of `path → value` (e.g. `ventures.0.ebitdaCents → 42`). `diffPaths(before, after)` is set difference over those maps. No `dart:mirrors`. This `flatten()` is a small, tested, hand-maintained function — listed here as real work, not a freebie.

```dart
final allowed = ALLOWED_GAMEPLAY_PATHS_FOR(before); // expands venture[*] to live indices

// (a) cards & consumables
for (final card in ContentDb.all) {
  final before = baseStateWith(card);          // sets up a legal target if needed
  final action = actionFor(card);              // PlayConsumable / AcquireAddOn / ...
  final after  = resolver.apply(before, action, RunRng(seed: 1));
  final touched = diffPaths(before, after);
  expect(touched.difference(allowed).difference(BOOKKEEPING_PATHS), isEmpty,
         reason: 'Card ${card.id} mutated a forbidden field');
}

// (b) EVENTS, DRIFT, DECAY, INTEREST, SYNERGY are also "events" under §7 —
//     covered explicitly, because they mutate the five inputs too and the
//     loop above only covers ContentDb cards (the earlier draft missed this):
for (final ev in [marketDrift, decayTick, interestCharge, ...ContentDb.events]) {
  final after = ev.apply(before, RunRng(seed: 1));
  final touched = diffPaths(before, after);
  expect(touched.difference(allowed).difference(BOOKKEEPING_PATHS), isEmpty,
         reason: 'Resolver event ${ev.name} mutated a forbidden field');
}
```

**3. Directionality (§7 "directionality must stay real") — stated honestly.** Sign correctness, NOT a generic "arbitrage is always accretive" claim (that is FALSE for the legal cross-sector case in §Q6 and would fail). Concretely:
- `TakeDebt`/`DividendRecap` strictly **increase** NetDebt.
- `RaiseEquity` strictly **decreases** Ownership% (and increases Cash).
- **Same-sector** add-on is net-accretive (asserted with the +20% synergy at a *fixed* platform multiple — a unit test, deterministic).
- **Cross-sector** add-on drags the blended platform multiple **down** (asserted as a sign, may be net-dilutive — also fine).
- The broad "is arbitrage accretive across all sectors/markets?" question is **balance-harness territory (§11 #8), not a unit test** — it needs Monte-Carlo over platform multiples and the discount, so it lives in the sim plan, not the millisecond invariant suite.

This invariant suite is pure Dart, no device, milliseconds, every commit. The §7 invariant cannot silently rot as content grows.

### 5.1 Market drift vs. the banned permanent multiple buff
Market drift legally mutates `multiple` because it is **exogenous global weather**, applied by the resolver's drift step, never by a card (§Q3, §Q2 MEMO ban). The invariant test checks *which field moved*; the **ban on a card-driven permanent multiple buff is enforced separately**: a static content lint asserts no card/consumable `effect` writes a positive `multiple` delta (only drift, a resolver event, may raise a multiple). That lint is the actual guard for the locked §Q2 ban, which a "which-field" diff alone cannot catch.

> **Errata (2026-06-06, Phase 2):** the lint's scope is CONSUMABLES only, not "card/consumable" as written above — doc 04 §1's locked table legally gives raise/partner cards positive `multiple` deltas (FIN_SEED_RAISE +1000, PRT_GROWTH_HACKER +500), events are resolver-side market weather (EVT_SECTOR_BUBBLE's +4200 is the market, exempt), and the GDD §8 Q2 ban targets the consumable "MEMO" (a permanent sector-multiple buff PLAY). Enforced in `packages/engine/test/content_lint_test.dart`.

---

## 6. Local saves + persistence (§11 #6, folded in)

Fully offline, on-device only. No cloud, no accounts.

- **Format:** JSON in the app's private documents dir via `path_provider`. No SQLite at this scale; small human-readable files. `shared_preferences` for tiny meta flags only.
- **Two save scopes:**
  - **Run save (mid-run autosave):** the *minimal* reproducible state — `{schemaVersion, seed, cursor, startConfig, actionLog}`. A cached `currentDerivedState` is stored **only as an optimization**, and the rule is explicit: **on load, if `schemaVersion` mismatches the engine, discard the cache AND the run (do not replay a stale stream); otherwise verify the cache by checking that replaying `actionLog` reproduces it, else discard the cache and replay from `{seed, actionLog}`.** Two sources of truth are reconciled, never trusted blindly (the earlier draft left this as a silent-corruption risk).
  - **Meta save (persists across runs, §Q7):** Reputation total + meta-level, unlocked card/sector pool, Backgrounds/Hard Modes, local title ladder, furthest-tier-reached, opposite-death callback history. Access state only; nothing power-creeps.
- **Versioning:** every save carries `schemaVersion`. `migrate(json, fromVersion) -> currentSchema` runs on load, forward-only pure functions, unit-tested. **But a change to RNG algorithm/draw order or the five-input schema is a hard bump: such runs CANNOT be replayed and in-progress run saves are ABANDONED on that bump** (a migration cannot fix a broken seed; meta saves still migrate normally). This is the honest rule the earlier draft contradicted.
- **Corruption safety:** atomic writes (temp file + rename); on load failure fall back to "no run in progress." Meta save keeps a `.bak`.

---

## 7. Builds for both stores

> **Deployment decision (locked 2026-06-06): Flutter confirmed, ANDROID-FIRST.** The solo dev is on Windows; Apple's toolchain requires macOS to build/sign/upload for *any* stack, so this is a pipeline choice, not a stack one. Develop and ship **Android entirely from Windows** (`flutter build appbundle` → Play Console). Day-to-day work (code, Android emulator, pure-Dart `dart test`, balance harness) is 100% Windows-resident. **iOS is deferred**; when ready, build+sign+TestFlight via **Codemagic free-tier** (Flutter-native cloud Mac CI) or GitHub Actions macOS runners, or a rented/owned Mac. One codebase means iOS is a build/sign exercise, not a rewrite. *Guardrail:* keep code platform-neutral (no Android-only plugin without an iOS-capable equivalent) and the engine package free of Flutter imports, so the iOS on-ramp stays a pipeline step.

One Flutter repo, two build targets, one toolchain.

| Concern | Android (Play) | iOS (App Store) |
|---|---|---|
| Build command | `flutter build appbundle --release` | `flutter build ipa --release` |
| Output | `.aab` | `.ipa` via Xcode archive |
| Signing | upload keystore (local) | Apple cert + provisioning profile (Mac + Xcode) |
| Store review note | finance/sim, **not gambling**; "no data collected" | same; App Privacy "Data Not Collected" |

- **Mac requirement is unavoidable on any stack** for iOS signing. One Mac (or a CI mac runner) between two people suffices.
- **No backend, no accounts, no IAP, no ads** → light compliance: declare "no data collected," answer the gambling question (simulated finance, no real-money wager, no payout → not gambling).
- **Leaderboards (§Q7) are platform-native (Game Center / Play Games), OFF by default, fully optional.** Clarification for the locked "no accounts" constraint: this uses the player's **OS-level platform identity**, not an app account we create or store; score submission is opt-in and the game is 100% playable with it off. It is the only external touchpoint and is degradeable. (Honest note: enabling it adds a plugin + the platform sign-in surface — kept off by default to honor the constraint.)
- **CI (lean, two-person):** one GitHub Actions workflow runs `dart test` on the engine package (including the invariant, golden draw-order, and static guard tests) plus `build_runner` codegen check on every push; release builds run on demand to keep mac-minutes cheap.

---

## 8. Scope: vertical slice first

Per GDD §11 #7, the first buildable target is **not** the full card set. Build, in order:

1. The engine model (§4.1), RNG (§3), and net-worth getter — with the invariant + golden tests *before* content.
2. **The arbitrage merge in isolation** (§4.2) — GDD §Q6 says prove this FIRST.
3. T1 loop with ~6–10 cards (a venture-to-start, an add-on, a raise, a debt instrument, the baseline reinvest, 1–2 plays) — enough to prove "T1 + merge is fun."
4. Only then scale toward the ~15–20 starting cards (GDD doc #4) and the ~25–35 ship target (§Q7).

---

## 9. Summary of locked technical decisions

| Decision | Choice | Why |
|---|---|---|
| Stack | **Flutter + Dart** | Testable pure engine + dual-store; one language (see `data/stack-decision.json`) |
| State model | **Per-venture five inputs + global Cash; net worth derived** | Matches GDD §2/§Q4; merge needs live per-venture state |
| RNG | Single stream, explicit cursor, **SplitMix64 pinned**, integer-only | Bit-perfect replay for AUTOPSY + harness |
| Determinism | **No floats below UI; golden draw-order file; static grep test** | Byte-for-byte replay across ABIs |
| Merge | **Resolver computation, not card deltas** | Accretion depends on live platform state (§Q6) |
| Architecture | Pure `engine` (no Flutter) ← one-way ← `app` | Math can't be corrupted by UI; runs headless |
| Content | Spreadsheet → JSON (in-binary) → typed Dart via build_runner | Tune without recompiling; codegen is a real CI step |
| Invariant | Derived net worth + explicit `flatten()`/path-diff over cards AND events; sign-only directionality; separate multiple-buff lint | §7 enforced executably and honestly |
| Saves | Atomic JSON; cache reconciled or discarded; in-progress runs abandoned on RNG/schema bump | Offline, resumable, never silently corrupt |
| Builds | `flutter build appbundle` / `ipa`; leaderboard opt-in, OS identity not an app account | One repo, two stores, no backend, honors "no accounts" |
| Scope | Vertical slice (T1 + merge, ~6–10 cards) before full set | Two-person reality (§11 #7) |

The throughline: MULTIPLES is a numbers game, so the toolchain and the architecture are chosen to make the *numbers* trivially testable and reproducible, and to keep the UI strictly downstream of, and powerless over, the rules.
