import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../widgets/figure_list_editor.dart';

// ---------------------------------------------------------------------------
// FigureDraftSnapshot — immutable copy of a [FigureDraft]'s mutable fields.
// ---------------------------------------------------------------------------

@immutable
class FigureDraftSnapshot {
  const FigureDraftSnapshot({
    required this.id,
    required this.move,
    required this.params,
    required this.note,
    required this.progression,
    required this.schemaVersion,
  });

  factory FigureDraftSnapshot.fromDraft(FigureDraft draft) =>
      FigureDraftSnapshot(
        id: draft.id,
        move: draft.move,
        params: Map.unmodifiable(Map<String, Object?>.of(draft.params)),
        note: draft.note,
        progression: draft.progression,
        schemaVersion: draft.schemaVersion,
      );

  final String id;
  final String? move;
  final Map<String, Object?> params;
  final String note;
  final bool progression;
  final int schemaVersion;

  FigureDraft toDraft() => FigureDraft(
    id: id,
    move: move,
    params: Map<String, Object?>.of(params),
    note: note,
    progression: progression,
    schemaVersion: schemaVersion,
  );
}

// ---------------------------------------------------------------------------
// LinkSnapshot — immutable copy of a single link draft's mutable fields.
// ---------------------------------------------------------------------------

@immutable
class LinkSnapshot {
  const LinkSnapshot({
    required this.id,
    required this.kind,
    required this.url,
    required this.label,
    this.targetDanceId,
  });

  final String id;
  final LinkKind kind;

  /// URL for source/video/other kinds; empty string for relatedDance.
  final String url;

  final String label;

  /// Set when [kind] is [LinkKind.relatedDance]; `null` otherwise.
  final String? targetDanceId;
}

// ---------------------------------------------------------------------------
// EditorSnapshot — complete immutable working-state snapshot.
// ---------------------------------------------------------------------------

/// An immutable snapshot of the dance editor's full working state (metadata
/// + figure drafts + links + custom values).  Used both for the in-memory
/// undo/redo stack and as the serialization unit for autosave drafts.
///
/// All list/map fields are unmodifiable so callers cannot accidentally mutate
/// a stored snapshot.
@immutable
class EditorSnapshot {
  const EditorSnapshot({
    required this.title,
    required this.hook,
    required this.notes,
    required this.phrase,
    required this.formationDetail,
    required this.form,
    required this.formationShape,
    required this.progression,
    required this.status,
    this.level,
    this.mixedLevel = false,
    this.composedOn,
    this.revisedOn,
    required this.authorIds,
    required this.tagIds,
    required this.tunes,
    required this.links,
    required this.customValues,
    required this.figureDrafts,
  });

  // ---- Text fields ----
  final String title;
  final String hook;
  final String notes;
  final String phrase;
  final String formationDetail;

  // ---- Enum fields ----
  final DanceForm form;
  final FormationShape formationShape;
  final Progression progression;
  final DanceStatus status;

  /// Difficulty on the ordered [DanceLevel] scale; `null` when unspecified.
  final DanceLevel? level;

  /// Whether the dance spans the difficulty scale (distinct from [level]).
  final bool mixedLevel;

  /// Author composition date at partial precision; `null` when unspecified.
  final PartialDate? composedOn;

  /// Author revision date at partial precision; `null` when unspecified.
  final PartialDate? revisedOn;

  // ---- Multi-value lists ----
  final List<String> authorIds;
  final List<String> tagIds;
  final List<String> tunes;

  // ---- Links ----

  /// All editable links (source, video, other, and relatedDance).
  final List<LinkSnapshot> links;

  // ---- Custom fields ----
  final Map<String, Object?> customValues;

  // ---- Figures ----
  final List<FigureDraftSnapshot> figureDrafts;
}
