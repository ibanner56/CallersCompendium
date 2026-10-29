import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/figure_summary.dart';
import '../data/repositories_scope.dart';
import '../data/show_custom_figures_scope.dart';
import '../editor/figure_draft.dart';
import '../theme/destructive_button_style.dart';
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
                summary: _summarize(context, renderer, dialect, mappings[i]),
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
    BuildContext context,
    FigureRenderer renderer,
    Dialect dialect,
    ShorthandMapping mapping,
  ) => mapping.figures
      .map((f) => renderFigureSummary(context, renderer, f, dialect))
      .join(' → ');

  Future<void> _createNew(
    BuildContext context,
    ShorthandMappingsController controller,
  ) async {
    // Say so before the editor opens, so the user does not build a shorthand
    // that cannot be saved.
    if (controller.mappings.length >= maxShorthandMappings) {
      _showLimitReached(context);
      return;
    }
    final existing = controller.takenTokens;
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
    try {
      await controller.upsert(edited);
    } on ArgumentError {
      // diagnostics: silent — the expected cap refusal, shown to the user as a
      // snackbar; any other ArgumentError is rethrown. The list filled while
      // the editor was open (e.g. a sync landed); the editor screens the other
      // rejections.
      if (controller.mappings.length < maxShorthandMappings) rethrow;
      if (context.mounted) _showLimitReached(context);
    }
  }

  static void _showLimitReached(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('shorthand-limit-reached'),
        content: Text(
          AppLocalizations.of(
            context,
          ).shorthandMappingsLimitReached(maxShorthandMappings),
        ),
      ),
    );
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
      for (final u in controller.userFigureShorthands) u.normalizedToken,
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

  /// The tokens of the shorthands for the user's own figures, of both kinds,
  /// while their section is hidden (Custom Figures off): still taken, but not
  /// on screen.
  static Set<String> _hiddenCompoundTokens(
    BuildContext context,
    ShorthandMappingsController controller,
  ) => customFiguresShown(context)
      ? const {}
      : {
          for (final c in controller.compoundShorthands) c.normalizedToken,
          for (final u in controller.userFigureShorthands) u.normalizedToken,
        };

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
            style: destructiveFilledButtonStyle(Theme.of(ctx).colorScheme),
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

  /// Every shorthand's token but the one being edited: the compound
  /// shorthand at [compoundIndex] or the new figure's at [userFigureIndex].
  Set<String> _tokensExcept({int? compoundIndex, int? userFigureIndex}) {
    final controller = widget.controller;
    return {
      for (final m in controller.mappings) m.normalizedToken,
      for (var i = 0; i < controller.compoundShorthands.length; i++)
        if (i != compoundIndex)
          controller.compoundShorthands[i].normalizedToken,
      for (var i = 0; i < controller.userFigureShorthands.length; i++)
        if (i != userFigureIndex)
          controller.userFigureShorthands[i].normalizedToken,
    };
  }

  /// Opens the editor on the compound shorthand at [compoundIndex], the new
  /// figure's at [userFigureIndex], or a new one. The editor may hand back
  /// the other kind, when another kind of figure was chosen: the edited one
  /// is then removed and the result added, under its own key.
  Future<void> _open(
    BuildContext context, {
    int? compoundIndex,
    int? userFigureIndex,
  }) async {
    final controller = widget.controller;
    final edited = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => CompoundShorthandEditorScreen(
          initial: compoundIndex == null
              ? null
              : controller.compoundShorthands[compoundIndex],
          initialUserFigure: userFigureIndex == null
              ? null
              : controller.userFigureShorthands[userFigureIndex],
          existingTokens: _tokensExcept(
            compoundIndex: compoundIndex,
            userFigureIndex: userFigureIndex,
          ),
        ),
      ),
    );
    switch (edited) {
      case CompoundShorthand() when userFigureIndex != null:
        await controller.replaceUserFigureWithCompound(userFigureIndex, edited);
      case CompoundShorthand():
        await controller.upsertCompound(edited, index: compoundIndex);
      case UserFigureShorthand() when compoundIndex != null:
        await controller.replaceCompoundWithUserFigure(compoundIndex, edited);
      case UserFigureShorthand():
        await controller.upsertUserFigure(edited, index: userFigureIndex);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    int? compoundIndex,
    int? userFigureIndex,
  }) async {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    final token = compoundIndex != null
        ? controller.compoundShorthands[compoundIndex].token
        : controller.userFigureShorthands[userFigureIndex!].token;
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
            style: destructiveFilledButtonStyle(Theme.of(ctx).colorScheme),
            key: const ValueKey('compound-shorthand-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (compoundIndex != null) {
      await controller.removeCompoundAt(compoundIndex);
    } else {
      await controller.removeUserFigureAt(userFigureIndex!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final shorthands = widget.controller.compoundShorthands;
    final userFigureShorthands = widget.controller.userFigureShorthands;
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
            onPressed: () => _open(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.shorthandsCompoundNew),
          ),
        ),
        if (shorthands.isEmpty && userFigureShorthands.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l10n.shorthandsCompoundEmpty,
              key: const ValueKey('compound-shorthand-empty'),
            ),
          ),
        for (var i = 0; i < shorthands.length; i++)
          _row(context, l10n, dialect, shorthands[i], i, figureTokens),
        for (var i = 0; i < userFigureShorthands.length; i++)
          _userFigureRow(
            context,
            l10n,
            dialect,
            userFigureShorthands[i],
            i,
            figureTokens,
          ),
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
      onTap: () => _open(context, compoundIndex: index),
      trailing: PopupMenuButton<String>(
        key: ValueKey('compound-shorthand-menu-$key'),
        tooltip: l10n.shorthandMappingsActionsTooltip,
        onSelected: (value) => value == 'edit'
            ? _open(context, compoundIndex: index)
            : _confirmDelete(context, compoundIndex: index),
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

  /// A shorthand for one of the user's new figures (#1023): its token, and
  /// the line it inserts, in the figure's current wording. Like a compound
  /// shorthand's row, it says when it can't be used, or when a figure
  /// shorthand with the same token wins.
  Widget _userFigureRow(
    BuildContext context,
    AppLocalizations l10n,
    Dialect dialect,
    UserFigureShorthand shorthand,
    int index,
    Set<String> figureTokens,
  ) {
    final theme = Theme.of(context);
    // The entries this section watches, as the compound rows read them.
    final userFigures = UserFigureCatalog.fromEntries(
      _entries?.values ?? const [],
    );
    final use = userFigureUseFigure(
      id: shorthand.figureId,
      args: shorthand.args,
      text: shorthand.figureName,
      beats: shorthand.beats,
    );
    final renderer = FigureRenderer(contraTaxonomy, userFigures: userFigures);
    final usable = renderer.renderUserFigureCanonical(use) != null;
    final shadowed = figureTokens.contains(shorthand.normalizedToken);
    // A compound shorthand with the same token is resolved first, so it wins
    // too: tokens are kept unique, but two devices can each add one.
    final shadowedByCompound = {
      for (final c in widget.controller.compoundShorthands) c.normalizedToken,
    }.contains(shorthand.normalizedToken);
    final problem = shadowed
        ? l10n.shorthandsCompoundShadowed
        : shadowedByCompound
        ? l10n.shorthandsUserFigureShadowedByCompound
        : usable || _entries == null
        ? null
        : l10n.shorthandsCompoundUnavailable;
    final key = shorthand.normalizedToken;
    final beats = shorthand.beats;
    return ListTile(
      key: ValueKey('user-figure-shorthand-tile-$key'),
      title: Text(shorthand.token),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            beats == null
                ? renderFigureSummary(context, renderer, use, dialect)
                : '${renderFigureSummary(context, renderer, use, dialect)} · '
                      '${l10n.danceFigureBeats(beats)}',
          ),
          if (problem != null)
            Text(
              problem,
              key: ValueKey('user-figure-shorthand-problem-$key'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
      onTap: () => _open(context, userFigureIndex: index),
      trailing: PopupMenuButton<String>(
        key: ValueKey('user-figure-shorthand-menu-$key'),
        tooltip: l10n.shorthandMappingsActionsTooltip,
        onSelected: (value) => value == 'edit'
            ? _open(context, userFigureIndex: index)
            : _confirmDelete(context, userFigureIndex: index),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l10n.commonEdit)),
          PopupMenuItem(
            key: const ValueKey('user-figure-shorthand-delete'),
            value: 'delete',
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}
