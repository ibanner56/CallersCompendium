import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/capitalize_figures_scope.dart';
import '../../data/decimal_turns_scope.dart';
import '../../data/verbose_figure_rendering_scope.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';

/// The Glossary destination (issue #695): the shipped, read-only reference of
/// the app's bundled figures, shown in the user's dialect.
///
/// Every entry is derived from the taxonomy at runtime
/// ([figureGlossaryEntries]) — nothing is stored, so nothing syncs. Shown in
/// the app shell only while the Experimental "Show Glossary" setting is on.
///
/// - **Narrow (< [splitBreakpoint]):** a searchable list; selecting a figure
///   pushes its detail page.
/// - **Wide:** list and detail side by side.
///
/// The global command palette searches dances and programs, not figures, so
/// this screen deliberately has no app-bar global-search action: its own
/// search field is the glossary's search.
class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({super.key, this.entries});

  /// The figures to list; defaults to the shipped glossary. A test seam.
  @visibleForTesting
  final List<FigureGlossaryEntry>? entries;

  /// Width (logical pixels) at which list and detail sit side by side.
  static const double splitBreakpoint = 900;

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);
final List<FigureGlossaryEntry> _shippedEntries = figureGlossaryEntries(
  contraTaxonomy,
);

/// The name [entry] is listed and headed by under [dialect].
///
/// Usually the figure's dialect name. When another entry in [all] shares that
/// name — the two `pull by` aliases share it with `pull by` itself — an alias
/// is qualified by the values it pins (`pull by (neighbors)`), so no two rows
/// read the same.
String _entryTitle(
  AppLocalizations l10n,
  FigureGlossaryEntry entry,
  List<FigureGlossaryEntry> all,
  Dialect dialect,
) {
  final name = _renderer.displayMoveName(entry.id, dialect);
  final alias = contraTaxonomy.aliases[entry.id];
  if (alias == null || alias.pinnedParams.isEmpty) return name;
  final collides = all.any(
    (other) =>
        other.id != entry.id &&
        _renderer.displayMoveName(other.id, dialect).toLowerCase() ==
            name.toLowerCase(),
  );
  if (!collides) return name;
  final target = contraTaxonomy.moves[alias.targetMove]!;
  final detail = [
    for (final MapEntry(key: param, value: value) in alias.pinnedParams.entries)
      if (target.params[param] case final spec?)
        figureParamChoiceLabel(l10n, spec, dialect, '$value'),
  ].join(', ');
  return l10n.glossaryNameWithDetail(name, detail);
}

/// An entry resolved for display under one dialect.
class _ShownEntry {
  _ShownEntry(this.entry, this.name, this.definition);

  final FigureGlossaryEntry entry;

  /// The figure's name in the active dialect.
  final String name;

  /// The definition in the active dialect, or `null` when none ships yet.
  final String? definition;
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<FigureGlossaryEntry> get _entries => widget.entries ?? _shippedEntries;

  List<_ShownEntry> _shown(AppLocalizations l10n, Dialect dialect) {
    final shown = [
      for (final e in _entries)
        _ShownEntry(
          e,
          _entryTitle(l10n, e, _entries, dialect),
          switch (e.definition) {
            final d? => _renderer.renderFreeText(d.definition, dialect),
            null => null,
          },
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return shown;
    return [
      for (final s in shown)
        if (s.name.toLowerCase().contains(q) ||
            s.entry.canonicalName.toLowerCase().contains(q) ||
            s.entry.searchKeywords.any((k) => k.toLowerCase().contains(q)) ||
            (s.definition?.toLowerCase().contains(q) ?? false))
          s,
    ];
  }

  void _open(BuildContext context, _ShownEntry shown, {required bool wide}) {
    if (wide) {
      setState(() => _selectedId = shown.entry.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(shown.name)),
          body: GlossaryFigureDetail(
            entryId: shown.entry.id,
            entries: _entries,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final shown = _shown(l10n, dialect);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.glossaryTitle)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= GlossaryScreen.splitBreakpoint;
          final list = _GlossaryList(
            search: _search,
            onQueryChanged: (q) => setState(() => _query = q),
            entries: shown,
            query: _query,
            selectedId: wide ? _selectedId : null,
            onOpen: (s) => _open(context, s, wide: wide),
          );
          if (!wide) return list;
          final selected = _selectedId;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 360, child: list),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: selected == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            l10n.glossarySelectPrompt,
                            key: const ValueKey('glossary-select-prompt'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : GlossaryFigureDetail(
                        key: ValueKey('glossary-detail-$selected'),
                        entryId: selected,
                        entries: _entries,
                        showName: true,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlossaryList extends StatelessWidget {
  const _GlossaryList({
    required this.search,
    required this.onQueryChanged,
    required this.entries,
    required this.query,
    required this.selectedId,
    required this.onOpen,
  });

  final TextEditingController search;
  final ValueChanged<String> onQueryChanged;
  final List<_ShownEntry> entries;
  final String query;
  final String? selectedId;
  final ValueChanged<_ShownEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: TextField(
            key: const ValueKey('glossary-search'),
            controller: search,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.glossarySearchHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      l10n.glossaryNoMatches(query.trim()),
                      key: const ValueKey('glossary-no-matches'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final s = entries[i];
                    final definition = s.definition;
                    return ListTile(
                      key: ValueKey('glossary-entry-${s.entry.id}'),
                      title: Text(s.name),
                      subtitle: definition == null
                          ? null
                          : Text(
                              definition,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      selected: s.entry.id == selectedId,
                      onTap: () => onOpen(s),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The detail view of one shipped glossary figure, in the active dialect.
class GlossaryFigureDetail extends StatelessWidget {
  const GlossaryFigureDetail({
    super.key,
    required this.entryId,
    this.entries,
    this.showName = false,
  });

  /// The move or alias id of the entry to show.
  final String entryId;

  /// The glossary [entryId] is looked up in, for its aliases too; defaults to
  /// the shipped glossary.
  final List<FigureGlossaryEntry>? entries;

  /// Whether to show the figure's name as a heading — on in the wide split
  /// pane; off on the pushed page, whose app bar already names it.
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dialect = ActiveDialectScope.of(context);
    final capitalize = CapitalizeFiguresScope.of(context);
    final decimals = DecimalTurnsScope.of(context);
    final verbose = VerboseFigureRenderingScope.of(context);
    final all = entries ?? _shippedEntries;
    final entry = all.firstWhere((e) => e.id == entryId);
    final name = _entryTitle(l10n, entry, all, dialect);
    final definition = entry.definition;

    // Other names: the canonical name (when a custom dialect renames the
    // figure), the aliases of this move, then its search keywords — minus
    // anything that just repeats the name shown.
    final shownLower = {
      _renderer.displayMoveName(entry.id, dialect).toLowerCase(),
    };
    final otherNames = <String>[entry.canonicalName];
    for (final e in all) {
      if (e.isAlias && e.targetMoveId == entry.id) {
        otherNames.add(_renderer.displayMoveName(e.id, dialect));
      }
    }
    otherNames.addAll(entry.searchKeywords);
    final seen = <String>{};
    final alsoKnownAs = [
      for (final n in otherNames)
        if (!shownLower.contains(n.toLowerCase()) && seen.add(n.toLowerCase()))
          n,
    ];

    // The example follows the same display settings as a dance's figure list
    // (figure_table.dart): decimal turns, always-verbose, and capitalization;
    // a screen reader always gets the spoken-style rendering.
    final figure = Figure(move: entry.id);
    final spoken = _renderer.renderVerbose(figure, dialect);
    final example = capitalizeFirstLetter(
      verbose ? spoken : _renderer.render(figure, dialect, decimals: decimals),
      capitalize: capitalize,
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );

    return ListView(
      key: const ValueKey('glossary-detail'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (showName)
          Semantics(
            header: true,
            child: Text(name, style: theme.textTheme.headlineSmall),
          ),
        if (entry.isAlias)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.glossaryVariantOf(
                _renderer.displayMoveName(entry.targetMoveId, dialect),
              ),
              key: const ValueKey('glossary-variant-of'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (definition == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              l10n.glossaryNoDefinition,
              key: const ValueKey('glossary-no-definition'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              _renderer.renderFreeText(definition.definition, dialect),
              key: const ValueKey('glossary-definition'),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _renderer.renderFreeText(definition.description, dialect),
              key: const ValueKey('glossary-description'),
            ),
          ),
        ],
        heading(l10n.glossaryExample),
        Text(
          example,
          key: const ValueKey('glossary-example'),
          semanticsLabel: spoken,
        ),
        if (entry.params.isNotEmpty) ...[
          heading(l10n.glossaryParameters),
          Text(
            [
              for (final p in entry.params)
                figureParamKeyLabel(l10n, p, moveId: entry.targetMoveId),
            ].join(', '),
            key: const ValueKey('glossary-parameters'),
          ),
        ],
        if (alsoKnownAs.isNotEmpty) ...[
          heading(l10n.glossaryAlsoKnownAs),
          Wrap(
            key: const ValueKey('glossary-also-known-as'),
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final n in alsoKnownAs)
                _OtherName(
                  n,
                  discouraged: dialect.discouragedTerms.contains(
                    n.toLowerCase(),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One "also known as" name. A discouraged term is struck through, as the
/// dance editor shows it, and announced as discouraged.
class _OtherName extends StatelessWidget {
  const _OtherName(this.name, {required this.discouraged});

  final String name;
  final bool discouraged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Chip(
      label: Text(
        name,
        semanticsLabel: discouraged
            ? l10n.danceEditorDiscouragedTermSemantic(name)
            : null,
        style: discouraged
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
    );
  }
}
