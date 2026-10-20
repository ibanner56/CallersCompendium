import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/dialect_library_controller.dart';
import '../../data/dialect_library_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/program_matrix_column_config_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/settings_keys.dart';
import '../../data/show_custom_figures_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../glossary/custom_figures.dart';
import '../../glossary/user_figure_defaults.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import 'compound_editor_screen.dart';
import 'user_figure_switch_screen.dart';

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
    // One action at a time: a delete and a switch both retire the figure.
    if (_deleting || _switching) return;
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
    // The Trash's dances keep the line each last stored (plan C9).
    final trashed = isFigure
        ? await repos.dances.countTrashedDancesUsingUserFigure(widget.entryId)
        : 0;
    // Whether the default figure lists use it, to say so.
    final inDefaults = isFigure && (await _frozenDefaults(repos)).isNotEmpty;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.glossaryCustomDeleteTitle(name)),
        content: Text(
          uses == null
              ? l10n.glossaryCustomDeleteBody
              : [
                  l10n.glossaryCustomDeleteUses(uses),
                  if (trashed > 0) l10n.glossaryCustomDeleteTrash(trashed),
                  if (inDefaults) l10n.glossaryCustomDeleteDefaults,
                ].join(' '),
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
      // Read again now, not when the dialog opened: the lists, or the figure,
      // may have changed while it was open. Read before the delete, while the
      // figure still renders.
      final frozenDefaults = await _frozenDefaults(repos);
      await repos.deleteUserFigure(widget.entryId);
      await _forgetSettings(navigator, repos, dialects, frozenDefaults);
    } else {
      await repos.userGlossary.delete(widget.entryId);
    }
    if (!widget.showName && mounted) navigator.pop();
  }

  /// Set while a switch is being chosen or asked about, so a second tap
  /// opens no second screen.
  bool _switching = false;

  /// Switches this figure to the shipped figure [target] that now has its
  /// name (#1023, maintainer decision 5): the user maps it onto [target]
  /// ([UserFigureSwitchScreen]), confirms with how many dances use it, and
  /// then its uses become [target]'s and it is retired.
  Future<void> _switch(
    BuildContext context,
    UserFigureDefinition figure,
    String target,
  ) async {
    if (_switching || _deleting) return;
    _switching = true;
    try {
      await _chooseAndSwitch(context, figure, target);
    } finally {
      _switching = false;
    }
  }

  Future<void> _chooseAndSwitch(
    BuildContext context,
    UserFigureDefinition figure,
    String target,
  ) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repos = _repos!;
    // Read before anything is awaited: the switch can unmount this page (in
    // the wide Glossary it does).
    final dialects = DialectLibraryScope.maybeOf(context);
    final shorthands = ShorthandMappingsScope.maybeOf(context);
    final targetName = _renderer.displayMoveName(
      target,
      ActiveDialectScope.of(context),
    );
    final mapping = await navigator.push<UserFigureSwitch>(
      MaterialPageRoute(
        builder: (_) => UserFigureSwitchScreen(figure: figure, target: target),
      ),
    );
    if (mapping == null || !context.mounted) return;
    final uses = await repos.dances.countDancesUsingUserFigure(widget.entryId);
    final trashed = await repos.dances.countTrashedDancesUsingUserFigure(
      widget.entryId,
    );
    final inDefaults = (await _switchedDefaults(repos, mapping)).isNotEmpty;
    // Only those that will insert the app's figure: one whose values the
    // figure no longer has, or whose token an ordinary shorthand has, stays.
    final shorthandCount =
        shorthands?.userFigureShorthands
            .where(
              (s) =>
                  s.figureId == widget.entryId &&
                  !shorthands.mappings.any(
                    (m) => m.normalizedToken == s.normalizedToken,
                  ) &&
                  _switchedShorthand(s, figure, mapping) != null,
            )
            .length ??
        0;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.userFigureSwitchConfirmTitle(targetName)),
        content: Text(
          [
            l10n.userFigureSwitchConfirmUses(uses, targetName),
            if (trashed > 0) l10n.glossaryCustomDeleteTrash(trashed),
            if (inDefaults) l10n.userFigureSwitchConfirmDefaults,
            if (shorthandCount > 0)
              l10n.userFigureSwitchConfirmShorthands(
                shorthandCount,
                targetName,
              ),
          ].join(' '),
          key: const ValueKey('user-figure-switch-confirm-body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('user-figure-switch-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.userFigureSwitchAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Read again now, not when the dialog opened, and before the switch,
    // while the figure is still live.
    final current = await _liveDefinition(repos);
    final switchedDefaults = await _switchedDefaults(repos, mapping);
    try {
      await repos.switchUserFigureToBuiltIn(widget.entryId, mapping);
    } on StateError catch (e, stackTrace) {
      // The figure changed since it was mapped (an edit synced in, say), or
      // is gone: nothing was written.
      logCaughtError(
        e,
        stackTrace,
        source: 'GlossaryCustomFigureDetail._chooseAndSwitch',
      );
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.userFigureSwitchFailed)),
      );
      return;
    }
    // Its shorthands insert the shipped figure now. A failure leaves them
    // inert, showing the figure's name, as after a delete.
    if (current != null) {
      try {
        await shorthands?.switchUserFigureShorthands(
          widget.entryId,
          (shorthand) => _switchedShorthand(shorthand, current, mapping),
        );
      } on Object catch (e, stackTrace) {
        logCaughtError(
          e,
          stackTrace,
          source: 'GlossaryCustomFigureDetail._chooseAndSwitch',
        );
      }
    }
    await _forgetSettings(navigator, repos, dialects, switchedDefaults);
    if (!widget.showName && mounted) navigator.pop();
  }

  /// The figure the shorthand [shorthand] inserts once this figure is
  /// switched to [mapping]'s target, or null to leave it as it is: the use
  /// it inserts, switched as a dance's would be.
  Figure? _switchedShorthand(
    UserFigureShorthand shorthand,
    UserFigureDefinition definition,
    UserFigureSwitch mapping,
  ) {
    final use = userFigureUseFigure(
      id: widget.entryId,
      args: shorthand.args,
      text: shorthand.figureName,
      beats: shorthand.beats,
    );
    final switched = switchUserFigureUsesIn(
      [use],
      widget.entryId,
      definition,
      mapping,
      contraTaxonomy,
      _renderer,
    ).single;
    return switched.move == customMoveId ? null : switched;
  }

  /// This figure's definition as stored now, or null once it is gone or no
  /// longer decodes.
  Future<UserFigureDefinition?> _liveDefinition(
    CompendiumRepositories repos,
  ) async {
    final entry = await repos.userGlossary.getById(widget.entryId);
    if (entry == null || entry.kind != UserGlossaryEntryKind.customFigure) {
      return null;
    }
    return decodeUserFigureDefinition(entry.payload);
  }

  /// The default figure lists that use this figure, switched to [mapping]'s
  /// target ([switchedDefaultFigureLists]); none once it is gone.
  Future<Map<String, String>> _switchedDefaults(
    CompendiumRepositories repos,
    UserFigureSwitch mapping,
  ) async {
    final entry = await repos.userGlossary.getById(widget.entryId);
    final definition = entry == null
        ? null
        : decodeUserFigureDefinition(entry.payload);
    if (entry == null || definition == null) return const {};
    return switchedDefaultFigureLists(
      repos.settings,
      widget.entryId,
      definition,
      mapping,
      FigureRenderer(
        contraTaxonomy,
        userFigures: UserFigureCatalog.fromEntries([entry]),
      ),
    );
  }

  /// What the settings keep for this figure once it is retired, by a delete
  /// or a switch (#1023, plan C9): its uses in the default figure lists
  /// rewritten as [defaults] holds them, and each dialect's name and wording
  /// for it and its matrix column dropped. The figure is gone either way, so
  /// a failure in either step is logged rather than stopping the page from
  /// closing, and neither skips the other.
  Future<void> _forgetSettings(
    NavigatorState navigator,
    CompendiumRepositories repos,
    DialectLibraryController? dialects,
    Map<String, String> defaults,
  ) async {
    // Each dialect's name and wording for it, and its matrix column's place,
    // hiding and rename: nothing would read them again, but they would stay
    // in every backup and sync. A failure leaves only inert keys.
    try {
      await dialects?.forgetUserFigure(widget.entryId);
      // Through the navigator's context: in the wide Glossary the delete
      // unmounts this page as soon as the list no longer holds the entry, and
      // the matrix scope sits above the navigator.
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
        source: 'GlossaryCustomFigureDetail._forgetSettings',
      );
    }
    // Its uses in the default figure lists, rewritten as the dances were. A
    // failure leaves a list holding uses of a figure that is gone: each still
    // shows its stored line, and the dance editor makes it plain text when a
    // dance holding it is saved.
    try {
      for (final MapEntry(:key, :value) in defaults.entries) {
        await persistSetting(repos.settings, key, value);
      }
    } on Object catch (e, stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'GlossaryCustomFigureDetail._forgetSettings',
      );
    }
  }

  /// The default figure lists that use this figure, frozen
  /// ([frozenDefaultFigureLists]); none once it is gone.
  Future<Map<String, String>> _frozenDefaults(
    CompendiumRepositories repos,
  ) async {
    final entry = await repos.userGlossary.getById(widget.entryId);
    if (entry == null) return const {};
    return frozenDefaultFigureLists(
      repos.settings,
      widget.entryId,
      FigureRenderer(
        contraTaxonomy,
        userFigures: UserFigureCatalog.fromEntries([entry]),
      ),
    );
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
    // A later version of the app shipped a figure of this one's name (#1023,
    // maintainer decision 5): rename it, or switch to the app's. Only a
    // figure of your own that can be used can switch. (With Custom Figures
    // off, the Glossary lists none.)
    final shippedTarget = figure != null && !item.unsupported
        ? shippedFigureNamed(entry.name, contraTaxonomy)
        : null;
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
        if (shippedTarget != null)
          attention(
            l10n.glossaryCustomShippedNameBody(
              _renderer.displayMoveName(shippedTarget, dialect),
            ),
            'glossary-custom-shipped-name',
          )
        else if (item.renameNeeded)
          attention(
            l10n.glossaryCustomRenameNeededBody,
            'glossary-custom-rename-needed',
          ),
        if (shippedTarget != null && figure != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.xl,
              top: AppSpacing.sm,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton(
                  key: const ValueKey('glossary-custom-rename-mine'),
                  onPressed: _repos == null
                      ? null
                      : () => _edit(context, entry),
                  child: Text(l10n.glossaryCustomRenameMine),
                ),
                OutlinedButton(
                  key: const ValueKey('glossary-custom-switch-to-shipped'),
                  onPressed: _repos == null
                      ? null
                      : () => _switch(context, figure, shippedTarget),
                  child: Text(l10n.glossaryCustomSwitchToShipped),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Text(
            _renderer.renderFreeText(entry.definition, dialect),
            key: const ValueKey('glossary-definition'),
            style: theme.textTheme.bodyLarge,
          ),
        ),
        if (entry.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _renderer.renderFreeText(entry.description, dialect),
              key: const ValueKey('glossary-description'),
            ),
          ),
        // Where a term comes from, as it was written: a Caller's Companion
        // term's source (#1023). Kept whole, so not rendered in the dialect.
        if (item.isTerm)
          if (glossaryTermSource(entry.payload) case final source?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                l10n.glossaryTermSource(source),
                key: const ValueKey('glossary-term-source'),
                style: theme.textTheme.bodySmall,
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
            // Its conditions in words, as its editor shows them.
            wordingForEditing(
              mapUserFigureTemplateText(
                figure.template,
                (text) => _renderer.renderFreeText(text, dialect),
              ),
              _renderer.userFigureWordingVocabulary(figure, dialect),
            ),
            key: const ValueKey('glossary-custom-wording'),
          ),
          if (example != null) ...[
            heading(l10n.glossaryCustomExample),
            Text(example, key: const ValueKey('glossary-custom-example')),
          ],
          // For display only: the copy keeps no link to the figure it came
          // from (#1023, maintainer decision 6).
          if (figure.copiedFrom case final copiedFrom?
              when contraTaxonomy.resolve(copiedFrom) != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                l10n.glossaryCustomCopiedFrom(
                  _renderer.displayMoveName(copiedFrom, dialect),
                ),
                key: const ValueKey('glossary-custom-copied-from'),
                style: theme.textTheme.bodySmall,
              ),
            ),
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
