import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../editor/figure_draft.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// What one line of the **Add figures from text** sheet becomes.
class FigureTextLineReading {
  const FigureTextLineReading({
    required this.line,
    required this.drafts,
    required this.unrecognized,
  });

  /// The line as the parser read it, without any phrase label it dropped.
  final FigureTextLine line;

  /// The rows the line inserts, in order: one per figure, or one for a
  /// compound or own-figure shorthand.
  final List<FigureDraft> drafts;

  /// Whether any of [drafts] is a figure the parser did not recognise, kept
  /// as an unrecognized figure carrying the text.
  final bool unrecognized;
}

/// What the text in the **Add figures from text** sheet becomes: a reading
/// per line, or why the text was refused.
class FigureTextReading {
  const FigureTextReading({required this.lines}) : refusal = null;

  const FigureTextReading.refused(FigureTextRefusal this.refusal)
    : lines = const [];

  final List<FigureTextLineReading> lines;

  /// Set when the text was over a cap. Nothing is offered for insertion.
  final FigureTextRefusal? refusal;

  /// Every row the text inserts, line by line.
  List<FigureDraft> get drafts => [for (final line in lines) ...line.drafts];

  int get unrecognizedLines => lines.where((line) => line.unrecognized).length;
}

/// The dance editor's **Add figures from text** sheet (#2326): a multi-line
/// text box where each non-empty line is read as one figure line, as typing it
/// in the Move box with Free-text entry on would read it. A live preview says
/// how many figures each line gives and marks the lines kept as unrecognized
/// figures. **Add figures** closes the sheet with the rows to insert; Cancel,
/// Back or a tap outside closes it with nothing.
///
/// The sheet does no reading of its own: [read] turns the text into rows, so
/// the host reads lines with the dance's taxonomy, dialect, shorthands,
/// formation and meter, as its Move box does.
class FigureTextSheet extends StatefulWidget {
  const FigureTextSheet({
    super.key,
    required this.read,
    required this.dropsPhraseLabels,
  });

  /// Reads the sheet's text. Called on every change, so it must not change
  /// the dance.
  final FigureTextReading Function(String text) read;

  /// Whether [read] drops a leading `A1`…`C2` phrase label (contra dances),
  /// which the help text then says.
  final bool dropsPhraseLabels;

  /// Opens the sheet and resolves to the rows to insert, or null when the
  /// user closed it without adding any.
  static Future<List<FigureDraft>?> show(
    BuildContext context, {
    required FigureTextReading Function(String text) read,
    required bool dropsPhraseLabels,
  }) {
    return showModalBottomSheet<List<FigureDraft>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          FigureTextSheet(read: read, dropsPhraseLabels: dropsPhraseLabels),
      sheetAnimationStyle: AppMotion.styleFor(context),
    );
  }

  @override
  State<FigureTextSheet> createState() => _FigureTextSheetState();
}

class _FigureTextSheetState extends State<FigureTextSheet> {
  final _textController = TextEditingController();
  FigureTextReading _reading = const FigureTextReading(lines: []);

  @override
  void initState() {
    super.initState();
    _textController.addListener(_reread);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// The text [_reading] was read from. The controller also notifies on a
  /// caret or selection move, which must not re-read the whole text.
  String _readText = '';

  void _reread() {
    final text = _textController.text;
    if (text == _readText) return;
    _readText = text;
    final reading = widget.read(text);
    setState(() => _reading = reading);
  }

  void _add() {
    final drafts = _reading.drafts;
    if (_reading.refusal != null || drafts.isEmpty) return;
    Navigator.of(context).pop(drafts);
  }

  String? _refusalMessage(AppLocalizations l10n) => switch (_reading.refusal) {
    FigureTextRefusal.tooLong => l10n.figureTextSheetTooLong(
      maxFigureTextLength,
    ),
    FigureTextRefusal.tooManyLines => l10n.figureTextSheetTooManyLines(
      maxFigureTextLines,
    ),
    FigureTextRefusal.lineTooLong => l10n.figureTextSheetLineTooLong(
      maxFreeTextEntryLength,
    ),
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final refusal = _refusalMessage(l10n);
    final figureCount = _reading.drafts.length;
    final canAdd = refusal == null && figureCount > 0;
    return Padding(
      // The route does not lift a sheet above the keyboard.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              // At most [maxFigureTextLines] preview rows, so building them
              // all is cheap, and none goes missing from the semantics tree.
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.figureTextSheetTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.dropsPhraseLabels
                          ? l10n.figureTextSheetHelpDropsLabels
                          : l10n.figureTextSheetHelp,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const ValueKey('figure-text-sheet-field'),
                      controller: _textController,
                      autofocus: true,
                      minLines: 5,
                      maxLines: 12,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        labelText: l10n.figureTextSheetFieldLabel,
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                        errorText: refusal,
                        errorMaxLines: 4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (refusal == null) ...[
                      // Not a live region: it changes on almost every keystroke.
                      Text(
                        key: const ValueKey('figure-text-sheet-summary'),
                        l10n.figureTextSheetSummary(figureCount),
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_reading.unrecognizedLines > 0)
                        Text(
                          key: const ValueKey('figure-text-sheet-unrecognized'),
                          l10n.figureTextSheetUnrecognizedSummary(
                            _reading.unrecognizedLines,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      for (final (index, line) in _reading.lines.indexed)
                        _LinePreview(
                          key: ValueKey('figure-text-sheet-line-$index'),
                          reading: line,
                        ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: AppSpacing.sm,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('figure-text-sheet-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton(
                    key: const ValueKey('figure-text-sheet-add'),
                    onPressed: canAdd ? _add : null,
                    child: Text(l10n.figureTextSheetAdd),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the preview: the text as read, and what it gives.
class _LinePreview extends StatelessWidget {
  const _LinePreview({super.key, required this.reading});

  final FigureTextLineReading reading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = reading.drafts.length;
    final outcome = reading.unrecognized
        ? l10n.figureTextSheetLineUnrecognized
        : l10n.figureTextSheetLineFigures(count);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
              child: Icon(
                reading.unrecognized
                    ? Icons.help_outline
                    : Icons.check_circle_outline,
                size: 18,
                color: reading.unrecognized
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reading.line.text, style: theme.textTheme.bodyMedium),
                  Text(
                    outcome,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: reading.unrecognized
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
