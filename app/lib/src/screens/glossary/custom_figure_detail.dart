import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/dialect_library_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/program_matrix_column_config_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/settings_keys.dart';
import '../../data/show_custom_figures_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../glossary/custom_figures.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import 'compound_editor_screen.dart';

final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

/// The name a parameter kind is offered and shown under in a custom figure.
String compoundParamKindLabel(AppLocalizations l10n, ParamKind kind) =>
    switch (kind) {
      ParamKind.dancerSet => l10n.compoundParamKindDancers,
      ParamKind.dancerPair => l10n.compoundParamKindDancerPair,
      ParamKind.handedness => l10n.compoundParamKindHand,
      ParamKind.shoulder => l10n.compoundParamKindShoulder,
      ParamKind.spinDirection => l10n.compoundParamKindSpin,
      ParamKind.direction => l10n.compoundParamKindDirection,
      ParamKind.fraction => l10n.compoundParamKindFraction,
      ParamKind.rotation => l10n.compoundParamKindRotation,
      ParamKind.places => l10n.compoundParamKindPlaces,
      ParamKind.beats => l10n.compoundParamKindBeats,
      ParamKind.flag => l10n.compoundParamKindFlag,
      ParamKind.choice => l10n.compoundParamKindChoice,
      ParamKind.text => l10n.compoundParamKindText,
    };

/// The marker a custom figure carries in the Glossary list: "Custom", plus
/// what needs the user's attention, in words rather than colour alone.
class CustomFigureMarker extends StatelessWidget {
  const CustomFigureMarker({super.key, required this.item});

  final CustomGlossaryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final attention = item.unsupported
        ? l10n.glossaryCustomUnsupported
        : item.broken
        ? l10n.glossaryCustomNeedsRepair
        : item.renameNeeded
        ? l10n.glossaryCustomRenameNeeded
        : null;
    return Column(
      key: ValueKey('glossary-custom-marker-${item.entry.id}'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.person_outline, size: 16),
          label: Text(l10n.glossaryCustomMarker),
        ),
        if (attention != null)
          Text(
            attention,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// The detail view of one of the user's own glossary entries (#709), in the
/// active dialect, with its edit and delete actions.
///
/// It reads the entry itself, by id, so it stays current after an edit made
/// from it, wherever it is shown.
class GlossaryCustomFigureDetail extends StatefulWidget {
  const GlossaryCustomFigureDetail({
    super.key,
    required this.entryId,
    this.showName = false,
  });

  /// The [UserGlossaryEntry.id] to show.
  final String entryId;

  /// Whether to head it with its name: on in the wide split pane, off on the
  /// pushed page, whose app bar already names it — and which is closed when
  /// the entry is deleted.
  final bool showName;

  @override
  State<GlossaryCustomFigureDetail> createState() =>
      _GlossaryCustomFigureDetailState();
}

class _GlossaryCustomFigureDetailState
    extends State<GlossaryCustomFigureDetail> {
  CompendiumRepositories? _repos;
  StreamSubscription<List<UserGlossaryEntry>>? _sub;
  List<UserGlossaryEntry>? _entries;

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

  Future<void> _edit(
    BuildContext context,
    UserGlossaryEntry entry, {
    bool convertToFigure = false,
  }) => Navigator.of(context).push<UserGlossaryEntry>(
    MaterialPageRoute(
      builder: (_) => CompoundEditorScreen(
        initial: entry,
        convertToFigure: convertToFigure,
      ),
    ),
  );

  /// Set while a delete is being asked about, so a second tap opens no
  /// second dialog.
  bool _deleting = false;

  Future<void> _delete(
    BuildContext context,
    String name, {
    required bool isFigure,
  }) async {
    if (_deleting) return;
    _deleting = true;
    try {
      await _confirmAndDelete(context, name, isFigure: isFigure);
    } finally {
      _deleting = false;
    }
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    String name, {
    required bool isFigure,
  }) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final repos = _repos!;
    // Read before anything is awaited: the delete can unmount this page (in
    // the wide Glossary it does).
    final dialects = DialectLibraryScope.maybeOf(context);
    // A figure of your own is used by reference (#1023): say how many dances
    // keep its current wording as plain text (maintainer decision 2).
    final uses = isFigure
        ? await repos.dances.countDancesUsingUserFigure(widget.entryId)
        : null;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.glossaryCustomDeleteTitle(name)),
        content: Text(
          uses == null
              ? l10n.glossaryCustomDeleteBody
              : l10n.glossaryCustomDeleteUses(uses),
          key: const ValueKey('glossary-custom-delete-body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('glossary-custom-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (isFigure) {
      await repos.deleteUserFigure(widget.entryId);
      // Then what the settings keep for it (#1023, plan C9): each dialect's
      // name and wording for it, and its matrix column's place, hiding and
      // rename. Nothing would read them again, and they would otherwise stay
      // in every backup and sync. The figure is gone either way: a failure
      // here leaves only inert keys, so it is logged rather than stopping the
      // page from closing.
      try {
        await dialects?.forgetUserFigure(widget.entryId);
        // Through the navigator's context: in the wide Glossary the delete
        // unmounts this page as soon as the list no longer holds the entry,
        // and the matrix scope sits above the navigator.
        final scopeContext = navigator.context;
        if (scopeContext.mounted &&
            ProgramMatrixColumnConfigScope.maybeNotifierOf(scopeContext) !=
                null) {
          await _dropMatrixColumn(scopeContext, repos);
        }
      } on Object catch (e, stackTrace) {
        logCaughtError(
          e,
          stackTrace,
          source: 'GlossaryCustomFigureDetail._confirmAndDelete',
        );
      }
    } else {
      await repos.userGlossary.delete(widget.entryId);
    }
    if (!widget.showName && mounted) navigator.pop();
  }

  /// Drops the deleted figure's matrix column from the live config, then
  /// stores it, as the Matrix columns screen writes it (#1023, plan C9).
  Future<void> _dropMatrixColumn(
    BuildContext scopeContext,
    CompendiumRepositories repos,
  ) {
    final matrix = ProgramMatrixColumnConfigScope.notifierOf(scopeContext);
    final kept = matrix.value.withoutColumn(userFigureKeyFor(widget.entryId));
    if (identical(kept, matrix.value)) return Future.value();
    matrix.value = kept;
    return persistSetting(
      repos.settings,
      kProgramMatrixColumnsKey,
      kept.toJson(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dialect = ActiveDialectScope.of(context);
    final entries = _entries;
    if (entries == null) return const SizedBox.shrink();
    final items = resolveCustomGlossary(
      entries,
      taxonomy: contraTaxonomy,
      dialects: [
        dialect,
        ...?DialectLibraryScope.maybeOf(context)?.customDialects,
      ],
      shorthandTokens: ShorthandMappingsScope.tokensOf(context),
    );
    final item = items.where((i) => i.entry.id == widget.entryId).firstOrNull;
    if (item == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            l10n.glossaryCustomGone,
            key: const ValueKey('glossary-custom-gone'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final entry = item.entry;
    final name = _renderer.renderFreeText(entry.name, dialect);
    final definition = item.definition;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );

    Widget attention(String text, String key) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, key: ValueKey(key))),
        ],
      ),
    );

    final figure = item.figure;
    final example = figure == null ? null : _exampleOf(entry, figure, dialect);
    final args = definition == null
        ? null
        : previewArguments(definition, contraTaxonomy);
    final expanded = definition == null || args == null
        ? null
        : expandCompound(definition, args, contraTaxonomy);

    return ListView(
      key: const ValueKey('glossary-custom-detail'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (widget.showName)
          Semantics(
            header: true,
            child: Text(name, style: theme.textTheme.headlineSmall),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: CustomFigureMarker(item: item),
        ),
        if (item.unsupported)
          attention(
            l10n.glossaryCustomUnsupportedBody,
            'glossary-custom-unsupported',
          )
        else if (item.broken)
          attention(
            l10n.glossaryCustomNeedsRepairBody,
            'glossary-custom-needs-repair',
          ),
        if (item.renameNeeded)
          attention(
            l10n.glossaryCustomRenameNeededBody,
            'glossary-custom-rename-needed',
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Text(
            _renderer.renderFreeText(entry.definition, dialect),
            key: const ValueKey('glossary-definition'),
            style: theme.textTheme.bodyLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            _renderer.renderFreeText(entry.description, dialect),
            key: const ValueKey('glossary-description'),
          ),
        ),
        if (definition != null && definition.params.isNotEmpty) ...[
          heading(l10n.glossaryParameters),
          Text(
            [
              for (final p in definition.params)
                l10n.compoundParamWithKind(
                  p.key,
                  compoundParamKindLabel(l10n, p.kind),
                ),
            ].join(', '),
            key: const ValueKey('glossary-parameters'),
          ),
        ],
        if (figure != null) ...[
          if (figure.params.isNotEmpty) ...[
            heading(l10n.glossaryParameters),
            Text(
              [
                for (final p in figure.params)
                  l10n.compoundParamWithKind(
                    p.key,
                    compoundParamKindLabel(l10n, p.kind),
                  ),
              ].join(', '),
              key: const ValueKey('glossary-parameters'),
            ),
          ],
          heading(l10n.glossaryCustomWording),
          Text(
            mapUserFigureTemplateText(
              figure.template,
              (text) => _renderer.renderFreeText(text, dialect),
            ),
            key: const ValueKey('glossary-custom-wording'),
          ),
          if (example != null) ...[
            heading(l10n.glossaryCustomExample),
            Text(example, key: const ValueKey('glossary-custom-example')),
          ],
        ],
        if (!item.unsupported) ...[
          heading(l10n.glossaryEntryFormLabel),
          Text(
            glossaryEntryFormLabel(l10n, item.form),
            key: const ValueKey('glossary-custom-form'),
          ),
        ],
        // The expansion stays out of the flat list and is folded here until
        // asked for (maintainer, #709).
        if (expanded != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: ExpansionTile(
              key: const ValueKey('glossary-custom-expands-to'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                l10n.glossaryCustomExpandsTo(
                  CompoundDefinition.beatsOf(expanded, contraTaxonomy),
                ),
              ),
              children: [
                for (final figure in expanded)
                  ListTile(
                    dense: true,
                    title: Text(_renderer.renderSummary(figure, dialect)),
                  ),
              ],
            ),
          ),
        if (entry.keywords.isNotEmpty) ...[
          heading(l10n.glossaryAlsoKnownAs),
          Wrap(
            key: const ValueKey('glossary-also-known-as'),
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final k in entry.keywords)
                Chip(label: Text(_renderer.renderFreeText(k, dialect))),
            ],
          ),
        ],
        if (entry.notes case final notes?) ...[
          heading(l10n.glossaryNotes),
          Text(
            _renderer.renderFreeText(notes, dialect),
            key: const ValueKey('glossary-notes'),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('glossary-custom-edit'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.commonEdit),
                onPressed: item.unsupported || _repos == null
                    ? null
                    : () => _edit(context, entry),
              ),
              // A term can be given a figure, once (#1023, maintainer
              // decision 7); a figure of your own needs Custom Figures on.
              if (item.isTerm && customFiguresShown(context))
                OutlinedButton.icon(
                  key: const ValueKey('glossary-term-make-figure'),
                  icon: const Icon(Icons.add_box_outlined),
                  label: Text(l10n.glossaryTermMakeFigure),
                  onPressed: _repos == null
                      ? null
                      : () => _edit(context, entry, convertToFigure: true),
                ),
              OutlinedButton.icon(
                key: const ValueKey('glossary-custom-delete'),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.commonDelete),
                onPressed: _repos == null
                    ? null
                    : () => _delete(
                        context,
                        name,
                        isFigure:
                            entry.kind == UserGlossaryEntryKind.customFigure,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How a figure of your own reads with its defaults, in [dialect], or null
/// when it can't be rendered.
String? _exampleOf(
  UserGlossaryEntry entry,
  UserFigureDefinition figure,
  Dialect dialect,
) {
  final renderer = FigureRenderer(
    contraTaxonomy,
    userFigures: UserFigureCatalog.fromEntries([entry]),
  );
  final use = userFigureUseFigure(
    id: entry.id,
    args: {
      for (final p in figure.params)
        if (p.defaultValue != null) p.key: p.defaultValue,
    },
    text: '',
  );
  if (renderer.renderUserFigureCanonical(use) == null) return null;
  return renderer.render(use, dialect);
}

/// A custom figure's name in the active dialect, kept current as the entry
/// changes: the title of its pushed detail page, from which it can be renamed.
/// [fallback] shows until the entry is read. The page closes when the entry
/// is deleted from it.
class CustomFigureTitle extends StatefulWidget {
  const CustomFigureTitle({
    super.key,
    required this.entryId,
    required this.fallback,
  });

  final String entryId;
  final String fallback;

  @override
  State<CustomFigureTitle> createState() => _CustomFigureTitleState();
}

class _CustomFigureTitleState extends State<CustomFigureTitle> {
  CompendiumRepositories? _repos;
  StreamSubscription<List<UserGlossaryEntry>>? _sub;
  String? _name;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    unawaited(_sub?.cancel());
    _sub = repos?.userGlossary.watchAll().listen((entries) {
      final name = entries
          .where((e) => e.id == widget.entryId)
          .firstOrNull
          ?.name;
      if (mounted && name != null) setState(() => _name = name);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name;
    return Text(
      name == null
          ? widget.fallback
          : _renderer.renderFreeText(name, ActiveDialectScope.of(context)),
      key: const ValueKey('glossary-custom-title'),
    );
  }
}
