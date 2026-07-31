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
    this.meanwhileSides,
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
  ///
  /// When [figure] `isMeanwhile` (#590/#593), the draft becomes a **meanwhile
  /// group**: [meanwhileSides] is seeded from [Figure.subFigures] (each side
  /// recursively seeded via this same factory — flat only, so a side's own
  /// `meanwhileSides` is always `null`), and `params['beats']` carries the
  /// container's single SHARED beat count rather than any per-side count.
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
    meanwhileSides: figure.isMeanwhile
        ? [for (final side in figure.subFigures) FigureDraft.fromFigure(side)]
        : null,
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

  /// Non-`null` ⇒ this draft is a **meanwhile group** (#590/#593): the
  /// concurrent sides being authored, in order. `move`/most `params` are
  /// unused for a group — `params['beats']` instead holds the single SHARED
  /// beat count for the whole group (read via [beats], same as any other
  /// draft). `null` (the default) means an ordinary, non-grouped figure —
  /// today's ubiquitous case.
  ///
  /// **Flat only**: a side's own [meanwhileSides] is always `null`. This is
  /// enforced at the UI boundary (the editor never offers a "group" action on
  /// a side's own row), not by this field alone, matching the core model's
  /// flat-only invariant ([Figure.isMeanwhile] may not nest).
  List<FigureDraft>? meanwhileSides;

  /// Whether this draft is a meanwhile group. Mirrors [Figure.isMeanwhile].
  bool get isMeanwhileGroup => meanwhileSides != null;

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
    meanwhileSides: meanwhileSides
        ?.map((side) => side.clone())
        .toList(growable: true),
  );

  /// Whether this draft holds any content worth preserving even though it
  /// has no [move] chosen yet (used by [toFigure] to decide whether an
  /// in-progress meanwhile side should be best-effort materialized rather
  /// than silently dropped — see [_bestEffortFigure]). A freshly-added blank
  /// placeholder side (no note, no params, no walkthrough override) has
  /// nothing to lose and is the only case still skipped.
  bool get _hasUnsavedContent =>
      note.trim().isNotEmpty ||
      params.isNotEmpty ||
      walkthroughOverride != null;

  /// Best-effort immutable figure for a meanwhile side that has no [move]
  /// chosen yet but does have [_hasUnsavedContent] (#679 review): rather than
  /// silently dropping the side out of the persisted container — losing the
  /// user's partial authoring the moment an autosave/undo snapshot fires —
  /// represent it as a [customMove] figure carrying whatever was entered so
  /// far. Never called for a side whose [toFigure] already succeeds.
  Figure _bestEffortFigure() {
    final trimmedNote = note.trim();
    return Figure(
      schemaVersion: schemaVersion,
      move: customMove,
      params: Map<String, Object?>.of(params),
      note: trimmedNote.isEmpty ? null : trimmedNote,
      progression: progression,
      customOrigin: customOrigin,
      assumedSubject: false,
      walkthroughOverride: walkthroughOverride,
    );
  }

  /// Builds the immutable figure, or `null` when no move is chosen yet (or,
  /// for a meanwhile group, when fewer than 2 sides can be materialized —
  /// an in-progress group never corrupts the saved dance; it simply isn't
  /// written until it is ready).
  Figure? toFigure() {
    final sides = meanwhileSides;
    if (sides != null) {
      // Never silently drop a side that the user has started authoring
      // (#679 review): only a genuinely untouched placeholder side (no move,
      // no note/params/walkthrough override) is skipped — mirroring how an
      // untouched top-level draft isn't persisted either. A side with no
      // move but SOME content is preserved via a best-effort custom figure
      // instead, so an in-progress group can never lose a side out from
      // under the user on autosave/undo.
      final readySides = [
        for (final side in sides)
          if (side.toFigure() case final fig?)
            fig
          else if (side._hasUnsavedContent)
            side._bestEffortFigure(),
      ];
      if (readySides.length < 2) return null;
      // Defensive clamp mirroring the codec's untrusted-input behavior: the
      // UI never lets the side count exceed the cap, but this keeps toFigure()
      // from ever throwing even if that invariant is somehow violated.
      final cappedSides = readySides.length > kMaxMeanwhileSides
          ? readySides.sublist(0, kMaxMeanwhileSides)
          : readySides;
      final trimmedNote = note.trim();
      return Figure.meanwhile(
        figures: cappedSides,
        beats: beats,
        note: trimmedNote.isEmpty ? null : trimmedNote,
        progression: progression,
      );
    }
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
