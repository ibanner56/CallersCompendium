/// The text or Markdown file import source (#2330): the caller's own notes,
/// a dance per heading or per block, read into the spreadsheet import's
/// columns so the same map-columns step, review and commit apply.
library;

import 'package:meta/meta.dart';

import '../csv/csv_reader.dart';
import '../csv/csv_writer.dart' show encodeCsv, guardCsvFormula;
import 'csv_adapter.dart';
import 'figure_text_lines.dart' show splitPhraseLabel;
import 'label_lines.dart';

/// Most dances one file may hold: the spreadsheet import's row cap, less the
/// header row the file becomes.
const int kMaxTextDocumentDances = kMaxCsvImportRows - 1;

/// Longest line a file may hold, and the most text one dance's details or
/// figures may come to: the spreadsheet import's cell cap, since each becomes
/// one cell.
const int kMaxTextDocumentLineChars = kMaxCsvImportCellChars;

/// Most different labels a file may use: the spreadsheet import's column cap,
/// less the title, notes and figures columns.
const int kMaxTextDocumentLabels = kMaxCsvImportColumns - 3;

/// The longest label a `Label: value` line may have, in words. A longer one
/// is a sentence with a colon in it, kept in the notes.
const int kMaxTextDocumentLabelWords = 3;

/// Why a text file could not be read.
enum TextDocumentReadFailure {
  /// More bytes than [kMaxCsvImportBytes].
  tooLarge,

  /// Bytes that are not valid UTF-8.
  notUtf8,

  /// More dances than [kMaxTextDocumentDances].
  tooManyDances,

  /// A line longer than [kMaxTextDocumentLineChars].
  lineTooLong,

  /// One dance's figures, notes or one label's values come to more than
  /// [kMaxTextDocumentLineChars].
  danceTooLong,

  /// More different labels than [kMaxTextDocumentLabels].
  tooManyLabels,
}

/// A text file that could not be read, and why; [limit] is the cap passed.
class TextDocumentReadException implements Exception {
  const TextDocumentReadException(this.reason, {this.limit});

  final TextDocumentReadFailure reason;
  final int? limit;

  @override
  String toString() =>
      'TextDocumentReadException(${reason.name}'
      '${limit == null ? '' : ', limit $limit'})';
}

/// [bytes] as text, refused when too large or not UTF-8, as a spreadsheet's
/// are ([decodeCsvBytes]).
String decodeTextDocumentBytes(List<int> bytes) {
  try {
    return decodeCsvBytes(bytes);
  } on CsvReadException catch (e) {
    throw TextDocumentReadException(
      e.reason == CsvReadFailure.tooLarge
          ? TextDocumentReadFailure.tooLarge
          : TextDocumentReadFailure.notUtf8,
      limit: e.limit,
    );
  }
}

/// One dance read from a text file.
@immutable
class TextDocumentDance {
  const TextDocumentDance({
    required this.title,
    this.labels = const [],
    this.notes = const [],
    this.figureLines = const [],
  });

  final String title;

  /// Each `Label: value` line (and `by …`, as `Authors`), in order, the label
  /// as written.
  final List<(String, String)> labels;

  /// Lines that are neither a label nor a figure, in order.
  final List<String> notes;

  /// The figure lines, list markers removed, phrase labels and counts kept.
  final List<String> figureLines;

  bool get hasBody =>
      labels.isNotEmpty || notes.isNotEmpty || figureLines.isNotEmpty;
}

/// A heading that starts a dance: `#` or `##`, then the title.
final RegExp _danceHeading = RegExp(r'^(#{1,2})\s+(.*?)(?:\s+#+)?\s*$');

/// Any Markdown heading (`#` to `######`).
final RegExp _anyHeading = RegExp(r'^#{1,6}(\s|$)');

/// A Markdown list marker at the start of a line: `-`, `*`, `+`, `1.`, `1)`.
final RegExp _listMarker = RegExp(r'^(?:[-*+]|\d{1,3}[.)])\s+');

/// A count at the start of a figure line: `(8)`, `[8]`, `8`, `(8 beats)`.
final RegExp _leadingCount = RegExp(
  r'^(?:[(\[]\s*\d{1,4}(?:\s*beats?)?\s*[)\]]|\d{1,4}\s)',
  caseSensitive: false,
);

/// A bracketed count, `(8)` or `[8 beats]`: unlike a bare `8`, never how a
/// title starts.
final RegExp _bracketedCount = RegExp(
  r'^[(\[]\s*\d{1,4}(?:\s*beats?)?\s*[)\]]',
  caseSensitive: false,
);

/// A line break of any style.
final RegExp _lineBreak = RegExp('\r\n|[\n\r\u2028\u2029\u0085]');

/// Reads [text], a plain-text or Markdown file of dances (#2330).
///
/// **Splitting into dances.** When the file has a `##` heading, or more than
/// one `#` heading, each such heading starts a dance titled by it, and blank
/// lines do not. Otherwise a dance starts at the first line, at a lone `#`
/// heading, and at each line after a blank line that is not a detail of the
/// dance before it and does not start like a figure (a list marker, a phrase
/// label or a bracketed count; a bare number does not, so `12 Days of
/// Christmas` is a title). A block with no detail, figure or note is a title
/// only and is still a dance. Text before the first heading that names no
/// figure and no label is kept in the first dance's notes.
///
/// **Reading a dance.** After the title:
/// - `Label: value` (a label of up to [kMaxTextDocumentLabelWords] words and
///   30 characters; `**Label:**` emphasis and a full-width `：` are read
///   too) is a detail, and so is `by Name` before any figure or note;
///   `by Name` and `Author:` are kept under `Authors`;
/// - a line with a list marker (`-`, `*`, `+`, `1.`), a phrase label (`A1`…)
///   or a leading count (`(8)`, `8`) is a figure, list marker removed, and so
///   is any other line straight after a figure line (a wrapped line, or
///   `Circle left: 3 places`);
/// - anything else is a note.
///
/// A `#` heading with no figure under it is the file's own title or a section
/// heading, not a dance, and is left out with its text, unless every dance in
/// the file is a `#` heading.
///
/// Markdown is read as text: only headings and list markers are read; links,
/// emphasis and other syntax come in as written.
///
/// Throws [TextDocumentReadException] past [kMaxTextDocumentDances] dances,
/// a line over [kMaxTextDocumentLineChars], or a dance's text over it.
List<TextDocumentDance> readTextDocument(String text) {
  final lines = text.split(_lineBreak);
  // Headings split the file when it has a `##` heading or more than one `#`
  // heading. A lone `#` heading is the file's title, or its one dance, in a
  // file whose dances are split by blank lines.
  var topHeadings = 0;
  var hasSecondLevel = false;
  for (final l in lines) {
    final m = _danceHeading.firstMatch(l.trim());
    if (m == null) continue;
    if (m.group(1)!.length == 2) {
      hasSecondLevel = true;
    } else {
      topHeadings++;
    }
  }
  final byHeadings = hasSecondLevel || topHeadings > 1;
  final blocks = <_Block>[];
  _Block? current;
  var afterBlank = true;
  final preamble = <String>[];

  void start(String title, {required int level}) {
    if (blocks.length == kMaxTextDocumentDances) {
      throw const TextDocumentReadException(
        TextDocumentReadFailure.tooManyDances,
        limit: kMaxTextDocumentDances,
      );
    }
    current = _Block(title, level: level);
    blocks.add(current!);
  }

  for (final raw in lines) {
    if (raw.length > kMaxTextDocumentLineChars) {
      throw const TextDocumentReadException(
        TextDocumentReadFailure.lineTooLong,
        limit: kMaxTextDocumentLineChars,
      );
    }
    final line = raw.trim();
    if (line.isEmpty) {
      afterBlank = true;
      continue;
    }
    final wasAfterBlank = afterBlank;
    afterBlank = false;
    if (byHeadings) {
      final heading = _danceHeading.firstMatch(line);
      if (heading != null) {
        start(heading.group(2)!, level: heading.group(1)!.length);
        continue;
      }
      final block = current;
      if (block == null) {
        preamble.add(line);
      } else {
        block.read(line, afterBlank: wasAfterBlank);
      }
      continue;
    }
    final block = current;
    final heading = _danceHeading.firstMatch(line);
    if (block == null ||
        heading != null ||
        (wasAfterBlank && !_isLabelLine(line, block) && !_startsFigure(line))) {
      if (heading != null) {
        start(heading.group(2)!, level: 1);
      } else {
        start(_stripHeading(line), level: 0);
      }
      continue;
    }
    block.read(line, afterBlank: wasAfterBlank);
  }

  // A `#` heading with no figures under it, in a file whose dances are `##`
  // headings or blocks after blank lines, is the file's own title or a
  // section heading, not a dance. In a file whose dances are all `#`
  // headings, each is a dance.
  if ((hasSecondLevel || !byHeadings) &&
      blocks.any((b) => b.level != 1 || b.figureLines.isNotEmpty)) {
    blocks.removeWhere((b) => b.level == 1 && b.figureLines.isEmpty);
  }

  // Text before the first heading: a dance of its own when it reads as one,
  // else kept as notes so nothing is lost.
  if (preamble.isNotEmpty) {
    final lead = _Block(_stripHeading(preamble.first), level: 0);
    for (final line in preamble.skip(1)) {
      lead.read(line, afterBlank: false);
    }
    if (lead.figureLines.isNotEmpty || lead.labels.isNotEmpty) {
      blocks.insert(0, lead);
    } else if (blocks.isNotEmpty) {
      blocks.first.leadNotes.addAll(preamble);
    } else {
      blocks.add(lead);
    }
  }
  return [for (final block in blocks) block.toDance()];
}

/// [line] without a Markdown heading's `#`s.
String _stripHeading(String line) => _anyHeading.hasMatch(line)
    ? line.replaceFirst(_headingOpen, '').replaceFirst(_headingClose, '')
    : line;

final RegExp _headingOpen = RegExp(r'^#+\s*');
final RegExp _headingClose = RegExp(r'\s#+$');

/// Whether [line] reads as a detail of [block]: a `Label: value` line, or a
/// `by Name` line while [block] has only details so far.
bool _isLabelLine(String line, _Block block) =>
    splitPhraseLabel(line).$1 == null &&
    !_listMarker.hasMatch(line) &&
    ((block.figureLines.isEmpty &&
            block.notes.isEmpty &&
            splitByLine(line) != null) ||
        _labelOf(line) != null);

/// [line] as a `Label: value` detail, or null. A web address (`https://…`) is
/// not a label and its scheme.
(String, String)? _labelOf(String line) {
  final bold = _boldLabel.firstMatch(line);
  final plain = bold == null
      ? line.replaceFirst('：', ':')
      : '${bold.group(2)}: ${bold.group(3)}';
  final label = splitLabelLine(plain, maxWords: kMaxTextDocumentLabelWords);
  if (label == null ||
      label.$1.length > _maxLabelChars ||
      label.$2.startsWith('//')) {
    return null;
  }
  return label;
}

/// A Markdown bold or italic label: `**Formation:** Becket`,
/// `**Formation**: Becket`, `_Music:_ Any reel`.
final RegExp _boldLabel = RegExp(
  r'^(\*\*|__|\*|_)([^*_:：]+)(?:[:：]\1|\1[:：])\s*(.*)$',
);

/// The longest label, in characters: a longer one is a sentence with a colon
/// in it, also in a language written without spaces between words.
const int _maxLabelChars = 30;

/// Whether [line], after a blank line in a file split by blank lines, goes on
/// the dance before it as a figure rather than starting a dance: a list
/// marker, a phrase label or a bracketed count. A bare leading number does
/// not count, so a title such as `12 Days of Christmas` starts a dance.
bool _startsFigure(String line) =>
    _listMarker.hasMatch(line) ||
    splitPhraseLabel(line).$1 != null ||
    _bracketedCount.hasMatch(line);

bool _isFigureLine(String line) =>
    _listMarker.hasMatch(line) ||
    splitPhraseLabel(line).$1 != null ||
    _leadingCount.hasMatch(line);

/// The label a `by Name` or `Author:` line is kept under: the English name
/// of the spreadsheet import's authors column, so it is matched to Authors.
const String _authorsLabel = 'Authors';

class _Block {
  _Block(this.title, {required this.level});

  final String title;

  /// The heading level that started the block (`#` 1, `##` 2), or 0.
  final int level;
  final labels = <(String, String)>[];
  final notes = <String>[];
  final leadNotes = <String>[];
  final figureLines = <String>[];

  /// Reads one non-blank line of the dance; [afterBlank] when a blank line
  /// came before it.
  void read(String line, {required bool afterBlank}) {
    // A line straight after a figure line goes on the figures (a card's
    // wrapped line, or `Circle left: 3 places`), even when it has a colon.
    final continuesFigures = figureLines.isNotEmpty && !afterBlank;
    if (!continuesFigures &&
        splitPhraseLabel(line).$1 == null &&
        !_listMarker.hasMatch(line)) {
      // `by Name` names the authors only among the details at the top, so a
      // note such as `By the end everyone is home.` stays a note.
      final by = figureLines.isEmpty && notes.isEmpty
          ? splitByLine(line)
          : null;
      if (by != null) {
        labels.add((_authorsLabel, by));
        return;
      }
      final label = _listMarker.hasMatch(line) ? null : _labelOf(line);
      if (label != null) {
        // `Author:` and `Authors:` are one label, as the Caller's Companion
        // text adapter reads them, named as the spreadsheet import's column.
        labels.add(
          label.$1.toLowerCase() == 'author'
              ? (_authorsLabel, label.$2)
              : label,
        );
        return;
      }
    }
    // A line that does not look like a figure continues the figures only
    // straight after one (a card's wrapped line); after a blank line it is
    // prose, such as a note under a Markdown list.
    if (_isFigureLine(line) || continuesFigures) {
      final figure = line.replaceFirst(_listMarker, '').trim();
      if (figure.isNotEmpty) figureLines.add(figure);
      return;
    }
    notes.add(_stripHeading(line));
  }

  TextDocumentDance toDance() => TextDocumentDance(
    title: title,
    labels: List.unmodifiable(labels),
    notes: List.unmodifiable([...leadNotes, ...notes]),
    figureLines: List.unmodifiable(figureLines),
  );
}

/// The header of the column [textDocumentToCsv] puts a dance's title in.
const String kTextDocumentTitleColumn = 'Title';

/// The header of the column for a dance's lines that are neither a label nor
/// a figure.
const String kTextDocumentNotesColumn = 'Calling notes';

/// The header of the column for a dance's figure lines.
const String kTextDocumentFiguresColumn = 'Figures';

/// [dances] as a spreadsheet the CSV import reads (#2329), comma-separated
/// ([encodeCsv], whose formula guard the import undoes): a header row, then
/// one row per dance. The columns are the title ([titleColumn]), one per
/// label the file uses (first-seen spelling; labels that differ only in case
/// share one), the notes ([notesColumn]) and the figures ([figuresColumn]);
/// the app passes their names in the UI language.
/// A label a dance repeats is joined with `, ` in its cell; notes and
/// figures are one per line.
///
/// Throws [TextDocumentReadException] for more than [kMaxTextDocumentLabels]
/// labels, or a cell over [kMaxTextDocumentLineChars].
String textDocumentToCsv(
  List<TextDocumentDance> dances, {
  String titleColumn = kTextDocumentTitleColumn,
  String notesColumn = kTextDocumentNotesColumn,
  String figuresColumn = kTextDocumentFiguresColumn,
}) {
  final labelColumns = <String, int>{};
  final labelNames = <String>[];
  for (final dance in dances) {
    for (final (label, _) in dance.labels) {
      final key = label.toLowerCase();
      if (labelColumns.containsKey(key)) continue;
      if (labelNames.length == kMaxTextDocumentLabels) {
        throw const TextDocumentReadException(
          TextDocumentReadFailure.tooManyLabels,
          limit: kMaxTextDocumentLabels,
        );
      }
      labelColumns[key] = labelNames.length;
      labelNames.add(label);
    }
  }
  String cell(String value) {
    // Measured as written, with the formula guard's apostrophe, which the
    // spreadsheet reader counts.
    if (guardCsvFormula(value).length > kMaxTextDocumentLineChars) {
      throw const TextDocumentReadException(
        TextDocumentReadFailure.danceTooLong,
        limit: kMaxTextDocumentLineChars,
      );
    }
    return value;
  }

  final rows = <List<String>>[
    [titleColumn, ...labelNames, notesColumn, figuresColumn],
  ];
  for (final dance in dances) {
    final values = List<List<String>>.generate(labelNames.length, (_) => []);
    for (final (label, value) in dance.labels) {
      values[labelColumns[label.toLowerCase()]!].add(value);
    }
    rows.add([
      cell(dance.title),
      for (final v in values) cell(v.join(', ')),
      cell(dance.notes.join('\n')),
      cell(dance.figureLines.join('\n')),
    ]);
  }
  return encodeCsv(rows);
}

/// The column mapping a text file starts with in the map-columns step: the
/// title, notes and figures columns mapped, each label column by [autoMapped]
/// (the spreadsheet import's header matching), and a label nothing matched
/// kept in the calling notes with its label ([CsvColumnMapping.labelledNotes]),
/// so nothing is lost unless the caller chooses Ignore.
List<CsvColumnMapping> textDocumentDefaultColumns(
  List<String> header,
  List<CsvColumnMapping> autoMapped,
) => [
  for (var i = 0; i < header.length; i++)
    if (i == 0)
      const CsvColumnMapping(CsvColumnTarget.title)
    else if (i == header.length - 1)
      const CsvColumnMapping(CsvColumnTarget.figures)
    else if (i == header.length - 2)
      const CsvColumnMapping(CsvColumnTarget.callingNotes)
    else if (i < autoMapped.length &&
        autoMapped[i].target != CsvColumnTarget.ignore &&
        autoMapped[i].target != CsvColumnTarget.title &&
        autoMapped[i].target != CsvColumnTarget.figures)
      autoMapped[i]
    else
      CsvColumnMapping.labelledNotes,
];
