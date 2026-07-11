import 'package:meta/meta.dart';

/// A dance author. "Traditional" and "Unknown" are real rows, not magic
/// values, so authorship stays a uniform ordered list on every dance.
@immutable
class Choreographer {
  Choreographer({
    required this.id,
    required this.name,
    this.website,
    this.notes,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be non-empty');
    }
  }

  final String id;
  final String name;
  final String? website;
  final String? notes;

  Choreographer copyWith({String? name, String? website, String? notes}) =>
      Choreographer(
        id: id,
        name: name ?? this.name,
        website: website ?? this.website,
        notes: notes ?? this.notes,
      );

  @override
  bool operator ==(Object other) =>
      other is Choreographer &&
      other.id == id &&
      other.name == name &&
      other.website == website &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(id, name, website, notes);
}
