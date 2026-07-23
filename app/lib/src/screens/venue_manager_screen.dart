import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import 'venue_editor_sheet.dart';

/// A full-screen manager to browse, search, create, edit, and delete the
/// reusable [Venue] records. Reached from Settings ▸ Venues.
///
/// Deletion is permanent (venues are not soft-deleted) and guarded: the
/// repository throws when a venue is still referenced by a program's
/// `venueId`. That guard error is caught and surfaced as a friendly message
/// rather than crashing (the user must unlink the venue from those programs
/// first).
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final venues = await _repos.venues.listAll();
      if (!mounted) return;
      setState(() {
        _venues = venues;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load venues: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
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
    if (!mounted) return;
    await _load();
  }

  Future<void> _edit(Venue venue) async {
    final updated = await VenueEditorSheet.show(context, initial: venue);
    if (updated == null || !mounted) return;
    await _repos.venues.upsert(updated);
    if (!mounted) return;
    await _load();
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
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.venueManagerDeletedSnack(venue.name))),
      );
    } on StateError {
      // The delete guard fired: the venue is still linked to one or more
      // programs. Surface a friendly, actionable message instead of crashing.
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
            TextButton(onPressed: _load, child: Text(l10n.commonRetry)),
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
