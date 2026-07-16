// Editor model: the mutable working draft for a single figure in the dance
// editor. Extracted from figure_list_editor.dart so model consumers (codec,
// snapshot, controller, settings) can depend on the model without importing
// the large widget file. Pure data — no Flutter/UI dependencies.

import 'package:compendium_core/compendium_core.dart';

/// Mutable working state for a single figure while it is being edited in the
/// dance editor. Committed to an immutable [Figure] on save via [toFigure].
class FigureDraft {
  FigureDraft({
    String? id,
    this.move,
    Map<String, Object?>? params,
    this.note = '',
    this.progression = false,
    this.schemaVersion = figureSchemaVersion,
    this.beatsTouched = false,
  }) : id = id ?? uuidV4(),
       params = params ?? <String, Object?>{};

  /// Seeds a draft from an existing figure, keeping its params/note/flags.
  ///
  /// [beatsTouched] is set only when the loaded figure carries an explicit
  /// `beats` value — that authored count is user-owned and never auto-filled
  /// over (see [beatsTouched]). A figure with no `beats` (older/partial data)
  /// stays untouched so it can still adopt the taxonomy default on the next
  /// resync rather than remaining stuck at 0.
  factory FigureDraft.fromFigure(Figure figure) => FigureDraft(
    move: figure.move,
    params: Map<String, Object?>.of(figure.params),
    note: figure.note ?? '',
    progression: figure.progression,
    schemaVersion: figure.schemaVersion,
    beatsTouched: figure.params.containsKey('beats'),
  );

  /// Stable identity for widget keys across reorders/rebuilds.
  final String id;

  /// Canonical move (or alias) id, or `null` until the user picks one.
  String? move;
  final Map<String, Object?> params;
  String note;
  bool progression;
  final int schemaVersion;

  /// Whether the user has explicitly taken ownership of the `beats` value.
  ///
  /// Beats are auto-filled from the taxonomy: picking a move seeds the move's
  /// canonical default and clears this flag. Once the user edits the beats
  /// field directly (or the draft is seeded from a loaded figure that already
  /// carries an explicit `beats` via [FigureDraft.fromFigure]), this becomes
  /// `true` and the editor stops auto-filling beats so a manual override is
  /// never silently overwritten.
  bool beatsTouched;

  int get beats => (params['beats'] as int?) ?? 0;

  /// Builds the immutable figure, or `null` when no move is chosen yet.
  Figure? toFigure() {
    final id = move;
    if (id == null) return null;
    final trimmedNote = note.trim();
    return Figure(
      schemaVersion: schemaVersion,
      move: id,
      params: Map<String, Object?>.of(params),
      note: trimmedNote.isEmpty ? null : trimmedNote,
      progression: progression,
    );
  }
}
