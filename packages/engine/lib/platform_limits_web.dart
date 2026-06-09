/// Integer-width limits for WEB (dart2js / dart2wasm), where Dart `int` is a
/// JavaScript number and only integers up to 2^53-1 are exact.
///
/// These mirror the native limits ([platform_limits_io.dart]) but sit safely
/// inside 2^53 so the saturation/overflow guards trip BELOW the precision
/// boundary instead of silently losing low bits. Every value reachable in a
/// winnable run (<= the $1B bar = 1e11 cents) is far under these caps, so
/// observable play is unchanged on web; only absurd ultra-deep endless
/// magnitudes (> ~$4.5B net worth) saturate sooner than they would on native.
///
/// WHY 2^52 for the satMul cap: netWorthCents divides each `satMul` product by
/// 1000 / 10000 BEFORE summing, so the summed terms are tiny; the cap only has
/// to (a) be <= 2^53 so a clamped product stays an exact int, and (b) exceed
/// every real product. The largest real product is `equity * ownershipBp`
/// (~1e15 near a $1B+ run); 2^52 (~4.5e15) clears that with headroom and still
/// leaves a 2x margin under 2^53 for any summation.
library;

/// satMul saturation magnitude on web: 2^52 cents (~$4.5e13 in dollars after
/// the /100). Above every real net-worth product, below 2^53 so it stays
/// exact.
const int kSatMulMaxCents = 1 << 52;

/// Web width sentinel: 2^53-1, the largest exact JavaScript integer. Used as
/// the endless-bar sentinel and (divided by the max growth rate) the compound
/// overflow cap.
const int kIntWidthMaxCents = 9007199254740991;
