import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

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
    } catch (error) {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete venue?'),
        content: Text(
          'Permanently delete “${venue.name}”? This can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('venue-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _delete(venue);
  }

  Future<void> _delete(Venue venue) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repos.venues.delete(venue.id);
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted “${venue.name}”')),
      );
    } on StateError {
      // The delete guard fired: the venue is still linked to one or more
      // programs. Surface a friendly, actionable message instead of crashing.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('venue-delete-blocked'),
          content: Text(
            'Can’t delete “${venue.name}” while it’s still linked to a '
            'program. Change or remove its venue on those programs first.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Venues')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('venue-manager-add'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New venue'),
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
                hintText: 'Search venues…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load venues.'),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_venues.isEmpty) {
      return const Center(
        key: ValueKey('venue-manager-empty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No venues yet. Add one with the button below, or from a program '
            'when reusable venues are turned on.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return const Center(
        key: ValueKey('venue-manager-no-matches'),
        child: Text('No venues match your search.'),
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
            tooltip: 'Delete ${venue.name}',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(venue),
          ),
        );
      },
    );
  }
}
