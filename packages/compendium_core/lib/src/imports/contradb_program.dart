import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:meta/meta.dart';

import '../util/text_sanitizer.dart';

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
  /// [title] is the dance title as shown on the program page (surrounding
  /// whitespace trimmed, otherwise verbatim, aside from the #444/#611
  /// bidi/zero-width sanitization below). [note] is optional free text
  /// attached to this dance on the program (e.g. "Called as ladles:'pirates'…");
  /// its content is preserved as-is (outer whitespace trimmed) and never
  /// guessed.
  ///
  /// [title] is sanitized as a single-line field
  /// (`sanitizeImportedText(allowLineBreaks: false)`) and [note] as multi-line
  /// prose (`sanitizeImportedText`, default) — the same #444 defense the dance
  /// import paths apply — so a hostile program page can't smuggle bidi
  /// overrides or invisible/zero-width characters into stored program text
  /// (issue #611). A [title] that sanitizes down to nothing is stored as
  /// `null` rather than an empty string, so fallback display text still
  /// triggers.
  factory ContraDbProgramActivity.dance({
    required String danceId,
    required String title,
    String? note,
  }) {
    final cleanNote = (note != null && note.trim().isNotEmpty)
        ? sanitizeImportedText(note.trim()).trim()
        : null;
    // Normalize a title that sanitizes down to nothing (e.g. one consisting
    // only of bidi/zero-width spoofing characters) to null rather than an
    // empty string, so `activity.title ?? <fallback>` call sites (the preview
    // tile, `resolveContraDbProgram`) still show their fallback instead of a
    // blank title (issue #611 review follow-up).
    final cleanTitle = sanitizeImportedText(title, allowLineBreaks: false);
    return ContraDbProgramActivity._(
      isDance: true,
      danceId: danceId,
      title: cleanTitle.isEmpty ? null : cleanTitle,
      text: (cleanNote != null && cleanNote.isNotEmpty) ? cleanNote : null,
    );
  }

  /// A standalone free-text note activity (announcement / waltz / break). Its
  /// content is preserved as-is (surrounding whitespace trimmed) other than
  /// the #444/#611 bidi/zero-width sanitization (`sanitizeImportedText`,
  /// multi-line prose); consumers must render it as a note slot and must
  /// **not** try to resolve it to a dance.
  factory ContraDbProgramActivity.note(String text) =>
      ContraDbProgramActivity._(
        isDance: false,
        text: sanitizeImportedText(text.trim()).trim(),
      );

  /// Whether this activity is a linked dance ([danceId]/[title] set). When
  /// false it is a standalone note ([text] holds the note body).
  final bool isDance;

  /// ContraDB dance id (numeric string) for a linked dance; null for a note.
  final String? danceId;

  /// Dance title for a linked dance (null when the source title sanitized
  /// down to nothing, e.g. all bidi/zero-width spoofing characters); null for
  /// a note.
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

/// A parsed **ContraDB program** (set list): its [title], the [contributor]
/// who uploaded it (when present), and its ordered [activities].
@immutable
class ContraDbProgram {
  const ContraDbProgram({
    required this.title,
    required this.activities,
    this.contributor,
  });

  /// The program title (the page `h1`); may be empty if the page had none.
  final String title;

  /// The ContraDB user who uploaded the program (the `user:` line on the page),
  /// taken **verbatim**, or null when the page has no contributor or the value
  /// was empty/implausible. Sanitized on parse (whitespace/control chars
  /// collapsed, bounded length) so untrusted page markup can never inject into
  /// downstream display; see [parseContraDbProgram].
  final String? contributor;

  /// The program's activities in source order (dances + notes interleaved).
  final List<ContraDbProgramActivity> activities;

  @override
  bool operator ==(Object other) =>
      other is ContraDbProgram &&
      other.title == title &&
      other.contributor == contributor &&
      _listEquals(other.activities, activities);

  @override
  int get hashCode =>
      Object.hash(title, contributor, Object.hashAll(activities));

  @override
  String toString() =>
      'ContraDbProgram(title: $title, contributor: $contributor, '
      'activities: $activities)';
}

/// Parses the **server-rendered HTML** of a ContraDB program page
/// (`contradb.com/programs/{id}`) into an ordered [ContraDbProgram].
///
/// ## Confirmed DOM (live, `contradb.com/programs/33`)
/// The program title is the `.programs-show-content h1`. The **contributor**
/// (uploader) is the sole user link inside the program content —
/// `.programs-show-content a[href="/users/{numericId}"]` (the `user:` line);
/// the nav's `/users/sign_up` & `/users/sign_in` links live outside that
/// container and the numeric-id guard excludes them. The activity list is
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

  final title = sanitizeImportedText(
    (document.querySelector('.programs-show-content h1') ??
                document.querySelector('h1'))
            ?.text
            .trim() ??
        '',
    allowLineBreaks: false,
  );

  final contributor = _parseContributor(document);

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
        _addNoteIfNotEmpty(activities, danceTitle);
      }
      continue;
    }

    final noteHeading = block.querySelector('h2.activity-breakdown-text');
    if (noteHeading != null) {
      _addNoteIfNotEmpty(activities, noteHeading.text.trim());
      continue;
    }
    // Empty activity (`~ ~ ~`) or an unrecognised block: nothing to preserve.
  }

  return ContraDbProgram(
    title: title,
    contributor: contributor,
    activities: activities,
  );
}

/// Builds a [ContraDbProgramActivity.note] from [rawText] and appends it to
/// [activities], but only when it still has content **after** the #444/#611
/// bidi/zero-width sanitization. A source line that is entirely spoofing
/// characters (e.g. a lone bidi override) would otherwise sanitize down to an
/// empty string and produce a useless empty note tile; skipping it here keeps
/// the same "nothing to preserve" fidelity rule the empty-activity (`~ ~ ~`)
/// case already follows. [rawText] itself must already be non-empty
/// (pre-sanitization) — callers only reach this once they've confirmed the
/// scraped text isn't blank.
void _addNoteIfNotEmpty(
  List<ContraDbProgramActivity> activities,
  String rawText,
) {
  final activity = ContraDbProgramActivity.note(rawText);
  if (activity.text != null && activity.text!.isNotEmpty) {
    activities.add(activity);
  }
}

/// Maximum contributor length we accept from the untrusted page. ContraDB
/// display names are short; anything longer is implausible/adversarial and is
/// rejected (treated as no contributor) so a hostile page can't push a giant
/// string downstream.
const int _kMaxContributorLength = 100;

/// Extracts the ContraDB contributor (uploader) from the program page, or null
/// when absent/implausible.
///
/// Scoped to `.programs-show-content` and to `/users/{numericId}` links so the
/// nav's `/users/sign_up`/`/users/sign_in` are never mistaken for a
/// contributor. The visible text is taken **verbatim** (fidelity rule) but
/// defensively sanitized — `package:html` already strips tags/decodes entities,
/// and we additionally collapse whitespace/control characters and bound the
/// length so untrusted markup cannot inject into or bloat the caller field.
/// Never throws: any failure yields null and the import falls back to the
/// user's default caller.
String? _parseContributor(dom.Document document) {
  try {
    final content = document.querySelector('.programs-show-content');
    if (content == null) return null;
    for (final link in content.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href == null) continue;
      if (!RegExp(r'^/users/\d+$').hasMatch(href)) continue;
      final name = _sanitizeContributor(link.text);
      if (name != null) return name;
    }
    return null;
  } on Object {
    return null;
  }
}

/// Collapses internal whitespace, strips control/bidi/zero-width characters,
/// trims, and bounds the length of a scraped contributor name. Returns null
/// for an empty or over-long (implausible) value so the caller can fall back
/// to the default.
///
/// Reuses the shared #444 sanitizer (`sanitizeImportedText`) rather than a
/// second, divergent hand-rolled scrubber (issue #611) — it strips the same
/// bidi-override/zero-width spoofing characters the dance import paths
/// guard against, not just C0/C1 controls.
String? _sanitizeContributor(String raw) {
  final sanitized = sanitizeImportedText(raw, allowLineBreaks: false);
  // Collapse runs of whitespace (incl. any newlines/tabs the single-line
  // sanitizer already stripped) to single spaces so a multi-line/padded name
  // normalizes cleanly.
  final cleaned = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return null;
  if (cleaned.length > _kMaxContributorLength) return null;
  return cleaned;
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
