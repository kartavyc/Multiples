# MULTIPLES — Flutter app

The Flutter shell for **MULTIPLES**. All game logic lives in the pure-Dart
engine at [`../packages/engine`](../packages/engine); the widgets here only
read `GameState` and dispatch engine calls (operate / endTurn / runOperate /
deadline checks), and format numbers via the engine's `money.dart` helpers.

See the [repository README](../README.md) for what the game is, how to play,
and the full build instructions.

## Quick commands

```bash
flutter analyze
flutter test

# Android
flutter build apk --release

# Web (WASM-only — the engine's 64-bit integer math can't target dart2js)
flutter build web --wasm --release --no-tree-shake-icons
```

## Layout

- `lib/controller.dart` — holds engine state, dispatches engine calls, owns the
  autosave journal.
- `lib/save_store.dart` + `lib/save_backend*.dart` — persistence: two small
  JSON blobs behind a platform seam (`dart:io` files on native,
  `SharedPreferences` on web, chosen by a conditional import).
- `lib/screens/`, `lib/widgets/` — the UI (art tokens per
  `../docs/07-art-style-bible.md`).
- `assets/data/` — build copies of `/data/*.json` (the source of truth),
  bundled so the engine can load cards + the economy model at runtime.
