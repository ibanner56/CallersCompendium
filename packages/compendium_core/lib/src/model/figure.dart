import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Current figure schema version. Persisted with every figure so old data
/// always parses after taxonomy/schema evolution.
const int figureSchemaVersion = 1;

/// Canonical move id for the free-text fallback figure.
const String customMove = 'custom';

/// Canonical taxonomy id for the custom move (same value as [customMove]).
const String customMoveId = customMove;

const DeepCollectionEquality _paramsEquality = DeepCollectionEquality();

/// How a [customMove] [Figure] came to exist. Only meaningful when
/// [Figure.isCustom]; non-custom figures always carry [userEntered].
///
/// A custom figure can arise two ways that are otherwise indistinguishable:
/// the user deliberately authored it, or an import hit a taxonomy coverage gap
/// and kept the source line verbatim (the parse-never-fails invariant). This
/// discriminator lets the UI flag the parse-gap flavor. It is a passive flag
/// only — it never triggers a re-parse or rewrite (that is a separate concern).
enum CustomOrigin {
  /// The user authored this custom figure (the default for every figure).
  userEntered,

  /// An import parser could not map the source line to a structured move and
  /// kept it verbatim as a custom figure.
  importGap,
}

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
    this.customOrigin = CustomOrigin.userEntered,
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

  /// How this custom figure originated (see [CustomOrigin]). Only meaningful
  /// when [isCustom]; defaults to [CustomOrigin.userEntered] so plain-built and
  /// non-custom figures — and existing stored data lacking the key — are
  /// unaffected.
  final CustomOrigin customOrigin;

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
    CustomOrigin? customOrigin,
  }) => Figure(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    move: move ?? this.move,
    params: params ?? this.params,
    note: note ?? this.note,
    progression: progression ?? this.progression,
    customOrigin: customOrigin ?? this.customOrigin,
  );

  @override
  bool operator ==(Object other) =>
      other is Figure &&
      other.schemaVersion == schemaVersion &&
      other.move == move &&
      _paramsEquality.equals(other.params, params) &&
      other.note == note &&
      other.progression == progression &&
      other.customOrigin == customOrigin;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    move,
    _paramsEquality.hash(params),
    note,
    progression,
    customOrigin,
  );

  @override
  String toString() => 'Figure($move, $params)';
}
