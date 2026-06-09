# Engine content assets (BUILD COPIES — do not edit here)

`/data/cards.json` and `/data/economy-model.json` at the repo root are the SOURCE OF TRUTH
(authored content, versioned, human-reviewed). The files in this directory are byte-identical
build copies so the engine package is self-contained for tests and the eventual app bundle.

- To change content: edit `/data/*.json`, then re-copy here (the content tests assert the
  copies are byte-identical with the source, so a stale copy fails loudly).
- This is a pure Dart package, so there is no `flutter:` assets section in pubspec.yaml
  (the no-Flutter purity guard forbids one). Tests read these files via `dart:io`;
  the app layer does its own asset bundling and hands the engine raw JSON strings.
