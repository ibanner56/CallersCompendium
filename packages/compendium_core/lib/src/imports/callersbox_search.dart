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

/// TCB's **figures-permission** marker, `Ⓕ` — served as `&#x24bb;` because the
/// page is `windows-1252`, which cannot encode the character at all, and
/// decoded to this codepoint by `html_parser` before the parser sees it.
///
/// Matched as a decoded codepoint rather than as entity text on purpose: a raw
/// `&#x24bb;` substring test against the source HTML would never fire on the
/// decoded DOM, and would also match the many spellings of the entity that a
/// hostile page could use (`&#X24BB;`, `&#9403;`, an unterminated form) or the
/// literal characters `2`,`4`,`b`,`b` appearing in unrelated text.
const String _figuresPermissionMarker = '\u24bb';

/// The direct-child `<td>` elements of [row].
///
/// Deliberately NOT `row.querySelectorAll('td')`, which is descendant-scoped:
/// a nested `<table>` anywhere in the row interleaves its own cells into the
/// result in document order, which both shifts the author/formation offsets
/// (measured: a nested table in the title cell makes the author read as the
/// nested cell's text) and widens the window scanned for the permission marker
/// to content the row does not own.
List<dom.Element> _directCells(dom.Element row) =>
    row.children.where((e) => e.localName == 'td').toList(growable: false);

/// Whether [element] sits inside another `<tr>`.
///
/// `document.querySelectorAll('tr')` matches nested rows too, so a `<table>`
/// embedded in a cell yields phantom result rows whose id, name and permission
/// marker are all taken from that embedded markup. A genuine TCB result row is
/// never nested inside another row, so such rows are dropped rather than
/// trusted. This hazard predates issue #845 — a phantom row could already
/// contribute a bogus id — but the permission marker would let one claim
/// figures it does not have, so it is closed here rather than left to grow.
bool _isNestedRow(dom.Element element) {
  for (var p = element.parent; p != null; p = p.parent) {
    if (p.localName == 'tr') return true;
  }
  return false;
}

/// Parses a **Caller's Box** search results page (HTML) into its result rows.
///
/// The results page (verified live, mirrored code at
/// `ibiblio.org/contradance/thecallersbox/?title=…`) renders a bare `<table>`
/// whose result rows are `<tr>`s shaped as: a few leading icon `<td>`s
/// (figures-permission / source-link / video markers, any of which may be an
/// empty cell), then
/// `<td><a href='dance.php?id=N' target='_blank'>NAME</a></td>`, then a
/// `<td>` author column, then a `<td>` formation column.
///
/// The **figures-permission** marker `Ⓕ` is read from those leading cells into
/// [CallersBoxSearchResult.figuresAvailable] (issue #845); the source-link and
/// video markers are still ignored. Rows are **not** dropped here — the parser
/// stays lossless, so its two consumers can decide separately what a figureless
/// dance means to them.
///
/// This is **pure** (no I/O): the app layer fetches the page (decoding its
/// `windows-1252` bytes) and passes the decoded HTML string here.
///
/// Robustness: only `<tr>`s that contain a `dance.php?id=N` link are treated as
/// results (the "modify your query" form has no such links), so the count line
/// and page chrome are ignored, and rows nested inside another `<tr>` are
/// skipped ([_isNestedRow]). Cells are the row's **direct children**
/// ([_directCells]). Author/formation are read from the cells that *follow* the
/// link's cell (tolerant of a differing number of leading icon cells) and
/// default to empty when absent; the marker is *scanned* across the cells that
/// precede it rather than read at a fixed index. Malformed / non-results pages
/// yield an empty list rather than throwing — the caller renders that as "no
/// results".
List<CallersBoxSearchResult> parseCallersBoxSearchResults(String html) {
  final dom.Document document;
  try {
    document = html_parser.parse(html);
  } on Object {
    return const [];
  }

  final results = <CallersBoxSearchResult>[];
  for (final row in document.querySelectorAll('tr')) {
    if (_isNestedRow(row)) continue;
    final cells = _directCells(row);
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

    // Scan ONLY the icon cells preceding the link for the permission marker.
    // Bounding the window here is what stops the dance's own title — or its
    // author/formation cells, which follow the link — from spoofing the marker
    // with a literal Ⓕ character, which TCB is perfectly able to serve.
    var figuresAvailable = false;
    for (var i = 0; i < linkCellIndex; i++) {
      if (cells[i].text.contains(_figuresPermissionMarker)) {
        figuresAvailable = true;
        break;
      }
    }

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
        figuresAvailable: figuresAvailable,
      ),
    );
  }
  return results;
}

/// Trims and collapses internal whitespace runs (incl. newlines from the source
/// HTML's pretty-printing) to single spaces.
String _collapseWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Matches TCB's total-match count line, e.g.
/// `Of 16874 dances in the db, your query matches 10287.` (verified live on
/// both title and by-phrase searches, 2026-08-06).
///
/// Digits are capped at seven so a hostile page cannot force an oversized
/// parse; the corpus is ~16,900 dances, so anything near that cap is already
/// nonsense. The trailing `(?!\d)` makes the cap a REJECTION rather than a
/// truncation — without it a nine-digit value matches its first seven digits
/// and yields a plausible-looking number that was never on the page. Anchored
/// on the full phrase rather than the bare word `matches`.
final RegExp _matchCountLine = RegExp(r'your query matches\s+(\d{1,7})(?!\d)');

/// Reads the **total** number of dances TCB says a query matched, or `null`
/// when the page carries no readable count.
///
/// TCB returns only the first 50 rows unless `show_all` is requested, but it
/// always states the full total. [CallersBoxOnline] uses this to decide whether
/// re-requesting the complete set is worth the payload, so that filtering out
/// figure-hidden dances does not compound the cap by shrinking an already
/// truncated page.
///
/// Read from the parsed document's decoded text rather than the raw HTML, and
/// bounded. A spoofed value can do no more than add or skip a single further
/// bounded request, so this deliberately does not try to prove the line came
/// from TCB's own chrome rather than from a dance title.
int? parseCallersBoxMatchCount(String html) {
  final dom.Document document;
  try {
    document = html_parser.parse(html);
  } on Object {
    return null;
  }
  final match = _matchCountLine.firstMatch(document.body?.text ?? '');
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
