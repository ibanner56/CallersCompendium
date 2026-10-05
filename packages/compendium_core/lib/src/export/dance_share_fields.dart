import '../model/dance.dart';

/// The non-figures [Dance] fields a user can choose to include when a
/// program or dance is shared/copied/PDF'd (issue #1434).
///
/// Figures are deliberately excluded: they have their own long-standing,
/// separate opt-in (`ProgramFiguresPromptDialog`) and are not part of this
/// picker. Each value gates one block in `danceToPlainText`, the renderer
/// this PR wires it into; see that function's doc comment for the exact
/// line each one controls. The app's PDF dance-card renderers
/// (`dance_pdf.dart`, `program_pdf.dart`) gate on the same values: both build
/// a `DanceCardContent` from the chosen set and only lay it out.
///
/// Follows the same shape as `CollectionTileField` (issue #767,
/// `app/lib/src/data/collection_tile_fields_scope.dart`): a stable
/// `name`-keyed JSON codec so the app layer can persist a `Set<DanceShareField>`
/// under a single settings key, with open-world forward/backward
/// compatibility (an unrecognised stored name is ignored rather than
/// rejecting the whole preference).
enum DanceShareField {
  /// The dance's resolved author/choreographer names.
  authors,

  /// The dance's formation label.
  formation,

  /// The dance's resolved difficulty-level label.
  level,

  /// The mixer-dance flag line.
  mixer,

  /// The dance's status label (only ever shown for a non-active dance).
  status,

  /// The dance's non-standard phrase-structure notation.
  phraseStructure,

  /// The dance's calling notes.
  callingNotes,

  /// The dance's walkthrough text.
  walkthrough,

  /// The dance's suggested tune list. Unlike every other value here, no
  /// current renderer emits this field at all — enabling it is what actually
  /// turns tune rendering on for the first time (issue #1434).
  tunes;

  /// Every field, including [tunes]. Not the default for a fresh install —
  /// see [allExceptTunes].
  static const Set<DanceShareField> all = {
    DanceShareField.authors,
    DanceShareField.formation,
    DanceShareField.level,
    DanceShareField.mixer,
    DanceShareField.status,
    DanceShareField.phraseStructure,
    DanceShareField.callingNotes,
    DanceShareField.walkthrough,
    DanceShareField.tunes,
  };

  /// Every field the renderers already emit unconditionally today, minus
  /// [tunes]. This is the default for a fresh install / untouched setting,
  /// so a user who never opens the new Settings picker sees no change to
  /// their existing exports.
  static const Set<DanceShareField> allExceptTunes = {
    DanceShareField.authors,
    DanceShareField.formation,
    DanceShareField.level,
    DanceShareField.mixer,
    DanceShareField.status,
    DanceShareField.phraseStructure,
    DanceShareField.callingNotes,
    DanceShareField.walkthrough,
  };

  /// Encodes this field as a stable JSON string. Must not be renamed — the
  /// value is persisted in settings.
  String toJson() => name;

  /// Decodes a JSON string produced by [toJson]. Returns `null` for an
  /// unrecognised value so open-world safety is handled at the call site.
  static DanceShareField? fromJson(String raw) {
    for (final f in DanceShareField.values) {
      if (f.name == raw) return f;
    }
    return null;
  }
}
