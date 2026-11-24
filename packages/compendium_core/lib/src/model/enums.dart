import 'difficulty_level.dart';

/// Dance form discriminator. Figure taxonomies are per-form, so `ecd` and
/// `square` can be populated later without schema surgery.
enum DanceForm { contra, ecd, square }

/// What a square dance record holds (ADR-007 §8.1), `Dance.squareKind`.
/// Kept for every form, like the other square fields, so a dance whose form
/// is changed and changed back loses nothing; it means something only for a
/// square dance.
enum SquareKind {
  /// The main part: a phrased list of figures danced several times through
  /// (callers' "main figure"). The default, and what every held square is.
  main('main'),

  /// An intro, middle break or ending, stored as its own record (Q6).
  breakPart('break'),

  /// A free-form sequence or module.
  patter('patter');

  const SquareKind(this.wireName);

  /// The value storage, archives and sync carry. `break` is a Dart keyword,
  /// so [breakPart] is spelled differently from its stored value.
  final String wireName;

  /// The kind [wireName] names, or `null` for an unknown value.
  static SquareKind? fromWireName(String? name) {
    for (final kind in values) {
      if (kind.wireName == name) return kind;
    }
    return null;
  }
}

/// How a square's main part is repeated (ADR-007 §8.1), `Dance.repeatOrder`.
/// The held squares show the first three: twice with the heads leading then
/// twice with the sides (8 of 19), alternating (4), and four times through
/// with everyone active (5).
enum SquareRepeatOrder {
  /// Not given. The default.
  unstated('unstated'),

  /// Twice with the heads leading, then twice with the sides.
  headsHeadsSidesSides('HHSS'),

  /// Heads, sides, heads, sides.
  headsSidesHeadsSides('HSHS'),

  /// Four times through with everyone active.
  allFour('allFour'),

  /// Something else, described in `Dance.repeatOrderText`.
  other('other');

  const SquareRepeatOrder(this.wireName);

  /// The value storage, archives and sync carry; ADR-007 §8.1's spelling.
  final String wireName;

  /// The order [wireName] names, or `null` for an unknown value.
  static SquareRepeatOrder? fromWireName(String? name) {
    for (final order in values) {
      if (order.wireName == name) return order;
    }
    return null;
  }
}

/// Who a dancer ends each time through a square with (ADR-007 §8.1),
/// `Dance.newPartner`. 13 of the 19 held squares change partners, and the
/// source says to whom; the `mixer` flag stays the yes/no class.
enum SquareNewPartner {
  /// Not given. The default.
  unstated('unstated'),

  /// Partners do not change.
  none('none'),

  /// The corner becomes the new partner.
  corner('corner'),

  /// The robin on the lark's right becomes the new partner (stored
  /// role-neutrally, as the `rightHandRole2` selector is).
  rightHandRole2('rightHandRole2'),

  /// The opposite becomes the new partner.
  opposite('opposite'),

  /// Someone else, described in `Dance.newPartnerText`.
  other('other');

  const SquareNewPartner(this.wireName);

  /// The value storage, archives and sync carry.
  final String wireName;

  /// The value [wireName] names, or `null` for an unknown value.
  static SquareNewPartner? fromWireName(String? name) {
    for (final value in values) {
      if (value.wireName == name) return value;
    }
    return null;
  }
}

/// How the minor set progresses each time through the dance.
enum Progression { none, single, double, triple, quadruple, other }

/// Lifecycle status of a dance. `active`, `deprecated` and `broken` mirror
/// The Caller's Box vocabulary; `draft` and `variation` are app-local (#1121).
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
