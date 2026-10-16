import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';
import '../screens/import_user_figures_screen.dart';

/// What applying a shared file's figures did (#1023, plan C12): enough to
/// count it and to undo it.
class AppliedUserFigureImport {
  AppliedUserFigureImport._(this.addedIds, this.replaced, this.failed);

  /// The ids of the figures added, copies under their new ids.
  final List<String> addedIds;

  /// The user's own figures replaced with the sender's, as they were.
  final List<UserGlossaryEntry> replaced;

  /// How many could not be stored or replaced (the glossary was full, the
  /// repository refused one, or the write failed).
  final int failed;

  int get count => addedIds.length + replaced.length;

  /// Removes the figures added, leaving no deletion behind (so a later import
  /// of the same file offers them as new again, and sync has nothing to
  /// publish), and puts back the ones replaced, as a restore does, so the
  /// glossary's budget can't refuse the user's own version. Run after the
  /// import's own undo, which already restored the dances it pointed at a
  /// copy.
  Future<void> undo(CompendiumRepositories repos) async {
    for (final id in addedIds) {
      await repos.userGlossary.delete(id, permanent: true);
    }
    for (final entry in replaced) {
      await repos.userGlossary.upsertFromRestore(entry);
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
/// Never throws: a figure the repository refuses, or whose write fails, is
/// counted in [AppliedUserFigureImport.failed] (and a failure other than a
/// refusal logged), and a failed remap is logged, so what was written is
/// always returned for the Undo. The file is untrusted, and the dances are
/// imported either way.
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
      // diagnostics: silent — the glossary refusing an untrusted file's
      // figure (its bounds, its budget) is expected input, counted and shown
      // to the user, not a fault to log.
      failed++;
    } on Object catch (e, stackTrace) {
      failed++;
      logCaughtError(e, stackTrace, source: 'applyUserFigureImport');
    }
  }
  if (copies.isNotEmpty) {
    try {
      await repos.dances.remapUserFigureUses(
        importedDanceIds,
        copies,
        now: now,
      );
    } on Object catch (e, stackTrace) {
      // The copies stay, for the Undo to remove; the dances keep the ids they
      // came with, and show each use as its line.
      logCaughtError(e, stackTrace, source: 'applyUserFigureImport.remap');
    }
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
