import 'package:meta/meta.dart';

/// A user-configurable difficulty vocabulary entry.
///
/// IDs are the persisted relationship contract: labels and positions may change
/// without changing the dances that refer to an entry.
@immutable
class DifficultyLevel {
  DifficultyLevel({
    required this.id,
    required this.label,
    required this.position,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must be non-empty');
    }
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'must be non-empty');
    }
    if (position < 0) {
      throw ArgumentError.value(position, 'position', 'must not be negative');
    }
  }

  static const beginnerId = 'difficulty-beginner';
  static const intermediateId = 'difficulty-intermediate';
  static const advancedId = 'difficulty-advanced';

  static final beginner = DifficultyLevel(
    id: beginnerId,
    label: 'Beginner',
    position: 0,
  );
  static final intermediate = DifficultyLevel(
    id: intermediateId,
    label: 'Intermediate',
    position: 1,
  );
  static final advanced = DifficultyLevel(
    id: advancedId,
    label: 'Advanced',
    position: 2,
  );

  /// The immutable vocabulary shipped with every new collection.
  static final shipped = List<DifficultyLevel>.unmodifiable([
    beginner,
    intermediate,
    advanced,
  ]);

  /// Compatibility view of the three shipped values for pre-vocabulary
  /// callers. Configured custom levels are loaded from the repository.
  static List<DifficultyLevel> get values => shipped;

  static final shippedIds = Set<String>.unmodifiable({
    beginnerId,
    intermediateId,
    advancedId,
  });

  final String id;
  final String label;
  final int position;

  /// Legacy enum spelling used only by compatibility codecs.
  String get name => switch (id) {
    beginnerId => 'beginner',
    intermediateId => 'intermediate',
    advancedId => 'advanced',
    _ => id,
  };

  DifficultyLevel copyWith({String? label, int? position}) => DifficultyLevel(
    id: id,
    label: label ?? this.label,
    position: position ?? this.position,
  );

  @override
  bool operator ==(Object other) =>
      other is DifficultyLevel &&
      other.id == id &&
      other.label == label &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, label, position);

}
