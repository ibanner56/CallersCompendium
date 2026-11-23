/// The spreadsheet (CSV) import source (#2329): one dance per row, read
/// through a column mapping the caller chose.
library;

import 'package:meta/meta.dart';

import '../csv/csv_name_list.dart';
import '../csv/csv_reader.dart';
import '../csv/csv_writer.dart' show guardCsvFormula;
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../storage/shareable_text.dart' show normalizeShareableText;
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
    this.barWords = const {},
    this.levels = const {},
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

  /// The words the same count uses for bars (an English dance's export),
  /// folded. A count in bars is read off the line but does not set beats.
  final Set<String> barWords;

  /// The caller's configured difficulty levels, by folded name (their own
  /// label and the built-in name in each language) → level id.
  final Map<String, String> levels;
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

/// Between tunes in a tunes cell, besides a comma: a line break or a
/// semicolon. Only the comma can be escaped (`\,`), as the export writes it.
const Set<String> _tuneSeparators = {'\n', ';'};

/// A line break of any style.
final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');

/// A leading phrase label, as this app's own export writes one (`A1  …`).
final RegExp _phraseLabel = RegExp(r'^[A-Za-z][0-9]{1,2}[:.]?\s+');

/// A leading beat count in brackets, as Caller's Companion writes one: `(8)`.
final RegExp _leadingBeats = RegExp(r'^\(\s*(\d{1,4})\s*\)\s*');

/// The existing field a new-field [column] will reuse at commit, as
/// [CsvImporter] matches one: the first of the same type and folded label.
CustomFieldDef? _existingFieldNamed(
  CsvImportMapping mapping,
  CsvColumnMapping column,
) {
  final label = csvFold(column.newFieldLabel!);
  return mapping.existingFields.values
      .where((f) => f.type == column.newFieldType && csvFold(f.label) == label)
      .firstOrNull;
}

/// A trailing count as this app's own export writes one, in any language and
/// with or without the progression mark: `(16 beats)`, `(16 Schläge) ¶`,
/// `(1½ bars)`. The count is group 1 (a half only for bars); the
/// unit is group 2; [CsvValueVocabulary.beatWords] says which units are beats.
final RegExp _trailingCount = RegExp(
  r'\s*\((\d{1,4}½?|½)\s*([^()\d½]{1,20})\)\s*(¶)?\s*$',
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
  String? levelId;
  // Single-valued targets a column has already filled: a second column for
  // the same one keeps its value in the notes rather than overwriting.
  final filled = <Object>{};
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

  num? number(String value) => parseCsvNumber(value, mapping.separator);

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
    // A choice cell with nothing visible in it is an empty cell: it fills
    // nothing and is not kept in the notes.
    final choiceCell = switch (column.target) {
      CsvColumnTarget.newCustomField => column.newFieldType,
      CsvColumnTarget.customField =>
        mapping.existingFields[column.customFieldId]?.type,
      _ => null,
    };
    if (choiceCell == CustomFieldType.choice &&
        normalizeShareableText(value).trim().isEmpty) {
      continue;
    }
    final single = switch (column.target) {
      CsvColumnTarget.form ||
      CsvColumnTarget.formation ||
      CsvColumnTarget.progression ||
      CsvColumnTarget.level ||
      CsvColumnTarget.status ||
      CsvColumnTarget.mixer ||
      CsvColumnTarget.meter ||
      CsvColumnTarget.key ||
      CsvColumnTarget.hook ||
      CsvColumnTarget.walkthrough ||
      CsvColumnTarget.title => column.target,
      CsvColumnTarget.customField => column.customFieldId,
      // A new field is the one commit will give it: an existing field of that
      // name and type, else one shared by every new column of that name and
      // type. Two existing fields stay two, whatever their names.
      CsvColumnTarget.newCustomField =>
        _existingFieldNamed(mapping, column)?.id ??
            (csvFold(column.newFieldLabel!), column.newFieldType!),
      _ => null,
    };
    if (single != null && filled.contains(single)) {
      keep(i, value);
      continue;
    }
    // A value that does not fit (kept in the notes) leaves the field to a
    // later column; only one that is used fills it.
    final keptBefore = keptNotes.length;
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
        final id = vocab.levels[csvFold(value)];
        if (id == null) {
          keep(i, value);
        } else {
          levelId = id;
        }
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
        tagNames.addAll(splitNameList(value));
      case CsvColumnTarget.tunes:
        tunes.addAll(splitNameList(value, extraSeparators: _tuneSeparators));
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
        // Two columns for one phrase add up rather than overwrite.
        phraseCells.update(
          column.phrase!,
          (earlier) => '$earlier\n$value',
          ifAbsent: () => value,
        );
      case CsvColumnTarget.customField:
        final def = mapping.existingFields[column.customFieldId];
        final typed = def == null
            ? null
            : _typedValue(def, value, yesNo, number);
        if (def == null || typed == null) {
          keep(i, value);
        } else {
          customValues.add(CustomFieldValue(fieldId: def.id, value: typed));
        }
      case CsvColumnTarget.newCustomField:
        final type = column.newFieldType!;
        final typed = switch (type) {
          CustomFieldType.number => number(value),
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
    if (single != null && keptNotes.length == keptBefore) filled.add(single);
  }

  if (title == null || title.trim().isEmpty) {
    throw const FormatException('a row needs a title');
  }

  for (final phrase in phraseCells.keys.toList()..sort()) {
    figureLines.addAll(_figureLinesOf(phraseCells[phrase]!));
  }
  final figures = <Figure>[
    for (final line in figureLines) ..._figuresOf(line, vocab),
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
    difficultyLevelId: levelId,
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
List<Figure> _figuresOf(String line, CsvValueVocabulary vocab) {
  var text = line.replaceFirst(_phraseLabel, '');
  var beats = 0;
  var progression = false;
  final lead = _leadingBeats.firstMatch(text);
  if (lead != null) {
    beats = int.parse(lead.group(1)!);
    text = text.substring(lead.end);
  }
  final trail = _trailingCount.firstMatch(text);
  final unit = trail == null ? null : csvFold(trail.group(2)!);
  final count = trail == null ? null : int.tryParse(trail.group(1)!);
  // Beats are whole; a half count (`1½ bars`) is only ever bars.
  final isBeats =
      count != null &&
      unit != null &&
      (vocab.beatWords.contains(unit) || unit == 'beat' || unit == 'beats');
  final isBars =
      unit != null &&
      (vocab.barWords.contains(unit) || unit == 'bar' || unit == 'bars');
  // Only a count in beats or bars (this app's own export) is read off; any
  // other trailing bracket, `(3 places)`, is part of the figure.
  if (trail != null && (isBeats || isBars)) {
    // A count in bars is left to the figure's default, rather than guessed.
    if (isBeats) beats = count;
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
  num? Function(String) number,
) => switch (def.type) {
  CustomFieldType.text => value,
  CustomFieldType.number => number(value),
  CustomFieldType.boolean => yesNo(value),
  // A choice matches its option ignoring case, surrounding space and Unicode
  // form (a decomposed `café` is the option `café`), and is stored as the
  // field spells it.
  CustomFieldType.choice =>
    (def.choices ?? const <String>[])
        .where((c) => _choiceKey(c) == _choiceKey(value))
        .firstOrNull,
};

/// [value] as a choice cell is compared with an option: [csvFold] over the
/// spelling the repository stores ([normalizeShareableText]).
String _choiceKey(String value) => csvFold(normalizeShareableText(value));

/// Spaces a spreadsheet groups digits with: a space, a no-break space and a
/// narrow no-break space.
const String _groupingSpaces = ' \u00a0\u202f';

/// A number with `.` or a space between groups of three digits and `,` before
/// the decimals: `1.234,5`, `3,5`, `1 000`, `1.000`. A leading group never
/// starts with 0, so `0.500` is not grouped (it is a half).
final RegExp _continentalNumber = RegExp(
  '^[+-]?(?:[1-9]\\d{0,2}([.$_groupingSpaces])\\d{3}(?:\\1\\d{3})*|\\d+)(?:,\\d+)?\$',
);

/// A number cell as [separator] says the sheet writes it. In a `;` sheet (the
/// one Excel saves in Danish, German, French and Dutch) a `,` is the decimal
/// mark and `.` or a space groups thousands, so `3,5` is 3.5 and `1.000` is
/// 1000; a `,` before exactly three digits is still a decimal mark there
/// (`1,000` is 1). A value that is neither that nor a plain number, such as
/// `1,234.5`, is `null` rather than a guess. In any other sheet it reads as
/// [parseFiniteNumber] does.
num? parseCsvNumber(String raw, String separator) {
  if (separator != ';') return parseFiniteNumber(raw);
  final value = raw.trim();
  if (!_continentalNumber.hasMatch(value)) return parseFiniteNumber(value);
  return parseFiniteNumber(
    value.replaceAll(RegExp('[.$_groupingSpaces]'), '').replaceAll(',', '.'),
  );
}

/// [value] with the leading apostrophe this app's own export puts before a
/// formula-like cell ([guardCsvFormula]) taken off again, so its export reads
/// back as it was written. An apostrophe before anything else is kept.
String unguardCsvFormula(String value) {
  if (value.length < 2 || value[0] != "'") return value;
  final rest = value.substring(1);
  return guardCsvFormula(rest) == value ? rest : value;
}
