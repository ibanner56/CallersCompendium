import 'package:collection/collection.dart';

import 'figure.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// A [Dance]'s transcription, as a closed set of cases rather than a bare list.
///
/// ## Why this is not just `List<Figure>`
///
/// A dance's `figures_json` can be stored in a state no `List<Figure>` can
/// represent: text that `decodeFigures` rejects — not JSON at all, a root that
/// is not an array, or an entry that is not a well-formed figure object. Such a
/// row used to raise on the load path, which meant it raised out of
/// `ensureMigrated()` at startup and the app would not open (#1347, made total
/// in #1382). Giving the undecodable case a *representation* is what lets it
/// travel through the app instead of stopping it — but a representation is only
/// safe if nothing can quietly ignore it, which is what the rest of this comment
/// is about.
///
/// The representation does not by itself make any *particular* call site
/// tolerant. Tolerance belongs where the throw is: a caller that reads
/// `figures_json` and decodes it itself never passes through this type at all,
/// and stays as brittle as it was. Two such sites were found after the load
/// path had landed — the one-time maintenance sweeps in `repositories.dart`,
/// and `DanceRepository.previewImportGapReparse`, which bypasses `_toModel`
/// for query-count reasons.
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
/// The type has both of its cases: [DecodedFigures] and [UnreadableFigures].
/// They arrived in that order on purpose — the sealed type landed first as the
/// mechanical half, with no behaviour change at all, so that the case carrying
/// the hazard arrived on its own and broke every site that had to think about
/// it. Every production reader has since said what an unreadable transcription
/// means there. A third case would put them all back in front of the compiler
/// the same way, which is the property to preserve rather than the case count.
sealed class FigureSource {
  const FigureSource();
}

/// A transcription that was decoded successfully — the ordinary case.
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

/// A transcription that could **not** be decoded, carrying the stored text
/// exactly as it was read.
///
/// The case this type exists for (#1347). `decodeFigures` rejects text that is
/// not JSON, whose root is not an array, or whose entries are not well-formed
/// figure objects. Before this existed, meeting such a row raised out of the
/// load path, which meant out of `ensureMigrated()` at startup — the app's error
/// screen, with a Retry that failed identically every time.
///
/// ## [storedJson] is the transcription, not a diagnostic
///
/// It is the authoritative bytes, kept so that nothing downstream has to invent
/// a replacement for them. Every path that writes a dance back MUST re-emit it
/// verbatim rather than encoding an empty figure list: an ordinary edit to a
/// title or a tag must not destroy a transcription the app merely cannot read
/// today. It may be repairable later — by a future decoder, by a hand fix, or by
/// a peer's copy — and it cannot be if it has been overwritten.
///
/// The text is deliberately **not** validated or normalised here. It may not be
/// JSON at all; it may be JSON this decoder rejects; it may be perfectly
/// normalisable (`[1, 2, 3]` is) or not. Holding it untouched is the whole
/// contract — see the class doc above for why undecodable and un-normalisable
/// are different questions.
final class UnreadableFigures extends FigureSource {
  const UnreadableFigures(this.storedJson);

  /// The stored `figures_json` text, byte-for-byte as read.
  final String storedJson;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnreadableFigures && other.storedJson == storedJson;

  @override
  int get hashCode => storedJson.hashCode;

  /// Deliberately does not include [storedJson]: the text is user content and
  /// this string reaches logs and diagnostic reports.
  @override
  String toString() => 'UnreadableFigures(${storedJson.length} chars)';
}
