import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:meta/meta.dart';

/// One activity of a **ContraDB program** (set list), in the exact order it
/// appears on the program page.
///
/// A program activity is either a **linked dance** (a reference to a specific
/// `contradb.com/dances/{id}` page, carrying the verbatim id + title, plus any
/// attached free-text note) or a **standalone note** (an announcement / waltz /
/// break — free text the caller wrote between dances).
///
/// The [danceId] is the ContraDB *identity* of the referenced dance. It is the
/// only reliable key: a locally-stored dance with the same [title] may be a
/// *different* dance, so consumers must resolve linked activities by this id
/// (via the per-dance HTML scrape), never by a fuzzy title match.
@immutable
class ContraDbProgramActivity {
  const ContraDbProgramActivity._({
    required this.isDance,
    this.danceId,
    this.title,
    this.text,
  });

  /// A linked ContraDB dance. [danceId] is the numeric `/dances/{id}` id and
  /// [title] is the dance title as shown on the program page (both verbatim).
  /// [note] is optional free text attached to this dance on the program (e.g.
  /// "Called as ladles:'pirates'…"); it is preserved verbatim and never guessed.
  factory ContraDbProgramActivity.dance({
    required String danceId,
    required String title,
    String? note,
  }) => ContraDbProgramActivity._(
    isDance: true,
    danceId: danceId,
    title: title,
    text: (note != null && note.trim().isNotEmpty) ? note.trim() : null,
  );

  /// A standalone free-text note activity (announcement / waltz / break). Kept
  /// verbatim; consumers must render it as a note slot and must **not** try to
  /// resolve it to a dance.
  factory ContraDbProgramActivity.note(String text) =>
      ContraDbProgramActivity._(isDance: false, text: text.trim());

  /// Whether this activity is a linked dance ([danceId]/[title] set). When
  /// false it is a standalone note ([text] holds the note body).
  final bool isDance;

  /// ContraDB dance id (numeric string) for a linked dance; null for a note.
  final String? danceId;

  /// Dance title for a linked dance; null for a note.
  final String? title;

  /// For a linked dance: the optional attached note (null when none). For a
  /// note activity: the note body (non-null, may be empty only if the source
  /// note was blank — such notes are dropped by [parseContraDbProgram]).
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is ContraDbProgramActivity &&
      other.isDance == isDance &&
      other.danceId == danceId &&
      other.title == title &&
      other.text == text;

  @override
  int get hashCode => Object.hash(isDance, danceId, title, text);

  @override
  String toString() => isDance
      ? 'ContraDbProgramActivity.dance(danceId: $danceId, title: $title, '
            'note: $text)'
      : 'ContraDbProgramActivity.note($text)';
}

/// A parsed **ContraDB program** (set list): its [title] and its ordered
/// [activities].
@immutable
class ContraDbProgram {
  const ContraDbProgram({required this.title, required this.activities});

  /// The program title (the page `h1`); may be empty if the page had none.
  final String title;

  /// The program's activities in source order (dances + notes interleaved).
  final List<ContraDbProgramActivity> activities;

  @override
  bool operator ==(Object other) =>
      other is ContraDbProgram &&
      other.title == title &&
      _listEquals(other.activities, activities);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(activities));

  @override
  String toString() =>
      'ContraDbProgram(title: $title, activities: $activities)';
}

/// Parses the **server-rendered HTML** of a ContraDB program page
/// (`contradb.com/programs/{id}`) into an ordered [ContraDbProgram].
///
/// ## Confirmed DOM (live, `contradb.com/programs/33`)
/// The program title is the `.programs-show-content h1`. The activity list is
/// the sequence of `div.activity-breakdown` blocks, in document order. Each is:
/// - **linked dance** — `h2.activity-breakdown-dance-title` containing
///   `<a href="/dances/{id}">Title</a>`. A sibling `p.activity-breakdown-text`
///   (when present) is a note attached to that dance.
/// - **standalone note** — `h2.activity-breakdown-text` (rendered markdown of
///   the caller's free text).
/// - **empty slot** — `h2.activity-breakdown-empty-activity` (`~ ~ ~`): a
///   placeholder with no content; dropped (nothing to preserve).
///
/// ## Core is I/O-free
/// This never fetches; it parses an HTML *string* the app layer supplies (the
/// app's single, user-initiated GET). `package:html` is pure Dart, so the core
/// stays Flutter-free (ADR-001), matching `ContraDbHtmlAdapter`.
///
/// ## Parse-never-throws
/// Malformed HTML, a foreign page, or missing elements yield an empty/partial
/// [ContraDbProgram] rather than throwing — the caller renders "no dances found"
/// instead of crashing. Fidelity: dance ids/titles and note text are taken
/// verbatim; nothing is fabricated.
ContraDbProgram parseContraDbProgram(String html) {
  final dom.Document document;
  try {
    document = html_parser.parse(html);
  } on Object {
    return const ContraDbProgram(title: '', activities: []);
  }

  final title =
      (document.querySelector('.programs-show-content h1') ??
              document.querySelector('h1'))
          ?.text
          .trim() ??
      '';

  final activities = <ContraDbProgramActivity>[];
  for (final block in document.querySelectorAll('.activity-breakdown')) {
    final danceHeading = block.querySelector(
      'h2.activity-breakdown-dance-title',
    );
    if (danceHeading != null) {
      final link = danceHeading.querySelector('a[href]');
      final danceId = _danceIdFromHref(link?.attributes['href']);
      final danceTitle = (link?.text ?? danceHeading.text).trim();
      if (danceId != null && danceId.isNotEmpty) {
        activities.add(
          ContraDbProgramActivity.dance(
            danceId: danceId,
            title: danceTitle,
            note: _attachedNote(block),
          ),
        );
      } else if (danceTitle.isNotEmpty) {
        // A dance heading with no resolvable /dances/{id} link: we can't scrape
        // an identity, but the title is real ContraDB data — keep it verbatim as
        // a note so ordering and content are never lost.
        activities.add(ContraDbProgramActivity.note(danceTitle));
      }
      continue;
    }

    final noteHeading = block.querySelector('h2.activity-breakdown-text');
    if (noteHeading != null) {
      final text = noteHeading.text.trim();
      if (text.isNotEmpty) activities.add(ContraDbProgramActivity.note(text));
      continue;
    }
    // Empty activity (`~ ~ ~`) or an unrecognised block: nothing to preserve.
  }

  return ContraDbProgram(title: title, activities: activities);
}

/// Extracts the numeric dance id from a `/dances/{id}` href (absolute or
/// relative). Returns null when [href] is missing or not a dance link.
String? _danceIdFromHref(String? href) {
  if (href == null) return null;
  final match = RegExp(r'/dances/(\d+)').firstMatch(href);
  return match?.group(1);
}

/// Reads the note text attached to a linked dance inside [block], or null when
/// there is none.
///
/// ContraDB renders an attached note as `<p class="activity-breakdown-text">`
/// wrapping a `<div class="contra-markdown-block">`. Because a `<p>` may not
/// contain a `<div>`, the HTML parser closes the `<p>` early, leaving it empty
/// with the real text in the immediately-following `.contra-markdown-block`
/// sibling — so we read that sibling when the `<p>` itself is empty.
String? _attachedNote(dom.Element block) {
  final marker = block.querySelector('p.activity-breakdown-text');
  if (marker == null) return null;
  final direct = marker.text.trim();
  if (direct.isNotEmpty) return direct;
  final sibling = marker.nextElementSibling;
  if (sibling != null && sibling.classes.contains('contra-markdown-block')) {
    final text = sibling.text.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

bool _listEquals(
  List<ContraDbProgramActivity> a,
  List<ContraDbProgramActivity> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
