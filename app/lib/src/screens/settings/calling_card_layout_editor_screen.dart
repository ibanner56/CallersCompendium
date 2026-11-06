import 'dart:async';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/calling_card_settings_scope.dart';
import '../../data/canonical_discouraged_terms_scope.dart';
import '../../data/dance_share_fields_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/user_figures_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../export/calling_card_layout.dart';
import '../../export/calling_card_pdf.dart';
import '../../export/calling_card_sample.dart';
import '../../export/export_labels_l10n.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import 'calling_card_labels.dart';

/// Turns a one-page PDF into a PNG of its first page at [dpi]. Defaults to
/// [rasterizeCallingCard]; tests replace it, since the platform rasterizer is
/// not available under `flutter test`.
typedef CallingCardRasterizer =
    Future<Uint8List> Function(Uint8List pdf, double dpi);

/// The platform rasterizer: the `printing` plugin's pdfium (desktop), pdf.js
/// (web) or the OS renderer (mobile).
Future<Uint8List> rasterizeCallingCard(Uint8List pdf, double dpi) async {
  await for (final page in Printing.raster(pdf, pages: const [0], dpi: dpi)) {
    return page.toPng();
  }
  throw StateError('The calling-card PDF has no page to preview.');
}

/// Edits the calling-card layout (Settings › Experimental › Calling cards ›
/// Card layout), with the language's help, line-by-line problems and a live
/// preview of a sample dance beside it.
///
/// The text is saved as the user types (debounced), so leaving the screen
/// never loses work; Reset and the examples replace it, the examples with an
/// Undo.
class CallingCardLayoutEditorScreen extends StatefulWidget {
  const CallingCardLayoutEditorScreen({super.key, this.rasterizer});

  final CallingCardRasterizer? rasterizer;

  @override
  State<CallingCardLayoutEditorScreen> createState() =>
      _CallingCardLayoutEditorScreenState();
}

class _CallingCardLayoutEditorScreenState
    extends State<CallingCardLayoutEditorScreen> {
  /// How long typing must pause before the layout is saved and redrawn.
  @visibleForTesting
  static const debounce = Duration(milliseconds: 400);

  late final TextEditingController _controller;
  late CallingCardLayout _layout;
  Timer? _timer;
  bool _dirty = false;
  bool _started = false;

  /// Bumped per preview request, so a slow render never replaces a newer one.
  int _generation = 0;
  Uint8List? _png;
  CallingCardFitReport? _fit;
  bool _previewFailed = false;

  ValueNotifier<CallingCardSettings>? _notifier;
  SettingsRepository? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifier = CallingCardSettingsScope.notifierOf(context);
    _settings = RepositoriesScope.of(context).settings;
    if (!_started) {
      _started = true;
      final source = _notifier!.value.layoutSource;
      _controller = TextEditingController(text: source);
      _layout = CallingCardLayout.parse(source);
      _renderPreview();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_dirty) unawaited(_save(_controller.text));
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() => _layout = CallingCardLayout.parse(text));
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(_save(text));
      _renderPreview();
    });
  }

  /// Replaces the whole text, saves it at once and redraws.
  void _replaceText(String text) {
    _timer?.cancel();
    _controller.text = text;
    setState(() => _layout = CallingCardLayout.parse(text));
    unawaited(_save(text));
    _renderPreview();
  }

  Future<void> _save(String text) async {
    _dirty = false;
    final notifier = _notifier!;
    final next = notifier.value.copyWith(
      layout: () => text == kDefaultCallingCardLayout ? null : text,
    );
    if (next == notifier.value) return;
    notifier.value = next;
    await persistSetting(_settings!, kCallingCardSettingsKey, next.toJson());
  }

  Future<void> _renderPreview() async {
    final generation = ++_generation;
    final l10n = AppLocalizations.of(context);
    final settings = _notifier!.value;
    final layout = _layout;
    final rasterize = widget.rasterizer ?? rasterizeCallingCard;
    final dialect = ActiveDialectScope.of(context);
    final renderer = UserFiguresScope.rendererOf(context);
    final fields = DanceShareFieldsScope.of(context);
    final canonical = CanonicalDiscouragedTermsScope.of(context);
    final labels = danceExportLabels(l10n);
    final dance = callingCardSampleDance(
      title: l10n.callingCardSampleTitle,
      notes: l10n.callingCardSampleNotes,
      figureNote: l10n.callingCardSampleFigureNote,
    );
    final entry = CallingCardEntry(
      dance: dance,
      number: '3',
      labels: (
        authorNames: [l10n.callingCardSampleAuthor],
        formationLabel: formationDisplayLabel(
          l10n,
          dance.formation,
          renderer,
          dialect,
          canonicalizeDiscouragedTerms: canonical,
        ),
        levelLabel: l10n.commonDanceLevelBeginner,
        statusLabel: danceStatusLabel(l10n, dance.status),
        sourceLines: const [],
      ),
    );
    try {
      final report = CallingCardFitReport();
      final pdf = await buildCallingCardsPdf(
        [entry],
        layout: layout,
        size: settings.size,
        dialect: dialect,
        fields: fields,
        renderer: renderer,
        labels: labels,
        programTitle: l10n.callingCardSampleProgram,
        canonicalizeDiscouragedTerms: canonical,
        report: report,
      );
      final png = await rasterize(pdf, 144);
      if (!mounted || generation != _generation) return;
      setState(() {
        _png = png;
        _fit = report;
        _previewFailed = false;
      });
    } catch (error, stack) {
      logCaughtError(error, stack, source: 'calling_card_editor.preview');
      if (!mounted || generation != _generation) return;
      setState(() => _previewFailed = true);
    }
  }

  Future<void> _confirmReset() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.callingCardEditorResetConfirmTitle),
        content: Text(l10n.callingCardEditorResetConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('calling-card-reset-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.callingCardEditorReset),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _replaceText(kDefaultCallingCardLayout);
  }

  void _useExample(String source) {
    final l10n = AppLocalizations.of(context);
    final previous = _controller.text;
    if (previous == source) return;
    _replaceText(source);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.callingCardEditorReplaced),
          action: SnackBarAction(
            label: l10n.commonUndo,
            onPressed: () {
              if (mounted) _replaceText(previous);
            },
          ),
        ),
      );
  }

  /// Inserts [snippet] at the cursor: a block on a line of its own, an option
  /// after a space.
  void _insert(String snippet, {required bool block}) {
    final text = _controller.text;
    final selection = _controller.selection;
    final at = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before = text.substring(0, at);
    final String insertion;
    if (block) {
      final needsBreak = before.isNotEmpty && !before.endsWith('\n');
      insertion = '${needsBreak ? '\n' : ''}$snippet\n';
    } else {
      final needsSpace =
          before.isNotEmpty && !before.endsWith(' ') && !before.endsWith('\n');
      insertion = '${needsSpace ? ' ' : ''}$snippet';
    }
    final next = before + insertion + text.substring(end);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + insertion.length),
    );
    _onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editor = [
      _editorField(l10n),
      if (_layout.issues.isNotEmpty) _issues(l10n),
    ];
    final aside = [_preview(l10n), _help(l10n)];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.callingCardEditorTitle),
        actions: [
          TextButton(
            key: const ValueKey('calling-card-reset'),
            onPressed: _confirmReset,
            child: Text(l10n.callingCardEditorReset),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 840) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [...editor, ...aside],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: editor,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: aside,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
  );

  Widget _editorField(AppLocalizations l10n) => TextField(
    key: const ValueKey('calling-card-layout-field'),
    controller: _controller,
    onChanged: _onChanged,
    minLines: 10,
    maxLines: null,
    keyboardType: TextInputType.multiline,
    autocorrect: false,
    enableSuggestions: false,
    style: _mono,
    decoration: InputDecoration(
      labelText: l10n.callingCardEditorFieldLabel,
      helperText: l10n.callingCardEditorAutosaveHint,
      alignLabelWithHint: true,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _issues(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        key: const ValueKey('calling-card-issues'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.callingCardEditorIssuesTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          for (final issue in _layout.issues)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(callingCardIssueMessage(l10n, issue))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _preview(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final size = _notifier!.value.size;
    final png = _png;
    final fit = _fit;
    final Widget body;
    if (_previewFailed) {
      body = Text(
        l10n.callingCardEditorPreviewError,
        key: const ValueKey('calling-card-preview-error'),
      );
    } else if (png == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = AspectRatio(
        aspectRatio: size.widthPoints / size.heightPoints,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: kElevationToShadow[2],
          ),
          child: Image.memory(
            png,
            key: const ValueKey('calling-card-preview-image'),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }
    final scale = fit == null || fit.scales.isEmpty ? 1.0 : fit.scales.first;
    final overflowed = fit != null && fit.overflowed.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.callingCardEditorPreviewTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          body,
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.callingCardEditorPreviewCaption(
              callingCardSizeLabel(l10n, size),
            ),
            style: theme.textTheme.bodySmall,
          ),
          if (overflowed)
            Text(
              l10n.callingCardEditorPreviewOverflow,
              key: const ValueKey('calling-card-preview-overflow'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (scale < 1)
            Text(
              l10n.callingCardEditorPreviewShrunk((scale * 100).round()),
              key: const ValueKey('calling-card-preview-shrunk'),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _code(String code, {required bool block}) => ActionChip(
    key: ValueKey('calling-card-insert-$code'),
    label: Text(code, style: _mono),
    visualDensity: VisualDensity.compact,
    onPressed: () => _insert(code, block: block),
  );

  Widget _helpRow(List<String> codes, String text, {required bool block}) =>
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [for (final c in codes) _code(c, block: block)],
            ),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs, top: 2),
              child: Text(text),
            ),
          ],
        ),
      );

  Widget _help(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          key: const ValueKey('calling-card-help'),
          initiallyExpanded: true,
          leading: const Icon(Icons.help_outline),
          title: Text(l10n.callingCardHelpTitle),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.callingCardHelpIntro),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.callingCardHelpFields),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.callingCardHelpTapToInsert,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.callingCardHelpBlocksTitle, style: heading),
            for (final (codes, text) in _blockHelp(l10n))
              _helpRow(codes, text, block: true),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.callingCardHelpOptionsTitle, style: heading),
            for (final (codes, text) in _optionHelp(l10n))
              _helpRow(codes, text, block: false),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.callingCardHelpExamplesTitle, style: heading),
            for (final MapEntry(key: id, value: source)
                in kCallingCardLayoutExamples.entries)
              _example(l10n, id, source),
          ],
        ),
      ),
    );
  }

  Widget _example(AppLocalizations l10n, String id, String source) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      callingCardExampleLabel(l10n, id),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    key: ValueKey('calling-card-example-$id'),
                    onPressed: () => _useExample(source),
                    child: Text(l10n.callingCardHelpExampleUse),
                  ),
                ],
              ),
              SelectableText(source.trimRight(), style: _mono),
            ],
          ),
        ),
      ),
    );
  }

  /// The block reference: the names to tap, and what each prints.
  static List<(List<String>, String)> _blockHelp(AppLocalizations l10n) => [
    (['title'], l10n.callingCardHelpBlockTitle),
    (['authors'], l10n.callingCardHelpBlockAuthors),
    (['formation'], l10n.callingCardHelpBlockFormation),
    (['level'], l10n.callingCardHelpBlockLevel),
    (['meta'], l10n.callingCardHelpBlockMeta),
    (['figures'], l10n.callingCardHelpBlockFigures),
    (['notes'], l10n.callingCardHelpBlockNotes),
    (['walkthrough'], l10n.callingCardHelpBlockWalkthrough),
    (['hook'], l10n.callingCardHelpBlockHook),
    (['tunes'], l10n.callingCardHelpBlockTunes),
    (['sources'], l10n.callingCardHelpBlockSources),
    (['program'], l10n.callingCardHelpBlockProgram),
    (['number'], l10n.callingCardHelpBlockNumber),
    (['text "Called by me"'], l10n.callingCardHelpBlockText),
    (['rule'], l10n.callingCardHelpBlockRule),
    (['space 8'], l10n.callingCardHelpBlockSpace),
    (['card margin=18'], l10n.callingCardHelpBlockCard),
  ];

  /// The option reference.
  static List<(List<String>, String)> _optionHelp(AppLocalizations l10n) => [
    (['size=12'], l10n.callingCardHelpOptionSize),
    (['bold', 'italic'], l10n.callingCardHelpOptionStyle),
    (['left', 'center', 'right'], l10n.callingCardHelpOptionAlign),
    (['color=#b64545'], l10n.callingCardHelpOptionColor),
    (['lines=3'], l10n.callingCardHelpOptionLines),
    (['label="Notes: "'], l10n.callingCardHelpOptionLabel),
    (['width=2'], l10n.callingCardHelpOptionWidth),
    (
      ['beats=off', 'notes=off', 'phrases=off', 'dividers=off'],
      l10n.callingCardHelpOptionFigures,
    ),
    (['thickness=2'], l10n.callingCardHelpOptionThickness),
  ];
}
