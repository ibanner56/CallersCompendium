/// Dance form discriminator. Figure taxonomies are per-form, so `ecd` and
/// `square` can be populated later without schema surgery.
enum DanceForm { contra, ecd, square }

/// How the minor set progresses each time through the dance.
enum Progression { none, single, double, triple, quadruple, other }

/// Lifecycle status of a dance (mirrors The Caller's Box vocabulary).
enum DanceStatus { active, deprecated, broken, draft, variation }

/// Lifecycle status of a program (set list).
enum ProgramStatus { draft, finalized, performed }

/// Which half of a program a slot falls in, DERIVED from the first break slot
/// (see [Program.halfAtIndex]): everything before the first break is the
/// [first] half, everything after is the [second]. There is no persisted
/// half/section marker — the half is computed from the ordered slot list, so
/// this carries no migration concern. A program with no break has no derived
/// halves at all (every slot classifies as `null`).
enum ProgramHalf { first, second }

/// What a [DanceLink] points at.
enum LinkKind { source, video, relatedDance, other }

/// Value type of a user-defined custom field. Typed to keep search sane.
enum CustomFieldType { text, number, boolean, choice }

/// Where an imported dance came from.
enum ProvenanceSource {
  callersbox,
  contradb,
  callersCompanion,
  manual,
  json,
  publishedCollection,
}
