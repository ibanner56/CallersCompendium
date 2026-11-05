import 'package:meta/meta.dart';

import '../search/filter.dart';
import 'contradb_search.dart';

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

  /// A "then" sequence. The Collection means "this figure comes somewhere
  /// before that one"; ContraDB's `then` requires the two to **abut**, and
  /// wraps from the last figure to the first. Sending it would silently change
  /// the question.
  sequence,

  /// A figure condition with parameters or a phrase section. ContraDB
  /// compares parameters by position in each move's own formal-parameter list,
  /// which the app's named parameters are not mapped onto.
  figureDetail,

  /// A move ContraDB does not define. ContraDB treats an unknown move as a
  /// figure that matches nothing, so the search would look like "no results".
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
///
/// An empty [AndFilter]/[OrFilter] is refused as [ContraDbAdvancedUnsupported.other]:
/// the builder never produces one (`BuilderGroup.toFilter` returns null for an
/// empty group) and ContraDB's empty `and`/`or` do not mean "everything"/"nothing".
///
/// Moves are resolved through [canonicalContraDbFigureQuery], so case and
/// punctuation variants are accepted and the exact ContraDB spelling is sent.
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
    case ThenFilter():
      return ContraDbAdvancedUnsupported.sequence;
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
      final canonical = canonicalContraDbFigureQuery(move);
      return canonical == null
          ? ContraDbAdvancedUnsupported.figureName
          : <Object?>['figure', canonical];
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
