import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';

/// A dance's phrase structure as rows, for a form whose phrases are not named
/// (contra and square; #2304). Each row is one `phrases*bars*beatsPerBar`
/// component of the text: how many phrases, the bars in each, and the beats in
/// a bar. The rows write that same text ([PhraseStructure.raw]); they store no
/// names and no pass marker, so labels (A1 A2 B1 B2 …) are as they were, and a
/// dance whose rows are not edited keeps its stored text byte for byte. An
/// edit rewrites the text in its canonical spelling (` + ` between
/// components, blank for the standard structure), so imported text spelled
/// another way (`3*8*2+1*4*2`) is respelled once it is edited, and an edit
/// that is undone by hand is not unwound to the imported spelling.
///
/// The formula stays editable beside the rows. While it does not parse, or
/// holds phrase names this form cannot keep, the rows stay on screen
/// disabled, showing the last valid structure, so they do not vanish under the
/// caret on each keystroke of a formula being typed.
class PhraseGroupsEditor extends StatefulWidget {
  const PhraseGroupsEditor({
    super.key,
    required this.title,
    required this.structure,
    required this.onChanged,
  });

  /// The heading above the rows.
  final String title;

  /// The phrase structure as the text now reads, or null while the text holds
  /// one that does not parse.
  final PhraseStructure? structure;

  /// The new phrase structure text, when the rows make a valid one that
  /// differs from [structure]. [typed] is true for a number being typed, and
  /// false for adding or removing a row, which is its own undo step.
  final void Function(String raw, {required bool typed}) onChanged;

  @override
  State<PhraseGroupsEditor> createState() => _PhraseGroupsEditorState();
}

/// The most labels the summary line lists before it stops with an ellipsis.
const int _summaryLabelLimit = 12;

class _Row {
  _Row(PhraseComponent component)
    : phrases = TextEditingController(text: '${component.phraseCount}'),
      bars = TextEditingController(text: '${component.bars}'),
      beatsPerBar = TextEditingController(text: '${component.beatsPerBar}');

  _Row.blank({required int beatsPerBarValue})
    : phrases = TextEditingController(text: '1'),
      bars = TextEditingController(text: '8'),
      beatsPerBar = TextEditingController(text: '$beatsPerBarValue');

  final TextEditingController phrases;
  final TextEditingController bars;
  final TextEditingController beatsPerBar;

  static int? _count(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null ||
            value < 1 ||
            value > PhraseStructure.maxComponentNumber
        ? null
        : value;
  }

  int? get phraseCount => _count(phrases);
  int? get barCount => _count(bars);
  int? get beatCount => _count(beatsPerBar);

  /// This row as a component of the text, or null while a number is missing
  /// or out of range.
  String? get text {
    final p = phraseCount;
    final b = barCount;
    final n = beatCount;
    return p == null || b == null || n == null ? null : '$p*$b*$n';
  }

  void dispose() {
    phrases.dispose();
    bars.dispose();
    beatsPerBar.dispose();
  }
}

class _PhraseGroupsEditorState extends State<PhraseGroupsEditor> {
  final List<_Row> _rows = [];

  /// The text this editor last wrote, so a structure it wrote itself does not
  /// rebuild the rows under the caller's cursor.
  String? _written;

  /// The last structure that parsed and was unnamed: what the summary line
  /// reads while the rows are disabled.
  PhraseStructure? _shown;

  /// Whether the rows, as typed, make no valid structure (a number left empty
  /// or out of range, or a structure past its bounds).
  bool _invalid = false;

  /// The structure the rows may be loaded from, or null when the text does not
  /// parse or holds names (which only an English dance keeps).
  static PhraseStructure? _usable(PhraseStructure? structure) =>
      structure == null || structure.isNamed ? null : structure;

  /// Whether the rows can be edited now. Worked out from the structure on
  /// every build: a reload cannot decide it, because none runs when the text
  /// returns to the text this editor last wrote.
  bool get _enabled => _usable(widget.structure) != null;

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void didUpdateWidget(PhraseGroupsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final usable = _usable(widget.structure);
    if (usable == null) return;
    _shown = usable;
    final raw = usable.raw;
    if (raw != _written && raw != oldWidget.structure?.raw) _loadRows();
  }

  void _loadRows() {
    final usable = _usable(widget.structure);
    if (usable == null) return;
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll([for (final component in usable.components) _Row(component)]);
    _written = usable.raw;
    _shown = usable;
    _invalid = false;
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _write({required bool typed}) {
    final parts = <String>[];
    for (final row in _rows) {
      final text = row.text;
      if (text == null) {
        setState(() => _invalid = true);
        return;
      }
      parts.add(text);
    }
    final PhraseStructure parsed;
    try {
      parsed = PhraseStructure.parse(parts.join(' + '));
    } on FormatException {
      // diagnostics: silent — a structure past its bounds is shown on the rows
      // as invalid; nothing is written until it is fixed.
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    // Rows that read the same as the text keep the text as it is, so imported
    // text such as `3*8*2+1*4*2` is not rewritten for no change.
    if (parsed == widget.structure) return;
    final raw = parsed == PhraseStructure.standard ? '' : parsed.raw;
    _written = raw;
    _shown = parsed;
    widget.onChanged(raw, typed: typed);
  }

  void _add() {
    final perBar = _rows.isEmpty ? 2 : (_rows.last.beatCount ?? 2);
    setState(() => _rows.add(_Row.blank(beatsPerBarValue: perBar)));
    _write(typed: false);
  }

  void _remove(int index) {
    setState(() => _rows.removeAt(index).dispose());
    _write(typed: false);
  }

  String _summary(AppLocalizations l10n, PhraseStructure structure) {
    final labels = structure.labels;
    final shown = labels.take(_summaryLabelLimit).join(' ');
    return l10n.danceEditorPhraseRowsSummary(
      labels.length > _summaryLabelLimit ? '$shown …' : shown,
      structure.totalBeats,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final enabled = _enabled;
    final shown = _shown ?? PhraseStructure.standard;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        key: const ValueKey('phrase-rows'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.danceEditorPhraseRowsHelp,
            style: theme.textTheme.bodySmall,
          ),
          for (final (index, row) in _rows.indexed)
            _rowFor(context, index, row, enabled),
          if (_invalid)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  l10n.danceEditorPhraseRowsInvalid(
                    PhraseStructure.maxComponentNumber,
                  ),
                  key: const ValueKey('phrase-rows-invalid'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          if (_rows.length < PhraseStructure.maxComponents)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('phrase-rows-add'),
                onPressed: enabled ? _add : null,
                icon: const Icon(Icons.add),
                label: Text(l10n.danceEditorPhraseRowsAdd),
              ),
            ),
          // The summary and the note share one slot, each laid out whether it
          // shows or not, so the slot is as tall as the taller of the two and
          // the formula field below does not move when the rows are disabled.
          Stack(
            children: [
              Visibility(
                visible: enabled,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Text(
                  _summary(l10n, shown),
                  key: const ValueKey('phrase-rows-summary'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Visibility(
                visible: !enabled,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Text(
                  l10n.danceEditorPhraseRowsDisabledNote,
                  key: const ValueKey('phrase-rows-note'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The narrowest a number field is at the default text size; its label
  /// (Bars per phrase, Beats per bar) reads in it.
  static const double _fieldWidth = 128;

  Widget _rowFor(BuildContext context, int index, _Row row, bool enabled) {
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The label grows with the text size, so the field does too (to the
          // width there is), rather than cutting its label short.
          final width = constraints.hasBoundedWidth
              ? min(
                  constraints.maxWidth,
                  max(_fieldWidth, scaler.scale(_fieldWidth)),
                )
              : _fieldWidth;
          Widget field(
            String name,
            TextEditingController controller,
            String label,
            int? value,
          ) {
            // The row's number goes before the field's label for a screen
            // reader, since every row's three fields share their labels
            // (pre-release audit finding B-11).
            return SizedBox(
              width: width,
              child: Semantics(
                label: l10n.danceEditorPhraseRowsRow(index + 1),
                child: TextField(
                  key: ValueKey('phrase-row-$index-$name'),
                  controller: controller,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(
                      '${PhraseStructure.maxComponentNumber}'.length,
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: label,
                    errorText: value == null
                        ? l10n.danceEditorPhraseRowsRange(
                            PhraseStructure.maxComponentNumber,
                          )
                        : null,
                    errorMaxLines: 2,
                  ),
                  onChanged: (_) => _write(typed: true),
                ),
              ),
            );
          }

          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              field(
                'phrases',
                row.phrases,
                l10n.danceEditorPhraseRowsPhrasesLabel,
                row.phraseCount,
              ),
              field(
                'bars',
                row.bars,
                l10n.danceEditorPhraseRowsBarsLabel,
                row.barCount,
              ),
              field(
                'beats',
                row.beatsPerBar,
                l10n.danceEditorPhraseRowsBeatsLabel,
                row.beatCount,
              ),
              if (_rows.length > 1)
                IconButton(
                  key: ValueKey('phrase-row-$index-remove'),
                  tooltip: l10n.danceEditorPhraseRowsRemove(index + 1),
                  icon: const Icon(Icons.close),
                  onPressed: enabled ? () => _remove(index) : null,
                ),
            ],
          );
        },
      ),
    );
  }
}
