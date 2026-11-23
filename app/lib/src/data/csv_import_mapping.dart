import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../export/export_labels_l10n.dart';
import '../search/facet_labels.dart';

final RegExp _digits = RegExp(r'\d+');

/// The phrase labels a column can carry figures for, in order.
const List<String> csvPhraseLabels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// Every target a column can be mapped to, in the order the dropdown lists
/// them (#2329).
///
/// There is deliberately no target for an author's email or location: those
/// are a third party's private details, classified `deviceLocal`, about people
/// who never use the app (`field_registry.dart`, `choreographers.email` and
/// `choreographers.location`).
List<CsvColumnMapping> csvTargetChoices(List<CustomFieldDef> fields) => [
  CsvColumnMapping.ignore,
  for (final t in _plainTargets) CsvColumnMapping(t),
  for (final p in csvPhraseLabels) CsvColumnMapping.phrase(p),
  for (final f in fields) CsvColumnMapping.customField(f.id),
];

/// The targets that need nothing but their kind.
const List<CsvColumnTarget> _plainTargets = [
  CsvColumnTarget.title,
  CsvColumnTarget.authors,
  CsvColumnTarget.form,
  CsvColumnTarget.formation,
  CsvColumnTarget.progression,
  CsvColumnTarget.level,
  CsvColumnTarget.status,
  CsvColumnTarget.mixer,
  CsvColumnTarget.tags,
  CsvColumnTarget.tunes,
  CsvColumnTarget.meter,
  CsvColumnTarget.key,
  CsvColumnTarget.hook,
  CsvColumnTarget.callingNotes,
  CsvColumnTarget.walkthrough,
  CsvColumnTarget.figures,
];

/// The header names each plain target answers to in one language (the first
/// is its dropdown label): first the
/// export's own column heading (#2332), then the editor's label.
Map<CsvColumnTarget, List<String>> csvTargetHeaderNames(
  AppLocalizations l10n,
) => {
  CsvColumnTarget.title: [
    l10n.csvColumnTitle,
    l10n.danceEditorTitleRequiredLabel,
  ],
  CsvColumnTarget.authors: [
    l10n.csvColumnAuthors,
    l10n.danceEditorAuthorsLabel,
  ],
  CsvColumnTarget.form: [l10n.csvColumnForm, l10n.danceEditorFormLabel],
  CsvColumnTarget.formation: [
    l10n.csvColumnFormation,
    l10n.danceEditorFormationLabel,
  ],
  CsvColumnTarget.progression: [l10n.csvColumnProgression],
  CsvColumnTarget.level: [l10n.csvColumnLevel],
  CsvColumnTarget.status: [l10n.csvColumnStatus, l10n.danceEditorStatusLabel],
  CsvColumnTarget.mixer: [l10n.csvColumnMixer],
  CsvColumnTarget.tags: [l10n.csvColumnTags, l10n.danceEditorTagsLabel],
  CsvColumnTarget.tunes: [l10n.csvColumnTunes, l10n.danceEditorTunesLabel],
  CsvColumnTarget.meter: [l10n.csvColumnMeter, l10n.danceEditorMeterLabel],
  CsvColumnTarget.key: [l10n.csvColumnKey, l10n.danceEditorMusicalKeyLabel],
  CsvColumnTarget.hook: [l10n.csvColumnHook, l10n.danceEditorHookLabel],
  CsvColumnTarget.callingNotes: [
    l10n.csvColumnCallingNotes,
    l10n.danceEditorCallingNotesLabel,
  ],
  CsvColumnTarget.walkthrough: [
    l10n.csvColumnWalkthrough,
    l10n.danceEditorWalkthroughLabel,
  ],
  CsvColumnTarget.figures: [l10n.csvColumnFigures, l10n.danceSectionFigures],
};

/// The header each custom field of [fields] gets in the dances CSV export
/// (#2332), keyed by field id. Only fields that leave in a share file get one
/// (they are the only columns the export writes).
///
/// Labels are not unique (only keys are), and a label may equal a built-in
/// column name, so a header is its label, then `label (2)`, `label (3)`, ...
/// until [csvFold] finds it unused by an earlier header and by every name in
/// [reserved] (the built-in column names). The import reads the same headers
/// back through [csvTargetForHeader], so a round trip tells the columns apart.
Map<String, String> customFieldCsvHeaders(
  List<CustomFieldDef> fields,
  Iterable<String> reserved,
) {
  final used = {for (final name in reserved) csvFold(name)};
  // Numbered in (label, id) order, not the caller's: the repository orders
  // fields by label only, so equal labels have no defined order there.
  final ordered =
      [
        for (final f in fields)
          if (customFieldLeavesIn(f, ArchiveSerializationMode.share)) f,
      ]..sort((a, b) {
        final byLabel = csvFold(a.label).compareTo(csvFold(b.label));
        return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
      });
  final headers = <String, String>{};
  for (final field in ordered) {
    var header = field.label;
    for (var n = 2; used.contains(csvFold(header)); n++) {
      header = '${field.label} ($n)';
    }
    used.add(csvFold(header));
    headers[field.id] = header;
  }
  return headers;
}

/// Every header a built-in column answers to or is written under in
/// [languages] (the dances export's own columns, including those the import
/// has no target for), plus the phrase labels: the names
/// [customFieldCsvHeaders] must not reuse.
List<String> csvReservedHeaders(List<AppLocalizations> languages) => [
  for (final l10n in languages) ...[
    for (final names in csvTargetHeaderNames(l10n).values) ...names,
    l10n.csvColumnComposed,
    l10n.csvColumnInterpreters,
    l10n.csvColumnInterpreted,
    l10n.csvColumnMixedLevel,
    l10n.csvColumnRating,
    l10n.csvColumnBarnes,
    l10n.csvColumnSources,
  ],
  ...csvPhraseLabels,
];

/// The target a header names, in any of [languages] (the UI language and
/// English), or `null`. A phrase label (`A1`) names its phrase. A custom field
/// is named by its export header ([customFieldCsvHeaders]), or by its bare
/// label when it is not shared, or when its header was not renamed, or when
/// its renamed header (`Rating (2)`) is in none of [sheetHeaders]: a sheet
/// without the renamed header is not an export that needed it kept apart.
CsvColumnMapping? csvTargetForHeader(
  String header,
  List<AppLocalizations> languages,
  List<CustomFieldDef> fields, {
  Iterable<String> sheetHeaders = const [],
}) {
  final folded = csvFold(header);
  if (folded.isEmpty) return null;
  for (final l10n in languages) {
    for (final MapEntry(:key, :value) in csvTargetHeaderNames(l10n).entries) {
      if (value.any((name) => csvFold(name) == folded)) {
        return CsvColumnMapping(key);
      }
    }
  }
  for (final p in csvPhraseLabels) {
    if (csvFold(p) == folded) return CsvColumnMapping.phrase(p);
  }
  final exported = customFieldCsvHeaders(fields, csvReservedHeaders(languages));
  for (final f in fields) {
    if (exported[f.id] case final header? when csvFold(header) == folded) {
      return CsvColumnMapping.customField(f.id);
    }
  }
  // The plain label, for a field the export never writes and for a file from
  // before headers were made unique. A field whose header was changed to tell
  // it apart ("Rating (2)") keeps answering to its bare label only when the
  // sheet has no such header: in an export that has one, the bare label is the
  // built-in column it was kept apart from.
  final present = {for (final h in sheetHeaders) csvFold(h)};
  for (final f in fields) {
    final header = exported[f.id];
    final free = header == null || !present.contains(csvFold(header));
    if (free && csvFold(f.label) == folded) {
      return CsvColumnMapping.customField(f.id);
    }
  }
  return null;
}

/// Whether [firstRow] looks like a header: at least one cell names a target.
bool csvRowLooksLikeHeader(
  List<String> firstRow,
  List<AppLocalizations> languages,
  List<CustomFieldDef> fields,
) => firstRow.any(
  (c) =>
      csvTargetForHeader(c, languages, fields, sheetHeaders: firstRow) != null,
);

/// The starting mapping for a sheet whose first row is [header] (or, without
/// a header, [columnCount] columns of Ignore). Each target is taken by the
/// first column that names it; a later column naming it again starts as
/// Ignore, so a sheet never maps two columns to one field by itself.
List<CsvColumnMapping> autoMapCsvColumns(
  List<String>? header,
  int columnCount,
  List<AppLocalizations> languages,
  List<CustomFieldDef> fields,
) {
  final taken = <CsvColumnMapping>{};
  return [
    for (var i = 0; i < columnCount; i++)
      if (header != null && i < header.length)
        switch (csvTargetForHeader(
          header[i],
          languages,
          fields,
          sheetHeaders: header,
        )) {
          final m? when taken.add(m) => m,
          _ => CsvColumnMapping.ignore,
        }
      else
        CsvColumnMapping.ignore,
  ];
}

/// The words a cell may use for each closed field, in every one of
/// [languages], for the adapter to read values in either language. [levels]
/// are the caller's configured difficulty levels: each is read by its own
/// label and by its built-in name in each language.
CsvValueVocabulary csvValueVocabulary(
  List<AppLocalizations> languages, {
  List<DifficultyLevel> levels = const [],
}) => CsvValueVocabulary(
  levels: {
    for (final level in levels) csvFold(level.label): level.id,
    for (final l10n in languages)
      for (final level in levels)
        csvFold(danceLevelLabel(l10n, level)): level.id,
  },
  barWords: {
    for (final l10n in languages)
      for (final halfBars in const [0, 1])
        csvFold(l10n.danceFigureBars('8', halfBars).replaceAll(_digits, '')),
  },
  forms: {
    for (final l10n in languages)
      for (final f in DanceForm.values) csvFold(danceFormLabel(l10n, f)): f,
  },
  formations: {
    for (final l10n in languages)
      for (final s in FormationShape.values)
        csvFold(formationShapeLabel(l10n, s)): s,
  },
  improperFormations: {
    for (final l10n in languages)
      for (final s in FormationShape.values)
        csvFold(l10n.commonFormationImproperFlag(formationShapeLabel(l10n, s))):
            s,
  },
  beatWords: {
    for (final l10n in languages)
      for (final count in const [1, 16])
        csvFold(danceExportLabels(l10n).beats(count).replaceAll(_digits, '')),
  },
  progressions: {
    for (final l10n in languages)
      for (final p in Progression.values) csvFold(progressionLabel(l10n, p)): p,
  },
  statuses: {
    for (final l10n in languages)
      for (final s in DanceStatus.values) csvFold(danceStatusLabel(l10n, s)): s,
  },
  yes: {for (final l10n in languages) csvFold(l10n.commonYes)},
  no: {for (final l10n in languages) csvFold(l10n.commonNo)},
);
