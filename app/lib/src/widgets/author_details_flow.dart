import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../screens/settings/library_manager_list.dart';
import 'choreographer_details_dialog.dart';

/// The flows the Authors manager and the dance editor share for editing an
/// author (`docs/design/tags-and-people.md` T3): a name another live author
/// already holds is offered as a merge (D-N2-2, D-N2-4), not refused.

/// A merge the user accepted: [undo] reverses it, and [mergedIds] are every
/// author it combined, now one entry under [survivorId] called [name].
@immutable
class AuthorMerge {
  const AuthorMerge({
    required this.undo,
    required this.survivorId,
    required this.mergedIds,
    required this.name,
  });

  final ReferenceEditUndo undo;

  /// The smallest of [mergedIds] (sync-spec §6.6), whichever author the user
  /// merged into.
  final String survivorId;
  final Set<String> mergedIds;
  final String name;

  /// The snackbar text: "Merged 'X' into 'Y'", or "Combined N authors" when
  /// a rename found more than one author already holding the name.
  String snackText(AppLocalizations l10n, String fromName) =>
      mergedIds.length > 2
      ? l10n.authorManagerMergedSeveralSnack(mergedIds.length, name)
      : l10n.libraryManagerMergedSnack(fromName, name);
}

/// The label of [field], as the details dialogs label it.
String referenceDetailFieldLabel(
  AppLocalizations l10n,
  ReferenceDetailField field,
) => switch (field) {
  ReferenceDetailField.website => l10n.danceEditorWebsiteLabel,
  ReferenceDetailField.email => l10n.danceEditorEmailPrivateLabel,
  ReferenceDetailField.location => l10n.danceEditorLocationPrivateLabel,
  ReferenceDetailField.sourceAuthor => l10n.danceEditorSourceAuthorEditorLabel,
  ReferenceDetailField.year => l10n.danceEditorYearLabel,
  ReferenceDetailField.url => l10n.danceEditorUrlLabel,
  ReferenceDetailField.notes => l10n.danceEditorNotesLabel,
};

/// One line per value [conflicts] drop, for the merge dialogs.
List<String> droppedDetailLines(
  AppLocalizations l10n,
  List<ReferenceMergeConflict> conflicts,
) => [
  for (final conflict in conflicts)
    l10n.libraryManagerMergeDroppedLine(
      referenceDetailFieldLabel(l10n, conflict.field),
      conflict.dropped,
    ),
];

/// [from]'s new name, [typedName], is held by the live authors [liveIds]:
/// offers to merge [from] and all of them into one, listing the details the
/// merge drops for whichever the user picks (D-N2-2 = (b)).
///
/// [from] carries the details that take part: the stored row for a rename,
/// or the details dialog's values when the name was typed there. In the
/// second case [beforeMerge] writes those values first, under the old name,
/// in the same transaction as the merge, so the merge fills from them and an
/// Undo of the merge leaves them saved.
///
/// Returns `null` when the user chose **Keep editing**; the caller re-opens
/// what they typed in. Throws when the merge fails, writing nothing.
Future<AuthorMerge?> offerAuthorMerge(
  BuildContext context,
  CompendiumRepositories repos, {
  required String fromName,
  required Choreographer from,
  required String typedName,
  required List<String> liveIds,
  Future<void> Function()? beforeMerge,
}) async {
  final l10n = AppLocalizations.of(context);
  final matches = <Choreographer>[];
  final entries = <LibraryManagerEntry>[];
  for (final id in liveIds) {
    final match = await repos.choreographers.getById(id);
    if (match == null) continue;
    matches.add(match);
    entries.add(
      LibraryManagerEntry(
        id: id,
        name: match.name,
        liveDanceCount: await repos.references.liveDanceCount(
          ReferenceKind.author,
          id,
        ),
      ),
    );
  }
  // Every holder went between the rename and here: nothing to merge with,
  // so the caller tries the name again.
  if (matches.isEmpty) throw StateError('the authors holding the name went');
  if (!context.mounted) return null;
  final intoId = await showLibraryMergeOffer(
    context,
    fromName: fromName,
    typedName: typedName,
    matches: entries,
    droppedFor: (intoId) => droppedDetailLines(
      l10n,
      authorMergeConflicts(matches.firstWhere((match) => match.id == intoId), [
        from,
        ...matches.where((match) => match.id != intoId),
      ]),
    ),
  );
  if (intoId == null) return null;
  final mergedIds = {from.id, ...liveIds};
  final undo = await repos.transaction(() async {
    await beforeMerge?.call();
    return repos.references.merge(
      ReferenceKind.author,
      intoId: intoId,
      otherIds: mergedIds.where((id) => id != intoId),
      name: typedName,
    );
  });
  return AuthorMerge(
    undo: undo,
    survivorId: (mergedIds.toList()..sort()).first,
    mergedIds: mergedIds,
    name: typedName,
  );
}

/// What [editAuthorDetails] did.
sealed class AuthorDetailsOutcome {
  const AuthorDetailsOutcome();
}

/// The details were saved; [stored] is the row as written.
final class AuthorDetailsSaved extends AuthorDetailsOutcome {
  const AuthorDetailsSaved(this.stored);

  final Choreographer stored;
}

/// The name collided and the user merged.
final class AuthorDetailsMerged extends AuthorDetailsOutcome {
  const AuthorDetailsMerged(this.merge);

  final AuthorMerge merge;
}

/// Opens the author details dialog for [existing] and saves what it returns.
///
/// When the new name is another live author's, offers the merge
/// ([offerAuthorMerge]) instead of refusing it. **Keep editing** re-opens the
/// dialog with what was typed. Returns `null` when the user cancels.
///
/// Throws [DuplicateNaturalKeyError] when the name collided but no live
/// author holds it any more (a sync pass removed it meanwhile), and whatever
/// the write throws otherwise.
Future<AuthorDetailsOutcome?> editAuthorDetails(
  BuildContext context,
  CompendiumRepositories repos,
  Choreographer existing,
) async {
  var draft = existing;
  while (true) {
    if (!context.mounted) return null;
    final updated = await ChoreographerDetailsDialog.show(context, draft);
    if (updated == null || !context.mounted) return null;
    try {
      // Safe discard: `updated` carries the id of the already-persisted
      // `existing` row, so tombstone adoption cannot redirect the id.
      // ignore: unused_result
      await repos.choreographers.upsert(updated, localUserEdit: true);
      return AuthorDetailsSaved(
        await repos.choreographers.getById(existing.id) ?? updated,
      );
    } on DuplicateNaturalKeyError {
      // diagnostics: silent — not a failure: the name is taken, and the
      // merge offer below is the answer to it; rethrown when it is not.
      final liveIds = [
        for (final match in await repos.references.nameMatches(
          ReferenceKind.author,
          updated.name,
          excludeId: existing.id,
        ))
          if (!match.deleted) match.id,
      ];
      if (liveIds.isEmpty || !context.mounted) rethrow;
      final merge = await offerAuthorMerge(
        context,
        repos,
        fromName: existing.name,
        from: updated,
        typedName: updated.name,
        liveIds: liveIds,
        beforeMerge: () async {
          final stored = await repos.choreographers.getById(existing.id);
          if (stored == null) return;
          final details = updated.copyWith(name: stored.name);
          if (details == stored) return;
          // ignore: unused_result
          await repos.choreographers.upsert(details, localUserEdit: true);
        },
      );
      if (merge != null) return AuthorDetailsMerged(merge);
      draft = updated;
    }
  }
}
