import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/shorthand_mappings_controller.dart';
import '../data/shorthand_mappings_scope.dart';
import 'shorthand_mapping_editor_screen.dart';

/// Manager for the user's shorthand → figure(s) mappings (issue #420), reached
/// from the "Free-text entry" area of Settings. Mirrors the dialect library
/// manager: a "New shorthand" affordance plus one row per mapping (its token
/// and a preview of the figures it expands to) with edit / delete actions.
/// Editing a row opens the full-screen [ShorthandMappingEditorScreen].
class ShorthandMappingsScreen extends StatelessWidget {
  const ShorthandMappingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShorthandMappingsScope.of(context);
    final dialect = ActiveDialectScope.of(context);
    final renderer = FigureRenderer(contraTaxonomy);
    final mappings = controller.mappings;
    return Scaffold(
      appBar: AppBar(title: const Text('Figure shorthands')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Shorthands let you type a short token during free-text entry and '
              'have it expand to one or more figures you have set up here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('new-shorthand'),
                onPressed: () => _createNew(context, controller),
                icon: const Icon(Icons.add),
                label: const Text('New shorthand'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (mappings.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                key: ValueKey('shorthand-empty'),
                'No shorthands yet.',
              ),
            )
          else
            for (var i = 0; i < mappings.length; i++)
              _ShorthandRow(
                key: ValueKey('shorthand-tile-${mappings[i].normalizedToken}'),
                mapping: mappings[i],
                summary: _summarize(renderer, dialect, mappings[i]),
                onEdit: () => _edit(context, controller, i),
                onDelete: () => _confirmDelete(context, controller, i),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Renders the mapping's target figures into a single-line preview via the
  /// active dialect, e.g. "neighbors swing → circle left ¾".
  static String _summarize(
    FigureRenderer renderer,
    Dialect dialect,
    ShorthandMapping mapping,
  ) => mapping.figures.map((f) => renderer.render(f, dialect)).join(' → ');

  Future<void> _createNew(
    BuildContext context,
    ShorthandMappingsController controller,
  ) async {
    final existing = {for (final m in controller.mappings) m.normalizedToken};
    final edited = await Navigator.of(context).push<ShorthandMapping>(
      MaterialPageRoute(
        builder: (_) => ShorthandMappingEditorScreen(existingTokens: existing),
      ),
    );
    if (edited == null) return;
    await controller.upsert(edited);
  }

  Future<void> _edit(
    BuildContext context,
    ShorthandMappingsController controller,
    int index,
  ) async {
    final mappings = controller.mappings;
    if (index < 0 || index >= mappings.length) return;
    final current = mappings[index];
    // Every OTHER mapping's token is off-limits for uniqueness; the row being
    // edited may keep (or re-case) its own token.
    final existing = {
      for (var i = 0; i < mappings.length; i++)
        if (i != index) mappings[i].normalizedToken,
    };
    final edited = await Navigator.of(context).push<ShorthandMapping>(
      MaterialPageRoute(
        builder: (_) => ShorthandMappingEditorScreen(
          initial: current,
          existingTokens: existing,
        ),
      ),
    );
    if (edited == null) return;
    await controller.upsert(edited, index: index);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ShorthandMappingsController controller,
    int index,
  ) async {
    final mappings = controller.mappings;
    if (index < 0 || index >= mappings.length) return;
    final token = mappings[index].token;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete shorthand?'),
        content: Text('“$token” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.removeAt(index);
  }
}

/// One row in the shorthand manager: the token, a preview of the figures it
/// expands to, and an actions menu (edit / delete).
class _ShorthandRow extends StatelessWidget {
  const _ShorthandRow({
    super.key,
    required this.mapping,
    required this.summary,
    required this.onEdit,
    required this.onDelete,
  });

  final ShorthandMapping mapping;
  final String summary;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(mapping.token),
      subtitle: summary.isEmpty ? null : Text(summary),
      onTap: onEdit,
      trailing: PopupMenuButton<String>(
        key: ValueKey('shorthand-menu-${mapping.normalizedToken}'),
        tooltip: 'Shorthand actions',
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
