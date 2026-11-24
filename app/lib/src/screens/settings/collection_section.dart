// Part of the Settings screen, split by section.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/capitalize_figures_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/sort_ignore_articles_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/saved_search_actions.dart';
import '../../widgets/section_header.dart';
import '../reference_manager_screen.dart';
import '../tag_manager_screen.dart';
import 'settings_keys.dart';

/// The Collection settings section: the **Dances** group (moved here from
/// General: how titles sort, how figures are written, and the managers for
/// tags, authors and sources), then the user's **Saved searches** (#2325),
/// each of which can be renamed or deleted (with Undo) here.
///
/// A saved search is saved, loaded and updated from the Collection itself (its
/// ⋮ menu and its search field); this list is where every one of them,
/// including one this version cannot read, can be seen and removed.
class CollectionSection extends StatefulWidget {
  const CollectionSection({super.key});

  @override
  State<CollectionSection> createState() => _CollectionSectionState();
}

class _CollectionSectionState extends State<CollectionSection> {
  List<StoredSavedSearch>? _saved;
  int _readSeq = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final seq = ++_readSeq;
    try {
      final saved = await RepositoriesScope.of(context).savedSearches.list();
      if (!mounted || seq != _readSeq) return;
      setState(() => _saved = saved);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'collection_section._read');
      if (mounted) setState(() => _saved = const []);
    }
  }

  Future<void> _onSortIgnoreArticlesChanged(bool value) async {
    // Flip the live notifier so the dance list re-sorts immediately, then
    // persist in the background.
    SortIgnoreArticlesScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kSortIgnoreArticlesKey, value);
  }

  Future<void> _onCapitalizeFiguresChanged(bool value) async {
    CapitalizeFiguresScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kCapitalizeFiguresKey, value);
  }

  /// Rename and delete need no panel, clock or dialect: they never read or
  /// write a search's content.
  SavedSearchActions _actions() => SavedSearchActions(
    context,
    clock: const SearchClock(),
    dialect: Dialect.larksRobins,
    enrichment: SearchEnrichment.empty,
  );

  Future<void> _rename(SavedSearch search) async {
    if (await _actions().rename(search) != null) await _read();
  }

  Future<void> _delete(String id, String label) async {
    final deleted = await _actions().delete(id, label, onUndone: _read);
    if (deleted) await _read();
  }

  Future<void> _unreadable(String id) async {
    final deleted = await _actions().showUnreadable(id, onUndone: _read);
    if (deleted) await _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saved = _saved;
    final readable = [
      for (final s in saved ?? const <StoredSavedSearch>[]) ?s.search,
    ];
    final unreadable = [
      for (final s in saved ?? const <StoredSavedSearch>[])
        if (s.search == null) s,
    ];
    return ListView(
      keyboardDismissBehavior: textEntryKeyboardDismiss(),
      children: [
        SectionHeader(title: l10n.settingsGeneralLibraryHeader),
        SwitchListTile(
          key: const ValueKey('collection-sort-ignore-articles'),
          value: SortIgnoreArticlesScope.of(context),
          onChanged: _onSortIgnoreArticlesChanged,
          title: Text(l10n.settingsGeneralSortIgnoreArticlesTitle),
          subtitle: Text(l10n.settingsGeneralSortIgnoreArticlesSubtitle),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('collection-capitalize-figures'),
          value: CapitalizeFiguresScope.of(context),
          onChanged: _onCapitalizeFiguresChanged,
          title: Text(l10n.settingsGeneralCapitalizeFiguresTitle),
          subtitle: Text(l10n.settingsGeneralCapitalizeFiguresSubtitle),
          isThreeLine: true,
        ),
        ListTile(
          key: const ValueKey('collection-library-tags'),
          leading: const Icon(Icons.label_outline),
          title: Text(l10n.settingsGeneralLibraryTagsTitle),
          subtitle: Text(l10n.settingsGeneralLibraryTagsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TagManagerScreen()),
          ),
        ),
        ListTile(
          key: const ValueKey('collection-library-authors'),
          leading: const Icon(Icons.person_outline),
          title: Text(l10n.settingsGeneralLibraryAuthorsTitle),
          subtitle: Text(l10n.settingsGeneralLibraryAuthorsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ReferenceManagerScreen.authors(),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('collection-library-sources'),
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(l10n.settingsGeneralLibrarySourcesTitle),
          subtitle: Text(l10n.settingsGeneralLibrarySourcesSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ReferenceManagerScreen.sources(),
            ),
          ),
        ),
        SectionHeader(title: l10n.settingsSavedSearchesHeader),
        if (saved != null && saved.isEmpty)
          ListTile(
            key: const ValueKey('settings-saved-searches-none'),
            title: Text(l10n.settingsSavedSearchesEmpty),
          ),
        for (final search in readable)
          ListTile(
            key: ValueKey('settings-saved-search-${search.id}'),
            leading: const Icon(Icons.bookmark_border),
            title: Text(search.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey('settings-saved-search-rename-${search.id}'),
                  tooltip: l10n.settingsSavedSearchRenameTooltip(search.name),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _rename(search),
                ),
                IconButton(
                  key: ValueKey('settings-saved-search-delete-${search.id}'),
                  tooltip: l10n.settingsSavedSearchDeleteTooltip(search.name),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(search.id, search.name),
                ),
              ],
            ),
          ),
        if (unreadable.isNotEmpty) ...[
          SectionHeader(title: l10n.savedSearchNeedsAttention),
          for (final entry in unreadable)
            ListTile(
              key: ValueKey(
                'settings-saved-search-unreadable-${entry.savedSearchId}',
              ),
              leading: Icon(
                Icons.warning_amber,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l10n.savedSearchUnreadableItem),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _unreadable(entry.savedSearchId),
            ),
        ],
      ],
    );
  }
}
