<!-- PROJECT MEMORY CORE. Loaded in full every session. Keep under ~150 lines.
     Token-efficient memory: this file = always-loaded index. Details live in
     path-scoped .claude/rules/*.md (load only when touching matching files) and
     .claude/STATE.md (the living ledger, read on demand). Do NOT @import big files
     here: imports expand at launch and cost tokens. Reference by path instead. -->

# MULTIPLES (working title "Aura maxxing")

Single-player, offline finance roguelike for iOS + Android. You run private-equity-style
ventures, climb net-worth tiers against a deadline, and the signature moment is the
multiple-arbitrage merge. No server, no backend, not GUI-heavy. Built by the user + Claude.

## Architecture (monorepo, one-way dependency)

```
packages/engine/   PURE DART. No Flutter import. Deterministic rules engine. Runs under `dart test`.
app/               Flutter app (Android first; iOS later). Depends on engine via path.
data/              economy-model.json, cards.json, stack-decision.json (authoritative content).
docs/              01..06 = the 6 locked P0 design specs. Plan in docs/superpowers/plans/.
```
Dependency arrow points ONE way: `app -> engine`, never the reverse. Keep the engine pure and testable.

## LOCKED conventions (do not re-derive these; they cost a session to rediscover)

**Fixed-point integers only. NO `double` anywhere in `packages/engine`.**
- Money: integer **cents**.
- `multipleMilli`: multiple x1000 (14x = `14000`).
- `ownershipBp`: basis points x10000 (80% = `8000`, 100% = `10000`).
- Integer division **truncates toward zero** (`~/`). Do bp/milli divisions LAST.
- This is authoritative across doc 01 (says "authoritative"), doc 02, economy-model.json, and the
  resolver. Doc 03 §4.1 was reconciled to match (it had wrongly said multiple was basis points).

**The §7 invariant (most important rule in the codebase):**
- Only FIVE inputs ever mutate: `{ebitda, multiple, netDebt, own, cash}` (delta key for ownership is `own`).
- `ebitda/multiple/netDebt/own` are PER-VENTURE; `cash` is the single global quantity.
- Net worth is a DERIVED getter, never a stored/settable field. No card or action can write it.
- Card `deltas` keys must be a subset of those five. The invariant test enforces this.

**Determinism:** SplitMix64 RNG with an explicit cursor. Same seed + cursor reproduces the exact
stream (byte-identical iOS/Android). Replay/save depend on this. Never use `Math.random`/`Date.now`.

## Build / test / toolchain

- Engine tests: `cd packages/engine && dart test` (or `dart test test/<file>`). Analyze: `dart analyze lib test`.
- Dart SDK 3.12.1 lives at `C:\src\dart-sdk` (manual zip install). A `~/bin/dart` shim makes `dart`
  resolve in every shell incl. subagents. winget's Dart package downloads but its EXTRACT step is broken
  (exit 92); winget has no `Flutter.Flutter` package either. Install Flutter via official zip at Phase 3.
- TDD always: red -> green -> refactor. Verify (full suite + analyze) before every commit.
- Conventional commits; work on `feat/*` branches, never commit straight to `main`.
- End commit messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Where to look (read on demand, do not inline)

- **Current status + decisions:** `.claude/STATE.md` (read this at session start).
- **The build plan:** `docs/superpowers/plans/2026-06-06-multiple-vertical-slice.md` (phases 0-5).
- **Design specs (cold storage):** `docs/01-economy-math-spec.md` (economy, authoritative formulas),
  `docs/02-core-loop-game-state.md` (state schema + action pre/post), `docs/03-technical-design.md`
  (engine architecture), `docs/04-content-card-database.md` (cards), `docs/05-ux-flow-wireframes.md`
  (screens), `docs/06-save-persistence.md` (save format).
- **Authoritative constants:** `data/economy-model.json`. The proven prototype: `prototype/`.
- **Path-scoped detail rules:** `.claude/rules/` (engine, content, flutter-app) load automatically
  when you touch matching files.

## Writing style

No em dashes. Vary sentence length. Active voice, contractions. See ~/.claude/CLAUDE.md for the full house style.
