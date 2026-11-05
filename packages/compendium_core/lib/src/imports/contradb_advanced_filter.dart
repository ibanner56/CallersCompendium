import 'package:meta/meta.dart';

import '../search/filter.dart';

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

  /// A figure condition with parameters or a phrase section. ContraDB
  /// compares parameters by position in each move's own formal-parameter list,
  /// which the app's named parameters are not mapped onto.
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
  const ContraDbAdvancedExpression(this.expression);

  final List<Object?> expression;
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
/// [_contraDbMovesForCollectionMove]. A display name, a ContraDB spelling or a
/// dialect's term is refused as [ContraDbAdvancedUnsupported.figureName]: the
/// Collection resolves those through the active dialect, which this function
/// never sees, so it cannot know they mean what ContraDB's identically spelt
/// move means.
ContraDbAdvancedTranslation translateDanceFilterToContraDb(DanceFilter filter) {
  final result = _dance(filter);
  return switch (result) {
    final List<Object?> expression => ContraDbAdvancedExpression(expression),
    final ContraDbAdvancedUnsupported reason => ContraDbAdvancedRefused(reason),
    _ => throw StateError('unreachable'),
  };
}

/// Either a `List<Object?>` expression or a [ContraDbAdvancedUnsupported].
Object _dance(DanceFilter filter) {
  switch (filter) {
    case AndFilter(:final children):
      return _combine('and', children, _dance);
    case OrFilter(:final children):
      return _combine('or', children, _dance);
    case NotFilter(:final child):
      final inner = _dance(child);
      return inner is List<Object?> ? <Object?>['no', inner] : inner;
    case FigureFilter(:final query):
      // `FigureFilter(FigureNot(q))` means "no figure matches q" locally.
      if (query case FigureNot(:final child)) {
        final inner = _figure(child);
        return inner is List<Object?> ? <Object?>['no', inner] : inner;
      }
      return _figure(query);
    case TagFilter() || UntaggedFilter():
      return ContraDbAdvancedUnsupported.tag;
    case ThenFilter(:final before, :final after):
      // Both sides mean "immediately follows, wrapping from the last figure to
      // the first", as ContraDB's `then` does (`SearchMatch#abuts?`). The
      // operands are row-level, so a figure not under them is figurewise
      // `not`, never the dance-level `no`.
      return _combine('then', [before, after], _figure);
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

Object _figure(FigureQuery query) {
  switch (query) {
    case FigureLeaf(:final move, :final params, :final section):
      if (params.isNotEmpty || section != null) {
        return ContraDbAdvancedUnsupported.figureDetail;
      }
      final names = _contraDbMovesForCollectionMove[move];
      if (names == null) return ContraDbAdvancedUnsupported.figureName;
      final figures = [
        for (final name in names) <Object?>['figure', name],
      ];
      return figures.length == 1 ? figures.single : <Object?>['or', ...figures];
    case FigureAnd(:final children):
      return _combine('&', children, _figure);
    case FigureOr(:final children):
      return _combine('or', children, _figure);
    case FigureNot(:final child):
      final inner = _figure(child);
      return inner is List<Object?> ? <Object?>['not', inner] : inner;
  }
}

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

/// The ContraDB moves whose figures the importer turns into each Collection
/// move, for the Collection moves where that mapping is **exact** in both
/// directions (the live ContraDB importer, `contradb_figure_dialect.dart` and
/// `contradb_adapter.dart`'s move table, produces the Collection move from
/// exactly these ContraDB moves and no others). Spelled as ContraDB spells
/// them (`_contraDbFigureNames`'s values).
///
/// Left out on purpose, and therefore refused:
///
/// - **Aliases** (`see_saw`, `swat_the_flea`, `meltdown_swing`). The Collection
///   stores them resolved (`see_saw` is a `do_si_do` with a pinned parameter),
///   so a leaf for the alias id matches no stored figure, while ContraDB's
///   alias filter selects the target move with that parameter value.
/// - **`custom`** and **`star_promenade`**: the importer sends every line it
///   cannot structure (and every `star promenade`, by owner ruling #843) to the
///   Collection's `custom`, so that set is not ContraDB's `custom` set.
/// - **`allemande_orbit`**: not a figure the live importer produces; ContraDB's
///   `allemande orbit` is one figure, the Collection's is a container.
/// - **`pass_the_ocean`**: ContraDB's `pass through` with an ocean-wave
///   parameter, not a figure of its own (its `form an ocean wave` imports as
///   `form_short_waves`).
/// - Collection moves with no ContraDB figure (`two_hand_turn`,
///   `courtesy_turn`, `star_through`, `turn_as_couples`, `orbit`,
///   `circular_hey`).
const Map<String, List<String>> _contraDbMovesForCollectionMove = {
  'allemande': ['allemande'],
  'arch_and_dive': ['arch & dive'],
  'balance': ['balance'],
  'balance_the_ring': ['balance the ring'],
  'box_circulate': ['box circulate'],
  'box_the_gnat': ['box the gnat'],
  'butterfly_whirl': ['butterfly whirl'],
  'california_twirl': ['California twirl'],
  'chain': ['chain'],
  'circle': ['circle'],
  'contra_corners': ['contra corners'],
  'cross_trails': ['cross trails'],
  'do_si_do': ['do si do'],
  'dolphin_hey': ['dolphin hey'],
  'down_the_hall': ['down the hall'],
  'facing_star': ['facing star'],
  'figure_8': ['figure 8'],
  'form_a_long_wave': ['form a long wave'],
  'form_long_waves': ['form long waves'],
  'form_short_waves': ['form an ocean wave'],
  'gate': ['gate'],
  'give_and_take': ['give & take'],
  'hey': ['hey'],
  'long_lines': ['long lines'],
  'mad_robin': ['mad robin'],
  'pass_by': ['pass by'],
  'pass_through': ['pass through'],
  'petronella': ['petronella'],
  'poussette': ['poussette'],
  'promenade': ['promenade'],
  'pull_by': ['pull by dancers', 'pull by direction'],
  'revolving_door': ['revolving door'],
  'right_left_through': ['right left through'],
  'roll_away': ['roll away'],
  'rory_o_more': ["Rory O'More"],
  'shoulder_round': ['gyre'],
  'slice': ['slice'],
  'slide_along_set': ['slide along set'],
  'square_through': ['square through'],
  'stand_still': ['stand still'],
  'star': ['star'],
  'swing': ['swing'],
  'turn_alone': ['turn alone'],
  'up_the_hall': ['up the hall'],
  'zig_zag': ['zig zag'],
};
