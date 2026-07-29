import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import 'figure_draft.dart';

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
    this.assumedSubject = false,
    this.customOrigin = CustomOrigin.userEntered,
    this.walkthroughOverride,
  });

  factory FigureDraftSnapshot.fromDraft(FigureDraft draft) =>
      FigureDraftSnapshot(
        id: draft.id,
        move: draft.move,
        params: Map.unmodifiable(Map<String, Object?>.of(draft.params)),
        note: draft.note,
        progression: draft.progression,
        schemaVersion: draft.schemaVersion,
        assumedSubject: draft.assumedSubject,
        customOrigin: draft.customOrigin,
        walkthroughOverride: draft.walkthroughOverride,
      );

  final String id;
  final String? move;
  final Map<String, Object?> params;
  final String note;
  final bool progression;
  final int schemaVersion;

  /// Whether the figure's subject was parser-assumed (#460); preserved across
  /// undo/redo and autosave so the non-authoritative marker never silently
  /// disappears while editing.
  final bool assumedSubject;

  /// How the figure originated when it is a custom (see [CustomOrigin]);
  /// preserved across undo/redo and autosave so a free-text/import parser-gap
  /// custom keeps its [CustomOrigin.importGap] flag (#419/#417) while editing.
  final CustomOrigin customOrigin;

  /// The per-dance walkthrough snippet override (#411); preserved across
  /// undo/redo and autosave so an in-progress per-dance snippet is never lost.
  final String? walkthroughOverride;

  FigureDraft toDraft() => FigureDraft(
    id: id,
    move: move,
    params: Map<String, Object?>.of(params),
    note: note,
    progression: progression,
    schemaVersion: schemaVersion,
    assumedSubject: assumedSubject,
    customOrigin: customOrigin,
    walkthroughOverride: walkthroughOverride,
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
    this.walkthrough = '',
    required this.phrase,
    required this.formationDetail,
    required this.form,
    required this.formationShape,
    required this.progression,
    required this.status,
    this.level,
    this.mixedLevel = false,
    this.rating,
    this.composedOn,
    this.revisedOn,
    required this.authorIds,
    required this.tagIds,
    required this.tunes,
    required this.links,
    required this.sourceCitations,
    required this.customValues,
    required this.figureDrafts,
  });

  // ---- Text fields ----
  final String title;
  final String hook;
  final String notes;

  /// Free-form step-by-step walkthrough (issue #370); distinct from [notes].
  final String walkthrough;
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

  /// Curatorial star rating on the closed `1..5` scale; `null` when unrated.
  final int? rating;

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

  // ---- Source citations ----

  /// Ordered citations of reusable [PublishedSource]s (which source, and the
  /// freeform page/number the dance appears at). The [PublishedSource] details
  /// themselves are shared entities edited out-of-band; only the citation
  /// (sourceId + page + number) is part of the editor working state.
  final List<SourceCitation> sourceCitations;

  // ---- Custom fields ----
  final Map<String, Object?> customValues;

  // ---- Figures ----
  final List<FigureDraftSnapshot> figureDrafts;
}
