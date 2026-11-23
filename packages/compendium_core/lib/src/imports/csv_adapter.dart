/// The spreadsheet (CSV) import source (#2329): one dance per row, read
/// through a column mapping the caller chose.
library;

import 'package:meta/meta.dart';

import '../csv/csv_reader.dart';
import '../csv/csv_writer.dart' show guardCsvFormula;
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import 'author_tokenizer.dart';
import 'figure_front_end_fan_out.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// What one spreadsheet column is read as.
enum CsvColumnTarget {
  /// The column is left out.
  ignore,
  title,
  authors,
  form,
  formation,
  progression,
  level,
  status,
  mixer,
  tags,
  tunes,
  meter,
  key,
  hook,
  callingNotes,
  walkthrough,

  /// One cell of figures: one figure per line, or `;`-separated parts when
  /// the cell has no line breaks.
  figures,

  /// One phrase's figures (`A1`, `A2`, `B1`, `B2`…), in
  /// [CsvColumnMapping.phrase] order.
  figurePhrase,

  /// An existing custom field, [CsvColumnMapping.customFieldId].
  customField,

  /// A custom field the commit creates, named [CsvColumnMapping.newFieldLabel]
  /// and typed [CsvColumnMapping.newFieldType].
  newCustomField,
}

/// How one column is read. Use the named constructors.
@immutable
class CsvColumnMapping {
  const CsvColumnMapping(this.target)
    : phrase = null,
      customFieldId = null,
      newFieldLabel = null,
      newFieldType = null;

  const CsvColumnMapping.phrase(String this.phrase)
    : target = CsvColumnTarget.figurePhrase,
      customFieldId = null,
      newFieldLabel = null,
      newFieldType = null;

  const CsvColumnMapping.customField(String this.customFieldId)
    : target = CsvColumnTarget.customField,
      phrase = null,
      newFieldLabel = null,
      newFieldType = null;

  const CsvColumnMapping.newCustomField(
    String this.newFieldLabel,
    CustomFieldType this.newFieldType,
  ) : target = CsvColumnTarget.newCustomField,
      phrase = null,
      customFieldId = null;

  static const ignore = CsvColumnMapping(CsvColumnTarget.ignore);

  final CsvColumnTarget target;
  final String? phrase;
  final String? customFieldId;
  final String? newFieldLabel;
  final CustomFieldType? newFieldType;

  @override
  bool operator ==(Object other) =>
      other is CsvColumnMapping &&
      other.target == target &&
      other.phrase == phrase &&
      other.customFieldId == customFieldId &&
      other.newFieldLabel == newFieldLabel &&
      other.newFieldType == newFieldType;

  @override
  int get hashCode =>
      Object.hash(target, phrase, customFieldId, newFieldLabel, newFieldType);
}

/// The words a cell may use for each closed field, folded by [csvFold]: the
/// app fills these from its labels in the UI language and in English, so a
/// sheet in either language reads. Core knows only the enum names.
@immutable
class CsvValueVocabulary {
  const CsvValueVocabulary({
    this.forms = const {},
    this.formations = const {},
    this.improperFormations = const {},
    this.progressions = const {},
    this.statuses = const {},
    this.yes = const {},
    this.no = const {},
    this.beatWords = const {},
  });

  final Map<String, DanceForm> forms;
  final Map<String, FormationShape> formations;

  /// Formation names with the improper flag an English dance can carry
  /// (`Longways improper`), read as that shape with the flag set.
  final Map<String, FormationShape> improperFormations;
  final Map<String, Progression> progressions;
  final Map<String, DanceStatus> statuses;
  final Set<String> yes;
  final Set<String> no;

  /// The words a figure line's trailing count uses for beats, folded
  /// (`beats`, `schläge`…), so this app's own export in any language reads
  /// back: `(16 beats)`.
  final Set<String> beatWords;
}

/// Everything the caller chose in the map-columns step, carried on
/// [ImportRequest.options] under [CsvAdapter.mappingOption].
@immutable
class CsvImportMapping {
  CsvImportMapping({
    required this.separator,
    required this.hasHeader,
    required List<CsvColumnMapping> columns,
    this.vocabulary = const CsvValueVocabulary(),
    Map<String, CustomFieldDef> existingFields = const {},
  }) : columns = List.unmodifiable(columns),
       existingFields = Map.unmodifiable(existingFields);

  final String separator;
  final bool hasHeader;

  /// One entry per column, in order; a column past the end is ignored.
  final List<CsvColumnMapping> columns;
  final CsvValueVocabulary vocabulary;

  /// The caller's custom fields, by id, so a value can be typed.
  final Map<String, CustomFieldDef> existingFields;
}

/// Prefix of the placeholder tag id a draft carries for a tag named in the
/// sheet; [CsvImporter] resolves or creates the tag at commit and rewrites it,
/// as `kCcUserFieldIdPrefix` does for Caller's Companion user fields. A
/// placeholder that reaches the repository is refused, so a path that skips
/// the importer fails closed.
const String kCsvTagPlaceholderPrefix = 'csv-tag:';

/// Prefix of the placeholder field id a draft carries for a value of a
/// [CsvColumnTarget.newCustomField] column; the suffix is the column index.
const String kCsvNewFieldPlaceholderPrefix = 'csv-field:';

/// Issue code: a value that did not fit its field was kept in the calling
/// notes (#2329: "never dropped").
const String kCsvValueKeptInNotes = 'csv_value_kept_in_notes';

/// [value] folded for matching a cell against a vocabulary: trimmed, lower
/// case, inner whitespace collapsed.
String csvFold(String value) =>
    value.trim().toLowerCase().replaceAll(_whitespace, ' ');

final RegExp _whitespace = RegExp(r'\s+');

/// A cell RFC 4180 must quote.
final RegExp _needsQuotes = RegExp('[",\r\n]');

/// Between tunes in a tunes cell: a line break, a semicolon or a comma.
final RegExp _tuneSeparators = RegExp(r'[\n;,]');

/// A line break of any style.
final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');

/// A leading phrase label, as this app's own export writes one (`A1  …`).
final RegExp _phraseLabel = RegExp(r'^[A-Za-z][0-9]{1,2}[:.]?\s+');

/// A leading beat count in brackets, as Caller's Companion writes one: `(8)`.
final RegExp _leadingBeats = RegExp(r'^\(\s*(\d{1,4})\s*\)\s*');

/// A trailing count as this app's own export writes one, in any language and
/// with or without the progression mark: `(16 beats)`, `(16 Schläge) ¶`. The
/// unit is group 2; [CsvValueVocabulary.beatWords] says which units are beats.
final RegExp _trailingCount = RegExp(
  r'\s*\((\d{1,4})\s*([^()\d]{1,20})\)\s*(¶)?\s*$',
);

/// Reads a CSV the caller saved from a spreadsheet, one dance per row, through
/// the [CsvImportMapping] on the request (#2329).
///
/// A dance from the caller's own file records **no provenance**, as for a
/// hand-typed dance (maintainer decision on #2329): every [RawRecord] it makes
/// has [RawRecord.recordsProvenance] `false` and no external id, so dedupe uses
/// the fuzzy title-and-author tier only. [source] is an in-memory label only;
/// no provenance value is added for it.
///
/// Figures go through the shared fan-out ([parseFigureLinesFanOut]); a line it
/// cannot read becomes an unrecognized figure with its text. Authors go
/// through [splitAuthorNames]. A value that does not fit its field (an unknown
/// formation, text in a number field) is kept in the calling notes with a
/// [kCsvValueKeptInNotes] issue, never dropped.
class CsvAdapter implements SourceAdapter {
  CsvAdapter();

  /// The [ImportRequest.options] key that carries the [CsvImportMapping].
  static const String mappingOption = 'csvMapping';

  CsvImportMapping? _mapping;
  List<String> _header = const [];

  @override
  ProvenanceSource get source => ProvenanceSource.manual;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    final mapping = request.options[mappingOption];
    if (mapping is! CsvImportMapping) {
      throw ArgumentError('a CSV import needs a column mapping');
    }
    _mapping = mapping;
    final rows = readCsv(request.payload ?? '', separator: mapping.separator);
    _header = mapping.hasHeader && rows.isNotEmpty ? rows.first : const [];
    final body = mapping.hasHeader ? rows.skip(1) : rows;
    final titleColumn = mapping.columns.indexWhere(
      (c) => c.target == CsvColumnTarget.title,
    );
    final records = <DiscoveredRecord>[];
    var rowNumber = mapping.hasHeader ? 1 : 0;
    for (final row in body) {
      rowNumber++;
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      records.add(
        DiscoveredRecord(
          source: source,
          label: titleColumn >= 0 && titleColumn < row.length
              ? row[titleColumn].trim()
              : null,
          locator: {'row': rowNumber, 'cells': row},
        ),
      );
    }
    return records;
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final cells = (record.locator['cells']! as List).cast<String>();
    return RawRecord(
      source: source,
      payload: encodeCsvRowForRecord(cells),
      contentType: 'text/csv',
      sourceVersion: 'row ${record.locator['row']}',
      recordsProvenance: false,
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final mapping = _mapping;
    if (mapping == null) {
      throw StateError('parse before discover');
    }
    final cells = readCsv(raw.payload).firstOrNull ?? const <String>[];
    return csvRowToDraft(cells, mapping, raw: raw, header: _header);
  }
}

/// One row as the RFC 4180 text a [RawRecord] carries.
@visibleForTesting
String encodeCsvRowForRecord(List<String> cells) => [
  for (final cell in cells)
    cell.contains(_needsQuotes) ? '"${cell.replaceAll('"', '""')}"' : cell,
].join(',');

/// The draft for one row's [cells] read through [mapping]. [header] names the
/// columns in the notes a value that did not fit is kept under.
StructuredDraft csvRowToDraft(
  List<String> cells,
  CsvImportMapping mapping, {
  required RawRecord raw,
  List<String> header = const [],
}) {
  final vocab = mapping.vocabulary;
  final issues = <ImportIssue>[];
  final keptNotes = <String>[];
  String? title;
  final authors = <String>[];
  DanceForm? form;
  Formation? formation;
  Progression? progression;
  String? levelLabel;
  DanceStatus? status;
  bool? mixer;
  final tagNames = <String>[];
  final tunes = <String>[];
  var meter = '';
  var key = '';
  var hook = '';
  final notes = <String>[];
  var walkthrough = '';
  final figureLines = <String>[];
  final phraseCells = <String, String>{};
  final customValues = <CustomFieldValue>[];

  String columnName(int i) => i < header.length && header[i].trim().isNotEmpty
      ? header[i].trim()
      : '#${i + 1}';

  void keep(int i, String value) {
    keptNotes.add('${columnName(i)}: $value');
    issues.add(
      ImportIssue(
        severity: ImportIssueSeverity.warning,
        code: kCsvValueKeptInNotes,
        message: 'column ${i + 1} value did not fit; kept in calling notes',
      ),
    );
  }

  bool? yesNo(String value) {
    final f = csvFold(value);
    if (vocab.yes.contains(f) ||
        const {'yes', 'true', '1', 'x', 'y'}.contains(f)) {
      return true;
    }
    if (vocab.no.contains(f) || const {'no', 'false', '0', 'n'}.contains(f)) {
      return false;
    }
    return null;
  }

  for (var i = 0; i < cells.length && i < mapping.columns.length; i++) {
    final column = mapping.columns[i];
    final value = unguardCsvFormula(cells[i].trim());
    if (value.isEmpty) continue;
    switch (column.target) {
      case CsvColumnTarget.ignore:
        break;
      case CsvColumnTarget.title:
        title ??= value;
      case CsvColumnTarget.authors:
        authors.addAll(splitAuthorNames([value], issues: issues));
      case CsvColumnTarget.form:
        final f =
            vocab.forms[csvFold(value)] ?? _byName(DanceForm.values, value);
        if (f == null) {
          keep(i, value);
        } else {
          form = f;
        }
      case CsvColumnTarget.formation:
        final improper = vocab.improperFormations[csvFold(value)];
        final shape =
            vocab.formations[csvFold(value)] ??
            _byName(FormationShape.values, value);
        if (improper != null) {
          formation = Formation(improper, improper: true);
        } else if (shape == null) {
          keep(i, value);
        } else {
          formation = Formation(shape);
        }
      case CsvColumnTarget.progression:
        final p =
            vocab.progressions[csvFold(value)] ??
            _byName(Progression.values, value);
        if (p == null) {
          keep(i, value);
        } else {
          progression = p;
        }
      case CsvColumnTarget.level:
        levelLabel = value;
      case CsvColumnTarget.status:
        final s =
            vocab.statuses[csvFold(value)] ??
            _byName(DanceStatus.values, value);
        if (s == null) {
          keep(i, value);
        } else {
          status = s;
        }
      case CsvColumnTarget.mixer:
        final b = yesNo(value);
        if (b == null) {
          keep(i, value);
        } else {
          mixer = b;
        }
      case CsvColumnTarget.tags:
        tagNames.addAll(
          value.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
        );
      case CsvColumnTarget.tunes:
        tunes.addAll(
          value
              .split(_tuneSeparators)
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty),
        );
      case CsvColumnTarget.meter:
        meter = value;
      case CsvColumnTarget.key:
        key = value;
      case CsvColumnTarget.hook:
        hook = value;
      case CsvColumnTarget.callingNotes:
        notes.add(value);
      case CsvColumnTarget.walkthrough:
        walkthrough = value;
      case CsvColumnTarget.figures:
        figureLines.addAll(_figureLinesOf(value));
      case CsvColumnTarget.figurePhrase:
        phraseCells[column.phrase!] = value;
      case CsvColumnTarget.customField:
        final def = mapping.existingFields[column.customFieldId];
        final typed = def == null ? null : _typedValue(def, value, yesNo);
        if (def == null || typed == null) {
          keep(i, value);
        } else {
          customValues.add(CustomFieldValue(fieldId: def.id, value: typed));
        }
      case CsvColumnTarget.newCustomField:
        final type = column.newFieldType!;
        final typed = switch (type) {
          CustomFieldType.number => parseFiniteNumber(value),
          CustomFieldType.boolean => yesNo(value),
          // A new choice field takes its choices from the values it meets.
          CustomFieldType.text || CustomFieldType.choice => value,
        };
        if (typed == null) {
          keep(i, value);
        } else {
          customValues.add(
            CustomFieldValue(
              fieldId: '$kCsvNewFieldPlaceholderPrefix$i',
              value: typed,
            ),
          );
        }
    }
  }

  if (title == null || title.trim().isEmpty) {
    throw const FormatException('a row needs a title');
  }

  for (final phrase in phraseCells.keys.toList()..sort()) {
    figureLines.addAll(_figureLinesOf(phraseCells[phrase]!));
  }
  final figures = <Figure>[
    for (final line in figureLines) ..._figuresOf(line, vocab.beatWords),
  ];

  final callingNotes = [...notes, ...keptNotes].join('\n\n');
  final dance = Dance(
    id: 'csv-draft',
    title: title.trim(),
    form: form ?? DanceForm.contra,
    formation: formation ?? const Formation(FormationShape.dupleImproper),
    progression: progression ?? Progression.single,
    figures: figures,
    hook: hook,
    callingNotes: callingNotes,
    walkthrough: walkthrough,
    meter: meter,
    musicalKey: key,
    status: status ?? DanceStatus.active,
    mixer: mixer ?? false,
    tunes: tunes,
    tagIds: [
      for (final name in {...tagNames}) '$kCsvTagPlaceholderPrefix$name',
    ],
    customFields: customValues,
    createdAt: DateTime.utc(1970),
    updatedAt: DateTime.utc(1970),
  );
  return StructuredDraft(
    dance: dance,
    raw: raw,
    issues: issues,
    authorNames: authors,
    difficultyLevelLabel: levelLabel,
  );
}

/// The figure lines in one figures cell: one per line, or the `;`-separated
/// parts of a cell with no line breaks.
List<String> _figureLinesOf(String cell) {
  final lines = cell.contains('\n') || cell.contains('\r')
      ? cell.split(_lineBreak)
      : cell.split(';');
  return [
    for (final l in lines)
      if (l.trim().isNotEmpty) l.trim(),
  ];
}

/// One figure line through the shared fan-out, with a leading phrase label,
/// a leading `(8)` count, or this app's own trailing `(16 beats) ¶` read off
/// first.
List<Figure> _figuresOf(String line, Set<String> beatWords) {
  var text = line.replaceFirst(_phraseLabel, '');
  var beats = 0;
  var progression = false;
  final lead = _leadingBeats.firstMatch(text);
  if (lead != null) {
    beats = int.parse(lead.group(1)!);
    text = text.substring(lead.end);
  }
  final trail = _trailingCount.firstMatch(text);
  if (trail != null) {
    final word = csvFold(trail.group(2)!);
    // A count in beats sets the beats; one in another unit (bars) is read
    // off but left to the figure's default, rather than guessed.
    if (beatWords.contains(word) || word == 'beat' || word == 'beats') {
      beats = int.parse(trail.group(1)!);
    }
    progression = trail.group(3) != null;
    text = text.substring(0, trail.start);
  } else if (text.trimRight().endsWith('¶')) {
    progression = true;
    text = text.trimRight();
    text = text.substring(0, text.length - 1);
  }
  final figures = parseFigureLinesFanOut(
    text.trim().isEmpty ? line : text,
    beats: beats,
    progression: progression,
  );
  return figures.isEmpty
      ? [customFigure(line, beats: beats, origin: CustomOrigin.importGap)]
      : figures;
}

T? _byName<T extends Enum>(List<T> values, String raw) {
  final f = csvFold(raw).replaceAll(' ', '');
  for (final v in values) {
    if (v.name.toLowerCase() == f) return v;
  }
  return null;
}

Object? _typedValue(
  CustomFieldDef def,
  String value,
  bool? Function(String) yesNo,
) => switch (def.type) {
  CustomFieldType.text => value,
  CustomFieldType.number => parseFiniteNumber(value),
  CustomFieldType.boolean => yesNo(value),
  // A choice matches its option ignoring case and surrounding space, and is
  // stored as the field spells it.
  CustomFieldType.choice =>
    (def.choices ?? const <String>[])
        .where((c) => csvFold(c) == csvFold(value))
        .firstOrNull,
};

/// [value] with the leading apostrophe this app's own export puts before a
/// formula-like cell ([guardCsvFormula]) taken off again, so its export reads
/// back as it was written. An apostrophe before anything else is kept.
String unguardCsvFormula(String value) {
  if (value.length < 2 || value[0] != "'") return value;
  final rest = value.substring(1);
  return guardCsvFormula(rest) == value ? rest : value;
}
