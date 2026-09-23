import 'package:collection/collection.dart';

import 'figure.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// A [Dance]'s transcription, as a closed set of cases rather than a bare list.
///
/// ## Why this is not just `List<Figure>`
///
/// A dance's `figures_json` can be stored in a state no `List<Figure>` can
/// represent: text that `decodeFigures` rejects — not JSON at all, a root that
/// is not an array, or an entry that is not a well-formed figure object. Today
/// that raises on the load path (#1347). The fix is to give the undecodable
/// case a *representation*, so it can travel through the app instead of
/// crashing it — but a representation is only safe if nothing can quietly
/// ignore it.
///
/// ## Undecodable is not un-normalisable, and neither implies the other
///
/// Worth stating precisely, because this is the definition the next change will
/// be read against. The normalisation pass rejects a *different* set of values:
/// malformed JSON, object keys that normalise to one key, and values that decode
/// but cannot be re-encoded (`1e999` is legal JSON that parses to an infinity no
/// JSON encoder will emit — #1363). The two sets overlap only on text that is
/// not JSON at all.
///
/// * `[1, 2, 3]` normalises perfectly and does **not** decode.
/// * A figure whose params hold both `é` and `e` + `U+0301` decodes perfectly
///   and does **not** normalise — `decodeFigures` performs no normalisation
///   (`figure_codec.dart` imports neither the normaliser nor anything that
///   calls it).
///
/// An un-normalisable row is the normalisation pass's problem and is recorded
/// as a skip; an **undecodable** one is this type's.
///
/// ## Why not a flag
///
/// A `bool figuresUnreadable` beside a `List<Figure>` would not be safe: every
/// place that reads a transcription would keep compiling, silently receiving an
/// empty list. Many of those paths read a dance, change one field and write it
/// back, so an empty list there is not a display bug — it is the user's
/// transcription being overwritten with nothing, permanently, on an ordinary
/// edit.
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
  DecodedFigures(List<Figure> figures) : figures = List.unmodifiable(figures);

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
