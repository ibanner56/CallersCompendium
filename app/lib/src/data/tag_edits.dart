import 'package:compendium_core/compendium_core.dart';

import 'display_defaults.dart';

/// One rename, merge or delete of tags from the Tags manager, kept in memory
/// for its Undo (D-N2-5: the snackbar is the only Undo, and nothing is stored).
///
/// Wraps core's [ReferenceEditUndo] with what the same transaction did to
/// [kDefaultImportTagNamesKey], which core cannot rewrite because the key is
/// the app's (`docs/design/tags-and-people.md`, "The import-tags setting").
final class TagEdit {
  TagEdit._(this._core, this._importTagsBefore, this._importTagsAfter);

  final ReferenceEditUndo _core;

  /// The setting's stored value before the edit, and the value the edit wrote.
  /// Both `null` when the edit left the setting alone.
  final Object? _importTagsBefore;
  final String? _importTagsAfter;

  /// Live dances the edit changed: for a delete, the dances the tag was taken
  /// off. Dances in Recently deleted lose it too but are not counted.
  int get liveDanceCount => _core.liveDanceCount;
}

/// Renames the live tag [id] to [name], and the import-tags setting with it.
///
/// Throws [ReferenceNameTakenException], writing nothing, when a live tag
/// already holds the name; the caller offers [mergeTags].
Future<TagEdit> renameTag(
  CompendiumRepositories repos,
  String id,
  String name,
) => _withImportTags(
  repos,
  ids: [id],
  survivorOf: (_) => id,
  edit: () => repos.references.rename(ReferenceKind.tag, id, name),
);

/// Merges [otherIds] into [intoId] (see [ReferenceEditRepository.merge]), and
/// replaces every merged tag's name in the import-tags setting with the
/// result's, keeping one.
Future<TagEdit> mergeTags(
  CompendiumRepositories repos, {
  required String intoId,
  required Iterable<String> otherIds,
  String? name,
}) {
  final ids = {intoId, ...otherIds}.toList();
  return _withImportTags(
    repos,
    ids: ids,
    // The surviving id is the smallest, whichever tag the user chose
    // (sync-spec §6.6); the merged tag's name is read back from it.
    survivorOf: (ids) => (ids.toList()..sort()).first,
    edit: () => repos.references.merge(
      ReferenceKind.tag,
      intoId: intoId,
      otherIds: otherIds,
      name: name,
    ),
  );
}

/// Takes the tag [id] off every dance and deletes it (D-N2-7), and drops its
/// name from the import-tags setting, so a tag created later under that name
/// does not join imports without the user choosing it.
Future<TagEdit> deleteTag(CompendiumRepositories repos, String id) =>
    _withImportTags(
      repos,
      ids: [id],
      survivorOf: (_) => null,
      edit: () => repos.references.deleteTag(id),
    );

/// Reverses [edit], and puts the import-tags setting back as it was.
///
/// The setting is restored only while it still holds what the edit wrote: a
/// change made since, in Settings or by a sync pass, is newer than the edit
/// and stays. Throws [ReferenceUndoConflictException], writing nothing, as
/// [ReferenceEditRepository.undo] does.
Future<void> undoTagEdit(CompendiumRepositories repos, TagEdit edit) =>
    repos.transaction(() async {
      await repos.references.undo(edit._core);
      final after = edit._importTagsAfter;
      if (after == null) return;
      if (await repos.settings.get(kDefaultImportTagNamesKey) != after) return;
      await repos.settings.set(
        kDefaultImportTagNamesKey,
        edit._importTagsBefore,
      );
    });

/// Runs [edit] and rewrites the import-tags setting in one `repos.transaction`,
/// so a failure in either leaves both as they were.
///
/// Each of [ids]' names before the edit is replaced by the name of the tag
/// [survivorOf] picks afterwards, or dropped when it picks none. Names are
/// matched exactly, as `resolveDefaultImportTagIds` matches them at import.
/// An unreadable setting is left alone, as import treats it as empty.
Future<TagEdit> _withImportTags(
  CompendiumRepositories repos, {
  required List<String> ids,
  required String? Function(Iterable<String> ids) survivorOf,
  required Future<ReferenceEditUndo> Function() edit,
}) => repos.transaction(() async {
  final namesBefore = <String>{
    for (final id in ids) ?(await repos.tags.getById(id))?.name,
  };
  final core = await edit();

  final stored = await repos.settings.get(kDefaultImportTagNamesKey);
  final configured = tryDecodeDefaultImportTagNames(stored);
  if (configured == null || !configured.any(namesBefore.contains)) {
    return TagEdit._(core, null, null);
  }
  final survivor = survivorOf(ids);
  final replacement = survivor == null
      ? null
      : (await repos.tags.getById(survivor))?.name;
  final rewritten = encodeDefaultImportTagNames([
    for (final name in configured)
      if (!namesBefore.contains(name)) name else ?replacement,
  ]);
  if (rewritten == stored) return TagEdit._(core, null, null);
  await repos.settings.set(kDefaultImportTagNamesKey, rewritten);
  return TagEdit._(core, stored, rewritten);
});
