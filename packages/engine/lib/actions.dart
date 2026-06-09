/// The closed `Action` union the resolver dispatches over.
///
/// Doc 03 §4.1 defines the action set as a closed union of 11 variants
/// (12 since the PartnerEngine layer added HIRE_PARTNER, which doc 02 §3.5
/// always specified and doc 03's list carried as HIRE_PARTNER too); each
/// variant here cites the doc 02 §3 action it implements. Payloads carry RAW
/// engine inputs only — ids, integer cents, milli-unit multiples, basis
/// points — never card objects. The content layer maps a played card's face
/// values onto one of these actions later (doc 03 §4.2/§5), keeping the
/// engine pure and card-schema-agnostic.
///
/// LOCKED fixed-point conventions (mirrored from model.dart):
/// - Money is integer **cents**. No `double` anywhere in this package.
/// - `...MultipleMilli` = multiple x1000 (14x is `14000`).
/// - Basis-point fields are x10000 (30% is `3000`).
///
/// All variants are immutable value types with manual `==`/`hashCode`
/// (dependency-free, matching the rest of the package).
///
/// Pure and dependency-free except for the model types (only `dart:core`).
library;

import 'model.dart';

/// Base of the closed action union (doc 03 §4.1). `sealed` so the resolver's
/// dispatch switch is compiler-checked exhaustive — adding a variant without
/// a resolver branch is a compile error, not a runtime surprise.
sealed class Action {
  const Action();
}

/// Begin a new company; consumes a SLOT (doc 02 §3.1 START_VENTURE).
///
/// The face values arrive already mapped from the card by the content layer;
/// the resolver creates the venture at 100% ownership with [faceDebtCents]
/// as its opening net debt and charges [priceCents] from cash.
class StartVenture extends Action {
  const StartVenture({
    required this.ventureId,
    required this.sector,
    required this.ebitdaCents,
    required this.multipleMilli,
    required this.priceCents,
    required this.faceDebtCents,
  });

  /// Id the new venture will carry (seeded upstream; the engine doesn't mint ids).
  final String ventureId;

  /// The new venture's home sector.
  final Sector sector;

  /// Opening EBITDA in cents (the card's face EBITDA).
  final int ebitdaCents;

  /// Opening multiple in milli-units (face multiple, already in SECTOR_BAND
  /// by content guarantee — never clamped here, doc 02 §1).
  final int multipleMilli;

  /// Purchase price in cents (non-negative magnitude; a COST per the doc 02
  /// §1 facePrice sign convention).
  final int priceCents;

  /// Debt the venture opens with, in cents (becomes its netDebt).
  final int faceDebtCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StartVenture &&
        other.ventureId == ventureId &&
        other.sector == sector &&
        other.ebitdaCents == ebitdaCents &&
        other.multipleMilli == multipleMilli &&
        other.priceCents == priceCents &&
        other.faceDebtCents == faceDebtCents;
  }

  @override
  int get hashCode => Object.hash(ventureId, sector, ebitdaCents,
      multipleMilli, priceCents, faceDebtCents);

  @override
  String toString() => 'StartVenture(ventureId: $ventureId, sector: $sector, '
      'ebitda: $ebitdaCents, multiple: $multipleMilli, '
      'price: $priceCents, faceDebt: $faceDebtCents)';
}

/// Equity raise: grow the pie, cut your slice (doc 02 §3.2 RAISE; F5).
class RaiseEquity extends Action {
  const RaiseEquity({
    required this.ventureId,
    required this.raiseCents,
    this.ebitdaDeltaCents = 0,
    this.multipleDeltaMilli = 0,
  });

  /// The venture being raised into.
  final String ventureId;

  /// New money in cents (the "m" in F5 dilution; cash inflow per the doc 02
  /// §1 facePrice sign convention for a RAISE).
  final int raiseCents;

  /// GROWTH RIDER (doc 02 §3.2 POST "apply card defaults"; doc 04 §1 raise
  /// faces — FIN_SEED_RAISE +200k): EBITDA the raise buys, in cents,
  /// landing AFTER the dilution is computed on the as-is equity. 0 = none.
  final int ebitdaDeltaCents;

  /// Multiple rider in milli-units (FIN_SEED_RAISE +1000 = +1x of story),
  /// same post-dilution timing; floored downstream at 1000 milli. 0 = none.
  final int multipleDeltaMilli;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RaiseEquity &&
        other.ventureId == ventureId &&
        other.raiseCents == raiseCents &&
        other.ebitdaDeltaCents == ebitdaDeltaCents &&
        other.multipleDeltaMilli == multipleDeltaMilli;
  }

  @override
  int get hashCode =>
      Object.hash(ventureId, raiseCents, ebitdaDeltaCents, multipleDeltaMilli);

  @override
  String toString() => 'RaiseEquity(ventureId: $ventureId, '
      'raise: $raiseCents, ebitdaDelta: $ebitdaDeltaCents, '
      'multipleDelta: $multipleDeltaMilli)';
}

/// Leverage: cash now, a recurring interest bill forever (doc 02 §3.3 TAKE_DEBT).
class TakeDebt extends Action {
  const TakeDebt({
    required this.ventureId,
    required this.proceedsCents,
    required this.faceDebtCents,
  });

  /// The venture taking on the debt.
  final String ventureId;

  /// Cash proceeds in cents (facePrice is PROCEEDS for TAKE_DEBT, doc 02 §1).
  final int proceedsCents;

  /// Face debt added to the venture's netDebt, in cents.
  final int faceDebtCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TakeDebt &&
        other.ventureId == ventureId &&
        other.proceedsCents == proceedsCents &&
        other.faceDebtCents == faceDebtCents;
  }

  @override
  int get hashCode => Object.hash(ventureId, proceedsCents, faceDebtCents);

  @override
  String toString() => 'TakeDebt(ventureId: $ventureId, '
      'proceeds: $proceedsCents, faceDebt: $faceDebtCents)';
}

/// The signature merge — multiple arbitrage (doc 02 §3.4 BUY_ADDON; doc 03
/// §4.2: resolver-COMPUTED from live platform state, never card deltas).
///
/// Carries the add-on target's raw inputs; the resolver computes price
/// (economy-model.json `addonPrice`), synergy/drag, and the render-only
/// accretion flash at commit time.
class AcquireAddOn extends Action {
  const AcquireAddOn({
    required this.targetVentureId,
    required this.addonSector,
    required this.addonEbitdaCents,
    required this.addonBuyMultipleMilli,
    required this.addonFaceDebtCents,
  });

  /// The platform venture absorbing the add-on.
  final String targetVentureId;

  /// The add-on's home sector (same- vs cross-sector decides synergy vs drag).
  final Sector addonSector;

  /// The add-on's EBITDA in cents.
  final int addonEbitdaCents;

  /// The buy multiple in milli-units (the LOW face multiple, `m_buy`).
  final int addonBuyMultipleMilli;

  /// Face debt folded into the platform's netDebt, in cents.
  final int addonFaceDebtCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AcquireAddOn &&
        other.targetVentureId == targetVentureId &&
        other.addonSector == addonSector &&
        other.addonEbitdaCents == addonEbitdaCents &&
        other.addonBuyMultipleMilli == addonBuyMultipleMilli &&
        other.addonFaceDebtCents == addonFaceDebtCents;
  }

  @override
  int get hashCode => Object.hash(targetVentureId, addonSector,
      addonEbitdaCents, addonBuyMultipleMilli, addonFaceDebtCents);

  @override
  String toString() => 'AcquireAddOn(target: $targetVentureId, '
      'sector: $addonSector, ebitda: $addonEbitdaCents, '
      'buyMultiple: $addonBuyMultipleMilli, faceDebt: $addonFaceDebtCents)';
}

/// Dividend recap: pull cash out against the venture's EV, gated T2+
/// (doc 02 §3.6 DIVIDEND_RECAP; economy-model.json `dividendRecap`).
class DividendRecap extends Action {
  const DividendRecap({required this.ventureId, required this.recapPctBp});

  /// The venture being recapped.
  final String ventureId;

  /// Recap percentage of EV in basis points (16% = `1600`,
  /// economy-model.json constants.recapPct = 0.16 after the R12 tune from
  /// 0.30).
  final int recapPctBp;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DividendRecap &&
        other.ventureId == ventureId &&
        other.recapPctBp == recapPctBp;
  }

  @override
  int get hashCode => Object.hash(ventureId, recapPctBp);

  @override
  String toString() =>
      'DividendRecap(ventureId: $ventureId, recapPctBp: $recapPctBp)';
}

/// Acquisition / IPO — convert paper to real, frees a SLOT (doc 02 §3.7 EXIT).
class ExitVenture extends Action {
  const ExitVenture({
    required this.ventureId,
    required this.offerMultipleMilli,
    required this.liveMarketMultipleMilli,
  });

  /// The venture being sold.
  final String ventureId;

  /// The offer multiple in milli-units; the resolver picks the final exit
  /// multiple (`min(offer, sectorLiveMultiple)` / hot-window override,
  /// economy-model.json `exitMultiple`).
  final int offerMultipleMilli;

  /// The LIVE multiple in milli-units — the `live` side of
  /// `min(offer, live)` (economy-model.json formulas.exitMultiple) and the
  /// base of the hot-window override (live x135/100, apply.dart).
  ///
  /// Payload carrier BY DESIGN (the round-4 "TEMPORARY" note resolved in
  /// round 10): the engine's live mark for a venture IS its drifted
  /// `multipleMilli` (doc 01 §7.3 — per-venture, not stored per sector),
  /// and dealflow.exitOfferAction fills this field with exactly that when
  /// mapping the round's EXIT OFFER ticket. Hand-built actions (tests,
  /// future bespoke offers) keep the freedom to pass any live mark.
  final int liveMarketMultipleMilli;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExitVenture &&
        other.ventureId == ventureId &&
        other.offerMultipleMilli == offerMultipleMilli &&
        other.liveMarketMultipleMilli == liveMarketMultipleMilli;
  }

  @override
  int get hashCode =>
      Object.hash(ventureId, offerMultipleMilli, liveMarketMultipleMilli);

  @override
  String toString() => 'ExitVenture(ventureId: $ventureId, '
      'offerMultiple: $offerMultipleMilli, '
      'liveMarketMultiple: $liveMarketMultipleMilli)';
}

/// Delegation: convert a venture to passive at an agency cost
/// (doc 02 §3.10 HIRE_CEO).
class HireCEO extends Action {
  const HireCEO({required this.ventureId, required this.costCents});

  /// The venture going passive.
  final String ventureId;

  /// The CEO's hire cost in cents.
  final int costCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HireCEO &&
        other.ventureId == ventureId &&
        other.costCents == costCents;
  }

  @override
  int get hashCode => Object.hash(ventureId, costCents);

  @override
  String toString() => 'HireCEO(ventureId: $ventureId, cost: $costCents)';
}

/// Sell a held PLAY for ~50% of its purchase price — the liquidity lesson
/// (doc 02 §3.6 sell-a-play; doc 03 §4.1 SellPlay).
class SellPlay extends Action {
  const SellPlay({required this.playId, required this.purchasePriceCents});

  /// The held consumable being sold.
  final String playId;

  /// Its original purchase price in cents; proceeds are
  /// `trunc(price / 2)` per doc 02 §3.6.
  final int purchasePriceCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SellPlay &&
        other.playId == playId &&
        other.purchasePriceCents == purchasePriceCents;
  }

  @override
  int get hashCode => Object.hash(playId, purchasePriceCents);

  @override
  String toString() =>
      'SellPlay(playId: $playId, purchasePrice: $purchasePriceCents)';
}

/// Banker fee — redraw the current hand/offers (doc 02 §3.8 REROLL).
///
/// Carries [costCents] because the scaling fee `rerollCost(rerollsUsed)`
/// (doc 02 §4) is a content/SHOP-layer formula: the layer above computes the
/// cost and the engine charges exactly what it is handed. The redraw itself
/// (re-running draw-order steps 1-3, doc 03 §3.1) is deferred with the
/// deal-flow layer — see the resolver branch for the loud note.
class Reroll extends Action {
  const Reroll({required this.costCents});

  /// The banker fee in cents, computed upstream from `rerollsUsed`.
  final int costCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Reroll && other.costCents == costCents;
  }

  @override
  int get hashCode => Object.hash(Reroll, costCents);

  @override
  String toString() => 'Reroll(cost: $costCents)';
}

/// Play a held consumable (doc 02 §3.6 PLAY_CONSUMABLE).
///
/// The effect arrives as a raw `deltas` map over the five §7 inputs (keys
/// must be a subset of `kMutableInputs` in resolver.dart: `ebitda`,
/// `multiple`, `netDebt`, `own`, `cash`) — the doc 03 §5 `Deltas` shape,
/// already mapped from the card by the content layer. Context-free plays
/// pass a null [targetVentureId].
class PlayConsumable extends Action {
  /// The [deltas] map is copied into an unmodifiable map so the payload is
  /// deeply immutable.
  PlayConsumable({
    required this.playId,
    required Map<String, int> deltas,
    this.targetVentureId,
    this.armsHotWindow = false,
    this.readsMarket = false,
    this.recapBp = 0,
    this.secondaryBp = 0,
    this.spinsOff = false,
    this.earnOutPctBp = 0,
    this.earnOutRounds = 0,
  }) : deltas = Map.unmodifiable(deltas);

  /// The held consumable being played.
  final String playId;

  /// Deltas over the five mutable inputs (cents / milli / bp, additive).
  final Map<String, int> deltas;

  /// Target venture for targeted plays; null for context-free ones.
  final String? targetVentureId;

  /// True = arm `market.hotWindowArmed` (doc 02 §3.6 HOT_WINDOW: the next
  /// EXIT uses the hot multiple; one-window lifetime). Mapped by
  /// actionForCard from PLY_HOT_WINDOW.
  final bool armsHotWindow;

  /// True = set `market.marketReadHint` (doc 02 §3.6 MARKET_READ:
  /// next-round direction only; one-round lifetime). Mapped by
  /// actionForCard from PLY_MARKET_READ.
  final bool readsMarket;

  /// Dividend-recap fraction in basis points; 0 = not a recap. When > 0
  /// the resolver computes the CANONICAL doc 01 §7.7 pull AT RESOLVE TIME
  /// against the target venture's live EV — `amount = trunc(EV x
  /// recapBp / 10000)`, then `cash += amount; netDebt += amount` (economy
  /// formulas.dividendRecap; constants.recapPct = 0.16 -> 1600 after the
  /// R12 tune from 0.30). Mapped by
  /// actionForCard from PLY_DIVIDEND_RECAP, which STRIPS the card's
  /// illustrative fixed faces (the R12 canon reconciliation: the engine
  /// used to charge the $30k face, which neither scales nor matches the
  /// doc's formula — the "primary greed-death dial" was inert).
  final int recapBp;

  /// SECONDARY-SALE ownership magnitude in basis points; 0 = not a secondary
  /// sale (schemaVersion 9; audit L3). When > 0 the resolver sells this many
  /// bp of the target venture's stake AT THE LIVE MARK (doc 02 §3.6
  /// SECONDARY_SALE): `proceeds = trunc(ventureEquity(target) x secondaryBp /
  /// 10000)`, then `cash += proceeds; target.ownership -= secondaryBp`. The
  /// `target.ownership` reduction is carried HERE (not as an `own` delta) so
  /// the proceeds compute against the PRE-sale equity, exactly like recapBp
  /// carries the recap. Mapped by actionForCard from PLY_SECONDARY_SALE,
  /// which STRIPS the card's illustrative `cash: 0`/`own: -Δbp` faces (the
  /// $0 proceeds placeholder the audit flagged) and routes the magnitude
  /// here. Converts paper -> real and tallies to reputation as a secondary.
  final int secondaryBp;

  /// SPIN-OFF flag (schemaVersion 10; doc 02 §3.6 SPIN_OFF — whole-venture
  /// form). When true the resolver SPLITS the target venture back out at its
  /// CURRENT (drifted) live multiple — no offer haircut, no hot window —
  /// banking the equity stake and FREEING THE SLOT (a structural partial
  /// exit that LOCKS the value at the live mark). `proceeds =
  /// trunc((EV_at_live - netDebt) x own / 10000)`; `cash += proceeds`; the
  /// venture is removed. The card's 300k fee rides through deltas.cash as
  /// usual. Mapped by actionForCard from PLY_SPIN_OFF.
  ///
  /// DESIGN NOTE (doc reconciliation, documented): doc 02 §3.6 SPIN_OFF's
  /// PREFERRED form re-marks a single ADD-ON from a per-add-on ledger; the
  /// v1 engine merges add-ons DESTRUCTIVELY into the platform (no ledger),
  /// so the doc's own ALTERNATIVE — "if a whole venture: cash +=
  /// ventureNetWorth(v); remove from ventures[]" — is the faithful,
  /// implementable realization. It still teaches the lesson ("split a unit
  /// back out, lock the value, free a slot"); the per-add-on ledger is a
  /// future content layer (R21+).
  final bool spinsOff;

  /// EARN_OUT scheduled-drag PCT in basis points (schemaVersion 10; doc 02
  /// §3.6 EARN_OUT). 0 = not an earn-out. When > 0 the resolver pushes a
  /// non-recurring [ScheduledCost] of PCT_EBITDA basis on the target,
  /// charging `-trunc(target.ebitda x earnOutPctBp / 10000)` each OPERATE
  /// for [earnOutRounds] rounds (the seller is paid out of future earnings).
  /// The card's `ebitda` delta (the acquired earnings) lands NOW via the
  /// normal deltas path; no cash/debt/dilution upfront. Mapped by
  /// actionForCard from PLY_EARN_OUT.
  final int earnOutPctBp;

  /// EARN_OUT countdown length in rounds (the number of scheduled drags);
  /// 0 = not an earn-out. Paired with [earnOutPctBp].
  final int earnOutRounds;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayConsumable &&
        other.playId == playId &&
        other.targetVentureId == targetVentureId &&
        other.armsHotWindow == armsHotWindow &&
        other.readsMarket == readsMarket &&
        other.recapBp == recapBp &&
        other.secondaryBp == secondaryBp &&
        other.spinsOff == spinsOff &&
        other.earnOutPctBp == earnOutPctBp &&
        other.earnOutRounds == earnOutRounds &&
        _mapEquals(other.deltas, deltas);
  }

  @override
  int get hashCode => Object.hash(
        playId,
        targetVentureId,
        armsHotWindow,
        readsMarket,
        recapBp,
        secondaryBp,
        spinsOff,
        earnOutPctBp,
        earnOutRounds,
        Object.hashAllUnordered(
            deltas.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() => 'PlayConsumable(playId: $playId, '
      'deltas: $deltas, target: $targetVentureId, '
      'armsHotWindow: $armsHotWindow, readsMarket: $readsMarket, '
      'recapBp: $recapBp, secondaryBp: $secondaryBp, spinsOff: $spinsOff, '
      'earnOutPctBp: $earnOutPctBp, earnOutRounds: $earnOutRounds)';
}

/// The always-available baseline: brute-force EBITDA growth at decaying
/// efficiency (doc 02 §3.9 REINVEST; no hand unwinnable, §Q3).
class ReinvestBaseline extends Action {
  const ReinvestBaseline({required this.ventureId, required this.amountCents});

  /// The venture receiving the reinvestment.
  final String ventureId;

  /// Cash spent in cents; EBITDA gained is `mulBp(amount, efficiencyBp)`,
  /// resolved against the live decay curve (economy-model.json `reinvestEff`).
  final int amountCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReinvestBaseline &&
        other.ventureId == ventureId &&
        other.amountCents == amountCents;
  }

  @override
  int get hashCode => Object.hash(ventureId, amountCents);

  @override
  String toString() =>
      'ReinvestBaseline(ventureId: $ventureId, amount: $amountCents)';
}

/// Hire an operating partner onto a venture — the permanent-engine layer
/// (doc 02 §3.5 HIRE_PARTNER; the 12th union variant, landed with the
/// PartnerEngine layer at schemaVersion 5).
///
/// Payload notes:
/// - [perRoundEbitdaCents] is the engine's per-round +EBITDA (the card's
///   `ebitda` delta) — it accrues each OPERATE, never at hire time.
/// - [multipleDeltaMilli] is a ONE-TIME story bump applied at hire (the
///   PRT_GROWTH_HACKER face; 0 for most partners), floored downstream at
///   the 1000-milli live-venture floor.
/// - [fixedCostCents] > 0 registers a recurring [ScheduledCost] of
///   `-fixedCostCents` tied to the venture (doc 02 §3.5 PARTNER_FIXED_COST
///   — the operating-leverage knife). The v1 card SCHEMA carries no
///   fixed-cost face, so actionForCard maps 0 today; the channel is live
///   for when content lands it (PRT_COO_FIXED is out of the v1 slice).
class HirePartner extends Action {
  const HirePartner({
    required this.ventureId,
    required this.defId,
    required this.costCents,
    required this.perRoundEbitdaCents,
    this.multipleDeltaMilli = 0,
    this.fixedCostCents = 0,
  });

  /// The venture hiring the partner.
  final String ventureId;

  /// Content-DB archetype id stored on the attached engine.
  final String defId;

  /// Hire price in cents (facePrice is a COST for type `partner`,
  /// doc 02 §1 sign convention).
  final int costCents;

  /// Per-round +EBITDA the attached engine lands each OPERATE, in cents.
  final int perRoundEbitdaCents;

  /// One-time multiple delta at hire, in milli-units (usually 0).
  final int multipleDeltaMilli;

  /// Recurring per-OPERATE fixed cost in cents (0 = none).
  final int fixedCostCents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HirePartner &&
        other.ventureId == ventureId &&
        other.defId == defId &&
        other.costCents == costCents &&
        other.perRoundEbitdaCents == perRoundEbitdaCents &&
        other.multipleDeltaMilli == multipleDeltaMilli &&
        other.fixedCostCents == fixedCostCents;
  }

  @override
  int get hashCode => Object.hash(ventureId, defId, costCents,
      perRoundEbitdaCents, multipleDeltaMilli, fixedCostCents);

  @override
  String toString() => 'HirePartner(ventureId: $ventureId, defId: $defId, '
      'cost: $costCents, perRoundEbitda: $perRoundEbitdaCents, '
      'multipleDelta: $multipleDeltaMilli, fixedCost: $fixedCostCents)';
}

/// Key-and-value map equality (the package avoids a `collection` dependency,
/// so this small helper stands in for `mapEquals`).
bool _mapEquals(Map<String, int> a, Map<String, int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value || !b.containsKey(entry.key)) return false;
  }
  return true;
}
