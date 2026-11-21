import 'package:collection/collection.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// A [Dance]'s suggested tune list, as a closed set of cases rather than a bare
/// list.
///
/// The exact shape of [FigureSource], for the same reason and with the same
/// contract. Two small parallel types rather than one generic one: generalising
/// a merged, reviewed type to save a few dozen lines is a worse trade than the
/// duplication.
///
/// ## Why this is not just `List<String>`
///
/// `dances.tunes_json` can hold text no list can represent, and the load path
/// used to throw on all of it. It is in `_shareableJsonColumns`, so the
/// normalisation pass may leave such a row exactly as stored (#1363) — which
/// means the row is a live possibility rather than a hypothetical.
///
/// **The failure surface is wider than it looks, and was measured rather than
/// read off a doc comment:**
///
/// * `[{"a":`  -> `FormatException` — not JSON.
/// * `{"a":1}` -> `TypeError` — the root is not a list.
/// * `[1,2,3]` -> `TypeError` — an element is not a string.
/// * `[null]`  -> `TypeError` — same.
///
/// Three of the four are `TypeError`, not `FormatException`. And the element
/// failures are **lazy**: `(jsonDecode(raw) as List).cast<String>()` does not
/// throw at the cast, it throws when the list is first iterated — which happened
/// inside `List.unmodifiable(tunes)` in the [Dance] constructor. A guard wrapped
/// around the cast would have caught nothing.
///
/// ## Why a sealed type rather than a flag or a salvage
///
/// Salvaging the readable elements (`whereType<String>()`) turns `[1,2,3]` into
/// `[]`, and a `bool tunesUnreadable` beside a `List<String>` leaves every
/// reader compiling while it silently receives an empty list. Both are the same
/// mistake: **"cannot read it" becoming "it is empty"**, which is the error this
/// issue has produced repeatedly. A sealed type makes the compiler ask every
/// reader what it means, and makes the write path physically unable to emit an
/// empty list in place of text it never decoded.
sealed class TunesSource {
  const TunesSource();
}

/// A tune list that was decoded successfully — the ordinary case.
final class DecodedTunes extends TunesSource {
  DecodedTunes(List<String> tunes) : tunes = List.unmodifiable(tunes);

  /// The ordered tune names. Unmodifiable, so sharing one [DecodedTunes]
  /// between two [Dance]s cannot let one mutate the other's list.
  final List<String> tunes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecodedTunes && _listEq.equals(other.tunes, tunes);

  @override
  int get hashCode => Object.hashAll(tunes);

  @override
  String toString() => 'DecodedTunes(${tunes.length})';
}

/// A tune list that could **not** be decoded, carrying the stored text exactly
/// as it was read.
///
/// [storedJson] is the authoritative content, not a diagnostic. Every path that
/// writes a dance back MUST re-emit it verbatim: an edit to a title or a tag
/// must not replace a tune list the app merely cannot read today with nothing.
final class UnreadableTunes extends TunesSource {
  const UnreadableTunes(this.storedJson);

  /// The stored `tunes_json` text, byte-for-byte as read.
  final String storedJson;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnreadableTunes && other.storedJson == storedJson;

  @override
  int get hashCode => storedJson.hashCode;

  /// Deliberately excludes [storedJson]: it is user content and this string
  /// reaches logs and diagnostic reports.
  @override
  String toString() => 'UnreadableTunes(${storedJson.length} chars)';
}
