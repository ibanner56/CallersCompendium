import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Current figure schema version. Persisted with every figure so old data
/// always parses after taxonomy/schema evolution.
const int figureSchemaVersion = 1;

/// Canonical move id for the free-text fallback figure.
const String customMove = 'custom';

const DeepCollectionEquality _paramsEquality = DeepCollectionEquality();

/// One figure (move instance) in a dance transcription.
///
/// A value object: canonical [move] id from the form's taxonomy plus NAMED
/// [params] (never positional — a ContraDB pitfall). Whether [move] exists
/// in the taxonomy and whether [params] match its parameter schema is
/// validated by the taxonomy engine (roadmap 2.4); this class enforces only
/// structural invariants.
@immutable
class Figure {
  Figure({
    this.schemaVersion = figureSchemaVersion,
    required this.move,
    Map<String, Object?> params = const {},
    this.note,
    this.progression = false,
  }) : params = Map.unmodifiable(params) {
    if (move.trim().isEmpty) {
      throw ArgumentError.value(move, 'move', 'must be non-empty');
    }
    final beats = params['beats'];
    if (beats != null && (beats is! int || beats < 0)) {
      throw ArgumentError.value(
        beats,
        'params[beats]',
        'must be a non-negative integer',
      );
    }
  }

  final int schemaVersion;

  /// Canonical snake_case move id (e.g. `shoulder_round`), or [customMove].
  final String move;

  /// Named parameters (e.g. `{who: 'partners', beats: 16}`). Unmodifiable.
  final Map<String, Object?> params;

  /// Optional dialect-aware free-text note ("scoop them up").
  final String? note;

  /// Marks a progression point in the dance.
  final bool progression;

  bool get isCustom => move == customMove;

  /// Duration in beats; 0 when unset (taxonomy defaults apply at a higher
  /// layer) — 0 is also legitimate for formation labels.
  int get beats => (params['beats'] as int?) ?? 0;

  Figure copyWith({
    int? schemaVersion,
    String? move,
    Map<String, Object?>? params,
    String? note,
    bool? progression,
  }) => Figure(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    move: move ?? this.move,
    params: params ?? this.params,
    note: note ?? this.note,
    progression: progression ?? this.progression,
  );

  @override
  bool operator ==(Object other) =>
      other is Figure &&
      other.schemaVersion == schemaVersion &&
      other.move == move &&
      _paramsEquality.equals(other.params, params) &&
      other.note == note &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    move,
    _paramsEquality.hash(params),
    note,
    progression,
  );

  @override
  String toString() => 'Figure($move, $params)';
}
