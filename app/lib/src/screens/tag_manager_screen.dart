import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../data/tag_edits.dart';
import '../diagnostics/error_log.dart';
import '../widgets/color_edit_dialog.dart';
import '../widgets/load_error_view.dart';
import '../widgets/tag_chip.dart';
import '../utils/undo_snack_bar.dart';
import 'settings/library_manager_list.dart';

/// The Tags manager (FIND-3, `docs/design/tags-and-people.md` T2): rename,
/// merge, colour and delete tags. Reached from Settings › General › Library ›
/// Tags, and from Settings › Appearance › Tag colours, which used to open a
/// colours-only screen this one replaced (D-N2-3).
///
/// Every change writes at once and offers Undo in a snackbar, the only Undo
/// there is (D-N2-5). A delete therefore has no confirm (`ux.md`: confirm only
/// what Undo cannot reverse). Rename, merge and delete go through
/// `tag_edits.dart`, which rewrites the import-tags setting in the same
/// transaction. A colour is an ordinary edit of the tag row and has no Undo,
/// as on the colours screen before it.
///
/// The list is live: tags through [TagRepository.watchAll], and each tag's
/// count of live dances through
/// [ReferenceEditRepository.watchLiveDanceCounts], so an edit made anywhere,
/// a sync pass included, reaches it without this screen being told.
class TagManagerScreen extends StatefulWidget {
  const TagManagerScreen({super.key});

  @override
  State<TagManagerScreen> createState() => _TagManagerScreenState();
}

class _TagManagerScreenState extends State<TagManagerScreen> {
  late CompendiumRepositories _repos;
  bool _started = false;

  List<Tag>? _tags;
  Map<String, int>? _counts;
  Object? _loadError;

  StreamSubscription<List<Tag>>? _tagsSub;
  StreamSubscription<Map<String, int>>? _countsSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repos = RepositoriesScope.of(context);
    _subscribe();
  }

  void _subscribe() {
    void onError(Object e, StackTrace stackTrace) {
      logCaughtError(e, stackTrace, source: 'tag_manager_screen._subscribe');
      if (!mounted) return;
      setState(() => _loadError = e);
    }

    _tagsSub = _repos.tags.watchAll().listen((tags) {
      if (!mounted) return;
      setState(() => _tags = tags);
    }, onError: onError);
    _countsSub = _repos.references
        .watchLiveDanceCounts(ReferenceKind.tag)
        .listen((counts) {
          if (!mounted) return;
          setState(() => _counts = counts);
        }, onError: onError);
  }

  /// A stream that failed may have closed, so both are re-opened rather than
  /// waiting for an emit that will not come.
  void _retry() {
    unawaited(_tagsSub?.cancel());
    unawaited(_countsSub?.cancel());
    setState(() {
      _tags = null;
      _counts = null;
      _loadError = null;
    });
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_tagsSub?.cancel());
    unawaited(_countsSub?.cancel());
    super.dispose();
  }

  List<LibraryManagerEntry> get _entries => [
    for (final tag in _tags ?? const <Tag>[])
      LibraryManagerEntry(
        id: tag.id,
        name: tag.name,
        liveDanceCount: _counts?[tag.id] ?? 0,
      ),
  ];

  Tag? _tag(String id) {
    for (final tag in _tags ?? const <Tag>[]) {
      if (tag.id == id) return tag;
    }
    return null;
  }

  List<LibraryManagerAction> _actionsFor(LibraryManagerEntry entry) {
    final l10n = AppLocalizations.of(context);
    final coloured = _tag(entry.id)?.color != null;
    return [
      LibraryManagerAction(
        id: 'rename',
        label: l10n.libraryManagerRename,
        icon: Icons.edit_outlined,
        onSelected: () => unawaited(_rename(entry)),
      ),
      LibraryManagerAction(
        id: 'merge',
        label: l10n.libraryManagerMergeInto,
        icon: Icons.merge_type,
        onSelected: () => unawaited(_mergeInto(entry)),
      ),
      LibraryManagerAction(
        id: 'colour',
        label: l10n.tagManagerColour,
        icon: Icons.palette_outlined,
        onSelected: () => unawaited(_editColour(entry)),
      ),
      if (coloured)
        LibraryManagerAction(
          id: 'remove-colour',
          label: l10n.tagManagerRemoveColour,
          icon: Icons.format_color_reset_outlined,
          onSelected: () => unawaited(_setColour(entry.id, null)),
        ),
      LibraryManagerAction(
        id: 'delete',
        label: l10n.commonDelete,
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: () => unawaited(_delete(entry)),
      ),
    ];
  }

  Future<void> _rename(LibraryManagerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final name = await showLibraryRenameDialog(
      context,
      currentName: entry.name,
      fieldLabel: l10n.tagManagerNameLabel,
    );
    if (name == null || !mounted) return;
    try {
      final edit = await renameTag(_repos, entry.id, name);
      _offerUndo(edit, l10n.tagManagerRenamedSnack(entry.name, name));
    } on ReferenceNameTakenException catch (taken) {
      await _offerMerge(entry, name, taken.liveIds);
    } catch (e, stackTrace) {
      _reportFailure(e, stackTrace, 'tag_manager_screen._rename');
    }
  }

  /// The rename collided with [liveIds]: offer to merge [entry] and all of
  /// them into one tag under [typedName], into the one the user picks.
  Future<void> _offerMerge(
    LibraryManagerEntry entry,
    String typedName,
    List<String> liveIds,
  ) async {
    final l10n = AppLocalizations.of(context);
    final matches = <LibraryManagerEntry>[];
    for (final id in liveIds) {
      final tag = _tag(id) ?? await _repos.tags.getById(id);
      if (tag == null) continue;
      matches.add(
        LibraryManagerEntry(
          id: id,
          name: tag.name,
          liveDanceCount: _counts?[id] ?? 0,
        ),
      );
    }
    if (matches.isEmpty || !mounted) return;
    final intoId = await showLibraryMergeOffer(
      context,
      fromName: entry.name,
      typedName: typedName,
      matches: matches,
    );
    if (intoId == null || !mounted) return;
    try {
      final edit = await mergeTags(
        _repos,
        intoId: intoId,
        otherIds: [entry.id, ...liveIds.where((id) => id != intoId)],
        name: typedName,
      );
      _offerUndo(
        edit,
        matches.length == 1
            ? l10n.tagManagerMergedSnack(entry.name, typedName)
            : l10n.tagManagerMergedSeveralSnack(matches.length + 1, typedName),
      );
    } catch (e, stackTrace) {
      _reportFailure(e, stackTrace, 'tag_manager_screen._offerMerge');
    }
  }

  Future<void> _mergeInto(LibraryManagerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final into = await showLibraryMergePicker(
      context,
      from: entry,
      candidates: _entries,
      searchHint: l10n.tagManagerSearchHint,
    );
    if (into == null || !mounted) return;
    try {
      final edit = await mergeTags(
        _repos,
        intoId: into.id,
        otherIds: [entry.id],
      );
      _offerUndo(edit, l10n.tagManagerMergedSnack(entry.name, into.name));
    } catch (e, stackTrace) {
      _reportFailure(e, stackTrace, 'tag_manager_screen._mergeInto');
    }
  }

  Future<void> _delete(LibraryManagerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    try {
      final edit = await deleteTag(_repos, entry.id);
      _offerUndo(
        edit,
        l10n.tagManagerDeletedSnack(entry.name, edit.liveDanceCount),
      );
    } catch (e, stackTrace) {
      _reportFailure(e, stackTrace, 'tag_manager_screen._delete');
    }
  }

  void _offerUndo(TagEdit edit, String message) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repos = _repos;
    showUndoSnackBar(
      messenger,
      key: const ValueKey('tag-manager-undo-snackbar'),
      actionKey: const ValueKey('tag-manager-undo'),
      message: message,
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        try {
          await undoTagEdit(repos, edit);
        } on ReferenceUndoConflictException catch (conflict, stackTrace) {
          // Says more than the generic failure, so it reports itself and
          // does not throw (see showUndoSnackBar).
          logCaughtError(
            conflict,
            stackTrace,
            source: 'tag_manager_screen.undo',
          );
          if (!messenger.mounted) return;
          messenger
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                key: const ValueKey('tag-manager-undo-conflict'),
                content: Text(l10n.libraryManagerUndoConflict(conflict.name)),
              ),
            );
        }
      },
    );
  }

  void _reportFailure(Object e, StackTrace stackTrace, String source) {
    logCaughtError(e, stackTrace, source: source);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).libraryManagerEditFailed),
      ),
    );
  }

  Future<void> _editColour(LibraryManagerEntry entry) async {
    final tag = _tag(entry.id);
    if (tag == null) return;
    // Seed from the tag's current colour, else the theme's primary so the user
    // starts from an on-theme colour rather than plain black.
    final seed = tag.color == null
        ? Theme.of(context).colorScheme.primary
        : Color(tag.color!);
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorEditDialog(title: tag.name, initial: seed),
    );
    if (picked == null || !mounted) return;
    // Stored fully opaque, matching what the picker produces and what
    // `normalizeArgb` guarantees for every colour that reaches storage.
    await _setColour(entry.id, picked.toARGB32() | 0xFF000000);
  }

  Future<void> _setColour(String id, int? color) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      // Read the row afresh rather than from the list, so a rename that has
      // not reached the stream yet is not written back over.
      final tag = await _repos.tags.getById(id);
      if (tag == null) return;
      // Safe discard: withColor keeps the id, so no tombstone can be adopted
      // and the returned id is always this one.
      // ignore: unused_result
      await _repos.tags.upsert(tag.withColor(color), localUserEdit: true);
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'tag_manager_screen._setColour',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsTagColoursSaveError)),
      );
    }
    // No local splice: the upsert writes `tags`, which this screen watches, so
    // the new colour arrives through the stream.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loading = _tags == null || _counts == null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tagManagerTitle)),
      body: _loadError != null
          ? LoadErrorView(
              message: l10n.settingsTagColoursLoadError,
              onRetry: _retry,
            )
          : loading
          ? const Center(child: CircularProgressIndicator())
          : LibraryManagerList(
              keyPrefix: 'tag',
              entries: _entries,
              searchHint: l10n.tagManagerSearchHint,
              emptyMessage: l10n.settingsTagColoursEmpty,
              actionsFor: _actionsFor,
              // Preview the exact chip the collection and dance detail draw,
              // so a colour picked here is what the user gets there.
              titleBuilder: (context, entry) => Align(
                alignment: Alignment.centerLeft,
                child: TagChip(name: entry.name, color: _tag(entry.id)?.color),
              ),
            ),
    );
  }
}
