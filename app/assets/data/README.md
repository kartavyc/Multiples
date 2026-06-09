# App content assets (BUILD COPIES — do not edit here)

`/data/cards.json` and `/data/economy-model.json` at the repo root are the SOURCE OF TRUTH.
The files in this directory are byte-identical build copies bundled into the Flutter app
(declared under `flutter: assets:` in `app/pubspec.yaml`) and handed to the engine's
`loadCards` / `loadEconomy` as raw strings at startup.

Why copies and not package assets: the engine is a pure Dart package whose purity guard
forbids ANY `flutter:` key in its pubspec, and Flutter can only bundle a dependency's
assets if that dependency declares them itself. So the app owns the bundling, same as the
engine's own `packages/engine/assets/` build copies.

- To change content: edit `/data/*.json`, then re-copy BOTH here and to
  `packages/engine/assets/` (`copy /b` preserves bytes).
- `app/test/smoke_test.dart` pins these copies byte-identical to `/data`, so a stale
  copy fails the suite loudly.
