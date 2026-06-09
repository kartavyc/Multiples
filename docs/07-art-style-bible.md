# MULTIPLES — Art & Style Mini-Bible (P2 #13, pulled forward)

> Status: **direction locked 2026-06-06** after 4 mockup iterations (casino felt → retro-CXO fleet → terminal de-text rounds → v4).
> Canonical reference implementations: `docs/mockups/layout-a-v4.html` (the ACT screen + merge beat) and
> `docs/mockups/ui-v4-all-screens.html` (every S0–S10 screen). When this doc and those files disagree, the files win.
> Everything here is UI skin. It changes nothing in `packages/engine` and must never leak game logic into widgets.

## The metaphor

**"THE TERMINAL."** The game is played on a retro dealmaker terminal: matte black machine bezel, gunmetal
nameplate, a CRT screen with scanlines, vignette, and a faint flicker. Deals arrive as order tickets on a
blotter; commits feel like executing trades. Balatro's spirit (juice, pops, count-ups, screen shake)
on a Wall-Street machine instead of a card table. Not casino, not 8-bit: modern pixel-adjacent retro.

**The nameplate MARK = your net-worth tier (the machine levels with you).** The nameplate reads
`MULTIPLES MK·<tier> · №<seed>`: Tier 1 = **MK·I**, T2 = **MK·II**, T3 = **MK·III**, T4 = **MK·IV**,
Endless ($1B+) = **MK·V**. Derived in the UI from `run.tier` (skin-only; no engine field). On tier clear and
on victory the mark *stamps* to the next numeral (shrink → overshoot 1.5× with a green flash → settle, ~900ms)
as part of the S7/S10 beat — a diegetic "your hardware got upgraded" reward. New runs start back at MK·I.

## Palette (5 colors + neutrals; greyscale-legible by design)

| Token | Hex | Role |
|---|---|---|
| `bg` | `#07090c` (screen) on `#000` (bezel) | Neutral near-black. NEVER tinted blue. |
| `fg` | `#e6edf3` | White phosphor: all primary numbers. Labels dim to `#76828d`, faint `#3a434c`. |
| `accent` | `#4da3ff` (hi `#8cc7ff`) | **Blue is a budget, not a wallpaper.** Only: CASH box, prices/BUY values, the one primary key per screen, selection/target glows, cursor. If blue exceeds ~10% of a screen, it's wrong. |
| `gain` | `#4dff8a` | Green: positive deltas, synergy, the NW surge, EXECUTE keys. |
| `loss` | `#ff5566` | Red: negative deltas, danger meters, EXIT/death. (Raise/equity tickets use `#b48cff` purple as the lone semantic extra.) |

## Type (3 faces, fixed jobs)

- **VT323** — every big number. Numbers are the heroes; render them 2–3× label size.
- **Silkscreen** — tiny small-caps labels (8–10px, letterspaced), section heads, keys, nameplate.
- **IBM Plex Mono** — body/rows where pixel fonts would tire (napkin rows, tape).

**Label-over-number is law.** Every stat = tiny word label above a big numeral (EBITDA / MULT / DEBT / OWN).
No cryptic glyphs, ever: a 1-word label beats a symbol that needs decoding. Sector names spelled out
(SOFTWARE, not SW) anywhere wider than a tag chip. Word budget per screen ≈ 40; numbers dominate ~3:1.

## The two sacred treatments

1. **Paper vs real (Tension B):** CASH lives in a solid 2px blue-bordered box tagged REAL. NET WORTH lives in a
   1px *dashed* ghost box tagged PAPER, dimmed to ~36% white. This contrast must survive greyscale.
2. **The NET-WORTH SURGE (the signature):** whenever net worth increases — merge booked, exit cashed, tier
   cleared — the NW box flips green, the number counts up (~900ms, ease-out cubic), a screen-wide green tint +
   inset glow rises, the screen shakes ~420ms, and the device vibrates (80ms). Then everything settles back to
   ghost. Exits additionally collapse the dashed paper box INTO the solid cash box. Death screens get none of this.

## Juice rules (Flutter: implement with implicit animations + a shake controller)

- **Commit beat (BUY_ADDON / EXIT / RAISE):** full-screen takeover → staged count-ups (EBITDA, then EV,
  ~700ms each, 350ms stagger) → headline pop (`+$260,000`, scale overshoot 1.25 → settle) + shake + spark burst
  (~20 particles) + vibrate. Headline figures are RENDER-ONLY (engine's arbitrage flash; never stored).
- **Small deltas:** stat ticks scale-pop 1.3×; floating `+$48k` / `−$180k` drift up and fade (~1.2s).
- **Idle motion (subtle, ≤3 elements animating at rest):** CRT flicker, blinking cursor, scrolling news tape,
  market-needle drift, attract-pulse on the suggested ticket.
- **Everything legible static.** Animation is garnish (docs/05 §0.2). Buttons are chunky 3D-press keys
  (4px drop edge, translate down on press). Meters are segmented LEDs with literal numbers beside them.
- **Hints never overlay content** — they live inline in section headers plus an attract glow on the target.

## Sound shortlist (defer implementation; keep list tiny)

Mechanical key thunk (any key), ticket shuffle (draw), dot-matrix chatter (napkin open), rising phosphor hum +
cash-register hit (NW surge), dial-tone drone cut (bankruptcy), champagne-adjacent chime (tier clear). All retro
office-machine timbres, no slot-machine sounds.

## File map

- `docs/mockups/layout-a-v4.html` — canonical ACT screen + merge interaction (source of truth for tokens).
- `docs/mockups/ui-v4-all-screens.html` — S0–S10 in the language, dev nav strip.
- Earlier mockups (`ui-mockup-v1`, `layout-b/c`, `layout-a`, `layout-a-v2-*`, `layout-a-v3-final`) are
  superseded exploration history. Do not extend them.
