# MULTIPLES — Save / Persistence & Versioning Spec (P0 #6)

> Status: **draft, design-locked**. Implements GDD §11 #6 and §7; consumes the canonical schema in `docs/02-core-loop-game-state.md` (the `SaveFile` / `RunState` / `MetaState` shapes) and the stack + persistence decisions in `docs/03-technical-design.md` §3, §6, §7.
> Scope: on-device save format, exactly what persists, the `schemaVersion` migration strategy, autosave cadence + crash safety, and how this maps onto Flutter + Dart local storage. No cloud, no accounts, no server (GDD build context). One source of truth per fact; this doc does not re-derive game rules.

---

## 1. Principles (inherited, not re-argued)

1. **Fully offline, on-device only.** No cloud sync, no accounts, no backend. The seed *is* the bug report (TDD §3). Game Center / Play Games leaderboards are opt-in, OFF by default, and store **nothing** in our save (TDD §7).
2. **A run is fully described by `{seed, schemaVersion, startConfig, actionLog}`** (TDD §3.1). Everything else in `RunState` is *derivable* by replaying the action log into a freshly seeded engine. We persist the minimal reproducible state and treat the rich state as a cache.
3. **Two save scopes are physically separate files** so a corrupt mid-run save can never take meta-progression down with it.
4. **Versioned + migrated forward only.** Meta migrates across every bump. A run save survives content-only bumps and is **abandoned (not migrated)** on any RNG-algorithm / draw-order / five-input-schema bump, because a migration cannot un-break a seed whose stream moved (TDD §6).

---

## 2. What persists — two scopes, two files

| | **Run save** (mid-run, pause/resume) | **Meta save** (durable, across runs) |
|---|---|---|
| File | `run.json` (+ `run.json.tmp` during write) | `meta.json` (+ `meta.json.bak`, `meta.json.tmp`) |
| Lifetime | exists only while a run is in progress; deleted on RUN_OVER after meta is settled | permanent; created on first launch, updated at every RUN_OVER |
| Maps to schema | `SaveFile.run` (`RunState \| null`) | `SaveFile.meta` (`MetaState`) |
| On RNG/schema bump | **abandoned** (file deleted, "no run in progress") | **migrated** normally |
| Survives app delete? | no (private dir) | no (private dir; acceptable — horizontal-only progress, GDD §Q7) |

We **split the conceptual `SaveFile` into two physical files.** `SaveFile` in doc #2 is the *in-memory* union; **it is never serialized as a single object, so its top-level `SaveFile.schemaVersion` field (doc #2 line 317) is not written to disk.** Each physical file carries its own version: `run.schemaVersion` and `meta.schemaVersion` (the latter is `MetaState.schemaVersion`, doc #2 line 295). These two on-disk version fields are the authoritative ones; they migrate and fail independently. (If a coder is mapping doc #2 literally: serialize the two members separately, ignore the union wrapper's version.) `meta.json` is the durable store; `run.json` is the resumable autosave.

### 2.1 Run save — the minimal reproducible record (NOT the fat `RunState`)

We do **not** serialize the full `RunState` (ventures, hand, market, meters, derived caches) as the source of truth. We persist only what replay needs, plus an *optional* derived-state cache as an optimization:

```jsonc
// run.json
{
  "schemaVersion": 1,
  "seed": 7314159265358979,        // RunState.rng.seed — the run stream (authoritative)
  "cursor": 142,                   // RunState.rng.cursor — the resume point (authoritative)
  "startConfig": {                 // everything needed to construct round-1 state
    "runId": "r_7f3a…",            // RunState.runId — DERIVED from seed (denormalized convenience; see note)
    "backgroundId": "BOOTSTRAPPER" // RunState.backgroundId (§Q7) — affects starting state & draw bias
  },
  "actionLog": [                   // the ONLY gameplay source of truth (RunState.log shape)
    { "round": 1, "tier": 1, "type": "START_VENTURE", "cardDefId": "ven_saas_seed",
      "appliedDeltas": { "cash": -50000000, "ebitda": 800000, "ownership": 10000 },
      "cashAfter": 450000000, "netWorthAfterSnapshot": 461200000 }
    // … one LoggedAction per committed action, in commit order
  ],
  "cache": {                       // CACHE ONLY — see §2.2; never the source of truth
    "schemaVersion": 1,            // schema the cache was written at; MUST equal top-level or cache is dropped
    "state": { /* a serialized RunState snapshot, with rng stripped — see §2.2 */ }
  }
}
```

- `seed` + `cursor` + `actionLog` + `startConfig` is the **canonical record**. Given these and the same `schemaVersion`, the engine reconstructs the exact `RunState` by replaying (TDD §3.1).
- **`runId` is reconstructable from `seed`** (TDD §3: "the seed derives the run id"). It is stored in `startConfig` only as a display/debug convenience; on load, if it disagrees with the seed-derived id, the seed-derived id wins and a dev warning is logged. There is no separate run-id entropy.
- `actionLog` entries are exactly the `LoggedAction` shape from doc #2 (round, tier, type, cardDefId?, targetVentureId?, appliedDeltas, cashAfter, netWorthAfterSnapshot, note?). They are append-only and never rewritten. `appliedDeltas` keys are the canonical `Deltas` keys (`ebitda, multiple, netDebt, ownership, cash` — doc #2 §1; note the wire key for ownership is `ownership`, mapping to the basis-point field). `netWorthAfterSnapshot` is the §7-whitelisted log-only field (doc #2 line 234 / §5.1) — it is written once and never read by any effect path, so persisting it does not violate the no-`+score` invariant.
- **Why not store the fat state as truth?** Two reasons: (1) replay is the same code path the AUTOPSY and balance harness already depend on, so we get persistence correctness for free; (2) a fat blob can drift from the rules after a content tweak, the action log cannot.

### 2.2 The derived-state cache and its reconciliation rule (load-time)

`cache.state` is a serialized `RunState` kept **only to skip replay on the hot path** (instant resume on a phone). It is never trusted blindly.

**Two rules keep the cache from duplicating or contradicting the canonical record:**

1. **The RNG is stripped from `cache.state` on serialize.** The cache does *not* store `rng.seed` / `rng.cursor`; the top-level `seed` / `cursor` are the only copies. On deserialize we re-inject the top-level pair into `cache.state.rng`. This removes the "stored twice, which wins?" ambiguity entirely: there is exactly one seed and one cursor on disk.
2. **The cache is tagged with the schema it was written at** (`cache.schemaVersion`). If it differs from the top-level `run.schemaVersion` for any reason, the cache is dropped unread (it predates a migration and would spuriously mismatch a freshly replayed state, defeating its own purpose).

On load (TDD §6, made concrete):

```
load run.json:
  if file missing            -> "no run in progress" (fresh main menu)
  if JSON parse fails        -> discard run.json, "no run in progress" (crash safety, §5)
  if run.schemaVersion != ENGINE_SCHEMA_VERSION:
        if bump is CONTENT-ONLY (see §3) -> migrate run.json forward, DROP cache, replay
        else (RNG/draw-order/5-input bump) -> ABANDON the run (delete run.json), "no run in progress"
  else (versions match):
        if cache present AND cache.schemaVersion == run.schemaVersion:
            re-inject top-level {seed, cursor} into cache.state.rng
            verify (replay {seed, startConfig, actionLog} from cursor=0 -> `expected`):
                assert expected.rng.cursor == top-level cursor      // corruption signal; else discard & replay
                if flatten(expected) == flatten(cache.state) -> trust cache, resume
                else -> discard cache, resume from `expected` (log a dev warning)
        else:
            resume from replayed state
```

`flatten()` is **engine code, not a test helper** — the same hand-written `Map<String,int>` walk on `GameState` that the invariant test imports (doc #3 line 225). It lives in the pure `engine` package so the load path and the invariant test share one implementation; there is no second copy.

Two correctness notes on `flatten()` for *reconciliation* (it was authored for the *invariant* test, which has a narrower job):
- The invariant test's `BOOKKEEPING_PATHS` (doc #3 line 224) deliberately excludes `rngCursor`, `round`, `tier`. Reconciliation cares about those, but it does not rely on `flatten()` to cover them: **the `cursor` equality is asserted separately** (the line above), and `round`/`tier` fall out of the replay producing the same `expected` state anyway. So reconciliation = `flatten()` equality on the economic paths **plus** the explicit cursor assert.
- Reconciliation is "two sources of truth, never trusted blindly": the cache is an optimization that must *prove* it equals replay or be thrown away. If it disagrees, the replayed state silently wins.

**Where the verify runs:** on the **main thread**. A single tier's action log is a few dozen integer operations — microseconds — so replay-verify is cheaper than spawning an isolate and message-passing a full `RunState` across it. We do **not** mandate an isolate here. (If a real measurement on a low-end device ever shows resume jank — it won't at these sizes — moving verify to a `compute()` isolate is a one-line change, but it is not in v1.)

### 2.3 Meta save — the durable access store

`meta.json` is exactly `MetaState` from doc #2, serialized whole (it is small and all "access, never advantage", GDD §Q7):

```jsonc
// meta.json
{
  "schemaVersion": 1,
  "reputation": 184200,
  "metaLevel": 3,
  "furthestTierReached": 3,
  "unlockedCards": ["ven_saas_seed", "addon_bolt_sw", "fin_seriesA", …],
  "unlockedSectors": ["SOFTWARE", "SERVICES", "RETAIL", "INDUSTRIAL"],
  "unlockedBackgrounds": ["BOOTSTRAPPER", "OPERATOR"],
  "hardModes": [],
  "cosmetics": { "titles": ["Bootstrapper"], "activeTitle": null, "iconSkins": [] },
  "lastDeathCause": "MISSED_DEADLINE",   // opposite-death callback (§Q5)
  "runsPlayed": 27,
  "cleanExits": 9,
  "lastSettledRunId": "r_7f3a…"          // idempotency guard for RUN_OVER settlement (§5)
}
```

- Enum strings are **the json_serializable serialized form of the Dart enum**, not free text. `lastDeathCause` is one of the `DeathCause` values (`BANKRUPTCY` / `MISSED_DEADLINE`, doc #2 line 56); sectors/backgrounds likewise serialize to their enum/id names. A value outside the enum fails deserialization (caught by the migrate pass).
- `lastSettledRunId` is the only field this doc adds to `MetaState` beyond doc #2 — it exists purely for crash-safe settlement (§5). It is access/bookkeeping state, not economy.

Nothing here power-creeps; it is unlock/access state plus local-only stats. It is updated **only at RUN_OVER**, in the strict settlement sequence already defined in doc #2 §2 (build autopsy → settle reputation → bump furthestTier → set lastDeathCause/runsPlayed → set lastSettledRunId → only then `run = null` and delete `run.json`).

---

## 3. Versioning + the migration hook

Every file carries an integer `schemaVersion`. The engine pins one `ENGINE_SCHEMA_VERSION`. **Bumps fall into two classes**, and the class decides whether an in-progress run survives:

| Bump class | Examples | Run save | Meta save |
|---|---|---|---|
| **CONTENT-ONLY** (replay-safe) | new cards/economy tuning that does NOT change draw order, a new `MetaState` cosmetic field, a renamed display-only field | migrate forward, drop cache, **replay** | migrate forward |
| **STREAM-BREAKING** (replay-unsafe) | RNG algorithm change, draw-order change (TDD §3.1), any change to the five-input shape or a `LoggedAction` field replay reads | **ABANDON** (delete `run.json`) | migrate forward |

A migration **cannot un-break a seed whose stream moved**, so STREAM-BREAKING bumps abandon in-progress runs by design — meta-progression is untouched, so the player loses one mid-run, never their Track Record. Content drops ship inside the app binary (TDD §5), so a content drop that does not touch draw order is CONTENT-ONLY and resumes cleanly: this is what stops content updates from bricking saves.

### 3.1 Enforcing the classification (so a stream-breaking change can't ship as content-only)

The CONTENT-ONLY vs STREAM-BREAKING call is load-bearing, and a human can get it wrong (ship a draw-order change as a content bump → silently corrupt every resumed run). The **golden draw-order test (TDD §3.1, `test/golden/draw_order_v1.json`)** is the gate that forces the call:

- That test pins the first ~200 draws of a fixed seed. **Any change to the RNG algorithm or draw order makes it fail.**
- **CI rule:** a failing golden draw-order test may only be made green by *committing a new golden file under a new version number* (`draw_order_v2.json`) **and** bumping `ENGINE_SCHEMA_VERSION` with the new version classified STREAM-BREAKING in the abandon table. You cannot edit the existing golden file in place. This converts "did you remember to mark it stream-breaking?" from discipline into a test that won't go green otherwise.

### 3.2 The migration hook — concrete strategy

A single forward-only, pure, unit-tested function per file scope, applied as a chain `vN -> vN+1 -> … -> current`:

```dart
// pure, no I/O, no clock — testable in isolation
Map<String,dynamic> migrateMeta(Map<String,dynamic> json, int from);
Map<String,dynamic> migrateRun (Map<String,dynamic> json, int from); // may THROW AbandonRun

// registry: each step is a tiny pure function (from version N to N+1)
final metaMigrations = <int, Migration>{
  1: (j) => j..['cosmetics'] ??= {'titles': [], 'activeTitle': null, 'iconSkins': []},
  // 2: (j) => …  add the next step here; never edit a shipped step
};

T migrateChain<T>(json, from, current, steps) {
  var j = json;
  for (var v = from; v < current; v++) {
    final step = steps[v];
    if (step == null) throw AbandonRun('no migration $v->${v+1}'); // run: abandon; meta: hard-fail loudly
    j = step(j);
  }
  return j;
}
```

Rules that keep content drops from bricking saves:

1. **Forward-only.** No downgrades. An older app refusing a newer save shows "this save is from a newer version" rather than corrupting it.
2. **Additive-by-default for meta.** New `MetaState` fields get a defaulted migration step (e.g. `??=`); old saves gain the field with a safe default. Removing/repurposing a field is a deliberate numbered step.
3. **Each step is append-only and frozen once shipped.** You add step `N->N+1`; you never edit `2->3` after it ships, or you desync players mid-upgrade.
4. **Run migrations may legally THROW `AbandonRun`** for any STREAM-BREAKING change; the loader catches it and falls back to "no run in progress" (the meta save is loaded independently, so it is never affected).
5. **Tested, with a hard PR rule:** golden fixtures of every prior on-disk version live in `test/golden/saves/`; a test loads each through `migrateChain` and asserts it reaches current schema (or, for run saves on a stream-breaking version, that it abandons cleanly). **This is recurring work: every schema-bump PR MUST commit the golden save fixture for the version it leaves behind** (one fixture per prior version; ~one file per bump). A bump PR with no new fixture fails review. Without this rule the fixtures rot and the regression net silently shrinks.

---

## 4. Autosave cadence

We autosave **eagerly at every committed mutation** rather than on a timer, so the worst-case data loss is exactly one in-flight action:

- **After every committed `applyAction`** that changes state (i.e. every entry appended to `actionLog`), write `run.json` atomically (§5). One action = one log entry = one save.
- **At every phase transition** (OPERATE→ACT→SHOP→DEADLINE_CHECK), write as well, so the resumed `phase` is exact (OPERATE auto-resolves, so its post-state must be captured before the player can quit during ACT).
- **On app lifecycle background/pause** (`AppLifecycleState.paused`/`inactive`, `WidgetsBindingObserver`), force a synchronous flush — the "user got a phone call / swiped away" case must not lose the current action.
- **No autosave inside OPERATE's intermediate steps.** OPERATE is atomic and deterministic; we save its *result* once, not its eight internal steps. Mid-OPERATE crash → on resume we replay the log up to the last committed action and re-run OPERATE deterministically (same seed/cursor → same result).

**Honest cost — this is a full-file rewrite, not an append.** Plain JSON files cannot be appended in place: each autosave **re-serializes and rewrites the whole `run.json`**, including the `cache.state` snapshot (a `RunState` with up to 4 ventures, the hand, shop offers, scheduled effects, and meters). At a phone's I/O speeds this is still cheap (a few KB; see §4.1 ceiling), but do not picture it as a tiny log append — picture a small whole-file rewrite per action.

To keep the per-write cost honestly small, **the `cache.state` snapshot is the only "fat" part, and it is optional**: if profiling ever shows the per-action rewrite is too heavy, drop `cache` from the eager writes and write it only on phase-transition/pause saves (resume then replays from the log, which is correct anyway). v1 ships with the cache included on every write because at these sizes it is not worth the conditional.

### 4.1 Log-growth ceiling (back-of-envelope)

`actionLog` is append-only for an entire run (T1→T4). Worst case: ~4 tiers × ~8 rounds/tier × ~4 committed actions/round ≈ **~130 logged actions**, plus a handful for OPERATE-resolved events. Each `LoggedAction` is a small flat object (a few integer fields + two short string ids) ≈ ~150–250 bytes serialized, so a full end-game log is on the order of **~20–35 KB**. Add the `cache.state` snapshot (a few KB for 4 ventures) and `run.json` stays comfortably under ~50 KB for an entire run. A whole-file rewrite of <50 KB per action is trivial on any phone; no compaction or rotation is needed in v1.

---

## 5. Crash safety

- **Atomic-ish writes — stated honestly for `dart:io`.** Every write goes `write run.json.tmp` → `flush` → `rename` over `run.json`. On the common path `rename` is atomic, so a crash mid-write leaves either the old complete file or the new complete file, never a half-written one. **What plain `dart:io` does NOT give us:** a guaranteed-atomic rename on every Android storage backend, and a directory `fsync` (so the rename survives a power-loss within the OS's flush window). We do not pretend otherwise. The real guarantee we rely on is weaker and sufficient: **if a write tears, the load path treats the file as corrupt and recovers** (run → "no run in progress"; meta → `.bak` → fresh). Atomic-rename is the fast path; the corrupt-recovery path is the actual safety net. (TDD §6.)
- **Meta keeps a `.bak`, written with the same temp discipline.** Before overwriting `meta.json`: (1) write the new meta to `meta.json.tmp`, flush; (2) **copy the *current good* `meta.json` to `meta.json.bak` via `meta.json.bak.tmp` + rename** (so a crash during the backup copy cannot corrupt the existing `.bak`); (3) rename `meta.json.tmp` over `meta.json`. On load, if `meta.json` fails to parse, fall back to `meta.json.bak`; if both fail, start fresh meta (a rare, last-resort loss of *access* state only — never a run).
- **Parse failure is non-fatal.** A corrupt `run.json` → discard it, "no run in progress." A corrupt `meta.json` → `.bak` → fresh. The game always boots.
- **Replay is the ultimate integrity check.** Even a structurally valid but logically stale cache is caught by §2.2 reconciliation (replay must reproduce it, and the cursor must match). The action log + seed is the trustworthy core; the cache is disposable.

### 5.1 Settlement ordering + the double-settle guard (the dangerous case)

Meta is written only at RUN_OVER, whole-file, atomically, after the run is fully settled. The on-disk delete of `run.json` happens **last**, after the meta rename succeeds. But "meta rename succeeded, then crashed before deleting `run.json`" is a real window: on reboot a stale `run.json` sits next to already-settled meta, and a naive loader would replay and **re-settle the same run → double reputation**.

The guard is **`meta.lastSettledRunId`**, written inside the same atomic meta write as the settlement:

- Settlement sequence (extends doc #2 §2 step order): build autopsy → settle reputation → bump furthestTier → set `lastDeathCause` / `runsPlayed` → **set `meta.lastSettledRunId = run.runId`** → atomic meta write → **only then** delete `run.json` → in-memory `run = null`.
- **On boot, before resuming any `run.json`:** if `run.startConfig.runId == meta.lastSettledRunId`, this run was already settled; **delete `run.json` and do not replay/resettle it** (treat as "no run in progress"). Otherwise resume normally.
- This makes settlement idempotent: the worst a mid-settlement crash can do is leave an orphan `run.json` that the next boot recognizes and discards. Reputation is committed exactly once.

So a crash during settlement either keeps the pre-run meta (the run is still in `run.json` and replays cleanly next boot — not yet settled, `lastSettledRunId` unchanged) **or** commits the post-run meta with `lastSettledRunId` set (next boot discards the orphan `run.json`). There is no path that settles twice and none that loses a run that wasn't settled.

---

## 6. Mapping onto the Flutter + Dart stack

- **Storage primitive:** plain JSON files in the app's private documents directory via **`path_provider`** (`getApplicationDocumentsDirectory()`). No SQLite — the data is small and human-readable, which also aids two-person debugging (TDD §6). `dart:io` `File` for temp-write + `rename` (with the honest caveat in §5).
- **`shared_preferences`** holds only tiny **disposable** flags (e.g. "leaderboard opt-in", last-played-version banner) — **never** the run or meta save. These flags are *not* covered by the migration/`.bak` strategy and do **not** survive app delete reliably on either platform, so they are treated as independently defaulted: if a flag is missing it falls back to its safe default (leaderboard opt-in → OFF), and it may legitimately desync from `meta.json` (e.g. opt-in remembered while meta was reset). Nothing authoritative ever lives here.
- **Serialization:** `json_serializable` / `build_runner` codegen on the model classes (already a CI step, TDD §2). The migration functions operate on raw `Map<String,dynamic>` *before* typed deserialization, so an old-shape file is upgraded to current shape and only then parsed into typed objects (a missing field would otherwise throw at deserialize time). Enum fields serialize to their codegen string names (§2.3).
- **Threading:** replay-verification (§2.2) runs on the **main thread** — it is microseconds at our log sizes and an isolate would cost more than it saves. Only reach for a `compute()` isolate if a measured low-end-device profile ever shows jank (it won't in v1). The engine is pure Dart with no Flutter import (TDD §4), so it *can* run in an isolate unchanged if that day comes.
- **Where the code lives:** load/save/migrate is thin app-layer plumbing in `app/` (it does I/O); the *replay* and `flatten()` it calls are the pure `engine` package. The engine stays I/O-free and headless — persistence is the app's job, replay is the engine's.

---

## 7. The literal save-object shapes (canonical)

In-memory union is `SaveFile` (doc #2 §1); on disk it is the two files above, serialized as **two independent documents** — the `SaveFile` wrapper and its `schemaVersion` are not persisted (§2). Reference shapes, integer conventions inherited from doc #2 (cents / milli-units / basis points):

```ts
// ===== run.json (the resumable autosave; minimal reproducible record + cache) =====
interface RunSaveFile {
  readonly schemaVersion: number;          // gates migration / abandonment (authoritative on disk)
  readonly seed: number;                   // = RunState.rng.seed (the ONLY copy of seed on disk)
  cursor: number;                          // = RunState.rng.cursor (the ONLY copy of cursor on disk)
  readonly startConfig: {
    readonly runId: string;                // = RunState.runId — DERIVED from seed (denormalized; seed wins on conflict)
    readonly backgroundId: string;         // = RunState.backgroundId (§Q7)
  };
  actionLog: LoggedAction[];               // = RunState.log — THE source of truth, append-only
  cache?: {                                // CACHE ONLY; reconciled-or-discarded on load (§2.2)
    readonly schemaVersion: number;        // schema the snapshot was written at; must == top-level or dropped
    state: RunState;                        // rng STRIPPED on serialize; top-level seed/cursor re-injected on load
  };
}

// ===== meta.json (durable, across-runs access store) =====
type MetaSaveFile = MetaState;             // serialized whole (doc #2 §1); MetaState.schemaVersion is the on-disk version
//                                          // + the one persistence-added field: lastSettledRunId (§2.3, §5.1)
```

`LoggedAction`, `RunState`, and `MetaState` are defined once in `docs/02-core-loop-game-state.md` §1 and are not duplicated here. The only persistence-specific additions are: the physical two-file split (and the resulting drop of `SaveFile.schemaVersion`), `startConfig`, the optional `cache` wrapper with the rng-stripped snapshot, and `MetaState.lastSettledRunId`. Everything else is the locked game-state schema serialized as-is.
