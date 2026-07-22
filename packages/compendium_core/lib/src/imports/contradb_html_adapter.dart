import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../util/text_sanitizer.dart';
import 'figure_parser.dart';
import 'figure_text_scrub.dart';
import 'import_error.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// A [SourceAdapter] that imports a single dance from **ContraDB** by scraping
/// the **server-rendered HTML** at `contradb.com/dances/N` (the page a normal
/// website visitor sees).
///
/// ## Why a second ContraDB adapter?
/// The sibling [ContraDbAdapter] parses ContraDB's internal `figures_json` DB
/// column — a positional move/parameter model a typical user *cannot* obtain
/// from the website (ContraDB serves **no JSON**: `dances/N.json` → HTTP 406,
/// no public API). This adapter parses the reachable path — the clean,
/// server-rendered HTML — so a user can import a dance by pasting its URL. This
/// is the user-facing ContraDB import path (ROADMAP 6.4). The two adapters take
/// completely different inputs and are intentionally kept self-contained.
///
/// ## Core is I/O-free
/// This adapter never fetches the page. It parses an HTML *string* the app
/// layer supplies (the app's `UrlFetcher` performs the single, user-initiated
/// GET). Adding `package:html` (pure Dart) keeps the core Flutter-free (ADR-001).
///
/// ## Confirmed DOM (live, `contradb.com/dances/1`)
/// - `h1.dance-show-title` — dance title.
/// - `p.dance-show-choreographer` — `by: <strong><a href=…>NAME</a></strong>`.
/// - `p.dance-show-formation` — `formation: <free text>`.
/// - `table.contra-table-nonfluid` — the figures table. Each `<tr>` holds three
///   `<td>`s: a section label (A1/A2/B1/B2 — **empty on continuation rows**), a
///   `td.dance-show-beats`, and a `div.show-figure` with the figure text. A
///   `<u>…</u>` inside a figure and a trailing `⁋` (pilcrow) both mark the
///   progression point.
///
/// ## Figure parsing (shared parser + dialect scrub — matches CallersBox/CC)
/// Rows are read as (section-label, beats, free-text) tuples. Progression markers
/// (`<u>` / `⁋`) are stripped from the display text and captured via the figure's
/// [Figure.progression] flag. Each figure's text is routed through the CORE
/// canonicalization chokepoint [canonicalizeText] with [Dialect.canonical]
/// (gendered role terms → `role1`/`role2`), after a `gypsy` → `shoulder round`
/// legacy-move safety net, then through the shared [parseFigureLine]: recognised
/// moves import as structured [Figure]s, the rest fall back to [customFigure]
/// (beats + scrubbed text). Section labels are NOT embedded in the figure text —
/// they derive from cumulative beats via the domain model.
///
/// ## Metadata
/// - `h1.dance-show-title` → title (missing → a `ContraDB dance <id>` stub).
/// - `p.dance-show-formation` → [FormationShape] best-effort (original kept as
///   [Formation.detail]; unknown → [FormationShape.other] + a warning).
/// - `p.dance-show-choreographer` name → carried on the draft's `authorNames`
///   and resolved to a real [Choreographer] association ([Dance.authorIds]) by
///   the import pipeline (match-or-create); no longer folded into
///   [Dance.callingNotes].
///
/// ## Parse-never-fails
/// Missing/malformed elements become non-fatal [ImportIssue]s; a page with no
/// figures table still imports as a metadata stub with a warning. [parse] throws
/// only when the payload is not a ContraDB dance page at all.
class ContraDbHtmlAdapter implements SourceAdapter {
  ContraDbHtmlAdapter();

  @override
  ProvenanceSource get source => ProvenanceSource.contradb;

  /// The HTML captured by the most recent [discover], so [fetch] can wrap it in
  /// a self-contained [RawRecord]. [parse] never consults this.
  String? _html;
  String? _externalId;
  String? _label;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    _html = null;
    _externalId = null;
    _label = null;

    final payload = request.payload;
    if (payload == null || payload.trim().isEmpty) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'No ContraDB page content provided to import.',
      );
    }

    final dom.Document document;
    try {
      document = html_parser.parse(payload);
    } on Object catch (e) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'ContraDB page could not be parsed as HTML: $e',
        cause: e,
      );
    }

    final title = _extractTitle(document);
    final hasTable =
        document.querySelector('table.contra-table-nonfluid') != null;
    if ((title == null || title.isEmpty) && !hasTable) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'Page is not a ContraDB dance page: no "h1.dance-show-title" and '
            'no "table.contra-table-nonfluid" were found.',
      );
    }

    final externalId = _externalIdFrom(request.uri, title);
    _html = payload;
    _externalId = externalId;
    _label = (title != null && title.isNotEmpty) ? title : null;

    return [
      DiscoveredRecord(
        source: source,
        externalId: externalId,
        label: _label,
        locator: const {},
      ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final html = _html;
    if (html == null) {
      throw fetchError(
        source,
        'No ContraDB page has been discovered; re-run discover.',
        externalId: record.externalId,
      );
    }
    return RawRecord(
      source: source,
      externalId: record.externalId ?? _externalId,
      sourceVersion: 'contradb-html',
      payload: html,
      contentType: 'text/html',
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final dom.Document document;
    try {
      document = html_parser.parse(raw.payload);
    } on Object catch (e) {
      throw parseError(
        source,
        'ContraDB page could not be parsed as HTML: $e',
        externalId: raw.externalId,
        cause: e,
      );
    }

    final title = _extractTitle(document);
    final table = document.querySelector('table.contra-table-nonfluid');
    if ((title == null || title.isEmpty) && table == null) {
      throw parseError(
        source,
        'Payload is not a ContraDB dance page (no title and no figures table).',
        externalId: raw.externalId,
      );
    }

    final issues = <ImportIssue>[];

    final effectiveTitle = (title != null && title.isNotEmpty)
        ? title
        : 'ContraDB dance ${raw.externalId ?? '(unknown)'}';
    if (title == null || title.isEmpty) {
      issues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'contradb_html_missing_title',
          message:
              'Page had no "h1.dance-show-title"; imported with a placeholder '
              'title.',
        ),
      );
    }

    final formation = _parseFormation(document, issues);
    final figures = _parseFigures(table, issues);
    if (table == null) {
      issues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'contradb_html_no_figures_table',
          message:
              'Page had no "table.contra-table-nonfluid"; imported as a '
              'metadata-only stub (no figures).',
        ),
      );
    }

    final choreographer = _choreographer(document);

    return StructuredDraft(
      dance: Dance(
        id: 'contradb-html-import',
        title: effectiveTitle,
        formation: formation,
        figures: figures,
        callingNotes: _buildNotes(),
        // The pipeline attaches provenance at commit, derived from `raw`.
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
      raw: raw,
      issues: issues,
      authorNames: [
        if (choreographer != null && choreographer.isNotEmpty) choreographer,
      ],
    );
  }

  // --- Figures ---------------------------------------------------------------

  /// Walks the `table.contra-table-nonfluid` rows into [Figure]s via the shared
  /// [parseFigureLine]. Each row is `(section-label, beats, figure-text)`. `<u>`
  /// and `⁋` progression markers are stripped from the text and captured via the
  /// figure's progression flag. A row with no usable figure cell or only blank
  /// figure text is **skipped** (there is nothing to store); every remaining row
  /// is routed through the parser — recognised moves become structured figures,
  /// the rest fall back to [customFigure] (the parse-never-fails invariant —
  /// figure content never throws). Section labels are NOT stored in the figure
  /// text; they derive from cumulative beats via the domain model.
  List<Figure> _parseFigures(dom.Element? table, List<ImportIssue> issues) {
    if (table == null) return const [];
    final figures = <Figure>[];
    var index = 0;
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children.where((c) => c.localName == 'td').toList();
      if (cells.isEmpty) continue;

      final figureCell = _figureCell(cells);
      if (figureCell == null) continue;
      final hasProgression = _hasProgression(figureCell);
      final rawText = figureCell.text;
      final scrubbed = scrubFigureText(_stripProgressionMarkers(rawText));
      if (scrubbed.isEmpty) continue;

      // Parse beats only once the row is known to emit a figure, so a beats
      // issue's figureIndex points at this figure (not the next imported one).
      final beats = _parseBeats(_beatsCell(cells), index, issues);

      // Route the (already-scrubbed) text through the shared parser: recognised
      // moves become structured figures, the rest fall back to custom. The
      // section label is not embedded in the text (it derives from beats).
      // Non-null since `scrubbed` isn't empty.
      figures.add(
        parseFigureLine(
          scrubbed,
          beats: beats,
          progression: hasProgression,
          scrub: (s) => s,
        )!,
      );
      index++;
    }
    return figures;
  }

  /// The beats cell is `td.dance-show-beats`; fall back to the middle cell.
  dom.Element? _beatsCell(List<dom.Element> cells) {
    for (final cell in cells) {
      if (cell.classes.contains('dance-show-beats')) return cell;
    }
    return cells.length >= 3 ? cells[1] : null;
  }

  /// The figure cell holds `div.show-figure`; fall back to the last cell only
  /// when the row has the full three-column shape (label, beats, figure), so a
  /// malformed row that is just a stray label cell is not mistaken for a figure.
  dom.Element? _figureCell(List<dom.Element> cells) {
    for (final cell in cells) {
      if (cell.querySelector('div.show-figure') != null) return cell;
    }
    return cells.length >= 3 ? cells.last : null;
  }

  int _parseBeats(dom.Element? cell, int index, List<ImportIssue> issues) {
    final text = cell?.text.trim() ?? '';
    if (text.isEmpty) return 0;
    final beats = int.tryParse(text);
    if (beats == null || beats < 0) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.info,
          code: 'contradb_html_beats_unreadable',
          message: 'Beats "$text" is not a non-negative integer; used 0.',
          figureIndex: index,
        ),
      );
      return 0;
    }
    return beats;
  }

  bool _hasProgression(dom.Element figureCell) {
    if (figureCell.querySelector('u') != null) return true;
    return _progressionMarker.hasMatch(figureCell.text);
  }

  String _stripProgressionMarkers(String text) =>
      text.replaceAll(_progressionMarker, ' ');

  // --- Formation -------------------------------------------------------------

  Formation _parseFormation(dom.Document document, List<ImportIssue> issues) {
    final raw = document.querySelector('p.dance-show-formation')?.text.trim();
    final stripped = _stripLeadingLabel(raw, 'formation');
    final detailText = stripped == null
        ? null
        : sanitizeImportedText(stripped).trim();
    if (detailText == null || detailText.isEmpty) {
      return const Formation(FormationShape.dupleImproper);
    }

    final lower = detailText.toLowerCase();
    FormationShape? shape;
    if (lower.contains('becket')) {
      shape = (lower.contains('ccw') || lower.contains('counter'))
          ? FormationShape.becketCcw
          : FormationShape.becketCw;
    } else if (lower.contains('improper')) {
      shape = FormationShape.dupleImproper;
    } else if (lower.contains('indecent')) {
      shape = FormationShape.dupleIndecent;
    } else if (lower.contains('triplet')) {
      shape = FormationShape.triplet;
    } else if (lower.contains('triple')) {
      shape = FormationShape.tripleMinor;
    } else if (lower.contains('proper')) {
      shape = FormationShape.dupleProper;
    } else if (lower.contains('four facing four') ||
        lower.contains('four face four')) {
      shape = FormationShape.fourFaceFour;
    } else if (lower.contains('three facing three') ||
        lower.contains('three face three')) {
      shape = FormationShape.threeFaceThree;
    } else if (lower.contains('sicilian')) {
      shape = FormationShape.sicilianCircle;
    } else if (lower.contains('scatter')) {
      shape = FormationShape.scatterMixer;
    } else if (lower.contains('grid')) {
      shape = FormationShape.grid;
    } else if (lower.contains('circle')) {
      shape = FormationShape.circleMixer;
    } else if (lower.contains('longways')) {
      shape = FormationShape.longways;
    }

    if (shape == null) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'contradb_html_formation_unclassified',
          message:
              'Formation "$detailText" did not classify to a known shape; kept '
              'as detail on "other".',
        ),
      );
      return Formation(FormationShape.other, detail: detailText);
    }
    return Formation(shape, detail: detailText);
  }

  // --- Notes -----------------------------------------------------------------

  String _buildNotes() {
    // The choreographer name is resolved to a Choreographer association by the
    // import pipeline (Dance.authorIds) via the draft's authorNames, so it is
    // no longer folded into the notes.
    return 'Imported from ContraDB.';
  }

  /// Extracts the choreographer name from `p.dance-show-choreographer`,
  /// preferring the linked `<a>` text and falling back to the text after `by:`.
  String? _choreographer(dom.Document document) {
    final element = document.querySelector('p.dance-show-choreographer');
    if (element == null) return null;
    final link = element.querySelector('a')?.text.trim();
    if (link != null && link.isNotEmpty) {
      return sanitizeImportedText(link).trim();
    }
    final stripped = _stripLeadingLabel(element.text.trim(), 'by');
    if (stripped == null || stripped.isEmpty) return null;
    final clean = sanitizeImportedText(stripped).trim();
    return clean.isEmpty ? null : clean;
  }

  // --- Helpers ---------------------------------------------------------------

  /// Extracts and sanitizes the `h1.dance-show-title` text. Sanitizing here (at
  /// ingress) strips control/bidi/format spoofing characters before the title
  /// is stored or used to derive the dance's external id (issue #444). Returns
  /// null when the title element is absent.
  static String? _extractTitle(dom.Document document) {
    final raw = document.querySelector('h1.dance-show-title')?.text.trim();
    if (raw == null) return null;
    return sanitizeImportedText(raw).trim();
  }

  /// Removes a leading `label:` (or `label`) prefix, case-insensitively, from
  /// [text]. Returns `null` when [text] is null/blank.
  static String? _stripLeadingLabel(String? text, String label) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final pattern = RegExp(
      '^${RegExp.escape(label)}\\s*:?\\s*',
      caseSensitive: false,
    );
    return trimmed.replaceFirst(pattern, '').trim();
  }

  /// Derives a stable external id: the numeric dance id from a
  /// `contradb.com/dances/N` URL when available, else `name:<lowercased title>`.
  static String? _externalIdFrom(String? uri, String? title) {
    if (uri != null) {
      final match = _danceIdInUri.firstMatch(uri);
      if (match != null) return match.group(1);
    }
    if (title != null && title.trim().isNotEmpty) {
      return 'name:${title.trim().toLowerCase()}';
    }
    return null;
  }

  static final RegExp _danceIdInUri = RegExp(r'/dances/(\d+)');

  /// The progression markers ContraDB renders in figure text: the pilcrow
  /// `⁋` (U+204B) and the standard pilcrow `¶` (U+00B6). The `<u>` element is
  /// handled separately since it carries no distinctive character.
  static final RegExp _progressionMarker = RegExp('[\u204B\u00B6]');

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
}
