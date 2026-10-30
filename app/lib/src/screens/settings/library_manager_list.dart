import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/readable_width.dart';

/// One entry of a [LibraryManagerList]: a tag, an author or a source.
@immutable
class LibraryManagerEntry {
  const LibraryManagerEntry({
    required this.id,
    required this.name,
    required this.liveDanceCount,
  });

  final String id;

  /// What the list shows, searches and sorts by: a tag's or author's name, a
  /// source's title.
  final String name;

  /// Live dances citing the entry. Dances in Recently deleted do not count
  /// (trash-policy (b)); zero shows as **Not used**.
  final int liveDanceCount;
}

/// One action on an entry, offered both in the row's ⋮ menu and in the sheet
/// tapping the row opens.
@immutable
class LibraryManagerAction {
  const LibraryManagerAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  /// Stable within a manager; keys the menu item and the sheet tile
  /// (`<keyPrefix>-action-<id>-<entry id>`).
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// Drawn in the theme's error colour. It opens no confirm: a manager's
  /// delete offers Undo instead (`docs/design/ux.md`, confirm only what Undo
  /// cannot reverse).
  final bool destructive;
}

/// The list shared by the Tags, Authors and Sources managers
/// (`docs/design/tags-and-people.md`, "The manager screens").
///
/// It owns only list state: the search text, the **Not used** filter and the
/// sort. All three are session-only; persisting one would add a settings key,
/// which needs a privacy-registry entry. The screen around it owns loading,
/// the data and every write, and passes the entries in already loaded.
///
/// Each row shows [titleBuilder]'s widget (the entry's name by default), its
/// live dance count, and a trailing ⋮ holding [actionsFor]'s actions. Tapping
/// the row opens the same actions as a bottom sheet. There are no swipe
/// actions: they would be a third gesture model for one list.
///
/// Keys, for tests and for the managers built on it: `<keyPrefix>-search`,
/// `<keyPrefix>-not-used`, `<keyPrefix>-sort`, `<keyPrefix>-row-<id>`,
/// `<keyPrefix>-actions-<id>` and `<keyPrefix>-action-<action id>-<id>`.
class LibraryManagerList extends StatefulWidget {
  const LibraryManagerList({
    required this.keyPrefix,
    required this.entries,
    required this.searchHint,
    required this.emptyMessage,
    required this.actionsFor,
    this.titleBuilder,
    super.key,
  });

  final String keyPrefix;
  final List<LibraryManagerEntry> entries;

  /// The search field's hint, naming the kind ("Search tags").
  final String searchHint;

  /// Shown when there are no entries at all, before any filter.
  final String emptyMessage;

  final List<LibraryManagerAction> Function(LibraryManagerEntry entry)
  actionsFor;

  /// The row's title. Defaults to the entry's name as text; the Tags manager
  /// previews the chip instead.
  final Widget Function(BuildContext context, LibraryManagerEntry entry)?
  titleBuilder;

  @override
  State<LibraryManagerList> createState() => _LibraryManagerListState();
}

/// How a [LibraryManagerList] orders its rows.
enum LibraryManagerSort {
  /// By name, ignoring case.
  name,

  /// Most-cited first, then by name.
  danceCount,
}

class _LibraryManagerListState extends State<LibraryManagerList> {
  final TextEditingController _search = TextEditingController();
  bool _notUsedOnly = false;
  LibraryManagerSort _sort = LibraryManagerSort.name;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LibraryManagerEntry> get _visible {
    final query = naturalKeyMatchKey(_search.text.trim());
    final visible = [
      for (final entry in widget.entries)
        if ((!_notUsedOnly || entry.liveDanceCount == 0) &&
            (query.isEmpty || naturalKeyMatchKey(entry.name).contains(query)))
          entry,
    ];
    int byName(LibraryManagerEntry a, LibraryManagerEntry b) {
      final folded = naturalKeyMatchKey(
        a.name,
      ).compareTo(naturalKeyMatchKey(b.name));
      return folded != 0 ? folded : a.id.compareTo(b.id);
    }

    visible.sort(switch (_sort) {
      LibraryManagerSort.name => byName,
      LibraryManagerSort.danceCount => (a, b) {
        final count = b.liveDanceCount.compareTo(a.liveDanceCount);
        return count != 0 ? count : byName(a, b);
      },
    });
    return visible;
  }

  Future<void> _openSheet(LibraryManagerEntry entry) async {
    final actions = widget.actionsFor(entry);
    final chosen = await showModalBottomSheet<LibraryManagerAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                entry.name,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final action in actions)
              ListTile(
                key: ValueKey(
                  '${widget.keyPrefix}-action-${action.id}-${entry.id}',
                ),
                leading: Icon(
                  action.icon,
                  color: _colour(sheetContext, action),
                ),
                title: Text(
                  action.label,
                  style: TextStyle(color: _colour(sheetContext, action)),
                ),
                onTap: () => Navigator.of(sheetContext).pop(action),
              ),
          ],
        ),
      ),
    );
    // Run the action once the sheet has gone, so a dialog it opens is not
    // stacked over a closing sheet.
    chosen?.onSelected();
  }

  static Color? _colour(BuildContext context, LibraryManagerAction action) =>
      action.destructive ? Theme.of(context).colorScheme.error : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefix = widget.keyPrefix;
    if (widget.entries.isEmpty) {
      return ReadableListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            widget.emptyMessage,
            key: ValueKey('$prefix-empty'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }
    final visible = _visible;
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = readableContentPadding(constraints.maxWidth);
        return Column(
          children: [
            Padding(
              padding: readableContentPadding(
                constraints.maxWidth,
                const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
              ),
              child: TextField(
                key: ValueKey('$prefix-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: widget.searchHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.libraryManagerClearSearch,
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
            Padding(
              padding: readableContentPadding(
                constraints.maxWidth,
                const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
              ),
              child: Row(
                children: [
                  FilterChip(
                    key: ValueKey('$prefix-not-used'),
                    label: Text(l10n.libraryManagerNotUsed),
                    selected: _notUsedOnly,
                    onSelected: (selected) =>
                        setState(() => _notUsedOnly = selected),
                  ),
                  const Spacer(),
                  PopupMenuButton<LibraryManagerSort>(
                    key: ValueKey('$prefix-sort'),
                    tooltip: l10n.libraryManagerSortTooltip,
                    initialValue: _sort,
                    onSelected: (sort) => setState(() => _sort = sort),
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        key: ValueKey('$prefix-sort-name'),
                        value: LibraryManagerSort.name,
                        checked: _sort == LibraryManagerSort.name,
                        child: Text(l10n.libraryManagerSortByName),
                      ),
                      CheckedPopupMenuItem(
                        key: ValueKey('$prefix-sort-count'),
                        value: LibraryManagerSort.danceCount,
                        checked: _sort == LibraryManagerSort.danceCount,
                        child: Text(l10n.libraryManagerSortByDanceCount),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(switch (_sort) {
                            LibraryManagerSort.name =>
                              l10n.libraryManagerSortByName,
                            LibraryManagerSort.danceCount =>
                              l10n.libraryManagerSortByDanceCount,
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? ListView(
                      padding: padding.add(const EdgeInsets.all(AppSpacing.md)),
                      children: [
                        Text(
                          l10n.libraryManagerNoMatches,
                          key: ValueKey('$prefix-no-matches'),
                        ),
                      ],
                    )
                  : ListView.builder(
                      keyboardDismissBehavior: kTextEntryKeyboardDismiss,
                      padding: padding.copyWith(bottom: AppSpacing.lg),
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          _row(context, visible[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, LibraryManagerEntry entry) {
    final l10n = AppLocalizations.of(context);
    final prefix = widget.keyPrefix;
    final actions = widget.actionsFor(entry);
    return ListTile(
      key: ValueKey('$prefix-row-${entry.id}'),
      title: widget.titleBuilder?.call(context, entry) ?? Text(entry.name),
      subtitle: Text(l10n.libraryManagerDanceCount(entry.liveDanceCount)),
      onTap: () => _openSheet(entry),
      trailing: PopupMenuButton<LibraryManagerAction>(
        key: ValueKey('$prefix-actions-${entry.id}'),
        tooltip: l10n.libraryManagerActionsTooltip(entry.name),
        onSelected: (action) => action.onSelected(),
        itemBuilder: (menuContext) => [
          for (final action in actions)
            PopupMenuItem(
              key: ValueKey('$prefix-action-${action.id}-${entry.id}'),
              value: action,
              child: Text(
                action.label,
                style: TextStyle(color: _colour(menuContext, action)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks for a new name for [currentName]. Returns the trimmed name, or `null`
/// when the user cancels or leaves it unchanged or blank.
///
/// [initialText] seeds the field instead of [currentName]: the name typed
/// last time, when the user chose **Keep editing** in [showLibraryMergeOffer].
Future<String?> showLibraryRenameDialog(
  BuildContext context, {
  required String currentName,
  required String fieldLabel,
  String? initialText,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(
      currentName: currentName,
      initialText: initialText ?? currentName,
      fieldLabel: fieldLabel,
    ),
  );
  if (name == null || name.isEmpty || name == currentName) return null;
  return name;
}

/// Owns its controller, so it is disposed with the dialog rather than while
/// the dialog's exit animation still reads it.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.currentName,
    required this.initialText,
    required this.fieldLabel,
  });

  final String currentName;
  final String initialText;
  final String fieldLabel;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialText.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('library-rename-dialog'),
      title: Text(l10n.libraryManagerRenameTitle(widget.currentName)),
      content: TextField(
        key: const ValueKey('library-rename-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.fieldLabel),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          key: const ValueKey('library-rename-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('library-rename-confirm'),
          onPressed: _submit,
          child: Text(l10n.libraryManagerRename),
        ),
      ],
    );
  }
}

/// A searchable picker of the entries [from] can be merged into: every entry
/// in [candidates] other than [from]. Returns the chosen entry, or `null`.
Future<LibraryManagerEntry?> showLibraryMergePicker(
  BuildContext context, {
  required LibraryManagerEntry from,
  required List<LibraryManagerEntry> candidates,
  required String searchHint,
}) => showDialog<LibraryManagerEntry>(
  context: context,
  builder: (_) => _MergePickerDialog(
    from: from,
    candidates:
        [
          for (final entry in candidates)
            if (entry.id != from.id) entry,
        ]..sort(
          (a, b) =>
              naturalKeyMatchKey(a.name).compareTo(naturalKeyMatchKey(b.name)),
        ),
    searchHint: searchHint,
  ),
);

class _MergePickerDialog extends StatefulWidget {
  const _MergePickerDialog({
    required this.from,
    required this.candidates,
    required this.searchHint,
  });

  final LibraryManagerEntry from;
  final List<LibraryManagerEntry> candidates;
  final String searchHint;

  @override
  State<_MergePickerDialog> createState() => _MergePickerDialogState();
}

class _MergePickerDialogState extends State<_MergePickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = naturalKeyMatchKey(_query.trim());
    final matches = [
      for (final entry in widget.candidates)
        if (query.isEmpty || naturalKeyMatchKey(entry.name).contains(query))
          entry,
    ];
    return AlertDialog(
      key: const ValueKey('library-merge-picker'),
      title: Text(l10n.libraryManagerMergePickerTitle(widget.from.name)),
      content: SizedBox(
        width: 400,
        height: 360,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('library-merge-search'),
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.searchHint,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(l10n.libraryManagerNoMatches))
                  : ListView(
                      children: [
                        for (final entry in matches)
                          ListTile(
                            key: ValueKey('library-merge-into-${entry.id}'),
                            title: Text(entry.name),
                            subtitle: Text(
                              l10n.libraryManagerDanceCount(
                                entry.liveDanceCount,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(entry),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

/// Offers to merge [fromName] into the entry already holding [typedName], when
/// a rename collides (`docs/design/tags-and-people.md`, "Rename").
///
/// [matches] are the live entries holding the name as the app matches names.
/// With one, the dialog asks "'Flowy' already exists. Merge 'Flowing' into
/// it?", or names [typedName] as the result when it differs from the
/// match only in case. With several (the `UNIQUE` index compares bytes, so case variants
/// can coexist), it lists them and asks which to merge into, preselecting the
/// one whose bytes equal [typedName]; the rest are merged into it too.
///
/// A question, not a destructive confirm: the merge has an Undo. **Keep
/// editing** and **Merge**, in D-1's order for the discard dialog. Returns
/// the id chosen to merge into, or `null` to keep editing; the caller then
/// re-opens [showLibraryRenameDialog] with the typed name.
Future<String?> showLibraryMergeOffer(
  BuildContext context, {
  required String fromName,
  required String typedName,
  required List<LibraryManagerEntry> matches,
}) => showDialog<String>(
  context: context,
  builder: (_) => _MergeOfferDialog(
    fromName: fromName,
    typedName: typedName,
    matches: matches,
  ),
);

class _MergeOfferDialog extends StatefulWidget {
  const _MergeOfferDialog({
    required this.fromName,
    required this.typedName,
    required this.matches,
  });

  final String fromName;
  final String typedName;
  final List<LibraryManagerEntry> matches;

  @override
  State<_MergeOfferDialog> createState() => _MergeOfferDialogState();
}

class _MergeOfferDialogState extends State<_MergeOfferDialog> {
  late String _intoId = widget.matches
      .firstWhere(
        (entry) => entry.name == widget.typedName,
        orElse: () => widget.matches.first,
      )
      .id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final several = widget.matches.length > 1;
    return AlertDialog(
      key: const ValueKey('library-merge-offer'),
      title: Text(l10n.libraryManagerMergeOfferTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              several
                  ? l10n.libraryManagerMergeOfferSeveral(
                      widget.typedName,
                      widget.fromName,
                    )
                  : widget.matches.single.name == widget.typedName
                  ? l10n.libraryManagerMergeOfferOne(
                      widget.matches.single.name,
                      widget.fromName,
                    )
                  // A case variant: the merged tag takes the typed name, so
                  // the question says so rather than promise the old one.
                  : l10n.libraryManagerMergeOfferOneRenamed(
                      widget.matches.single.name,
                      widget.fromName,
                      widget.typedName,
                    ),
            ),
            if (several)
              RadioGroup<String>(
                groupValue: _intoId,
                onChanged: (id) {
                  if (id != null) setState(() => _intoId = id);
                },
                child: Column(
                  children: [
                    for (final entry in widget.matches)
                      RadioListTile<String>(
                        key: ValueKey('library-merge-offer-${entry.id}'),
                        value: entry.id,
                        title: Text(entry.name),
                        subtitle: Text(
                          l10n.libraryManagerDanceCount(entry.liveDanceCount),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('library-merge-offer-keep-editing'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonKeepEditing),
        ),
        FilledButton(
          key: const ValueKey('library-merge-offer-merge'),
          onPressed: () => Navigator.of(context).pop(_intoId),
          child: Text(l10n.libraryManagerMerge),
        ),
      ],
    );
  }
}
