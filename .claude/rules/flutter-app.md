---
paths:
  - "app/**"
---

# Flutter app rules

Loaded only when working in `app/`. (Phase 3+; the app shell does not exist yet.)

- The app depends on `engine` via a path dependency. **All game logic lives in the engine.** Widgets read
  `GameState` and dispatch `Action`s through `apply`; they never compute money, multiples, or net worth
  themselves. No business rules in the UI layer.
- Build grey-box first (per docs/05): correct numbers and flow before any art polish. The five inputs +
  derived net worth + forward meters (debt runway, hot/cold) are the HUD spine.
- The signature beat: `EV = EBITDA x Multiple` reveal, then the post-commit "MULTIPLE ARBITRAGE +$X"
  flash fired on the realized revaluation (never previewed - "show the chips, hide the wisdom", §Q6).
- Format money/multiples through the engine's `money.dart` helpers, not ad-hoc string code.
- Android dev on Windows; iOS via cloud-Mac CI later. Run on an emulator to verify, not just widget tests.
