import 'package:meta/meta.dart';

/// A dance's citation of a reusable [PublishedSource]: which source, and
/// (optionally) where within it the dance appears.
///
/// This is the value object the [Dance] carries — it is **not** the reusable
/// entity. [page] and [number] are freeform strings on purpose: pages may be
/// ranges or roman numerals ("12-14", "iv") and collection numbers may be
/// non-numeric ("A1"). Both are normalized (empty/whitespace -> `null`).
@immutable
class SourceCitation {
  SourceCitation({required this.sourceId, String? page, String? number})
    : page = _normalize(page),
      number = _normalize(number);

  /// The id of the referenced [PublishedSource].
  final String sourceId;

  /// Freeform page reference (e.g. "12", "12-14", "iv"); nullable.
  final String? page;

  /// Freeform number/index within the source (e.g. "A1", "37"); nullable.
  final String? number;

  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is SourceCitation &&
      other.sourceId == sourceId &&
      other.page == page &&
      other.number == number;

  @override
  int get hashCode => Object.hash(sourceId, page, number);
}
