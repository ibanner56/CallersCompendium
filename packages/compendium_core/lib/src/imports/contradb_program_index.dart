import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:meta/meta.dart';

/// One entry of the **ContraDB program index** — a `(id, name)` pair scraped
/// from the public `contradb.com/programs` listing page.
///
/// ContraDB exposes no JSON program-search API (`POST /api/v1/programs` → HTTP
/// 404). Its only searchable surface for programs is the public index page,
/// which renders **every** program as a `<a href="/programs/{id}">Name</a>`
/// anchor with no server-side search and no pagination. This type carries one
/// such anchor so the app can filter the list by [name] client-side and then
/// import the chosen program by its [id] via the existing program-import flow.
///
/// The [id] is the ContraDB program **identity** (the `/programs/{id}` id) — the
/// only reliable key. The [name] is the anchor's link text **verbatim** (outer
/// whitespace trimmed); it is a display label only and is never used to resolve
/// or fabricate a program.
@immutable
class ContraDbProgramIndexEntry {
  const ContraDbProgramIndexEntry({required this.id, required this.name});

  /// ContraDB program id (numeric string), from the `/programs/{id}` href.
  final String id;

  /// Program name as shown on the index page (link text, outer whitespace
  /// trimmed, otherwise verbatim).
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ContraDbProgramIndexEntry &&
      other.id == id &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'ContraDbProgramIndexEntry(id: $id, name: $name)';
}

/// Matches a program-page path (`/programs/{id}`) and captures the numeric id.
///
/// Anchored so nav links like `/programs`, `/programs/new`, or `/programs/33/edit`
/// do **not** match — only a bare `/programs/{digits}` path yields an entry.
final RegExp _programIdPath = RegExp(r'^/programs/(\d+)$');

/// Parses the **ContraDB program index** HTML (the body of `GET /programs`) into
/// an ordered list of [ContraDbProgramIndexEntry].
///
/// Selects every `a[href^="/programs/"]`, keeps only anchors whose href path is
/// exactly `/programs/{numericId}`, and pairs that id with the anchor's verbatim
/// (outer-trimmed) link text. Anchors without a numeric id (e.g. the `/programs`
/// nav link, `/programs/new`) or with empty link text are skipped — nothing is
/// invented.
///
/// **Parse-never-throws**: the ContraDB response is untrusted input, so malformed
/// or empty HTML (or any parser error) yields an empty list rather than throwing.
List<ContraDbProgramIndexEntry> parseContraDbProgramIndex(String html) {
  try {
    final document = html_parser.parse(html);
    final entries = <ContraDbProgramIndexEntry>[];
    for (final anchor in document.querySelectorAll('a[href^="/programs/"]')) {
      final entry = _entryFromAnchor(anchor);
      if (entry != null) entries.add(entry);
    }
    return entries;
  } on Object {
    return const [];
  }
}

ContraDbProgramIndexEntry? _entryFromAnchor(dom.Element anchor) {
  final href = anchor.attributes['href'];
  if (href == null) return null;
  // Compare against the path only; ignore any query/fragment defensively.
  final path = Uri.tryParse(href)?.path ?? href;
  final match = _programIdPath.firstMatch(path);
  if (match == null) return null;
  final name = anchor.text.trim();
  if (name.isEmpty) return null;
  return ContraDbProgramIndexEntry(id: match.group(1)!, name: name);
}
