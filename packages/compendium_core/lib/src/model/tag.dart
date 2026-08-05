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

  /// Returns a copy with [color] set, **including to `null`** — the "no colour
  /// assigned" state.
  ///
  /// [copyWith] cannot express this: its `color ?? this.color` fallback makes a
  /// `null` argument indistinguishable from an omitted one, so
  /// `copyWith(color: null)` silently keeps the existing colour. Clearing a
  /// tag's colour (issue #786) therefore needs its own entry point rather than
  /// a sentinel bolted onto [copyWith], which would change behaviour for every
  /// existing caller.
  Tag withColor(int? color) => Tag(id: id, name: name, color: color);

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}
