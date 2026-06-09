---
paths:
  - "data/**"
  - "packages/engine/assets/**"
  - "docs/04-content-card-database.md"
---

# Content rules (cards + economy data)

Loaded only when touching content JSON, engine assets, or the card DB doc.

## §7 invariant on cards
Every card's `deltas` block may only use the five keys `{ebitda, multiple, netDebt, own, cash}`
(ownership key is `own`). Anything else is a violation the invariant test must catch. Merges, raises,
and exits are NOT card deltas - they resolve through dedicated `apply` branches because they depend on
live state at commit time.

## Fixed-point in JSON
- Money fields are integer cents (`$56,000` = `5600000`).
- `multiple` is milli-units x1000 (`14x` = `14000`, additive deltas can be negative for conglomerate drag).
- `ownership` is basis points x10000.
- Tier bars (economy-model.json): T1 `100000000` ($1M), T2 `1000000000` ($10M), T3 `10000000000` ($100M),
  T4 `100000000000` ($1B). Deadlines 8/8/9/10 rounds.
- Seed state: cash `2000000` + one SOFTWARE venture (ebitda `600000`, multiple `6000`, own `10000`,
  debt `0`) = net worth `5600000` ($56,000).

## Pipeline
Authoring workbook -> `data/*.json` (versioned) -> copied to `packages/engine/assets/` -> typed runtime
objects via `json_serializable` + `build_runner` (a CI step). `data/economy-model.json` is the authoritative
source of constants and formula notes; treat its `_note` fields as canon.
