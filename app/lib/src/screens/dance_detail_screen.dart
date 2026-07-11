import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';

/// Minimal placeholder detail view for 3.1 (full dance detail/edit lands
/// with roadmap items 3.2+/3.3). Shows the fields already available on
/// [Dance]: title, authors, formation, hook, and tags.
class DanceDetailScreen extends StatefulWidget {
  const DanceDetailScreen({super.key, required this.danceId});

  final String danceId;

  @override
  State<DanceDetailScreen> createState() => _DanceDetailScreenState();
}

class _DanceDetailScreenState extends State<DanceDetailScreen> {
  late Future<_DanceDetail?> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load(RepositoriesScope.of(context));
  }

  Future<_DanceDetail?> _load(CompendiumRepositories repos) async {
    final dance = await repos.dances.getById(widget.danceId);
    if (dance == null) return null;

    final authorNames = <String>[];
    for (final id in dance.authorIds) {
      final c = await repos.choreographers.getById(id);
      if (c != null) authorNames.add(c.name);
    }
    final tagNames = <String>[];
    for (final id in dance.tagIds) {
      final t = await repos.tags.getById(id);
      if (t != null) tagNames.add(t.name);
    }
    return _DanceDetail(
      dance: dance,
      authorNames: authorNames,
      tagNames: tagNames,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dance')),
      body: FutureBuilder<_DanceDetail?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data;
          if (detail == null) {
            return const Center(child: Text('Dance not found.'));
          }
          final dance = detail.dance;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                dance.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (detail.authorNames.isNotEmpty)
                Text(detail.authorNames.join(', ')),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.grid_view, size: 18),
                  const SizedBox(width: 6),
                  Text(formationLabel(dance.formation)),
                ],
              ),
              if (dance.hook.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(dance.hook, style: Theme.of(context).textTheme.bodyLarge),
              ],
              if (detail.tagNames.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tag in detail.tagNames)
                      Chip(
                        avatar: const Icon(Icons.label_outline, size: 16),
                        label: Text(tag),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DanceDetail {
  _DanceDetail({
    required this.dance,
    required this.authorNames,
    required this.tagNames,
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;
}
