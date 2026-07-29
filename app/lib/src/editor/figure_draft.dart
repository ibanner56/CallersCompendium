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
    this.assumedSubject = false,
    this.customOrigin = CustomOrigin.userEntered,
    this.walkthroughOverride,
  }) : id = id ?? uuidV4(),
       params = params ?? <String, Object?>{};

  /// Seeds a draft from an existing figure, keeping its params/note/flags.
  ///
  /// [beatsTouched] is set only when the loaded figure carries an explicit
  /// `beats` value — that authored count is user-owned and never auto-filled
  /// over (see [beatsTouched]). A figure with no `beats` (older/partial data)
  /// stays untouched so it can still adopt the taxonomy default on the next
  /// resync rather than remaining stuck at 0.
  ///
  /// [assumedSubject] is preserved so an imported figure whose subject the
  /// parser DEFAULTED (#460) keeps its non-authoritative marker across an
  /// open/save round-trip; it is cleared the moment the user explicitly picks a
  /// move or edits the subject, which makes the subject a stated choice.
  factory FigureDraft.fromFigure(Figure figure) => FigureDraft(
    move: figure.move,
    params: Map<String, Object?>.of(figure.params),
    note: figure.note ?? '',
    progression: figure.progression,
    schemaVersion: figure.schemaVersion,
    beatsTouched: figure.params.containsKey('beats'),
    assumedSubject: figure.assumedSubject,
    customOrigin: figure.customOrigin,
    walkthroughOverride: figure.walkthroughOverride,
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

  /// Whether this figure's subject was ASSUMED by the import parser (the source
  /// omitted it) rather than stated (#460). Carried through the editor so an
  /// open/save round-trip preserves the provenance marker; the editor clears it
  /// as soon as the user picks a move or edits the `who` param, since either is
  /// an explicit, authoritative choice of subject.
  bool assumedSubject;

  /// How this figure originated when it is a [customMove] custom (see
  /// [CustomOrigin]). Carried through the editor so a custom figure produced by
  /// the opt-in free-text entry path (or an import) that the parser could not
  /// map keeps its [CustomOrigin.importGap] flag across open/save and
  /// undo/autosave round-trips — which is what keeps it showing the #398
  /// parser-gap marker and eligible for the reparse-customs upgrade (#419/#417).
  /// Only meaningful when the draft is a custom; explicitly choosing a move or
  /// authoring a custom in the structured editor resets it to
  /// [CustomOrigin.userEntered] (a stated, user-authored choice).
  CustomOrigin customOrigin;

  /// The per-dance, per-figure-instance **walkthrough snippet override** (#411):
  /// the step text to use for THIS occurrence, taking precedence over the global
  /// snippet library default (keyed by figure signature). `null` means "no
  /// override" — the figure falls back to the library default when a walkthrough
  /// is assembled. Holds ONLY the per-dance override; "use everywhere" edits
  /// update the library and leave this `null`.
  String? walkthroughOverride;

  int get beats => (params['beats'] as int?) ?? 0;

  /// Returns an independent copy with a FRESH [id] (the stable-identity
  /// contract: a duplicate is a distinct row) and every other field copied
  /// verbatim — the `params` map is deep-copied, and provenance/ownership flags
  /// ([assumedSubject], [beatsTouched]) are carried over so a duplicate behaves
  /// exactly like its source. Centralizing cloning here keeps the duplicate
  /// paths (dance editor and settings template) from silently dropping
  /// newly-added fields — the bug that lost [assumedSubject] on duplicate (#460).
  FigureDraft clone() => FigureDraft(
    move: move,
    params: Map<String, Object?>.of(params),
    note: note,
    progression: progression,
    schemaVersion: schemaVersion,
    beatsTouched: beatsTouched,
    assumedSubject: assumedSubject,
    customOrigin: customOrigin,
    walkthroughOverride: walkthroughOverride,
  );

  /// Builds the immutable figure, or `null` when no move is chosen yet.
  Figure? toFigure() {
    final id = move;
    if (id == null) return null;
    final trimmedNote = note.trim();
    final trimmedOverride = walkthroughOverride?.trim();
    return Figure(
      schemaVersion: schemaVersion,
      move: id,
      params: Map<String, Object?>.of(params),
      note: trimmedNote.isEmpty ? null : trimmedNote,
      progression: progression,
      assumedSubject: assumedSubject,
      customOrigin: customOrigin,
      walkthroughOverride: (trimmedOverride == null || trimmedOverride.isEmpty)
          ? null
          : trimmedOverride,
    );
  }
}
