import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../data/show_custom_figures_scope.dart';
import '../editor/figure_draft.dart';
import '../widgets/compound_argument_editor.dart';
import 'compound_shorthand_editor_screen.dart';
import '../data/shorthand_mappings_controller.dart';
import '../data/shorthand_mappings_scope.dart';
import 'shorthand_mapping_editor_screen.dart';

/// Manager for the user's shorthand → figure(s) mappings (issue #420), reached
/// from the "Free-text entry" area of Settings. Mirrors the dialect library
/// manager: a "New shorthand" affordance plus one row per mapping (its token
/// and a preview of the figures it expands to) with edit / delete actions.
/// Editing a row opens the full-screen [ShorthandMappingEditorScreen].
///
/// While Custom Figures is on it also lists the compound shorthands (#709),
/// each standing for one of the user's own figures with fixed values, edited
/// in [CompoundShorthandEditorScreen]. While it is off they are hidden, not
/// deleted. Tokens are unique across both kinds.
class ShorthandMappingsScreen extends StatelessWidget {
  const ShorthandMappingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShorthandMappingsScope.of(context);
    final dialect = ActiveDialectScope.of(context);
    final renderer = FigureRenderer(contraTaxonomy);
    final mappings = controller.mappings;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shorthandMappingsTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.shorthandMappingsIntro,
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
                label: Text(l10n.shorthandMappingsNew),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (mappings.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.shorthandMappingsEmpty,
                key: const ValueKey('shorthand-empty'),
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
          if (customFiguresShown(context))
            _CompoundShorthandsSection(controller: controller),
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
    final existing = {
      for (final m in controller.mappings) m.normalizedToken,
      for (final c in controller.compoundShorthands) c.normalizedToken,
    };
    final hidden = _hiddenCompoundTokens(context, controller);
    final edited = await Navigator.of(context).push<ShorthandMapping>(
      MaterialPageRoute(
        builder: (_) => ShorthandMappingEditorScreen(
          existingTokens: existing,
          hiddenTokens: hidden,
        ),
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
      for (final c in controller.compoundShorthands) c.normalizedToken,
    };
    final hidden = _hiddenCompoundTokens(context, controller);
    final edited = await Navigator.of(context).push<ShorthandMapping>(
      MaterialPageRoute(
        builder: (_) => ShorthandMappingEditorScreen(
          initial: current,
          existingTokens: existing,
          hiddenTokens: hidden,
        ),
      ),
    );
    if (edited == null) return;
    await controller.upsert(edited, index: index);
  }

  /// The compound shorthands' tokens while their section is hidden (Custom
  /// Figures off): still taken, but not on screen.
  static Set<String> _hiddenCompoundTokens(
    BuildContext context,
    ShorthandMappingsController controller,
  ) => customFiguresShown(context)
      ? const {}
      : {for (final c in controller.compoundShorthands) c.normalizedToken};

  Future<void> _confirmDelete(
    BuildContext context,
    ShorthandMappingsController controller,
    int index,
  ) async {
    final mappings = controller.mappings;
    if (index < 0 || index >= mappings.length) return;
    final token = mappings[index].token;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.shorthandMappingsDeleteTitle),
        content: Text(l10n.shorthandMappingsDeleteBody(token)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
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
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(mapping.token),
      subtitle: summary.isEmpty ? null : Text(summary),
      onTap: onEdit,
      trailing: PopupMenuButton<String>(
        key: ValueKey('shorthand-menu-${mapping.normalizedToken}'),
        tooltip: l10n.shorthandMappingsActionsTooltip,
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l10n.commonEdit)),
          PopupMenuItem(value: 'delete', child: Text(l10n.commonDelete)),
        ],
      ),
    );
  }
}

/// The compound shorthands (#709): a heading, a "new" action and one row per
/// shorthand, each saying what it stands for, or why it can't be used.
class _CompoundShorthandsSection extends StatefulWidget {
  const _CompoundShorthandsSection({required this.controller});

  final ShorthandMappingsController controller;

  @override
  State<_CompoundShorthandsSection> createState() =>
      _CompoundShorthandsSectionState();
}

class _CompoundShorthandsSectionState
    extends State<_CompoundShorthandsSection> {
  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  CompendiumRepositories? _repos;
  StreamSubscription<List<UserGlossaryEntry>>? _sub;

  /// The user's glossary entries by id; null until first read, when no row
  /// is yet judged usable or not.
  Map<String, UserGlossaryEntry>? _entries;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    unawaited(_sub?.cancel());
    _sub = repos?.userGlossary.watchAll().listen((entries) {
      if (mounted) {
        setState(() => _entries = {for (final e in entries) e.id: e});
      }
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  CompoundDefinition? _definition(String id) {
    final entry = _entries?[id];
    if (entry == null || entry.kind != UserGlossaryEntryKind.compound) {
      return null;
    }
    return decodeCompoundDefinition(entry.payload, contraTaxonomy);
  }

  Set<String> _tokensExcept(int index) => {
    for (final m in widget.controller.mappings) m.normalizedToken,
    for (var i = 0; i < widget.controller.compoundShorthands.length; i++)
      if (i != index) widget.controller.compoundShorthands[i].normalizedToken,
  };

  Future<void> _open(BuildContext context, int? index) async {
    final shorthands = widget.controller.compoundShorthands;
    final edited = await Navigator.of(context).push<CompoundShorthand>(
      MaterialPageRoute(
        builder: (_) => CompoundShorthandEditorScreen(
          initial: index == null ? null : shorthands[index],
          existingTokens: _tokensExcept(index ?? -1),
        ),
      ),
    );
    if (edited == null) return;
    await widget.controller.upsertCompound(edited, index: index);
  }

  Future<void> _confirmDelete(BuildContext context, int index) async {
    final l10n = AppLocalizations.of(context);
    final token = widget.controller.compoundShorthands[index].token;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.shorthandMappingsDeleteTitle),
        content: Text(l10n.shorthandMappingsDeleteBody(token)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('compound-shorthand-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.removeCompoundAt(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final shorthands = widget.controller.compoundShorthands;
    final figureTokens = {
      for (final m in widget.controller.mappings) m.normalizedToken,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.shorthandsCompoundTitle,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.shorthandsCompoundIntro,
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            key: const ValueKey('new-compound-shorthand'),
            onPressed: () => _open(context, null),
            icon: const Icon(Icons.add),
            label: Text(l10n.shorthandsCompoundNew),
          ),
        ),
        if (shorthands.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l10n.shorthandsCompoundEmpty,
              key: const ValueKey('compound-shorthand-empty'),
            ),
          ),
        for (var i = 0; i < shorthands.length; i++)
          _row(context, l10n, dialect, shorthands[i], i, figureTokens),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    Dialect dialect,
    CompoundShorthand shorthand,
    int index,
    Set<String> figureTokens,
  ) {
    final theme = Theme.of(context);
    final entry = _entries?[shorthand.compoundId];
    final name = _renderer.renderFreeText(
      entry?.name ?? shorthand.compoundName,
      dialect,
    );
    final usable =
        expandPlaceholder(
          CompoundPlaceholder(
            id: shorthand.compoundId,
            name: shorthand.compoundName,
            args: {...shorthand.args},
          ),
          _definition,
        ) !=
        null;
    // A figure shorthand with the same token wins: tokens are kept unique,
    // but two devices can each add one before they sync.
    final shadowed = figureTokens.contains(shorthand.normalizedToken);
    final problem = shadowed
        ? l10n.shorthandsCompoundShadowed
        : usable || _entries == null
        ? null
        : l10n.shorthandsCompoundUnavailable;
    final definition = _definition(shorthand.compoundId);
    final values = definition == null || definition.params.isEmpty
        ? ''
        : compoundArgumentsText(l10n, definition, shorthand.args, dialect);
    final key = shorthand.normalizedToken;
    return ListTile(
      key: ValueKey('compound-shorthand-tile-$key'),
      title: Text(shorthand.token),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            values.isEmpty
                ? name
                : l10n.danceEditorCompoundSummary(name, values),
          ),
          if (problem != null)
            Text(
              problem,
              key: ValueKey('compound-shorthand-problem-$key'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
      onTap: () => _open(context, index),
      trailing: PopupMenuButton<String>(
        key: ValueKey('compound-shorthand-menu-$key'),
        tooltip: l10n.shorthandMappingsActionsTooltip,
        onSelected: (value) => value == 'edit'
            ? _open(context, index)
            : _confirmDelete(context, index),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l10n.commonEdit)),
          PopupMenuItem(
            key: const ValueKey('compound-shorthand-delete'),
            value: 'delete',
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}
