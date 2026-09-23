import 'package:collection/collection.dart';

import 'figure.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// A [Dance]'s transcription, as a closed set of cases rather than a bare list.
///
/// ## Why this is not just `List<Figure>`
///
/// A dance's `figures_json` can be stored in a state no list can represent: a
/// value that is malformed, or whose object keys collide under normalization,
/// cannot be decoded into figures at all (#1347). Today that raises on the load
/// path. The fix is to give the unreadable case a *representation*, so it can
/// travel through the app instead of crashing it — but a representation is only
/// safe if nothing can quietly ignore it.
///
/// A `bool figuresUnreadable` flag beside a `List<Figure>` would not be safe:
/// every one of the ~50 places that read a transcription would keep compiling,
/// silently receiving an empty list. Six repository methods and eleven UI paths
/// read a dance, change one field and write it back, so an empty list there is
/// not a display bug — it is the user's transcription being overwritten with
/// nothing, permanently, on an ordinary edit.
///
/// Because this is a `sealed` class, a `switch` over it is checked for
/// exhaustiveness by the compiler. Adding a case is therefore not a change
/// callers *may* handle; it is a change that stops every reader compiling until
/// each one has said what it means there. That is the whole point of the type,
/// and it is why no method here returns a plain `List<Figure>`: such a shortcut
/// would make the next case compile cleanly everywhere and give back exactly the
/// silent-empty-list hazard this exists to prevent.
///
/// This class currently has one case. That is deliberate and temporary: this
/// change is the mechanical half, landing with no behaviour change at all, so
/// that the case which carries the hazard arrives on its own and breaks every
/// site that must think about it.
sealed class FigureSource {
  const FigureSource();
}

/// A transcription that was decoded successfully — the ordinary case, and
/// currently the only one.
final class DecodedFigures extends FigureSource {
  DecodedFigures(List<Figure> figures)
    : figures = List.unmodifiable(figures);

  /// The ordered figure list. Unmodifiable, so sharing one [DecodedFigures]
  /// between two [Dance]s (as `copyWith` and `duplicate` may) cannot let one
  /// mutate the other's transcription.
  final List<Figure> figures;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecodedFigures && _listEq.equals(other.figures, figures);

  @override
  int get hashCode => Object.hashAll(figures);

  @override
  String toString() => 'DecodedFigures(${figures.length})';
}
