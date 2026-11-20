import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/capitalize_figures_scope.dart';
import '../../data/decimal_turns_scope.dart';
import '../../data/display_defaults.dart';
import '../../data/dialect_library_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../data/show_custom_figures_scope.dart';
import '../../data/verbose_figure_rendering_scope.dart';
import '../../glossary/custom_figures.dart';
import '../../glossary/figure_titles.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/dirty_dialog_guard.dart';
import '../../widgets/sync_now_action.dart';
import 'compound_editor_screen.dart';
import 'custom_figure_detail.dart';
import '../../theme/app_breakpoints.dart';

/// The Glossary destination (issue #695): the shipped, read-only reference of
/// the app's bundled figures, shown in the user's dialect, and — while the
/// nested "Custom Figures" setting is on — the user's own compound figures
/// (#709), marked as custom, which can be added, edited and deleted here.
///
/// The shipped entries are derived from the taxonomy at runtime
/// ([figureGlossaryEntries]) and never stored. The user's entries, and their
/// notes on shipped figures, are read from the database. Shown in the app
/// shell only while the Experimental "Show glossary" setting is on.
///
/// - **Narrow (below [AppBreakpoints.split] of window width):** a searchable
///   list; selecting a figure pushes its detail page.
/// - **Wide:** list and detail side by side.
///
/// The global command palette searches dances and programs, not figures, so
/// this screen deliberately has no app-bar global-search action: its own
/// search field is the glossary's search.
class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({super.key, this.entries, this.isActive = true});

  /// Whether the Glossary is the destination on screen. The app shell keeps
  /// it alive while another is shown; each time it is shown again, it opens
  /// on the form a new dance now starts as, unless the user picked a form.
  final bool isActive;

  /// The figures to list; defaults to the shipped glossary of the form shown.
  /// A test seam: with it, the Glossary offers no choice of form.
  @visibleForTesting
  final List<FigureGlossaryEntry>? entries;

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

/// The dialect the Glossary shows [form]'s figures in: that form's own
/// (ADR-006 W4).
Dialect _dialectFor(BuildContext context, DanceForm form) =>
    ActiveDialectScope.of(context).forForm(form);

/// The dialect the Glossary shows the user's own entries in, whatever form
/// they were made for: contra's, as their detail, the Custom Figures screen
/// and the editor show them, so each reads the same everywhere. Each moves to
/// its own form's when those surfaces do (ADR-006 implementation plan, W7).
Dialect _customDialect(BuildContext context) =>
    _dialectFor(context, DanceForm.contra);

/// Renders the user's own entries, with [_customDialect].
final FigureRenderer _customRenderer = glossaryRenderer(DanceForm.contra);

/// The name [entry] is listed and headed by under [dialect]
/// ([glossaryFigureTitle]).
String _entryTitle(
  AppLocalizations l10n,
  FigureGlossaryEntry entry,
  List<FigureGlossaryEntry> all,
  Dialect dialect,
  DanceForm form,
) => glossaryFigureTitle(l10n, entry.id, all, dialect, form: form);

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

  /// The dance form whose figures are shown (ADR-006 W5). It opens on the
  /// form a new dance starts as (S6), read again each time the Glossary is
  /// shown ([GlossaryScreen.isActive]), until the user picks one.
  DanceForm _form = DanceForm.contra;
  bool _formPicked = false;

  FigureRenderer get _renderer => glossaryRenderer(_form);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    if (repos != null) unawaited(_openOnNewDanceForm(repos));
    unawaited(_userEntriesSub?.cancel());
    _userEntriesSub = repos?.userGlossary.watchAll().listen((entries) {
      if (mounted) setState(() => _userEntries = entries);
    });
  }

  /// Shows the form a new dance starts as (S6): the default-form setting,
  /// or the last form used. Contra if it can't be read, or for a form with
  /// no figures of its own ([glossaryFormFor]).
  Future<void> _openOnNewDanceForm(CompendiumRepositories repos) async {
    DanceForm form;
    try {
      form = resolveNewDanceForm(
        defaultFormStored: await repos.settings.get(kDefaultDanceFormKey),
        lastUsedStored: await repos.settings.get(kLastUsedDanceFormKey),
      );
    } catch (_) {
      // diagnostics: silent — the Glossary then opens on contra, as it did
      // before it had a choice of form.
      return;
    }
    final shown = glossaryFormFor(form);
    if (!mounted || _formPicked || shown == _form) return;
    setState(() {
      _form = shown;
      _selectedId = null;
    });
  }

  @override
  void didUpdateWidget(GlossaryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repos = _repos;
    if (widget.isActive && !oldWidget.isActive && repos != null) {
      unawaited(_openOnNewDanceForm(repos));
    }
  }

  void _pickForm(DanceForm form) {
    if (form == _form) return;
    setState(() {
      _form = form;
      _formPicked = true;
      _selectedId = null;
    });
  }

  @override
  void dispose() {
    unawaited(_userEntriesSub?.cancel());
    _search.dispose();
    super.dispose();
  }

  List<FigureGlossaryEntry> get _entries =>
      widget.entries ?? shippedFigureGlossaryEntriesFor(_form);

  List<_ShownEntry> _shown(
    AppLocalizations l10n,
    Dialect dialect,
    List<CustomGlossaryItem> custom,
    Dialect customDialect,
  ) {
    final shown = [
      for (final e in _entries)
        _ShownEntry.shipped(
          e,
          _entryTitle(l10n, e, _entries, dialect, _form),
          switch (e.definition) {
            final d? => _renderer.renderFreeText(d.definition, dialect),
            null => null,
          },
        ),
      for (final c in custom)
        _ShownEntry.custom(
          c,
          _customRenderer.renderFreeText(c.entry.name, customDialect),
          _customRenderer.renderFreeText(c.entry.definition, customDialect),
          keywords: [
            for (final k in c.entry.keywords)
              _customRenderer.renderFreeText(k, customDialect),
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

  /// The user's own entries resolved for display: their terms, and while
  /// Custom Figures is on, everything else too (#1023, maintainer decision
  /// 9). Each is checked for a rename against all of them, shown or not.
  List<CustomGlossaryItem> _custom(BuildContext context, Dialect dialect) {
    final figuresShown = customFiguresShown(context);
    final all = resolveCustomGlossary(
      _userEntries,
      // Checked against contra's figures, as the detail and the editor
      // check them.
      taxonomy: contraTaxonomy,
      dialects: [
        dialect,
        ...?DialectLibraryScope.maybeOf(context)?.allCustomDialects,
      ],
      shorthandTokens: ShorthandMappingsScope.tokensOf(context),
    );
    // Each entry is listed under its own form, or contra's for one with no
    // figures of its own, or one this build does not know.
    DanceForm listedUnder(UserGlossaryEntry entry) {
      final form = glossaryEntryForm(entry.payload);
      for (final value in DanceForm.values) {
        if (value.name == form) return glossaryFormFor(value);
      }
      return DanceForm.contra;
    }

    return [
      for (final item in all)
        if ((figuresShown || item.isTerm) &&
            (widget.entries != null || listedUnder(item.entry) == _form))
          item,
    ];
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
    final entry = shown.entry!;
    return GlossaryFigureDetail(
      key: ValueKey('glossary-detail-${shown.id}'),
      entryId: entry.id,
      entries: _entries,
      form: _form,
      showName: showName,
      // A figure of your own needs Custom Figures (maintainer decision 9),
      // and somewhere to be saved.
      onCopy: customFiguresShown(context) && _repos != null
          ? () => _copy(context, entry)
          : null,
    );
  }

  /// Opens the editor on a new figure of the user's own, copied from the
  /// shipped [entry] (#1023, maintainer decision 6): its parameters, beats
  /// and wording ([userFigureSeedFromMove]), and its definition and
  /// description, under the name "`<name>` (copy)", numbered if the user
  /// already has one. Nothing is stored until the user saves.
  Future<void> _copy(BuildContext context, FigureGlossaryEntry entry) async {
    if (_copying) return;
    _copying = true;
    try {
      await _copyOnce(context, entry);
    } finally {
      _copying = false;
    }
  }

  /// Whether a copy's editor is open or opening: a second tap does nothing.
  bool _copying = false;

  /// Whether the Glossary was last laid out split, the detail beside the
  /// list.
  bool _wide = false;

  Future<void> _copyOnce(
    BuildContext context,
    FigureGlossaryEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context);
    final form = _form;
    // The copy is one of the user's own, so it is named in the dialect the
    // editor shows those in.
    final dialect = _customDialect(context);
    final seed = userFigureSeedFromMove(
      shippedTaxonomies.forForm(form),
      entry.id,
      choiceLabel: (_, value) => humanizeToken(value),
      paramLabel: (key) => figureParamKeyLabel(l10n, key, moveId: entry.id),
    );
    if (seed == null) return;
    // Names are stored canonical, so a name is compared in that form, as the
    // editor checks it.
    String stored(String name) =>
        normalizeGlossaryName(canonicalizeGlossaryText(name, dialect));
    final taken = {
      for (final e in await _repos!.userGlossary.listAll())
        normalizeGlossaryName(e.name),
    };
    if (!context.mounted) return;
    final base = l10n.commonDuplicateTitleSuffix(
      _entryTitle(l10n, entry, _entries, dialect, form),
    );
    var name = base;
    for (var n = 2; taken.contains(stored(name)); n++) {
      name = '$base $n';
    }
    final definition = entry.definition;
    final saved = await Navigator.of(context).push<UserGlossaryEntry>(
      MaterialPageRoute(
        builder: (_) => CompoundEditorScreen(
          copyOf: UserGlossaryEntry(
            id: '',
            kindName: UserGlossaryEntryKind.customFigure.name,
            // The editor shows each field in the active dialect, as stored
            // text is shown; the name is already in it.
            name: name,
            definition: definition?.definition ?? '',
            description: definition?.description ?? '',
            // The copy is offered in the form it was copied from.
            payload: {...seed.toJson(), 'form': form.name},
            createdAt: DateTime.now().toUtc(),
          ),
        ),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _selectedId = customSelectionId(saved.id));
    // Narrow, the built-in's page is still on top: show the copy in its
    // place, as the wide pane shows it beside the list.
    if (!_wide && context.mounted) {
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: CustomFigureTitle(
                  entryId: saved.id,
                  fallback: saved.name,
                ),
              ),
              body: GlossaryCustomFigureDetail(
                key: ValueKey('glossary-detail-${customSelectionId(saved.id)}'),
                entryId: saved.id,
                showName: false,
              ),
            ),
          ),
        ),
      );
    }
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
    final termsOnly = !customFiguresShown(context);
    final saved = await Navigator.of(context).push<UserGlossaryEntry>(
      MaterialPageRoute(
        builder: (_) => CompoundEditorScreen(
          termsOnly: termsOnly,
          // Listed under the form it was added on (ADR-006 W5).
          initialForm: widget.entries == null ? _form : null,
        ),
      ),
    );
    if (saved != null && mounted) {
      setState(() => _selectedId = customSelectionId(saved.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialect = _dialectFor(context, _form);
    final customDialect = _customDialect(context);
    final custom = _custom(context, customDialect);
    final shown = _shown(l10n, dialect, custom, customDialect);
    // A term needs only the Glossary, which this screen is; a figure of your
    // own needs Custom Figures on too (#1023, maintainer decision 9).
    final canAdd = _repos != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.glossaryTitle),
        actions: [
          // Same Sync now entry as the Collection and Programs bars; renders
          // nothing unless Device Sync is on and paired.
          const SyncNowAction(),
          if (canAdd)
            IconButton(
              key: const ValueKey('glossary-add-custom'),
              icon: const Icon(Icons.add),
              tooltip: customFiguresShown(context)
                  ? l10n.glossaryAddCustomFigure
                  : l10n.glossaryAddTerm,
              onPressed: () => _add(context),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = AppBreakpoints.showsSplit(context, constraints.maxWidth);
          _wide = wide;
          final list = _GlossaryList(
            search: _search,
            onQueryChanged: (q) => setState(() => _query = q),
            entries: shown,
            query: _query,
            selectedId: wide ? _selectedId : null,
            onOpen: (s) => _open(context, s, wide: wide),
            form: _form,
            forms: widget.entries == null ? glossaryForms : const [],
            onFormChanged: _pickForm,
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
    required this.form,
    required this.forms,
    required this.onFormChanged,
  });

  /// The dance form shown, one of [forms]; no choice when there is only one.
  final DanceForm form;
  final List<DanceForm> forms;
  final ValueChanged<DanceForm> onFormChanged;

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
        if (forms.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: SegmentedButton<DanceForm>(
              key: const ValueKey('glossary-form'),
              showSelectedIcon: false,
              segments: [
                for (final f in forms)
                  ButtonSegment(
                    value: f,
                    label: Text(
                      danceFormLabel(l10n, f),
                      key: ValueKey('glossary-form-${f.name}'),
                    ),
                  ),
              ],
              selected: {form},
              onSelectionChanged: (selection) =>
                  onFormChanged(selection.single),
            ),
          ),
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
    this.form = DanceForm.contra,
    this.showName = false,
    this.onCopy,
  });

  /// The dance form whose figure this is, which sets its dialect.
  final DanceForm form;

  /// Copies the figure as one of the user's own (#1023); no button without
  /// it.
  final VoidCallback? onCopy;

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
    final dialect = _dialectFor(context, form);
    final renderer = glossaryRenderer(form);
    final capitalize = CapitalizeFiguresScope.of(context);
    final decimals = DecimalTurnsScope.of(context);
    final verbose = VerboseFigureRenderingScope.of(context);
    final all = entries ?? shippedFigureGlossaryEntriesFor(form);
    final entry = all.firstWhere((e) => e.id == entryId);
    final name = _entryTitle(l10n, entry, all, dialect, form);
    final definition = entry.definition;

    // Other names: the canonical name (when a custom dialect renames the
    // figure), the aliases of this move, then its search keywords — minus
    // anything that just repeats the name shown.
    final shownLower = {
      renderer.displayMoveName(entry.id, dialect).toLowerCase(),
    };
    final otherNames = <String>[entry.canonicalName];
    for (final e in all) {
      if (e.isAlias && e.targetMoveId == entry.id) {
        otherNames.add(renderer.displayMoveName(e.id, dialect));
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
    final spoken = renderer.renderVerbose(figure, dialect);
    final example = capitalizeFirstLetter(
      verbose ? spoken : renderer.render(figure, dialect, decimals: decimals),
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
                renderer.displayMoveName(entry.targetMoveId, dialect),
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
              renderer.renderFreeText(definition.definition, dialect),
              key: const ValueKey('glossary-definition'),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              renderer.renderFreeText(definition.description, dialect),
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
        if (onCopy != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('glossary-copy-figure'),
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined),
                label: Text(l10n.glossaryCopyAsOwnFigure),
              ),
            ),
          ),
        FigureNotesSection(figureId: entry.id, form: form),
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
  const FigureNotesSection({
    super.key,
    required this.figureId,
    this.form = DanceForm.contra,
  });

  /// The shipped move or alias id the notes are on.
  final String figureId;

  /// The dance form of [figureId], whose dialect the notes are shown and
  /// typed in.
  final DanceForm form;

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
    final l10n = AppLocalizations.of(context);
    // The dialog saves, not this method, so a note that is refused leaves the
    // dialog open with what the user typed and says why, instead of closing on
    // a message that asks them to try again with the text gone.
    await showDialog<void>(
      context: context,
      builder: (_) => _NotesDialog(
        initial: _notes == null
            ? ''
            : glossaryRenderer(widget.form).renderFreeText(_notes!, dialect),
        // Empty text deletes the note.
        save: (text) async {
          try {
            await repos.figureNotes.set(
              widget.figureId,
              canonicalizeGlossaryText(text, dialect),
            );
            return null;
          } on FigureNoteInvalid catch (e) {
            // diagnostics: silent — either the user's text is over the stored
            // bound, which canonical role tokens can push it past, or the whole
            // Glossary is full; the message says which and what to do.
            return e.overBudget
                ? l10n.glossaryOverBudget
                : l10n.glossaryNotesTooLong;
          }
        },
      ),
      animationStyle: AppMotion.styleFor(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_repos == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dialect = _dialectFor(context, widget.form);
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
            glossaryRenderer(widget.form).renderFreeText(notes, dialect),
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

/// Edits the notes on a shipped figure and stores them through [save]; stays
/// open with the reason when [save] refuses the text, and closes once it is
/// stored or on cancel.
/// Owns its controller, so it outlives the dialog's closing animation.
class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.initial, required this.save});

  final String initial;

  /// Stores the text; returns why it was refused, or null once it is stored.
  final Future<String?> Function(String text) save;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final String? error;
    try {
      error = await widget.save(_controller.text);
    } catch (_) {
      // diagnostics: silent — rethrown below, so it surfaces as it did before;
      // this only leaves Save usable for a retry (a refusal comes back as text,
      // not as an exception).
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _error = error;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Nothing closes the dialog while a save is in flight (Cancel, the barrier,
    // Escape or back): the save would finish into a route that is already
    // leaving and pop the one beneath it, and the note would be stored anyway.
    // Once the text differs from what the dialog opened with, the barrier,
    // Escape and back do nothing either, so a stray tap does not lose it.
    return DirtyDialogGuard(
      listenable: _controller,
      isDirty: () => _controller.text != widget.initial,
      blocked: _saving,
      child: AlertDialog(
        title: Text(l10n.glossaryNotesEditTitle),
        content: TextField(
          key: const ValueKey('glossary-notes-field'),
          controller: _controller,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: maxUserGlossaryTextLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          decoration: InputDecoration(
            hintText: l10n.glossaryNotesHint,
            errorText: _error,
            errorMaxLines: 4,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('glossary-notes-cancel'),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('glossary-notes-save'),
            onPressed: _saving ? null : _save,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
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
