import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/csv_import_mapping.dart';
import '../data/import_error_labels.dart';
import '../theme/app_spacing.dart';

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
/// Built to be reused by the plain-text import (#2330): it knows only the
/// text and the caller's custom fields, and hands back a [CsvImportMapping].
class CsvMappingStep extends StatefulWidget {
  const CsvMappingStep({
    super.key,
    required this.text,
    required this.fields,
    required this.onContinue,
    required this.onBack,
  });

  /// The decoded file ([decodeCsvBytes]).
  final String text;

  /// The caller's custom fields, offered as targets.
  final List<CustomFieldDef> fields;

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
    _separator = detectCsvSeparator(widget.text);
    _read(detectHeader: true);
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
    } on CsvReadException catch (e) {
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
    _columns = autoMapCsvColumns(
      _hasHeader && _rows.isNotEmpty ? _rows.first : null,
      _columnCount,
      _languages,
      widget.fields,
    );
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
      vocabulary: csvValueVocabulary(_languages),
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
        Text(l10n.importCsvMapTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.importCsvMapIntro),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: const ValueKey('csv-separator'),
          initialValue: _separator,
          decoration: InputDecoration(labelText: l10n.importCsvSeparatorLabel),
          items: [
            DropdownMenuItem(
              value: ',',
              child: Text(l10n.importCsvSeparatorComma),
            ),
            DropdownMenuItem(
              value: ';',
              child: Text(l10n.importCsvSeparatorSemicolon),
            ),
            DropdownMenuItem(
              value: '\t',
              child: Text(l10n.importCsvSeparatorTab),
            ),
          ],
          onChanged: (value) {
            if (value == null || value == _separator) return;
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
          DropdownButton<CsvColumnMapping>(
            key: ValueKey('csv-column-$index'),
            isExpanded: true,
            value: shown,
            items: [
              for (final c in choices)
                DropdownMenuItem(value: c, child: Text(labelOf(c))),
            ],
            onChanged: (m) {
              if (m != null) onChanged(m);
            },
          ),
        ],
      ),
    );
  }
}
