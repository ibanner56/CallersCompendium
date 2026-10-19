import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/dialect_library_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../glossary/custom_figures.dart';
import '../../theme/app_spacing.dart';
import 'compound_editor_screen.dart';
import 'custom_figure_detail.dart';

final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

/// The user's own figures on a screen of their own, opened from the
/// Experimental settings like the figure shorthands are from the dialect
/// settings, so they can be added, edited and deleted whether or not the
/// Glossary is shown.
///
/// It lists the same entries the Glossary marks as custom, apart from terms,
/// which belong to the Glossary (#1023, maintainer decision 9); selecting one
/// opens the Glossary's own detail page for it, with the same Edit and Delete.
class CustomFiguresScreen extends StatefulWidget {
  const CustomFiguresScreen({super.key});

  @override
  State<CustomFiguresScreen> createState() => _CustomFiguresScreenState();
}

class _CustomFiguresScreenState extends State<CustomFiguresScreen> {
  CompendiumRepositories? _repos;
  StreamSubscription<List<UserGlossaryEntry>>? _sub;
  List<UserGlossaryEntry> _entries = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    unawaited(_sub?.cancel());
    _sub = repos?.userGlossary.watchAll().listen((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _open(BuildContext context, CustomGlossaryItem item, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: CustomFigureTitle(entryId: item.entry.id, fallback: name),
          ),
          body: GlossaryCustomFigureDetail(
            key: ValueKey('glossary-detail-${item.selectionId}'),
            entryId: item.entry.id,
          ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    await Navigator.of(context).push<UserGlossaryEntry>(
      MaterialPageRoute(builder: (_) => const CompoundEditorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    // Each is checked for a rename against every entry, terms included.
    final all = resolveCustomGlossary(
      _entries,
      taxonomy: contraTaxonomy,
      dialects: [
        dialect,
        ...?DialectLibraryScope.maybeOf(context)?.customDialects,
      ],
      shorthandTokens: ShorthandMappingsScope.tokensOf(context),
    );
    final shown = [
      for (final item in all)
        if (!item.isTerm)
          (item, _renderer.renderFreeText(item.entry.name, dialect)),
    ]..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customFiguresTitle),
        actions: [
          if (_repos != null)
            IconButton(
              key: const ValueKey('custom-figures-add'),
              icon: const Icon(Icons.add),
              tooltip: l10n.glossaryAddCustomFigure,
              onPressed: () => _add(context),
            ),
        ],
      ),
      body: shown.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.customFiguresEmpty,
                  key: const ValueKey('custom-figures-empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final (item, name) in shown)
                  ListTile(
                    key: ValueKey('custom-figure-${item.entry.id}'),
                    title: Text(name),
                    subtitle: Text(
                      _renderer.renderFreeText(item.entry.definition, dialect),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: CustomFigureMarker(item: item),
                    onTap: () => _open(context, item, name),
                  ),
              ],
            ),
    );
  }
}
