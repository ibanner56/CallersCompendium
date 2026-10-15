import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/capitalize_figures_scope.dart';
import '../../data/decimal_turns_scope.dart';
import '../../data/dialect_library_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../data/show_custom_figures_scope.dart';
import '../../data/verbose_figure_rendering_scope.dart';
import '../../glossary/custom_figures.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import 'compound_editor_screen.dart';
import 'custom_figure_detail.dart';

/// The Glossary destination (issue #695): the shipped, read-only reference of
/// the app's bundled figures, shown in the user's dialect, and — while the
/// nested "Custom Figures" setting is on — the user's own compound figures
/// (#709), marked as custom, which can be added, edited and deleted here.
///
/// The shipped entries are derived from the taxonomy at runtime
/// ([figureGlossaryEntries]) and never stored. The user's entries, and their
/// notes on shipped figures, are read from the database. Shown in the app
/// shell only while the Experimental "Show Glossary" setting is on.
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

/// An entry resolved for display under one dialect: a shipped figure or one
/// of the user's own.
class _ShownEntry {
  _ShownEntry.shipped(
    FigureGlossaryEntry this.entry,
    this.name,
    this.definition,
  ) : custom = null,
      keywords = const [],
      id = entry.id;

  _ShownEntry.custom(
    CustomGlossaryItem this.custom,
    this.name,
    this.definition, {
    this.keywords = const [],
  }) : entry = null,
       id = custom.selectionId;

  /// The shipped figure, or null for one of the user's own.
  final FigureGlossaryEntry? entry;

  /// The user's own entry, or null for a shipped figure.
  final CustomGlossaryItem? custom;

  /// What the list selects it by; a custom entry's never equals a shipped id.
  final String id;

  /// The figure's name in the active dialect.
  final String name;

  /// The definition in the active dialect, or `null` when none ships yet.
  final String? definition;

  /// A custom entry's keywords in the active dialect, so they are found by
  /// what the user typed rather than by their stored form.
  final List<String> keywords;

  bool matches(String q) {
    if (name.toLowerCase().contains(q)) return true;
    if (definition?.toLowerCase().contains(q) ?? false) return true;
    final shipped = entry;
    if (shipped != null) {
      return shipped.canonicalName.toLowerCase().contains(q) ||
          shipped.searchKeywords.any((k) => k.toLowerCase().contains(q));
    }
    return keywords.any((k) => k.toLowerCase().contains(q));
  }
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _selectedId;

  CompendiumRepositories? _repos;
  StreamSubscription<List<UserGlossaryEntry>>? _userEntriesSub;
  List<UserGlossaryEntry> _userEntries = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    unawaited(_userEntriesSub?.cancel());
    _userEntriesSub = repos?.userGlossary.watchAll().listen((entries) {
      if (mounted) setState(() => _userEntries = entries);
    });
  }

  @override
  void dispose() {
    unawaited(_userEntriesSub?.cancel());
    _search.dispose();
    super.dispose();
  }

  List<FigureGlossaryEntry> get _entries => widget.entries ?? _shippedEntries;

  List<_ShownEntry> _shown(
    AppLocalizations l10n,
    Dialect dialect,
    List<CustomGlossaryItem> custom,
  ) {
    final shown = [
      for (final e in _entries)
        _ShownEntry.shipped(
          e,
          _entryTitle(l10n, e, _entries, dialect),
          switch (e.definition) {
            final d? => _renderer.renderFreeText(d.definition, dialect),
            null => null,
          },
        ),
      for (final c in custom)
        _ShownEntry.custom(
          c,
          _renderer.renderFreeText(c.entry.name, dialect),
          _renderer.renderFreeText(c.entry.definition, dialect),
          keywords: [
            for (final k in c.entry.keywords)
              _renderer.renderFreeText(k, dialect),
          ],
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return shown;
    return [
      for (final s in shown)
        if (s.matches(q)) s,
    ];
  }

  /// The user's own entries resolved for display, or none while custom
  /// figures are hidden.
  List<CustomGlossaryItem> _custom(BuildContext context, Dialect dialect) {
    if (!customFiguresShown(context)) return const [];
    return resolveCustomGlossary(
      _userEntries,
      taxonomy: contraTaxonomy,
      dialects: [
        dialect,
        ...?DialectLibraryScope.maybeOf(context)?.customDialects,
      ],
      shorthandTokens: [
        for (final m
            in ShorthandMappingsScope.maybeOf(context)?.mappings ??
                const <ShorthandMapping>[])
          m.token,
      ],
    );
  }

  Widget _detail(_ShownEntry shown, {required bool showName}) {
    final custom = shown.custom;
    if (custom != null) {
      return GlossaryCustomFigureDetail(
        key: ValueKey('glossary-detail-${shown.id}'),
        entryId: custom.entry.id,
        showName: showName,
      );
    }
    return GlossaryFigureDetail(
      key: ValueKey('glossary-detail-${shown.id}'),
      entryId: shown.entry!.id,
      entries: _entries,
      showName: showName,
    );
  }

  void _open(BuildContext context, _ShownEntry shown, {required bool wide}) {
    if (wide) {
      setState(() => _selectedId = shown.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          // A custom figure's title follows the entry, which can be renamed
          // from this page.
          appBar: AppBar(
            title: shown.custom == null
                ? Text(shown.name)
                : CustomFigureTitle(
                    entryId: shown.custom!.entry.id,
                    fallback: shown.name,
                  ),
          ),
          body: _detail(shown, showName: false),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final saved = await Navigator.of(context).push<UserGlossaryEntry>(
      MaterialPageRoute(builder: (_) => const CompoundEditorScreen()),
    );
    if (saved != null && mounted) {
      setState(() => _selectedId = customSelectionId(saved.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final custom = _custom(context, dialect);
    final shown = _shown(l10n, dialect, custom);
    final canAdd = customFiguresShown(context) && _repos != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.glossaryTitle),
        actions: [
          if (canAdd)
            IconButton(
              key: const ValueKey('glossary-add-custom'),
              icon: const Icon(Icons.add),
              tooltip: l10n.glossaryAddCustomFigure,
              onPressed: () => _add(context),
            ),
        ],
      ),
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
          // A selection that is no longer listed — a custom entry deleted, or
          // hidden by turning Custom Figures off — shows the prompt.
          final selected = shown.where((s) => s.id == _selectedId).firstOrNull;
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
                    : _detail(selected, showName: true),
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
                    final custom = s.custom;
                    return ListTile(
                      key: ValueKey('glossary-entry-${s.id}'),
                      title: Text(s.name),
                      trailing: custom == null
                          ? null
                          : CustomFigureMarker(item: custom),
                      subtitle: definition == null
                          ? null
                          : Text(
                              definition,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      selected: s.id == selectedId,
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
        FigureNotesSection(figureId: entry.id),
      ],
    );
  }
}

/// The user's own notes on a shipped figure (#709): shown, and editable,
/// wherever the Glossary is; absent where there is no database to keep them
/// in.
///
/// Stored canonically ([canonicalizeGlossaryText]) and read back in the
/// active dialect, as the shipped definitions are.
class FigureNotesSection extends StatefulWidget {
  const FigureNotesSection({super.key, required this.figureId});

  /// The shipped move or alias id the notes are on.
  final String figureId;

  @override
  State<FigureNotesSection> createState() => _FigureNotesSectionState();
}

class _FigureNotesSectionState extends State<FigureNotesSection> {
  CompendiumRepositories? _repos;
  StreamSubscription<List<FigureNote>>? _sub;
  String? _notes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    unawaited(_sub?.cancel());
    _sub = repos?.figureNotes.watchAll().listen((notes) {
      if (!mounted) return;
      setState(
        () => _notes = notes
            .where((n) => n.figureId == widget.figureId)
            .firstOrNull
            ?.notes,
      );
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _edit(BuildContext context, Dialect dialect) async {
    final repos = _repos!;
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _NotesDialog(
        initial: _notes == null
            ? ''
            : _renderer.renderFreeText(_notes!, dialect),
      ),
    );
    if (saved == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final tooLong = AppLocalizations.of(context).glossaryNotesTooLong;
    // Empty text deletes the note.
    try {
      await repos.figureNotes.set(
        widget.figureId,
        canonicalizeGlossaryText(saved, dialect),
      );
    } on FigureNoteInvalid {
      // diagnostics: silent — the user's text is over the stored bound, which
      // canonical role tokens can push it past; the message asks them to
      // shorten it.
      messenger.showSnackBar(SnackBar(content: Text(tooLong)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_repos == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dialect = ActiveDialectScope.of(context);
    final notes = _notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.lg,
            bottom: AppSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(l10n.glossaryNotes, style: theme.textTheme.titleSmall),
          ),
        ),
        if (notes == null)
          Text(
            l10n.glossaryNotesEmpty,
            key: const ValueKey('glossary-notes-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Text(
            _renderer.renderFreeText(notes, dialect),
            key: const ValueKey('glossary-notes'),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('glossary-notes-edit'),
            icon: const Icon(Icons.edit_note_outlined),
            label: Text(
              notes == null ? l10n.glossaryNotesAdd : l10n.glossaryNotesEdit,
            ),
            onPressed: () => _edit(context, dialect),
          ),
        ),
      ],
    );
  }
}

/// Edits the notes on a shipped figure; pops the text, or null on cancel.
/// Owns its controller, so it outlives the dialog's closing animation.
class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.initial});

  final String initial;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.glossaryNotesEditTitle),
      content: TextField(
        key: const ValueKey('glossary-notes-field'),
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: maxUserGlossaryTextLength,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        decoration: InputDecoration(
          hintText: l10n.glossaryNotesHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('glossary-notes-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonSave),
        ),
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
