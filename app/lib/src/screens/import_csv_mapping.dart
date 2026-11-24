import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/csv_import_mapping.dart';
import '../data/import_error_labels.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_dropdown_field.dart';
import 'custom_fields_screen.dart' show customFieldTypeLabel;
import '../diagnostics/error_log.dart';

/// Above this many dance rows the step warns that review may take a while, as
/// a large shared bundle does (`kSharedBundleSoftCapEntities`).
const int kCsvLargeBatchRows = 500;

/// The map-columns step of a spreadsheet import (#2329): between choosing the
/// file and the plan.
///
/// It shows the detected separator (changeable), whether the first row is a
/// header (detected, changeable), and one dropdown per column with a few of
/// its values, so the caller can see what each column holds. A column whose
/// header names a field, in the UI language or in English
/// ([autoMapCsvColumns]), starts mapped to it; every mapping can be changed,
/// and Ignore leaves a column out. Continue needs exactly one Title column.
///
/// The plain-text import (#2330) reuses it with [textDocument]: it knows only
/// the text and the caller's custom fields, and hands back a
/// [CsvImportMapping].
/// The dropdown label for [mapping].
String csvTargetLabel(
  AppLocalizations l10n,
  CsvColumnMapping mapping,
  Map<String, CustomFieldDef> fields,
) => switch (mapping.target) {
  CsvColumnTarget.ignore => l10n.importCsvTargetIgnore,
  CsvColumnTarget.callingNotes when mapping.labelled =>
    l10n.importTextTargetLabelledNotes,
  CsvColumnTarget.figurePhrase => l10n.importCsvTargetPhrase(mapping.phrase!),
  CsvColumnTarget.customField => l10n.importCsvTargetExistingField(
    fields[mapping.customFieldId]?.label ?? mapping.customFieldId!,
  ),
  CsvColumnTarget.newCustomField => l10n.importCsvTargetNewField(
    customFieldTypeLabel(l10n, mapping.newFieldType!),
  ),
  final t => csvTargetHeaderNames(l10n)[t]!.first,
};

class CsvMappingStep extends StatefulWidget {
  const CsvMappingStep({
    super.key,
    required this.text,
    required this.fields,
    this.levels = const [],
    this.textDocument = false,
    this.danceLevels = const [],
    this.danceLevel = 0,
    this.onDanceLevel,
    required this.onContinue,
    required this.onBack,
  });

  /// The decoded file ([decodeCsvBytes]).
  final String text;

  /// The caller's custom fields, offered as targets.
  final List<CustomFieldDef> fields;

  /// The caller's configured difficulty levels, for reading a Level column.
  final List<DifficultyLevel> levels;

  /// Whether [text] was read from a text or Markdown file (#2330,
  /// [textDocumentToCsv]): its separator and header row are fixed, so those
  /// controls are hidden; its columns are the file's labels, and a label no
  /// field takes starts in the calling notes with the label
  /// ([textDocumentDefaultColumns]).
  final bool textDocument;

  /// For [textDocument], where its dances may start: heading levels (1 for
  /// `#`) and 0 for titles after blank lines. With more than one, the step
  /// offers them, starting at [danceLevel], and [onDanceLevel] reads the file
  /// again into a new [text].
  final List<int> danceLevels;
  final int danceLevel;
  final ValueChanged<int>? onDanceLevel;

  final void Function(CsvImportMapping mapping) onContinue;

  /// Back to choosing a file or a source.
  final VoidCallback onBack;

  @override
  State<CsvMappingStep> createState() => _CsvMappingStepState();
}

class _CsvMappingStepState extends State<CsvMappingStep> {
  late String _separator;
  List<List<String>> _rows = const [];
  CsvReadException? _error;
  bool _hasHeader = true;
  List<CsvColumnMapping> _columns = const [];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _separator = widget.textDocument ? ',' : detectCsvSeparator(widget.text);
    _read(detectHeader: !widget.textDocument);
  }

  @override
  void didUpdateWidget(CsvMappingStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The text file was read again from another starting point: its labels
    // may differ, so they are mapped afresh.
    if (widget.text != oldWidget.text) {
      _read(detectHeader: !widget.textDocument);
    }
  }

  List<AppLocalizations> get _languages => [
    AppLocalizations.of(context),
    lookupAppLocalizations(const Locale('en')),
  ];

  int get _columnCount =>
      _rows.fold(0, (n, row) => row.length > n ? row.length : n);

  void _read({required bool detectHeader}) {
    try {
      _rows = readCsv(widget.text, separator: _separator);
      _error = null;
    } on CsvReadException catch (e, stackTrace) {
      // Shown on this step as its own message; the type is logged, never the
      // file's content (it is the caller's data).
      logCaughtErrorTypeOnly(e, stackTrace, source: 'import_csv_mapping._read');
      _rows = const [];
      _error = e;
    }
    if (detectHeader) {
      _hasHeader =
          _rows.isNotEmpty &&
          csvRowLooksLikeHeader(_rows.first, _languages, widget.fields);
    }
    _remap();
  }

  void _remap() {
    final header = _hasHeader && _rows.isNotEmpty ? _rows.first : null;
    final auto = autoMapCsvColumns(
      header,
      _columnCount,
      _languages,
      widget.fields,
    );
    _columns = widget.textDocument && header != null
        ? textDocumentDefaultColumns(header, auto)
        : auto;
  }

  /// The rows that hold dances: past the header, and not blank.
  List<List<String>> get _dataRows => [
    for (final row in _hasHeader ? _rows.skip(1) : _rows)
      if (row.any((cell) => cell.trim().isNotEmpty)) row,
  ];

  String _columnName(AppLocalizations l10n, int i) {
    final name = _hasHeader && _rows.isNotEmpty && i < _rows.first.length
        ? _rows.first[i].trim()
        : '';
    return name.isEmpty ? l10n.importCsvColumnFallback(i + 1) : name;
  }

  bool get _titleChosen =>
      _columns.where((c) => c.target == CsvColumnTarget.title).length == 1;

  void _continue() {
    final mapping = CsvImportMapping(
      separator: _separator,
      hasHeader: _hasHeader,
      columns: _columns,
      vocabulary: csvValueVocabulary(_languages, levels: widget.levels),
      existingFields: {for (final f in widget.fields) f.id: f},
    );
    widget.onContinue(mapping);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fieldsById = {for (final f in widget.fields) f.id: f};
    final error = _error;
    final dataRows = _dataRows;
    return ListView(
      key: const ValueKey('csv-mapping'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          widget.textDocument
              ? l10n.importTextMapTitle
              : l10n.importCsvMapTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.textDocument
              ? l10n.importTextMapIntro
              : l10n.importCsvMapIntro,
        ),
        const SizedBox(height: AppSpacing.md),
        if (widget.textDocument && widget.danceLevels.length > 1)
          AppDropdownField<int>(
            key: const ValueKey('text-dance-start'),
            value: widget.danceLevel,
            decoration: InputDecoration(
              labelText: l10n.importTextDanceStartLabel,
            ),
            entries: [
              for (final level in widget.danceLevels)
                AppDropdownEntry(
                  value: level,
                  label: level == 0
                      ? l10n.importTextDanceStartBlankLine
                      : l10n.importTextDanceStartHeading('#' * level),
                ),
            ],
            onChanged: (value) => widget.onDanceLevel?.call(value),
          ),
        if (!widget.textDocument) ...[
          AppDropdownField<String>(
            key: const ValueKey('csv-separator'),
            value: _separator,
            decoration: InputDecoration(
              labelText: l10n.importCsvSeparatorLabel,
            ),
            entries: [
              AppDropdownEntry(value: ',', label: l10n.importCsvSeparatorComma),
              AppDropdownEntry(
                value: ';',
                label: l10n.importCsvSeparatorSemicolon,
              ),
              AppDropdownEntry(value: '\t', label: l10n.importCsvSeparatorTab),
            ],
            onChanged: (value) {
              if (value == _separator) return;
              setState(() {
                _separator = value;
                _read(detectHeader: true);
              });
            },
          ),
          SwitchListTile(
            key: const ValueKey('csv-has-header'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.importCsvFirstRowHeader),
            value: _hasHeader,
            onChanged: error != null
                ? null
                : (value) => setState(() {
                    _hasHeader = value;
                    _remap();
                  }),
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              csvReadFailureMessage(l10n, error),
              key: const ValueKey('csv-read-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          )
        else ...[
          if (dataRows.length > kCsvLargeBatchRows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                l10n.importCsvLargeBatch(dataRows.length),
                key: const ValueKey('csv-large-batch'),
              ),
            ),
          Text(l10n.importCsvPreviewHeading, style: theme.textTheme.titleSmall),
          for (var i = 0; i < _columns.length; i++)
            _ColumnRow(
              key: ValueKey('csv-column-row-$i'),
              index: i,
              name: _columnName(l10n, i),
              samples: [
                for (final row in dataRows.take(3))
                  if (i < row.length && row[i].trim().isNotEmpty) row[i].trim(),
              ],
              value: _columns[i],
              choices: [
                ...csvTargetChoices(widget.fields),
                if (widget.textDocument) CsvColumnMapping.labelledNotes,
                for (final type in CustomFieldType.values)
                  CsvColumnMapping.newCustomField(_columnName(l10n, i), type),
              ],
              labelOf: (m) => csvTargetLabel(l10n, m, fieldsById),
              onChanged: (m) => setState(() {
                final next = [..._columns];
                next[i] = m;
                _columns = next;
              }),
            ),
          const SizedBox(height: AppSpacing.md),
          if (dataRows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                l10n.importCsvNoRows,
                key: const ValueKey('csv-no-rows'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            )
          else if (!_titleChosen)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                l10n.importCsvNeedsTitle,
                key: const ValueKey('csv-needs-title'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                key: const ValueKey('csv-back'),
                onPressed: widget.onBack,
                child: Text(l10n.commonBack),
              ),
              FilledButton(
                key: const ValueKey('csv-continue'),
                onPressed: _titleChosen && dataRows.isNotEmpty
                    ? _continue
                    : null,
                child: Text(l10n.importCsvContinue),
              ),
            ],
          ),
        ],
        if (error != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('csv-back'),
              onPressed: widget.onBack,
              child: Text(l10n.commonBack),
            ),
          ),
      ],
    );
  }
}

class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    super.key,
    required this.index,
    required this.name,
    required this.samples,
    required this.value,
    required this.choices,
    required this.labelOf,
    required this.onChanged,
  });

  final int index;
  final String name;
  final List<String> samples;
  final CsvColumnMapping value;
  final List<CsvColumnMapping> choices;
  final String Function(CsvColumnMapping) labelOf;
  final ValueChanged<CsvColumnMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = choices.contains(value) ? value : CsvColumnMapping.ignore;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: theme.textTheme.labelLarge),
          if (samples.isNotEmpty)
            Text(
              samples.map((s) => s.replaceAll('\n', ' / ')).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          AppDropdownField<CsvColumnMapping>(
            key: ValueKey('csv-column-$index'),
            value: shown,
            // Some thirty targets, plus the caller's custom fields: typing
            // narrows them.
            filterable: true,
            entries: [
              for (final (j, c) in choices.indexed)
                AppDropdownEntry(
                  key: ValueKey('csv-column-$index-option-$j'),
                  value: c,
                  label: labelOf(c),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
