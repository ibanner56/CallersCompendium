import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:meta/meta.dart';

/// One row of a **Caller's Box** (TCB) online title/author search results page.
///
/// TCB has no JSON search endpoint (see `docs/research/callersbox.md`); the only
/// search surface is the HTML results table served by the site root
/// (`?title=…`/`?author=…`). [parseCallersBoxSearchResults] turns that table into
/// these lightweight rows. The [id] is the TCB dance id (from the row's
/// `dance.php?id=N` link), which the app turns into the per-dance
/// `dance.php?id=N&format=JSON` endpoint (via `buildCallersBoxJsonUrl`) to
/// preview/import the full dance with [CallersBoxAdapter].
@immutable
class CallersBoxSearchResult {
  const CallersBoxSearchResult({
    required this.id,
    required this.name,
    required this.author,
    required this.formation,
    required this.figuresAvailable,
  });

  /// TCB dance id (numeric string), from the row's `dance.php?id=N` link.
  final String id;

  /// Dance title (the link text).
  final String name;

  /// Author/choreographer column (e.g. `Traditional`); may be empty.
  final String author;

  /// Formation column (e.g. `Triple Minor`); may be empty.
  final String formation;

  /// Whether TCB's row carried the **figures-permission** marker `Ⓕ`
  /// (U+24BB, `&#x24bb;` in the source bytes) in one of the icon cells that
  /// precede the dance link.
  ///
  /// False means TCB holds the dance's figures but will not serve them
  /// (`Permission` is `search` or blank rather than `full`), so importing it
  /// yields a metadata-only stub with no figures — see [CallersBoxAdapter].
  ///
  /// This is **not** the same as TCB's `Ⓛ` (U+24C1) marker, which only says a
  /// link to an external source for the figures is known; a row can carry `Ⓛ`
  /// and/or `Ⓥ` (U+24CB, video) while still refusing to serve its figures.
  /// Only `Ⓕ` implies the figures are available.
  final bool figuresAvailable;

  @override
  bool operator ==(Object other) =>
      other is CallersBoxSearchResult &&
      other.id == id &&
      other.name == name &&
      other.author == author &&
      other.formation == formation &&
      other.figuresAvailable == figuresAvailable;

  @override
  int get hashCode =>
      Object.hash(id, name, author, formation, figuresAvailable);

  @override
  String toString() =>
      'CallersBoxSearchResult(id: $id, name: $name, author: $author, '
      'formation: $formation, figuresAvailable: $figuresAvailable)';
}

/// Matches a TCB per-dance link (`dance.php?id=N`, any host/leading path) and
/// captures the numeric id.
final RegExp _danceLinkId = RegExp(r'dance\.php\?id=(\d+)');

/// Parses a **Caller's Box** search results page (HTML) into its result rows.
///
/// The results page (verified live, mirrored code at
/// `ibiblio.org/contradance/thecallersbox/?title=…`) renders a bare `<table>`
/// whose result rows are `<tr>`s shaped as: a few leading icon `<td>`s
/// (figures-visible / source-link / video markers, any of which may be empty),
/// then `<td><a href='dance.php?id=N' target='_blank'>NAME</a></td>`, then a
/// `<td>` author column, then a `<td>` formation column.
///
/// This is **pure** (no I/O): the app layer fetches the page (decoding its
/// `windows-1252` bytes) and passes the decoded HTML string here.
///
/// Robustness: only `<tr>`s that contain a `dance.php?id=N` link are treated as
/// results (the "modify your query" form has no such links), so the count line
/// and page chrome are ignored. Author/formation are read from the `<td>`s that
/// *follow* the link's cell (tolerant of a differing number of leading icon
/// cells) and default to empty when absent. Malformed / non-results pages yield
/// an empty list rather than throwing — the caller renders that as "no results".
List<CallersBoxSearchResult> parseCallersBoxSearchResults(String html) {
  final dom.Document document;
  try {
    document = html_parser.parse(html);
  } on Object {
    return const [];
  }

  final results = <CallersBoxSearchResult>[];
  for (final row in document.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.isEmpty) continue;

    // Find the cell that holds the dance link (the first td whose subtree has a
    // `dance.php?id=N` anchor). Everything before it is icon columns; the two
    // cells after it are author then formation.
    var linkCellIndex = -1;
    dom.Element? anchor;
    for (var i = 0; i < cells.length; i++) {
      final a = cells[i].querySelector('a[href]');
      final href = a?.attributes['href'];
      if (a != null && href != null && _danceLinkId.hasMatch(href)) {
        linkCellIndex = i;
        anchor = a;
        break;
      }
    }
    if (anchor == null || linkCellIndex < 0) continue;

    final id = _danceLinkId.firstMatch(anchor.attributes['href']!)!.group(1)!;
    final name = _collapseWhitespace(anchor.text);
    if (name.isEmpty) continue;

    final author = linkCellIndex + 1 < cells.length
        ? _collapseWhitespace(cells[linkCellIndex + 1].text)
        : '';
    final formation = linkCellIndex + 2 < cells.length
        ? _collapseWhitespace(cells[linkCellIndex + 2].text)
        : '';

    results.add(
      CallersBoxSearchResult(
        id: id,
        name: name,
        author: author,
        formation: formation,
        figuresAvailable: true,
      ),
    );
  }
  return results;
}

/// Trims and collapses internal whitespace runs (incl. newlines from the source
/// HTML's pretty-printing) to single spaces.
String _collapseWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();
