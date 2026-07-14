import 'package:meta/meta.dart';

/// A reusable published source (a book, collection, magazine, website, …) that
/// dances cite. A first-class entity like [Choreographer]/`Tag` — many dances
/// can reference the same source, so bibliographic edits happen in one place.
///
/// The dance-specific detail (which page/number a given dance appears at) lives
/// on the [SourceCitation] value object the dance carries, not here: this row
/// describes the source itself, faithful to CC's `Reference`/`MD_*` collection.
@immutable
class PublishedSource {
  PublishedSource({
    required this.id,
    required this.title,
    String? author,
    this.year,
    String? url,
    String? notes,
  }) : author = _normalize(author),
       url = _normalize(url),
       notes = _normalize(notes) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must be non-empty');
    }
    if (year != null && year! <= 0) {
      throw ArgumentError.value(year, 'year', 'must be null or a positive int');
    }
  }

  final String id;
  final String title;

  /// Bibliographic author/editor of the source (freeform); nullable.
  final String? author;

  /// Publication year; `null` when unknown. Only minimally constrained
  /// (positive) — we do not bound it to a calendar range.
  final int? year;

  /// Canonical URL for the source, if any; nullable.
  final String? url;

  /// Freeform notes about the source; nullable.
  final String? notes;

  /// Normalizes a freeform optional string: trims and treats empty/whitespace
  /// as `null`, so "unset" is a single canonical value (mirrors the
  /// [Choreographer] contact-field precedent).
  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Returns a copy with the given fields replaced. The `clear*` flags reset
  /// the respective nullable field to `null` and **win** over any value passed
  /// for the same field (precedent: [Choreographer.copyWith]).
  PublishedSource copyWith({
    String? title,
    String? author,
    bool clearAuthor = false,
    int? year,
    bool clearYear = false,
    String? url,
    bool clearUrl = false,
    String? notes,
    bool clearNotes = false,
  }) => PublishedSource(
    id: id,
    title: title ?? this.title,
    author: clearAuthor ? null : (author ?? this.author),
    year: clearYear ? null : (year ?? this.year),
    url: clearUrl ? null : (url ?? this.url),
    notes: clearNotes ? null : (notes ?? this.notes),
  );

  @override
  bool operator ==(Object other) =>
      other is PublishedSource &&
      other.id == id &&
      other.title == title &&
      other.author == author &&
      other.year == year &&
      other.url == url &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(id, title, author, year, url, notes);
}
