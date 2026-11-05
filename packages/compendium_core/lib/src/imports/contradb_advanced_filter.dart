import 'package:meta/meta.dart';

import '../search/filter.dart';
import 'contradb_advanced_params.dart';

/// Why an Advanced [DanceFilter] cannot be sent to ContraDB.
///
/// Each reason is a condition ContraDB's filter language cannot express with
/// the **same meaning** the Collection gives it. They are refused rather than
/// approximated, because an approximation would return a different result set
/// from the one the Advanced panel describes.
enum ContraDbAdvancedUnsupported {
  /// A "has tag" condition. Tags are the user's own local labels; ContraDB's
  /// `my-tag` operator reads the tags of a signed-in ContraDB account, which
  /// this app never has.
  tag,

  /// A figure condition with a phrase section (`B1`, ...). ContraDB's filter
  /// language has no section: it is not stored as part of a figure.
  ///
  /// Parameters never refuse a figure: ContraDB takes them by position, each
  /// one the app and ContraDB share is translated, and the rest are left out
  /// and reported in [ContraDbAdvancedExpression.ignoredParams].
  figureDetail,

  /// A move that has no exact ContraDB counterpart: one ContraDB does not
  /// define (its `figure` operator raises, a server error, for an undefined
  /// move on any dance that has figures), or one whose ContraDB meaning
  /// differs from the Collection's (see [translateDanceFilterToContraDb]).
  figureName,

  /// Any other local-only condition (formation, level, status, rating, called
  /// history, custom fields, and so on).
  other,
}

/// The outcome of [translateDanceFilterToContraDb]: either a ContraDB filter
/// expression or the first reason it could not be built.
@immutable
sealed class ContraDbAdvancedTranslation {
  const ContraDbAdvancedTranslation();
}

/// A ContraDB filter [expression] (the JSON array its `filter` parameter takes).
@immutable
class ContraDbAdvancedExpression extends ContraDbAdvancedTranslation {
  const ContraDbAdvancedExpression(
    this.expression, {
    this.ignoredParams = const <String>{},
  });

  final List<Object?> expression;

  /// `move.param` for each figure parameter the query set that ContraDB has no
  /// exact counterpart for and that was therefore left out of [expression]
  /// (for example `swing.endFacing`). The figure is still searched by its other
  /// parameters, so the search can differ from the Advanced panel (usually
  /// broader, narrower under a negation).
  final Set<String> ignoredParams;
}

/// The filter has a condition ContraDB cannot express; see [reason].
@immutable
class ContraDbAdvancedRefused extends ContraDbAdvancedTranslation {
  const ContraDbAdvancedRefused(this.reason);

  final ContraDbAdvancedUnsupported reason;
}

/// Translates the Advanced builder's [filter] into ContraDB's filter language
/// (`lib/filter_dances.rb` in the ContraDB source), or reports why it cannot.
///
/// Supported: boolean groups of figure conditions.
///
/// | App | ContraDB |
/// | --- | --- |
/// | [AndFilter] | `["and", …]` (the dance matches every operand) |
/// | [OrFilter] | `["or", …]` |
/// | [NotFilter] | `["no", …]` (the dance does not match the operand) |
/// | [FigureFilter] over a [FigureLeaf] | `["figure", <move>]` |
/// | [FigureAnd] (same figure) | `["&", …]` (figurewise and) |
/// | [FigureOr] | `["or", …]` |
/// | [FigureNot] under [FigureFilter] | `["no", …]` ("no figure matches") |
/// | [FigureNot] under [FigureAnd]/[FigureOr] | `["not", …]` (figurewise not) |
/// | [ThenFilter] | `["then", …]` (the second immediately follows the first) |
///
/// An empty [AndFilter]/[OrFilter] is refused as [ContraDbAdvancedUnsupported.other]:
/// the builder never produces one (`BuilderGroup.toFilter` returns null for an
/// empty group) and ContraDB's empty `and`/`or` do not mean "everything"/"nothing".
///
/// A [FigureLeaf.move] is the Collection's **move id** (what the builder
/// stores, e.g. `do_si_do`), which is not a ContraDB name; it is resolved by
/// `_contraDbForCollectionMove`. A display name, a ContraDB spelling or a
/// dialect's term is refused as [ContraDbAdvancedUnsupported.figureName]: the
/// Collection resolves those through the active dialect, which this function
/// never sees, so it cannot know they mean what ContraDB's identically spelt
/// move means.
ContraDbAdvancedTranslation translateDanceFilterToContraDb(DanceFilter filter) {
  final walk = _Walk();
  final result = walk.dance(filter);
  return switch (result) {
    final List<Object?> expression => ContraDbAdvancedExpression(
      expression,
      ignoredParams: walk.ignored,
    ),
    final ContraDbAdvancedUnsupported reason => ContraDbAdvancedRefused(reason),
    _ => throw StateError('unreachable'),
  };
}

/// One translation of a filter tree. Each method returns either a
/// `List<Object?>` expression or a [ContraDbAdvancedUnsupported].
class _Walk {
  /// The parameters left out of the figures translated so far.
  final Set<String> ignored = {};

  Object dance(DanceFilter filter) {
    switch (filter) {
      case AndFilter(:final children):
        return _combine('and', children, dance);
      case OrFilter(:final children):
        return _combine('or', children, dance);
      case NotFilter(:final child):
        final inner = dance(child);
        return inner is List<Object?> ? <Object?>['no', inner] : inner;
      case FigureFilter(:final query):
        // `FigureFilter(FigureNot(q))` means "no figure matches q" locally.
        if (query case FigureNot(:final child)) {
          final inner = figure(child);
          return inner is List<Object?> ? <Object?>['no', inner] : inner;
        }
        return figure(query);
      case TagFilter() || UntaggedFilter():
        return ContraDbAdvancedUnsupported.tag;
      case ThenFilter(:final before, :final after):
        // Both sides mean "immediately follows, wrapping from the last figure
        // to the first", as ContraDB's `then` does (`SearchMatch#abuts?`). The
        // operands are row-level, so a figure not under them is figurewise
        // `not`, never the dance-level `no`.
        return _combine('then', [before, after], figure);
      case FullTextFilter() ||
          AuthorFilter() ||
          SourceFilter() ||
          SourceIdFilter() ||
          TunesFilter() ||
          FormFilter() ||
          FormationFilter() ||
          ProgressionFilter() ||
          StatusFilter() ||
          LevelFilter() ||
          MixedLevelFilter() ||
          MixerFilter() ||
          CalledFilter() ||
          RatingFilter() ||
          CustomFieldFilter():
        return ContraDbAdvancedUnsupported.other;
    }
  }

  Object figure(FigureQuery query) {
    switch (query) {
      case FigureLeaf(:final move, :final params, :final section):
        if (section != null) return ContraDbAdvancedUnsupported.figureDetail;
        final fragment = _contraDbForCollectionMove[move];
        if (fragment == null) return ContraDbAdvancedUnsupported.figureName;
        if (params.isEmpty) return _copy(fragment);
        // Parameters are translated where ContraDB has them; the rest are
        // left out, never a reason to refuse the figure.
        final withParams = translateContraDbFigureParams(move, params);
        if (withParams == null) return _copy(fragment);
        ignored.addAll(withParams.ignored);
        return withParams.expression ?? _copy(fragment);
      case FigureAnd(:final children):
        return _combine('&', children, figure);
      case FigureOr(:final children):
        return _combine('or', children, figure);
      case FigureNot(:final child):
        final inner = figure(child);
        return inner is List<Object?> ? <Object?>['not', inner] : inner;
    }
  }
}

/// A mutable deep copy of a const expression fragment.
List<Object?> _copy(List<Object?> fragment) => [
  for (final part in fragment) part is List<Object?> ? _copy(part) : part,
];

Object _combine<T>(
  String operator,
  List<T> children,
  Object Function(T) translate,
) {
  if (children.isEmpty) return ContraDbAdvancedUnsupported.other;
  final parts = <Object?>[operator];
  for (final child in children) {
    final part = translate(child);
    if (part is ContraDbAdvancedUnsupported) return part;
    parts.add(part);
  }
  return parts;
}

/// The ContraDB figure filter for each Collection move, for the Collection
/// moves where the importer (`contradb_figure_dialect.dart`,
/// `contradb_html_adapter.dart`) turns ContraDB's own rendering of exactly
/// those figures into that move. Moves are spelled as ContraDB spells them
/// (`_contraDbFigureNames`'s values).
///
/// That is exact for the figures ContraDB defines, not for every dance, and
/// a query cannot know the difference. The importer also structures typed
/// `custom` prose into moves that ContraDB files under `custom` (`ladles trade
/// by the left shoulder` becomes `pass_by`; `partners swing, end facing
/// across` becomes `swing`), and it cannot read some real renderings, which
/// fall to `custom` here (a balanced `swat the flea`, a `*-hand chain`).
/// Those over- and under-matches are documented in `docs/design/search.md`,
/// not refused: almost any move can arrive from typed text.
///
/// Most are one `["figure", <move>]`. Exceptions, each derived by reading the
/// importer and ContraDB's `filter_dances.rb`. The expression for each is
/// pinned by `contradb_advanced_filter_test.dart`; only `allemande`'s importer
/// half is pinned (`contradb_advanced_translation_import_test.dart`). Nothing
/// checks that the dances ContraDB returns for them are the right ones: the
/// opt-in `tool/check_contradb_translation_live.dart` showed ContraDB accepts
/// each expression, and no more:
///
/// - **`pull_by`** is both `pull by dancers` and `pull by direction`.
/// - **Aliases.** ContraDB stores a see saw as a `do si do` and answers the
///   alias filter `see saw` with that move plus the alias's pinned parameter
///   (`filter_dances.rb`, `alias_filter`). The importer keeps `see_saw` (and
///   `swat_the_flea`) as moves of their own, apart from `do_si_do` (and
///   `box_the_gnat`). So `see_saw` is the alias filter, and `do_si_do` is the
///   target move *minus* the alias, expressed with the figurewise `&` / `not`.
///
/// Left out on purpose, and therefore refused:
///
/// - **`meltdown_swing`**: the importer stores a meltdown swing as a `swing`
///   with `prefix: meltdown`, so a leaf for the alias id matches no stored
///   figure.
/// - **`custom`** and **`star_promenade`**: the importer sends every line it
///   cannot structure (and every `star promenade`, by owner ruling #843) to the
///   Collection's `custom`, so that set is not ContraDB's `custom` set.
/// - **`allemande_orbit`**: not a figure the live importer produces; ContraDB's
///   `allemande orbit` is one figure, the Collection's is a container.
/// - **`pull_by_dancers`** and **`pull_by_direction`**: the Collection's
///   narrower pull-bys. `pull_by` covers both ContraDB figures; no ContraDB
///   figure selects exactly one of these two, so they are refused.
/// - **`pass_the_ocean`** and **`form_short_waves`**: ContraDB's one
///   `form an ocean wave` (with a `pass_through` parameter) imports as one or
///   the other, so each is a strict subset of it.
/// - Collection moves with no ContraDB figure (`two_hand_turn`,
///   `courtesy_turn`, `star_through`, `turn_as_couples`, `orbit`,
///   `circular_hey`).
///
/// `allemande` maps to `allemande` **or** `allemande orbit`: the importer
/// turns a real `allemande orbit` line into `meanwhile[allemande, orbit]`
/// (`contradb_figure_dialect.dart`, `_allemandeOrbitMeanwhile`), so the
/// Collection finds an allemande in that dance and ContraDB must be asked
/// for both of its moves to answer the same question.
const Map<String, List<Object?>> _contraDbForCollectionMove = {
  'allemande': [
    'or',
    ['figure', 'allemande'],
    ['figure', 'allemande orbit'],
  ],
  'arch_and_dive': ['figure', 'arch & dive'],
  'balance': ['figure', 'balance'],
  'balance_the_ring': ['figure', 'balance the ring'],
  'box_circulate': ['figure', 'box circulate'],
  'box_the_gnat': [
    '&',
    ['figure', 'box the gnat'],
    [
      'not',
      ['figure', 'swat the flea'],
    ],
  ],
  'butterfly_whirl': ['figure', 'butterfly whirl'],
  'california_twirl': ['figure', 'California twirl'],
  'chain': ['figure', 'chain'],
  'circle': ['figure', 'circle'],
  'contra_corners': ['figure', 'contra corners'],
  'cross_trails': ['figure', 'cross trails'],
  'do_si_do': [
    '&',
    ['figure', 'do si do'],
    [
      'not',
      ['figure', 'see saw'],
    ],
  ],
  'dolphin_hey': ['figure', 'dolphin hey'],
  'down_the_hall': ['figure', 'down the hall'],
  'facing_star': ['figure', 'facing star'],
  'figure_8': ['figure', 'figure 8'],
  'form_a_long_wave': ['figure', 'form a long wave'],
  'form_long_waves': ['figure', 'form long waves'],
  'gate': ['figure', 'gate'],
  'give_and_take': ['figure', 'give & take'],
  'hey': ['figure', 'hey'],
  'long_lines': ['figure', 'long lines'],
  'mad_robin': ['figure', 'mad robin'],
  'pass_by': ['figure', 'pass by'],
  'pass_through': ['figure', 'pass through'],
  'petronella': ['figure', 'petronella'],
  'poussette': ['figure', 'poussette'],
  'promenade': ['figure', 'promenade'],
  'pull_by': [
    'or',
    ['figure', 'pull by dancers'],
    ['figure', 'pull by direction'],
  ],
  'revolving_door': ['figure', 'revolving door'],
  'right_left_through': ['figure', 'right left through'],
  'roll_away': ['figure', 'roll away'],
  'rory_o_more': ['figure', "Rory O'More"],
  'see_saw': ['figure', 'see saw'],
  'shoulder_round': ['figure', 'gyre'],
  'slice': ['figure', 'slice'],
  'slide_along_set': ['figure', 'slide along set'],
  'square_through': ['figure', 'square through'],
  'stand_still': ['figure', 'stand still'],
  'star': ['figure', 'star'],
  'swat_the_flea': ['figure', 'swat the flea'],
  'swing': ['figure', 'swing'],
  'turn_alone': ['figure', 'turn alone'],
  'up_the_hall': ['figure', 'up the hall'],
  'zig_zag': ['figure', 'zig zag'],
};

/// The Collection move ids [translateDanceFilterToContraDb] has an entry
/// for, so a test can check the table itself (a misspelt key is otherwise
/// just a move that is never asked about, and is silently refused).
@visibleForTesting
Iterable<String> get contraDbTranslatableMoveIds =>
    _contraDbForCollectionMove.keys;
