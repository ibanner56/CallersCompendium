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

  /// The dance's suggested tune list. Like [hook] and [sources], no renderer
  /// emitted this field before the picker existed — enabling it is what
  /// actually turns tune rendering on for the first time (issue #1434).
  tunes,

  /// The dance's hook. Like [tunes], no renderer emitted it before this value
  /// existed, so it is off until selected (OUT-6).
  hook,

  /// The dance's published-source citations (title, author/year, page and
  /// number). Off until selected, like [tunes] (OUT-6). The app resolves each
  /// citation to a display line; this core only gates and lays them out.
  sources,

  /// The dance's tune details: its meter and key on one line, and its Barnes
  /// reference (where the tune is printed in the Barnes books) on another.
  /// On by default, unlike [tunes]: Hudson chose this when the field was
  /// added. Only a fresh or untouched setting picks it up, since a saved
  /// selection that predates it does not list it.
  music;

  /// Every field, including [tunes], [hook] and [sources]. Not the default for
  /// a fresh install — see [allExceptTunes].
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
    DanceShareField.hook,
    DanceShareField.sources,
    DanceShareField.music,
  };

  /// The default for a fresh install / untouched setting: every field the
  /// renderers emitted unconditionally before the picker existed, plus
  /// [music], which is on by default. The opt-in [tunes], [hook] and
  /// [sources] are left out.
  ///
  /// The name predates [hook], [sources] and [music]; it is kept because
  /// renaming a public constant would ripple through every call site.
  static const Set<DanceShareField> allExceptTunes = {
    DanceShareField.authors,
    DanceShareField.formation,
    DanceShareField.level,
    DanceShareField.mixer,
    DanceShareField.status,
    DanceShareField.phraseStructure,
    DanceShareField.callingNotes,
    DanceShareField.walkthrough,
    DanceShareField.music,
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

/// The dance-card fields a dances spreadsheet (CSV) export carries (#2332):
/// every one. A spreadsheet has one column per field, so it does not follow
/// the caller's **Choose which dance fields appear** selection, which shapes
/// cards, set lists and PDFs. Kept here, beside the other field sets, so the
/// app's export code chooses no fields of its own.
const Set<DanceShareField> spreadsheetDanceFields = DanceShareField.all;
