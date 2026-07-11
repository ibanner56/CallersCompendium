import 'package:meta/meta.dart';

/// A flat user tag, optionally colored (ARGB int).
@immutable
class Tag {
  Tag({required this.id, required this.name, this.color}) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be non-empty');
    }
  }

  final String id;
  final String name;
  final int? color;

  Tag copyWith({String? name, int? color}) =>
      Tag(id: id, name: name ?? this.name, color: color ?? this.color);

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}
