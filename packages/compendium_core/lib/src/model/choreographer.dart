import 'package:meta/meta.dart';

/// A dance author. "Traditional" and "Unknown" are real rows, not magic
/// values, so authorship stays a uniform ordered list on every dance.
///
/// Privacy: [email] and [location] are private contact data. They are safe in
/// the user's own full-DB snapshot/backup, but MUST NOT be emitted in any
/// shareable export (program/dance share paths). No core export currently
/// serializes choreographers; the 4b.4b UI/export work must preserve this.
@immutable
class Choreographer {
  Choreographer({
    required this.id,
    required this.name,
    this.website,
    this.notes,
    String? email,
    String? location,
    this.deceased = false,
  }) : email = _normalize(email),
       location = _normalize(location) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be non-empty');
    }
  }

  final String id;
  final String name;
  final String? website;
  final String? notes;

  /// Private contact email; permissive freeform (no format validation).
  final String? email;

  /// Freeform locality (e.g. "Portland, OR"); private contact metadata.
  final String? location;

  /// Whether the author is deceased. Defaults to `false`.
  final bool deceased;

  /// Normalizes a freeform contact string: trims and treats empty/whitespace
  /// as `null`. `website`/`notes` are stored verbatim (not normalized), but we
  /// normalize the new contact fields — it is the safest choice for optional,
  /// privacy-sensitive data and keeps "unset" a single canonical value (null).
  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Returns a copy with the given fields replaced. [clearEmail]/[clearLocation]
  /// reset the respective field to `null` and **win** over any value passed for
  /// the same field (precedent: [Dance.clearRating]/[Dance.clearComposedOn]).
  Choreographer copyWith({
    String? name,
    String? website,
    String? notes,
    String? email,
    bool clearEmail = false,
    String? location,
    bool clearLocation = false,
    bool? deceased,
  }) => Choreographer(
    id: id,
    name: name ?? this.name,
    website: website ?? this.website,
    notes: notes ?? this.notes,
    email: clearEmail ? null : (email ?? this.email),
    location: clearLocation ? null : (location ?? this.location),
    deceased: deceased ?? this.deceased,
  );

  @override
  bool operator ==(Object other) =>
      other is Choreographer &&
      other.id == id &&
      other.name == name &&
      other.website == website &&
      other.notes == notes &&
      other.email == email &&
      other.location == location &&
      other.deceased == deceased;

  @override
  int get hashCode =>
      Object.hash(id, name, website, notes, email, location, deceased);
}
