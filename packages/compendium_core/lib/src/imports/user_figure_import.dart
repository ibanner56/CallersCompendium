import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/user_glossary.dart';
import '../storage/shareable_text.dart';

/// What adding a shared figure to this device would do (#1023, maintainer
/// decision 3; plan C12).
enum UserFigureImportKind {
  /// No entry here has its id: it is added as it came.
  add,

  /// One of the user's figures here has its id and the same content: nothing
  /// to do.
  same,

  /// One of the user's figures here has its id and different content: the
  /// user keeps theirs or takes the sender's.
  differs,

  /// Its id is held here by an entry of another kind, or by a figure of the
  /// user's that was deleted: it is added as a copy, under a new id, and the
  /// dances the import wrote are pointed at the copy.
  copy,
}

/// One shared figure, and what adding it would do.
@immutable
final class UserFigureImportItem {
  const UserFigureImportItem({
    required this.incoming,
    required this.kind,
    this.mine,
  });

  /// The figure as the archive carries it ([decodeArchiveUserFigures]).
  final UserGlossaryEntry incoming;

  final UserFigureImportKind kind;

  /// This device's figure under the same id, for [UserFigureImportKind.same]
  /// and [UserFigureImportKind.differs].
  final UserGlossaryEntry? mine;
}

/// What adding each of [incoming], a shared archive's figures, would do, in
/// [incoming]'s order. [entries] are this device's glossary entries, live, of
/// every kind; [deletedIds] the ids of the deleted ones, which an import never
/// brings back to life (a figure deleted here stays deleted, so a shared one
/// with its id comes in as a copy).
///
/// Content is the figure's name, definition, description, keywords and
/// payload. Its notes and creation time are not compared: a shared figure
/// carries no notes, and the same figure keeps the time it was first made.
List<UserFigureImportItem> planUserFigureImport(
  List<UserGlossaryEntry> incoming, {
  required List<UserGlossaryEntry> entries,
  Set<String> deletedIds = const {},
}) {
  final byId = {for (final entry in entries) entry.id: entry};
  return [
    for (final figure in incoming)
      switch (byId[figure.id]) {
        null when !deletedIds.contains(figure.id) => UserFigureImportItem(
          incoming: figure,
          kind: UserFigureImportKind.add,
        ),
        final mine? when mine.kind == UserGlossaryEntryKind.customFigure =>
          UserFigureImportItem(
            incoming: figure,
            mine: mine,
            kind: sameUserFigureContent(mine, figure)
                ? UserFigureImportKind.same
                : UserFigureImportKind.differs,
          ),
        _ => UserFigureImportItem(
          incoming: figure,
          kind: UserFigureImportKind.copy,
        ),
      },
  ];
}

const DeepCollectionEquality _deepEq = DeepCollectionEquality();

/// Whether [a] and [b] define the same figure: the same name, definition,
/// description, keywords and payload. Notes and creation time are not
/// compared.
///
/// Each side is compared in the form the glossary stores
/// ([normalizeShareableText], [normalizeShareableJson]), so a figure read from
/// a file in another Unicode form still matches the copy stored from it.
/// A payload that can't be normalised (two keys that normalise to one) never
/// matches.
bool sameUserFigureContent(UserGlossaryEntry a, UserGlossaryEntry b) {
  String n(String text) => normalizeShareableText(text);
  final Object? payloadA;
  final Object? payloadB;
  try {
    payloadA = normalizeShareableJson(a.payload);
    payloadB = normalizeShareableJson(b.payload);
  } on ShareableJsonKeyCollision {
    return false;
  }
  return n(a.name) == n(b.name) &&
      n(a.definition) == n(b.definition) &&
      n(a.description) == n(b.description) &&
      _deepEq.equals(a.keywords.map(n).toList(), b.keywords.map(n).toList()) &&
      _deepEq.equals(payloadA, payloadB);
}
