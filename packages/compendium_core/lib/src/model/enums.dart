/// Dance form discriminator. Figure taxonomies are per-form, so `ecd` and
/// `square` can be populated later without schema surgery.
enum DanceForm { contra, ecd, square }

/// How the minor set progresses each time through the dance.
enum Progression { none, single, double, triple, quadruple, other }

/// Lifecycle status of a dance (mirrors The Caller's Box vocabulary).
enum DanceStatus { active, deprecated, broken }

/// Lifecycle status of a program (set list).
enum ProgramStatus { draft, finalized, performed }

/// What a [DanceLink] points at.
enum LinkKind { source, video, relatedDance, other }

/// Value type of a user-defined custom field. Typed to keep search sane.
enum CustomFieldType { text, number, boolean, choice }

/// Where an imported dance came from.
enum ProvenanceSource { callersbox, contradb, callersCompanion, manual, json }
