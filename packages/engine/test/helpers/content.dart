/// The ONE shared test-side ContentDb/EconomyConfig load (lazy, cached).
///
/// dart:io is TEST-ONLY (the engine lib stays pure; doc 03 §4); the test
/// runner's cwd is the package root (tool/wintest.bat cds there), so
/// assets/ resolves directly. assets/ is the byte-identical build copy of
/// /data, pinned by content_test.dart.
library;

import 'dart:io';

import 'package:engine/content.dart';

/// The real 33-card database (19-card vertical slice inside).
final ContentDb kContent =
    loadCards(File('assets/cards.json').readAsStringSync());

/// The real economy constants.
final EconomyConfig kEconomyConfig =
    loadEconomy(File('assets/economy-model.json').readAsStringSync());
