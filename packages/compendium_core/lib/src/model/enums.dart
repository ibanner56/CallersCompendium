import 'difficulty_level.dart';

/// Dance form discriminator. Figure taxonomies are per-form, so `ecd` and
/// `square` can be populated later without schema surgery.
enum DanceForm { contra, ecd, square }

/// How the minor set progresses each time through the dance.
enum Progression { none, single, double, triple, quadruple, other }

/// Lifecycle status of a dance (mirrors The Caller's Box vocabulary).
enum DanceStatus { active, deprecated, broken, draft, variation }

/// Backward-compatible source alias for the shipped difficulty values.
///
/// New code should use [DifficultyLevel] and persist its `id`. This alias keeps
/// existing integrations source-compatible while they migrate from the former
/// enum API.
typedef DanceLevel = DifficultyLevel;

/// Lifecycle status of a program (set list).
enum ProgramStatus { draft, finalized, performed }

/// The legacy first/second projection used by calling-history statistics.
///
/// Matrix/editor consumers use numbered sections derived from every break.
/// Section 1 projects to [first], sections 2 and later project to [second];
/// break and break-less slots project to `null`.
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
