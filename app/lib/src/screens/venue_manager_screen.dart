import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import 'venue_editor_sheet.dart';

/// A full-screen manager to browse, search, create, edit, and delete the
/// reusable [Venue] records. Reached from Settings ▸ Venues.
///
/// Deletion is **irreversible from the UI but soft at the storage layer**, and
/// guarded: the repository throws when a venue is still referenced by a
/// program's `venueId`. That guard error is caught and surfaced as a friendly
/// message rather than crashing (the user must unlink the venue from those
/// programs first).
///
/// The two halves of that first clause were previously stated as one — the doc
/// read "deletion is permanent (venues are not soft-deleted)", which is true of
/// what the user can do and false of what the database holds.
/// `VenueRepository.delete` tombstones via `stampExistenceTransition` unless
/// `permanent: true`, which this screen never passes, and venues have no
/// entry in the recently-deleted screen — so nothing can bring one back, while
/// the row itself survives.
///
/// The distinction is load-bearing in both directions: the tombstone write is
/// what re-emits on the watched stream below (a hard delete would too, but the
/// row would be gone rather than filtered), and a surviving row is data that
/// export and any future device sync must account for. Reads filter
/// `deleted_at IS NULL`, so a deleted venue is absent from every list here.
class VenueManagerScreen extends StatefulWidget {
  const VenueManagerScreen({super.key});

  @override
  State<VenueManagerScreen> createState() => _VenueManagerScreenState();
}

class _VenueManagerScreenState extends State<VenueManagerScreen> {
  final TextEditingController _searchController = TextEditingController();

  late CompendiumRepositories _repos;
  bool _started = false;
  bool _loading = true;
  Object? _error;
  List<Venue> _venues = const [];
  String _query = '';

  /// The live venue catalogue (issue #768).
  ///
  /// Replaces a one-shot read plus a `_load()` after each of this screen's own
  /// writes. That worked only because this screen was the sole writer of the
  /// table while it was mounted — a property of where it happens to be mounted
  /// rather than of the code, and precisely the assumption that broke for the
  /// kept-alive Collection and Programs lists when their parenting changed
  /// underneath it.
  StreamSubscription<List<Venue>>? _venuesSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _subscribe();
    }
  }

  void _subscribe() {
    _venuesSub = _repos.venues.watchAll().listen(
      (venues) {
        if (!mounted) return;
        setState(() {
          _venues = venues;
          _loading = false;
          _error = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Could not load venues: $error\n$stackTrace');
        }
        logCaughtError(
          error,
          stackTrace,
          source: 'venue_manager_screen._subscribe',
        );
        if (!mounted) return;
        setState(() {
          _error = error;
          _loading = false;
        });
      },
    );
  }

  /// Retry after a load error. The stream may have terminated with it, so the
  /// old subscription is cancelled and a new one opened rather than waiting for
  /// an emit a closed source will never produce.
  void _retry() {
    unawaited(_venuesSub?.cancel());
    _venuesSub = null;
    setState(() {
      _loading = true;
      _error = null;
    });
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_venuesSub?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  List<Venue> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _venues;
    return _venues
        .where((v) => v.displayName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _create() async {
    final created = await VenueEditorSheet.show(context);
    if (created == null || !mounted) return;
    await _repos.venues.upsert(created);
    // No reload: the upsert writes `venues`, which this screen watches.
  }

  Future<void> _edit(Venue venue) async {
    final updated = await VenueEditorSheet.show(context, initial: venue);
    if (updated == null || !mounted) return;
    await _repos.venues.upsert(updated);
    // No reload: the upsert writes `venues`, which this screen watches.
  }

  Future<void> _confirmDelete(Venue venue) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.venueManagerDeleteTitle),
        content: Text(l10n.venueManagerDeleteBody(venue.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('venue-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _delete(venue);
  }

  Future<void> _delete(Venue venue) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await _repos.venues.delete(venue.id);
      // No reload: the delete tombstones the row in `venues`, which this
      // screen watches, so the list drops it without being told.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.venueManagerDeletedSnack(venue.name))),
      );
    } on StateError catch (e, stackTrace) {
      // The delete guard fired: the venue is still linked to one or more
      // programs. Surface a friendly, actionable message instead of crashing.
      logCaughtError(e, stackTrace, source: 'venue_manager_screen._delete');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('venue-delete-blocked'),
          content: Text(l10n.venueManagerDeleteBlocked(venue.name)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.venueManagerTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('venue-manager-add'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(l10n.venueNew),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('venue-manager-search'),
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.venueManagerSearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.venueManagerClearSearchTooltip,
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.venueLoadError),
            const SizedBox(height: 8),
            TextButton(onPressed: _retry, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }
    if (_venues.isEmpty) {
      return Center(
        key: const ValueKey('venue-manager-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.venueManagerEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return Center(
        key: const ValueKey('venue-manager-no-matches'),
        child: Text(l10n.venueManagerNoMatches),
      );
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final venue = filtered[index];
        return ListTile(
          key: ValueKey('venue-manager-tile-${venue.id}'),
          leading: const Icon(Icons.place_outlined),
          title: Text(venue.name),
          subtitle: venue.displayName == venue.name
              ? null
              : Text(venue.displayName),
          onTap: () => _edit(venue),
          trailing: IconButton(
            key: ValueKey('venue-manager-delete-${venue.id}'),
            tooltip: l10n.venueManagerDeleteTooltip(venue.name),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(venue),
          ),
        );
      },
    );
  }
}
