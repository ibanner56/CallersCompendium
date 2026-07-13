import 'package:meta/meta.dart';

/// Kinds of figure parameters (design/figure-taxonomy.md §Parameter types).
///
/// Each kind implies a value domain checked by [ParamSpec.validate].
enum ParamKind {
  /// A set of dancers (`everyone`, `role1s`, `partners`, `shadows`, …).
  dancerSet,

  /// A pairing of dancers valid for a paired move (subset of dancerSet).
  dancerPair,

  /// `right` / `left` hand.
  handedness,

  /// `right` / `left` shoulder.
  shoulder,

  /// `clockwise` / `counterclockwise`.
  spinDirection,

  /// Amount of turn in full turns, quarter-turn steps: 0.25 … 2.5.
  rotation,

  /// Distance travelled around a ring/star, 1–10 "places" (circle, star,
  /// facing star, square through). Stored as places directly (not ContraDB's
  /// degrees), analogous to [rotation] being stored in turns.
  places,

  /// `quarter` / `half` / `threeQuarter` / `full` / `other` (heys, poussettes).
  fraction,

  /// Duration 0–64 beats (0 allowed: formation labels).
  beats,

  /// Spatial direction (`along`, `across`, diagonals, in/out, up/down).
  direction,

  /// Move-specific enum (grips, enders, prefixes, …) — domain in [ParamSpec.choices].
  choice,

  /// Free text; dialect-aware.
  text,

  /// Boolean flag (e.g. `withBalance`).
  flag,
}

/// Canonical value vocabularies for the closed parameter kinds.
abstract final class ParamVocab {
  /// Pair/group-level dancer sets — everything except the single-dancer
  /// identities. These are the values valid wherever a param names a *pair* or
  /// group (e.g. hey's `pass2`, most `who`/`whom` params).
  static const List<String> pairDancerSets = [
    'everyone',
    'role1s',
    'role2s',
    'ones',
    'twos',
    'firstCorners',
    'secondCorners',
    'partners',
    'neighbors',
    'sameRoles',
    'shadows',
    'secondShadows',
    'prevNeighbors',
    'nextNeighbors',
    'thirdNeighbors',
    'fourthNeighbors',
    // Roadmap 2.4a (PR3): the center dancers as a group (Rory O'More's
    // chooser_pairc_or_everyone).
    'centers',
  ];

  /// Single-dancer identities — one couple (1s/2s) × one role — for moves that
  /// name an individual (figure_8's `lead`, dolphin_hey's `whom`). Equivalent
  /// to ContraDB's chooser_dancer "first/second gentlespoon/ladle" (2.4a PR3).
  static const List<String> singleDancers = [
    'onesRole1',
    'onesRole2',
    'twosRole1',
    'twosRole2',
  ];

  /// All dancer tokens (pair/group + single-dancer identities). The default
  /// domain for [ParamKind.dancerSet] / [ParamKind.dancerPair].
  static const List<String> dancerSets = [...pairDancerSets, ...singleDancers];
  static const List<String> sides = ['right', 'left'];
  static const List<String> spins = ['clockwise', 'counterclockwise'];
  static const List<String> fractions = [
    'quarter',
    'half',
    'threeQuarter',
    'full',
    'other',
  ];
  static const List<String> directions = [
    'along',
    'across',
    'rightDiagonal',
    'leftDiagonal',
    'in',
    'out',
    'up',
    'down',
  ];
}

/// Specification of one named move parameter: kind, default, and (for
/// [ParamKind.choice], or to narrow dancer kinds) an explicit value domain.
@immutable
class ParamSpec {
  const ParamSpec(this.kind, {required this.defaultValue, this.choices});

  final ParamKind kind;

  /// Value assumed when the figure omits this parameter.
  final Object? defaultValue;

  /// Explicit allowed values. Required for [ParamKind.choice]; optional for
  /// dancer kinds (narrows the shared vocabulary to what the move accepts).
  final List<String>? choices;

  /// Whether [value] belongs to this parameter's domain.
  bool validate(Object? value) {
    switch (kind) {
      case ParamKind.dancerSet:
      case ParamKind.dancerPair:
        return value is String &&
            (choices ?? ParamVocab.dancerSets).contains(value);
      case ParamKind.handedness:
      case ParamKind.shoulder:
        return value is String && ParamVocab.sides.contains(value);
      case ParamKind.spinDirection:
        return value is String && ParamVocab.spins.contains(value);
      case ParamKind.rotation:
        return value is num &&
            value >= 0.25 &&
            value <= 2.5 &&
            (value * 4) % 1 == 0;
      case ParamKind.places:
        return value is int && value >= 1 && value <= 10;
      case ParamKind.fraction:
        return value is String && ParamVocab.fractions.contains(value);
      case ParamKind.beats:
        return value is int && value >= 0 && value <= 64;
      case ParamKind.direction:
        return value is String && ParamVocab.directions.contains(value);
      case ParamKind.choice:
        return value is String && (choices?.contains(value) ?? false);
      case ParamKind.text:
        return value is String;
      case ParamKind.flag:
        return value is bool;
    }
  }
}
