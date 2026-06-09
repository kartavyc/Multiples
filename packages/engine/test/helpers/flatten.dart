/// The shared flatten() state walker (doc 03 §5; docs/06 §2.2) — ONE
/// implementation, now living in the ENGINE (lib/serialize.dart) so the
/// save-layer cache reconciliation and the §7 invariant / golden tests share
/// the EXACT same view of state. This helper is a thin re-export so the
/// test imports (`import 'helpers/flatten.dart'`) keep working unchanged.
///
/// Do NOT fork or duplicate the walker. Adding a path there widens what the
/// invariant test can catch AND changes the golden replay serialization — a
/// golden change is STREAM-BREAKING per docs/03 §6, so any edit requires
/// versioning a new golden file + a schemaVersion bump (the v8 bump moved it
/// into lib and added venture.displayName; see lib/serialize.dart's header
/// and lib/model.dart's engineSchemaVersion history).
library;

export 'package:engine/serialize.dart' show flatten;
