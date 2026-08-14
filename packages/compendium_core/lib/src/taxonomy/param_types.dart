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
    // Mixer partner series (issue #732, v24): a mixer's previous / successive
    // partners beyond the current one (P1 = `partners`). Named to parallel the
    // neighbour series above; `prevPartners` covers P0 (the partner before your
    // current one). P6+ and every negative P-n have no token, mirroring the
    // existing refusal of `N-1`/`N-2`.
    'prevPartners',
    'nextPartners',
    'thirdPartners',
    'fourthPartners',
    'fifthPartners',
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

  /// The five mixer partner-series tokens (taxonomy v24, issue #732): the
  /// previous and successive partners in a mixer beyond P1 (`partners`).
  ///
  /// Named as an explicit set rather than derived from a suffix/prefix
  /// pattern for three reasons:
  ///
  /// 1. Membership is a **taxonomy fact**, not a spelling coincidence. A future
  ///    token that happens to end in `Partners` would silently join the gated
  ///    group without anyone deciding it should; an explicit list forces that
  ///    decision.
  /// 2. An explicit list is auditable against the version history; a pattern
  ///    is not.
  /// 3. A naive case-insensitive match would catch `partners` (P1, which must
  ///    always be offered); the explicit constant removes that failure mode
  ///    rather than depending on every future maintainer preserving case
  ///    sensitivity. (`'partners'.endsWith('Partners')` is false in Dart —
  ///    case-sensitive — so a case-sensitive suffix would not catch it, but
  ///    reasons (1) and (2) stand independently.)
  static const List<String> mixerPartnerSeries = [
    'prevPartners',
    'nextPartners',
    'thirdPartners',
    'fourthPartners',
    'fifthPartners',
  ];

  /// All dancer tokens (pair/group + single-dancer identities). The default
  /// domain for [ParamKind.dancerSet] / [ParamKind.dancerPair].
  static const List<String> dancerSets = [...pairDancerSets, ...singleDancers];
  static const List<String> sides = ['right', 'left'];
  static const List<String> spins = ['clockwise', 'counterclockwise'];

  /// Sentinel value meaning "the source states nothing here".
  ///
  /// The rule, deliberately stated instead of enumerated: a param admits the
  /// sentinel **iff** it names it explicitly in [ParamSpec.choices] and its
  /// [ParamKind]'s validator consults `choices` — every kind with a closed
  /// vocabulary does, plus [ParamKind.rotation] by an explicit opt-in. Nothing
  /// admits it implicitly. That includes the semantically typed kinds, which is
  /// why `form_long_waves.hand` can be a [ParamKind.handedness] and still mean
  /// "not stated" (issue #739); a param does NOT have to be laundered through
  /// [ParamKind.choice] to carry it. A list of the params that opt in would
  /// only drift out of date — `sentinel_choices_test.dart` sweeps the live
  /// taxonomy and is the mechanically-enforced source of truth for which
  /// params opt in and which kinds may.
  ///
  /// It is NOT a dancer or a direction, so the renderer emits it as the empty
  /// string — which is what lets such a param sit in a `renderTemplate` without
  /// changing the canonical text of any figure that leaves it unset.
  static const String unspecified = 'unspecified';
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

  /// The "other pair" for each nameable two-couple pairing, mirroring ContraDB
  /// `dance.js` `invertPair` (`app/javascript/libfigure/dance.js` @13f38a5).
  /// ContraDB inverts only the four-dancer pairings it can name; every other
  /// dancer token (`partners`, `neighbors`, the single-dancer identities, …)
  /// has no inverse. See [invertPairDancerSet].
  static const Map<String, String> pairInverse = <String, String>{
    'role1s': 'role2s',
    'role2s': 'role1s',
    'ones': 'twos',
    'twos': 'ones',
    'firstCorners': 'secondCorners',
    'secondCorners': 'firstCorners',
  };
}

/// The "other pair" for a dancer-set token [who], or `null` when [who] has no
/// nameable inverse (ContraDB inverts only role1s↔role2s, ones↔twos,
/// firstCorners↔secondCorners; anything else — `partners`, `neighbors`, a
/// single-dancer identity, an out-of-domain value — returns `null`).
///
/// The single source of truth for pair inversion, shared by the display
/// renderer (`invertPair`), the `allemande_orbit` → `meanwhile[allemande,
/// orbit]` schema migration, and the ContraDB structured-import decomposition
/// (issue #295) so the three paths can never drift. Pure and Flutter-free.
/// Callers decide their own out-of-domain fallback (the renderer renders
/// "others"; the orbit decomposition declines to a byte-identical/custom
/// figure) — this never fabricates a pair.
String? invertPairDancerSet(String who) => ParamVocab.pairInverse[who];

/// The hand a `chain.who` value implies, mirroring ContraDB's `chainChange`
/// (`app/javascript/libfigure/figure.js` @master, `:256-263`): `role2s`
/// (ladles) take right hands, `role1s` (gentlespoons) take left hands. `null`
/// for any other `who` (`ones`/`twos`/a single-dancer identity/unset) — those
/// have no implied hand, so a caller must not populate one for them (issue
/// #976 §6.1.3: populating a hand with no role word actually read would
/// derive it from our default rather than from the source).
///
/// The single source of truth for this mapping, shared by every write/read
/// site that must agree on it: both `_selectMove` implementations and
/// `_applyNonBeatsParamChange` in `figure_list_editor.dart`, the ContraDB and
/// shared-recognizer `_chain` parsers, the one-time backfill sweep, and the
/// canonical/display silencing rule in `renderer.dart`. Kept here (not in
/// `contra_taxonomy.dart`) because the app-layer editor needs it too.
String? chainHandForWho(String who) {
  switch (who) {
    case 'role2s':
      return 'right';
    case 'role1s':
      return 'left';
    default:
      return null;
  }
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
        // `choices` is optional here too (issue #726): when a spec narrows
        // the domain — or opts into the `unspecified` sentinel — `choices` is
        // the single shared domain between this validator and the editor
        // (`FigureParamEditor`'s dropdown), so both MUST consult it rather
        // than the fixed vocabulary. A spec that omits `choices` keeps
        // exactly today's strict domain.
        return value is String && (choices ?? ParamVocab.sides).contains(value);
      case ParamKind.spinDirection:
        return value is String && (choices ?? ParamVocab.spins).contains(value);
      case ParamKind.rotation:
        // A rotation is numeric, but a spec MAY opt into the "source stated
        // nothing" sentinel by listing it in [choices] (taxonomy v22: the
        // merged `gate.turn` — ContraDB's gate states an ending facing and no
        // turn amount at all, so a numeric default there would fabricate one).
        // The opt-in is deliberate: rotation params that omit `choices` keep
        // the strict numeric domain.
        if (value is String) {
          return choices != null &&
              value == ParamVocab.unspecified &&
              choices!.contains(value);
        }
        return value is num &&
            value >= 0.25 &&
            value <= 2.5 &&
            (value * 4) % 1 == 0;
      case ParamKind.places:
        return value is int && value >= 1 && value <= 10;
      case ParamKind.fraction:
        return value is String &&
            (choices ?? ParamVocab.fractions).contains(value);
      case ParamKind.beats:
        return value is int && value >= 0 && value <= 64;
      case ParamKind.direction:
        return value is String &&
            (choices ?? ParamVocab.directions).contains(value);
      case ParamKind.choice:
        return value is String && (choices?.contains(value) ?? false);
      case ParamKind.text:
        return value is String;
      case ParamKind.flag:
        return value is bool;
    }
  }
}
