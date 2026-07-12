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
// LinkSnapshot — immutable copy of a URL-kind link draft's mutable fields.
// ---------------------------------------------------------------------------

@immutable
class LinkSnapshot {
  const LinkSnapshot({
    required this.id,
    required this.kind,
    required this.url,
    required this.label,
  });

  final String id;
  final LinkKind kind;
  final String url;
  final String label;
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
    required this.authorIds,
    required this.tagIds,
    required this.tunes,
    required this.links,
    required this.preservedLinks,
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

  // ---- Multi-value lists ----
  final List<String> authorIds;
  final List<String> tagIds;
  final List<String> tunes;

  // ---- Links ----

  /// URL-kind links that the editor can directly edit (source, video, other).
  final List<LinkSnapshot> links;

  /// Links the editor cannot edit yet (e.g. relatedDance — target picker
  /// deferred to a later phase).  Held verbatim to survive round-trips.
  final List<DanceLink> preservedLinks;

  // ---- Custom fields ----
  final Map<String, Object?> customValues;

  // ---- Figures ----
  final List<FigureDraftSnapshot> figureDrafts;
}
