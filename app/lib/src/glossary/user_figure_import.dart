import 'package:compendium_core/compendium_core.dart';

import '../screens/import_user_figures_screen.dart';

/// What applying a shared file's figures did (#1023, plan C12): enough to
/// count it and to undo it.
class AppliedUserFigureImport {
  AppliedUserFigureImport._(this.addedIds, this.replaced, this.failed);

  /// The ids of the figures added, copies under their new ids.
  final List<String> addedIds;

  /// The user's own figures replaced with the sender's, as they were.
  final List<UserGlossaryEntry> replaced;

  /// How many could not be stored (the glossary was full, or the repository
  /// refused one).
  final int failed;

  int get count => addedIds.length + replaced.length;

  /// Removes the figures added and puts back the ones replaced. Run after the
  /// import's own undo, which already restored the dances it pointed at a
  /// copy.
  Future<void> undo(CompendiumRepositories repos) async {
    for (final id in addedIds) {
      await repos.userGlossary.delete(id);
    }
    for (final entry in replaced) {
      await repos.userGlossary.upsert(entry);
    }
  }
}

/// Applies [choices] to [items] ([planUserFigureImport]):
/// - adds each new figure chosen as it came;
/// - adds each copy chosen under an id from [newId], and points the uses in
///   [importedDanceIds], the dances the import wrote, at it;
/// - replaces each of the user's figures chosen with the sender's version,
///   keeping the user's notes on it and when it was made.
///
/// A figure the repository refuses is counted in
/// [AppliedUserFigureImport.failed], never thrown: the file is untrusted, and
/// the dances are imported either way.
Future<AppliedUserFigureImport> applyUserFigureImport(
  CompendiumRepositories repos,
  List<UserFigureImportItem> items,
  UserFigureImportChoices choices, {
  required Iterable<String> importedDanceIds,
  required String Function() newId,
  required DateTime now,
}) async {
  final added = <String>[];
  final replaced = <UserGlossaryEntry>[];
  final copies = <String, String>{};
  var failed = 0;
  for (final item in items) {
    final figure = item.incoming;
    final mine = item.mine;
    try {
      switch (item.kind) {
        case UserFigureImportKind.add when choices.add.contains(figure.id):
          await repos.userGlossary.upsert(figure, at: now);
          added.add(figure.id);
        case UserFigureImportKind.copy when choices.add.contains(figure.id):
          final id = newId();
          await repos.userGlossary.upsert(_withId(figure, id), at: now);
          added.add(id);
          copies[figure.id] = id;
        case UserFigureImportKind.differs
            when mine != null && choices.useTheirs.contains(figure.id):
          await repos.userGlossary.upsert(
            UserGlossaryEntry(
              id: mine.id,
              kindName: mine.kindName,
              name: figure.name,
              definition: figure.definition,
              description: figure.description,
              keywords: figure.keywords,
              notes: mine.notes,
              payload: figure.payload,
              createdAt: mine.createdAt,
            ),
            at: now,
          );
          replaced.add(mine);
        default:
          break;
      }
    } on UserGlossaryEntryInvalid {
      failed++;
    }
  }
  if (copies.isNotEmpty) {
    await repos.dances.remapUserFigureUses(importedDanceIds, copies, now: now);
  }
  return AppliedUserFigureImport._(added, replaced, failed);
}

UserGlossaryEntry _withId(UserGlossaryEntry figure, String id) =>
    UserGlossaryEntry(
      id: id,
      kindName: figure.kindName,
      name: figure.name,
      definition: figure.definition,
      description: figure.description,
      keywords: figure.keywords,
      payload: figure.payload,
      createdAt: figure.createdAt,
    );
