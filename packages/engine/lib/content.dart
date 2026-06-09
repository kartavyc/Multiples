/// Typed content loading: cards.json + economy-model.json -> immutable Dart
/// objects (doc 03 §5 pipeline; doc 04 §0 units; plan task 2.1).
///
/// PURE parsing: [loadCards] and [loadEconomy] take raw JSON STRINGS. The
/// app/test layer does the I/O (no `dart:io` here — the engine stays a
/// headless library per doc 03 §4). Only `dart:core` + `dart:convert`.
///
/// LOCKED fixed-point conventions (economy-model.json `fixedPoint`):
/// - Money is integer **cents**. No `double` type anywhere in this package.
/// - `multiple` deltas/faces are milli-units x1000; `own` deltas are basis
///   points x10000.
/// - economy-model.json authors fractional constants as JSON decimals
///   (e.g. `0.35`); [fixedPointFromJsonNum] converts them ONCE at parse into
///   integer fixed-point (bp / milli / permille) via DECIMAL-TEXT integer
///   arithmetic — the binary float from `jsonDecode` is only ever
///   stringified (Dart prints the shortest exact round-trip text), never
///   computed with, so the engine sees integers only.
///
/// VALIDATION (fails loudly with [FormatException] naming the offending
/// card id; the Phase-1 audit requires the content layer to guarantee face
/// values because the engine charges exactly what it is handed):
/// - card `deltas` keys must be a subset of the §7 five inputs
///   `{ebitda, multiple, netDebt, own, cash}`;
/// - no unknown top-level card keys, sector/type/rarity spellings;
/// - all money/milli/bp values are integers (a JSON decimal is rejected);
/// - `cost` face values (cash/debt/dilution) are >= 0 magnitudes per doc 04
///   §0 sign conventions (deltas may be negative; the cost block must not).
///
/// CODEGEN SPLIT (task 2.2): `json_serializable` generates the SHAPE decode
/// (`*.g.dart`, gitignored and rebuilt by `tool/winbuild.bat` / CI); the
/// hand-written validation in this file owns the SEMANTICS (key sets,
/// spellings, signs, integer-ness) and always runs FIRST, so the generated
/// decoders only ever see pre-validated maps. `createToJson: false`
/// everywhere — content is parse-only.
library;

import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import 'model.dart';

part 'content.g.dart';

// ---------------------------------------------------------------------------
// Card enums (spellings verified against data/cards.json)
// ---------------------------------------------------------------------------

/// The six card types of doc 04 §1.
enum CardType { venture, addon, partner, financing, event, consumable }

/// Card rarity (doc 04 §1 legend).
enum Rarity { common, uncommon, rare }

CardType _cardTypeFromJson(String json, String cardId) {
  for (final t in CardType.values) {
    if (t.name == json) return t;
  }
  throw FormatException(
      'Card $cardId: unknown card type "$json" '
      '(expected one of ${CardType.values.map((t) => t.name).join('/')})');
}

Rarity _rarityFromJson(String json, String cardId) {
  for (final r in Rarity.values) {
    if (r.name == json) return r;
  }
  throw FormatException(
      'Card $cardId: unknown rarity "$json" '
      '(expected one of ${Rarity.values.map((r) => r.name).join('/')})');
}

// --- codegen converters (shape decode only; semantics validated upstream) ---

/// Nullable sector decode for [Card.sector] (null = sector-agnostic).
Sector? _sectorFromJsonNullable(String? spelling) =>
    spelling == null ? null : sectorFromJson(spelling);

/// Required sector decode for economy rows.
Sector _sectorRequiredFromJson(String spelling) => sectorFromJson(spelling);

/// Strict integer decode: rejects JSON decimals instead of truncating them
/// (the generated default `(v as num).toInt()` would silently truncate).
int _strictIntFromJson(Object? value) {
  if (value is int) return value;
  throw FormatException(
      'economy-model.json: expected an INTEGER fixed-point value, got $value');
}

/// Fraction -> basis points (0.35 -> 3500) at parse.
int _bpFromJson(Object? value) =>
    fixedPointFromJsonNum(value, 10000, 'economy-model.json (bp)');

/// Fraction -> milli (1.15 -> 1150) at parse.
int _milliFromJson(Object? value) =>
    fixedPointFromJsonNum(value, 1000, 'economy-model.json (milli)');

/// Fraction -> permille (0.30 -> 300) at parse.
int _permilleFromJson(Object? value) =>
    fixedPointFromJsonNum(value, 1000, 'economy-model.json (permille)');

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

/// The §7 five inputs — the ONLY legal `deltas` keys (CLAUDE.md; doc 04 §0).
const Set<String> kAllowedDeltaKeys = {
  'ebitda',
  'multiple',
  'netDebt',
  'own',
  'cash',
};

const Set<String> _allowedCardKeys = {
  'id',
  'name',
  'type',
  'sector',
  'rarity',
  'tierGate',
  'cost',
  'deltas',
  'lesson',
  'flavor',
  'inVerticalSlice',
};

const Set<String> _allowedCostKeys = {'cash', 'debt', 'dilution'};

int _requireInt(Object? value, String what, String cardId) {
  if (value is int) return value;
  throw FormatException(
      'Card $cardId: $what must be an INTEGER fixed-point value '
      '(cents/milli/bp), got $value');
}

String _requireString(Object? value, String what, String cardId) {
  if (value is String) return value;
  throw FormatException('Card $cardId: $what must be a string, got $value');
}

bool _requireBool(Object? value, String what, String cardId) {
  if (value is bool) return value;
  throw FormatException('Card $cardId: $what must be a boolean, got $value');
}

/// Converts a JSON number to integer fixed-point at [scale] (10000 = bp,
/// 1000 = milli/permille-of-ten, 1 = pass-through cents).
///
/// Integers scale directly. Fractions go through their shortest decimal
/// TEXT (`num.toString()` round-trips exactly), then pure integer
/// arithmetic, so no float math ever happens; a fraction that is not exactly
/// representable at [scale] is rejected loudly rather than rounded.
int fixedPointFromJsonNum(Object? value, int scale, String context) {
  if (value is int) return value * scale;
  if (value is! num) {
    throw FormatException('$context: expected a number, got $value');
  }
  final text = value.toString();
  final match = RegExp(r'^(-?)(\d+)\.(\d+)$').firstMatch(text);
  if (match == null) {
    throw FormatException(
        '$context: cannot parse "$text" as a plain decimal '
        '(exponent forms are not supported in content JSON)');
  }
  final negative = match[1] == '-';
  final digits = int.parse(match[2]! + match[3]!);
  var denominator = 1;
  for (var i = 0; i < match[3]!.length; i++) {
    denominator *= 10;
  }
  final scaled = digits * scale;
  if (scaled % denominator != 0) {
    throw FormatException(
        '$context: $text is not exactly representable at fixed-point '
        'scale x$scale');
  }
  final result = scaled ~/ denominator;
  return negative ? -result : result;
}

// ---------------------------------------------------------------------------
// Card model
// ---------------------------------------------------------------------------

/// The up-front price block in three currencies (doc 04 §0: a human-facing
/// summary; the real economic effect is always the deltas). All three are
/// NON-NEGATIVE face magnitudes — validated at parse, because a negative
/// face value would invert an action's economics downstream (Phase-1 audit).
@JsonSerializable(createToJson: false)
class CardCost {
  const CardCost({
    required this.cashCents,
    required this.debtCents,
    required this.dilutionBp,
  });

  /// Shape-only decode (generated). [Card.fromJsonValidated] has already
  /// checked key set, integer-ness, and signs before this runs.
  factory CardCost.fromJson(Map<String, dynamic> json) =>
      _$CardCostFromJson(json);

  /// Cash price in integer cents (>= 0).
  @JsonKey(name: 'cash', defaultValue: 0)
  final int cashCents;

  /// Face debt taken on in integer cents (>= 0).
  @JsonKey(name: 'debt', defaultValue: 0)
  final int debtCents;

  /// Nominal dilution surrendered in basis points (>= 0); the engine's
  /// post-money recompute is authoritative (doc 04 §4).
  @JsonKey(name: 'dilution', defaultValue: 0)
  final int dilutionBp;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CardCost &&
        other.cashCents == cashCents &&
        other.debtCents == debtCents &&
        other.dilutionBp == dilutionBp;
  }

  @override
  int get hashCode => Object.hash(cashCents, debtCents, dilutionBp);

  @override
  String toString() =>
      'CardCost(cash: $cashCents, debt: $debtCents, dilution: $dilutionBp)';
}

/// One typed, immutable card row mirroring the data/cards.json shape 1:1.
///
/// `deltas` is an unmodifiable `name -> integer fixed-point` map whose keys
/// are guaranteed (at parse) to be a subset of [kAllowedDeltaKeys]. Content
/// objects are loaded once and shared; they use identity equality.
@JsonSerializable(createToJson: false)
class Card {
  Card({
    required this.id,
    required this.name,
    required this.type,
    required this.sector,
    required this.rarity,
    required this.tierGate,
    required this.cost,
    required Map<String, int> deltas,
    required this.lesson,
    required this.flavor,
    required this.inVerticalSlice,
  }) : deltas = Map.unmodifiable(deltas);

  /// Shape-only decode (generated). Use [Card.fromJsonValidated] —
  /// it runs the semantic validation first.
  factory Card.fromJson(Map<String, dynamic> json) => _$CardFromJson(json);

  /// Stable content id (e.g. `VEN_SW_GARAGE`).
  final String id;

  /// Display name.
  final String name;

  /// Which of the six card families this is.
  final CardType type;

  /// Sector, or null for sector-agnostic cards (partners, financing, PLAYS).
  @JsonKey(fromJson: _sectorFromJsonNullable)
  final Sector? sector;

  /// Rarity tier.
  final Rarity rarity;

  /// Lowest tier at which this card can appear (1..4).
  final int tierGate;

  /// Up-front price summary (non-negative face magnitudes).
  final CardCost cost;

  /// §7 deltas over the five inputs only. Values are integer fixed-point
  /// (cents / milli / bp) and MAY be negative.
  final Map<String, int> deltas;

  /// The secret lesson (curriculum text).
  final String lesson;

  /// Flavor text.
  final String flavor;

  /// True if the card ships in the v1 vertical slice (doc 04 §3).
  final bool inVerticalSlice;

  /// Parses and VALIDATES one card object ([raw] must be a JSON map).
  /// [position] is used for the error message when `id` itself is missing.
  factory Card.fromJsonValidated(Object? raw, int position) {
    if (raw is! Map<String, Object?>) {
      throw FormatException(
          'Card at index $position: expected a JSON object, got $raw');
    }
    final id = raw['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException(
          'Card at index $position: missing/invalid "id" (got $id)');
    }

    final unknownKeys = raw.keys.toSet().difference(_allowedCardKeys);
    if (unknownKeys.isNotEmpty) {
      throw FormatException(
          'Card $id: unknown top-level key(s) ${unknownKeys.join(', ')} '
          '(allowed: ${_allowedCardKeys.join(', ')})');
    }

    // Sector: null is legal (sector-agnostic); a bad spelling is not.
    final rawSector = raw['sector'];
    if (rawSector != null) {
      final spelling = _requireString(rawSector, '"sector"', id);
      try {
        sectorFromJson(spelling);
      } on ArgumentError {
        throw FormatException(
            'Card $id: unknown sector "$spelling" '
            '(expected SOFTWARE/SERVICES/RETAIL/INDUSTRIAL or null)');
      }
    }

    // Cost block: known keys, integer, NON-NEGATIVE face magnitudes.
    final rawCost = raw['cost'];
    if (rawCost is! Map<String, Object?>) {
      throw FormatException('Card $id: missing/invalid "cost" block');
    }
    final unknownCost = rawCost.keys.toSet().difference(_allowedCostKeys);
    if (unknownCost.isNotEmpty) {
      throw FormatException(
          'Card $id: unknown cost key(s) ${unknownCost.join(', ')} '
          '(allowed: ${_allowedCostKeys.join(', ')})');
    }
    for (final key in _allowedCostKeys) {
      final value = _requireInt(rawCost[key] ?? 0, 'cost.$key', id);
      if (value < 0) {
        throw FormatException(
            'Card $id: cost.$key is $value but cost face values must be '
            '>= 0 magnitudes (doc 04 §0 sign conventions; a negative face '
            'value would invert the action\'s economics)');
      }
    }

    // Deltas: §7 subset, integer values (signs free).
    final rawDeltas = raw['deltas'];
    if (rawDeltas is! Map<String, Object?>) {
      throw FormatException('Card $id: missing/invalid "deltas" block');
    }
    final unknownDeltas =
        rawDeltas.keys.toSet().difference(kAllowedDeltaKeys);
    if (unknownDeltas.isNotEmpty) {
      throw FormatException(
          'Card $id: deltas key(s) ${unknownDeltas.join(', ')} violate the '
          '§7 invariant (allowed: ${kAllowedDeltaKeys.join(', ')}; there is '
          'no score)');
    }
    for (final entry in rawDeltas.entries) {
      _requireInt(entry.value, 'deltas.${entry.key}', id);
    }

    final tierGate = _requireInt(raw['tierGate'], '"tierGate"', id);
    if (tierGate < 1 || tierGate > 4) {
      throw FormatException(
          'Card $id: tierGate $tierGate is outside the 4-tier ladder (1..4)');
    }

    // Remaining scalar/spelling checks, then hand the now pre-validated map
    // to the generated shape decoder (codegen = shape, this factory =
    // semantics).
    _cardTypeFromJson(_requireString(raw['type'], '"type"', id), id);
    _rarityFromJson(_requireString(raw['rarity'], '"rarity"', id), id);
    _requireString(raw['name'], '"name"', id);
    _requireString(raw['lesson'], '"lesson"', id);
    _requireString(raw['flavor'], '"flavor"', id);
    _requireBool(raw['inVerticalSlice'], '"inVerticalSlice"', id);
    return Card.fromJson(raw);
  }

  @override
  String toString() => 'Card(id: $id, type: ${type.name}, deltas: $deltas)';
}

/// The loaded card database: ordered list + id lookup.
class ContentDb {
  ContentDb(List<Card> cards)
      : cards = List.unmodifiable(cards),
        verticalSlice = List.unmodifiable(cards.where((c) => c.inVerticalSlice)),
        _byId = {for (final c in cards) c.id: c};

  /// All cards, in file order. Unmodifiable.
  final List<Card> cards;

  /// The doc 04 §3 v1 vertical-slice subset (`inVerticalSlice == true`),
  /// in file order. Unmodifiable. This is the deck the Phase-3 app deals
  /// from; the full [cards] list is the post-slice content pool.
  final List<Card> verticalSlice;

  final Map<String, Card> _byId;

  /// Looks a card up by id; throws [ArgumentError] on an unknown id so a
  /// content/code drift fails loudly.
  Card byId(String id) {
    final card = _byId[id];
    if (card == null) {
      throw ArgumentError.value(id, 'id', 'Unknown card id');
    }
    return card;
  }
}

/// Parses + validates a raw cards.json STRING into a [ContentDb].
///
/// Throws [FormatException] naming the offending card id on any violation
/// (see the library doc for the full validation list).
ContentDb loadCards(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw FormatException('cards.json is not valid JSON: ${e.message}');
  }
  if (decoded is! List) {
    throw FormatException(
        'cards.json: expected a top-level array of cards, got $decoded');
  }
  final cards = <Card>[];
  final seen = <String>{};
  for (var i = 0; i < decoded.length; i++) {
    final card = Card.fromJsonValidated(decoded[i], i);
    if (!seen.add(card.id)) {
      throw FormatException('Card ${card.id}: duplicate card id');
    }
    cards.add(card);
  }
  return ContentDb(cards);
}

// ---------------------------------------------------------------------------
// Economy model
// ---------------------------------------------------------------------------

/// The `constants` block of economy-model.json, converted to integer
/// fixed-point at parse (cents / milli x1000 / bp x10000). The JSON's
/// fraction-vs-integer authoring is normalized away here, once.
@JsonSerializable(createToJson: false)
class EconomyConstants {
  const EconomyConstants({
    required this.startCashCents,
    required this.startEbitdaCents,
    required this.startSector,
    required this.startMultipleMilli,
    required this.startOwnershipBp,
    required this.startNetDebtCents,
    required this.cashYieldBp,
    required this.organicGrowthDefaultBp,
    required this.carrySeedFracBp,
    required this.reseedMultMilli,
    required this.interestMinBp,
    required this.interestMaxBp,
    required this.targetLeverageMilli,
    required this.dangerLeverageMilli,
    required this.reinvestStartBp,
    required this.reinvestEndBp,
    required this.synergySameSectorBp,
    required this.congDiscountPerAddonBp,
    required this.recapPctBp,
    required this.bridgeLoanRepayMulMilli,
  });

  /// Shape decode (generated); the `_note` keys etc. are ignored by design.
  factory EconomyConstants.fromJson(Map<String, dynamic> json) =>
      _$EconomyConstantsFromJson(json);

  /// Seed pocket cash in cents ($20,000 = 2000000).
  @JsonKey(name: 'startCash', fromJson: _strictIntFromJson)
  final int startCashCents;

  /// Seed venture EBITDA in cents ($6,000 = 600000).
  @JsonKey(name: 'startEbitda', fromJson: _strictIntFromJson)
  final int startEbitdaCents;

  /// Seed venture sector.
  @JsonKey(name: 'startSector', fromJson: _sectorRequiredFromJson)
  final Sector startSector;

  /// Seed venture multiple in milli (6x = 6000 — a low seed, NOT the
  /// SOFTWARE base 14x; see the JSON `_note`).
  @JsonKey(name: 'startMultiple', fromJson: _strictIntFromJson)
  final int startMultipleMilli;

  /// Seed ownership in bp (100% = 10000).
  @JsonKey(name: 'startOwnership', fromJson: _strictIntFromJson)
  final int startOwnershipBp;

  /// Seed net debt in cents.
  @JsonKey(name: 'startNetDebt', fromJson: _strictIntFromJson)
  final int startNetDebtCents;

  /// Per-round cash yield on EBITDA, bp (0.35 -> 3500).
  @JsonKey(name: 'cashYield', fromJson: _bpFromJson)
  final int cashYieldBp;

  /// Default organic growth, bp (0.10 -> 1000).
  @JsonKey(name: 'organicGrowthDefault', fromJson: _bpFromJson)
  final int organicGrowthDefaultBp;

  /// Momentum carried between tiers, bp (0.24 -> 2400).
  @JsonKey(name: 'carrySeedFrac', fromJson: _bpFromJson)
  final int carrySeedFracBp;

  /// Reseed multiple, milli (8000 = 8x, already milli in the JSON).
  @JsonKey(name: 'reseedMult', fromJson: _strictIntFromJson)
  final int reseedMultMilli;

  /// Interest band floor, bp (0.08 -> 800).
  @JsonKey(name: 'interestMin', fromJson: _bpFromJson)
  final int interestMinBp;

  /// Interest band ceiling, bp (0.14 -> 1400).
  @JsonKey(name: 'interestMax', fromJson: _bpFromJson)
  final int interestMaxBp;

  /// Target leverage ratio, milli (3.0 -> 3000).
  @JsonKey(name: 'targetLeverage', fromJson: _milliFromJson)
  final int targetLeverageMilli;

  /// Danger leverage ratio, milli (6.0 -> 6000).
  @JsonKey(name: 'dangerLeverage', fromJson: _milliFromJson)
  final int dangerLeverageMilli;

  /// Reinvest efficiency at tier start, bp (0.55 -> 5500).
  @JsonKey(name: 'reinvestStart', fromJson: _bpFromJson)
  final int reinvestStartBp;

  /// Reinvest efficiency at deadline, bp (0.35 -> 3500).
  @JsonKey(name: 'reinvestEnd', fromJson: _bpFromJson)
  final int reinvestEndBp;

  /// Same-sector synergy bonus, bp (0.20 -> 2000).
  @JsonKey(name: 'synergySameSector', fromJson: _bpFromJson)
  final int synergySameSectorBp;

  /// Conglomerate discount per cross-sector add-on, bp (0.08 -> 800;
  /// positive magnitude applied as multiple *= (1 - this), per the `_note`).
  @JsonKey(name: 'congDiscountPerAddon', fromJson: _bpFromJson)
  final int congDiscountPerAddonBp;

  /// Dividend-recap share of EV, bp (0.16 -> 1600 in the shipped model
  /// after the R12 tune from 0.30; the parser reads whatever the JSON sets).
  @JsonKey(name: 'recapPct', fromJson: _bpFromJson)
  final int recapPctBp;

  /// Bridge-loan repay multiplier, milli (1.15 -> 1150).
  @JsonKey(name: 'bridgeLoanRepayMul', fromJson: _milliFromJson)
  final int bridgeLoanRepayMulMilli;
}

/// One sector row: base multiple (milli) + volatility (integer permille).
@JsonSerializable(createToJson: false)
class SectorConfig {
  const SectorConfig({
    required this.sector,
    required this.baseMultipleMilli,
    required this.volatilityPermille,
  });

  /// Shape decode (generated).
  factory SectorConfig.fromJson(Map<String, dynamic> json) =>
      _$SectorConfigFromJson(json);

  /// Which sector this row configures.
  @JsonKey(name: 'name', fromJson: _sectorRequiredFromJson)
  final Sector sector;

  /// Seed/base multiple in milli (SOFTWARE 14000 = 14x). Per the JSON
  /// `_sectorsNote`: used only to seed new ventures and as sectorNorm,
  /// never as a per-round resample source.
  @JsonKey(name: 'baseMultiple', fromJson: _strictIntFromJson)
  final int baseMultipleMilli;

  /// Drift volatility as integer permille (0.30 -> 300).
  @JsonKey(name: 'volatility', fromJson: _permilleFromJson)
  final int volatilityPermille;
}

/// One tier bar: net-worth bar in cents + the deadline in rounds.
@JsonSerializable(createToJson: false)
class TierBarConfig {
  const TierBarConfig({
    required this.tier,
    required this.barCents,
    required this.deadlineRounds,
  });

  /// Shape decode (generated).
  factory TierBarConfig.fromJson(Map<String, dynamic> json) =>
      _$TierBarConfigFromJson(json);

  /// Tier number (1..4).
  @JsonKey(fromJson: _strictIntFromJson)
  final int tier;

  /// Net-worth bar in integer cents (T1 $1M = 100000000).
  @JsonKey(name: 'bar', fromJson: _strictIntFromJson)
  final int barCents;

  /// Rounds allowed to clear this tier.
  @JsonKey(fromJson: _strictIntFromJson)
  final int deadlineRounds;
}

/// The typed economy config: constants + sectors + tier bars.
///
/// economy-model.json also carries documentation blocks (`formulas`,
/// `curves`, `simCheck`, `_note` fields, ...) that are CANON as prose but
/// not runtime data; the loader intentionally reads only the three runtime
/// sections. Unknown top-level keys are therefore legal here, unlike cards.
@JsonSerializable(createToJson: false)
class EconomyConfig {
  EconomyConfig({
    required this.constants,
    required List<SectorConfig> sectors,
    required List<TierBarConfig> tierBars,
  })  : sectors = List.unmodifiable(sectors),
        tierBars = List.unmodifiable(tierBars);

  /// Shape decode (generated). Use [loadEconomy] — it validates the block
  /// structure first.
  factory EconomyConfig.fromJson(Map<String, dynamic> json) =>
      _$EconomyConfigFromJson(json);

  /// The converted `constants` block.
  final EconomyConstants constants;

  /// The four sector rows. Unmodifiable.
  final List<SectorConfig> sectors;

  /// The four tier bars, in tier order. Unmodifiable.
  final List<TierBarConfig> tierBars;
}

/// Parses + validates a raw economy-model.json STRING into an
/// [EconomyConfig]. Fractions become integer fixed-point here, once (via
/// the `@JsonKey(fromJson: ...)` converters above).
EconomyConfig loadEconomy(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw FormatException(
        'economy-model.json is not valid JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) {
    throw FormatException(
        'economy-model.json: expected a top-level object, got $decoded');
  }
  if (decoded['constants'] is! Map<String, Object?>) {
    throw FormatException(
        'economy-model.json: missing/invalid "constants" block');
  }
  if (decoded['sectors'] is! List) {
    throw FormatException(
        'economy-model.json: missing/invalid "sectors" array');
  }
  if (decoded['tierBars'] is! List) {
    throw FormatException(
        'economy-model.json: missing/invalid "tierBars" array');
  }
  return EconomyConfig.fromJson(decoded);
}
