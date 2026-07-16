import 'dart:convert';

import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';
import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../model/phrase_structure.dart';
import 'import_error.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// A [SourceAdapter] that imports dances from **The Caller's Box** (TCB)
/// per-dance JSON, as served by
/// `ibiblio.org/contradance/thecallersbox/dance.php?id=N&format=JSON`
/// (surveyed in `docs/research/callersbox.md`; conventions in
/// `docs/design/imports.md` §"CallersBox" and `docs/design/callersbox-snapshot.md`).
///
/// **Core is I/O-free** — this adapter never fetches the endpoint. It parses a
/// payload *string* that the app layer supplies (a separate PR adds the URL
/// fetch + in-app wiring, at which point ROADMAP 6.2/6.3 tick). The same parse
/// path is reused by the future 6.2 hosted-snapshot NDJSON import.
///
/// ## Scope: figures imported as CUSTOM (dialect-scrubbed text + beats)
/// TCB figure lines are free text of the form `(beats) text` (e.g.
/// `(4) Neighbor balance`). A `(beats) text` → **structured-move** grammar
/// parser is a genuinely separate, large effort and is **deferred to a
/// follow-up** (the same call the ContraDB 6.4 and Caller's Companion 6.5
/// adapters made). Here every figure line is imported as a [customFigure]
/// carrying its beats and its **canonicalized** text, so the headline asks —
/// by-link parsing + gendered-term dialect scrubbing — are fully delivered and
/// `parse` never fails on figure content.
///
/// ## Dialect scrubbing (the headline ask)
/// Each figure line's text is routed through the CORE canonicalization
/// chokepoint [canonicalizeText] with [Dialect.canonical], whose always-on
/// legacy-synonym map rewrites gendered role terms
/// (gents/ladies/larks/robins/ladles/gentlespoons) to canonical role tokens
/// (`role1`/`role2`). Storage is dialect-agnostic; the app renders per the
/// user's active dialect. As a safety net the legacy move term `gypsy` is also
/// substituted to `shoulder round` (TCB already did this globally in Oct 2025).
///
/// ## Permission tiers (honored exactly)
/// - `Permission: full` → phrases/figures imported normally.
/// - anything else (`search`, blank, omitted) → TCB serves only metadata
///   (empty/omitted `phrases`); imported as a **metadata-only** draft (title,
///   formation, notes) with **no** reconstructed figures and a warning issue.
///   Figures are never fabricated for a non-full dance.
///
/// ## Choreographers / metadata
/// The pipeline resolves authors by id and does not create Choreographer rows
/// from names, so [Dance.authorIds] is left **empty**; each TCB `Authors[]`
/// name is folded into [Dance.callingNotes] and surfaced as an info issue for
/// the review step. `FormationBase`/`FormationDetail` classify to a
/// [FormationShape] best-effort (original kept as [Formation.detail]);
/// `Progression` maps best-effort; `PhraseStructure` empty means the default.
///
/// ## Contract
/// - [discover] decodes the payload once and accepts a single TCB dance object,
///   an array of dances, or an object with a `dances`/`records` array. It
///   throws a discover [ImportError] on a missing/blank/undecodable payload, an
///   empty set, or a payload that is not a TCB dance (no `ID`/`Name`). It emits
///   one [DiscoveredRecord] per dance (`externalId` = TCB `ID`, `label` =
///   `Name`).
/// - [fetch] re-serializes the single dance into a self-contained [RawRecord]
///   (permission + a `sourceVersion` tag carried through) so [parse] never
///   depends on discover state.
/// - [parse] maps one TCB dance JSON → [StructuredDraft]. It throws a parse
///   [ImportError] only when there is no usable dance at all (undecodable / not
///   an object / no `ID` and no `Name`). It never fails on figure content.
class CallersBoxAdapter implements SourceAdapter {
  CallersBoxAdapter();

  @override
  ProvenanceSource get source => ProvenanceSource.callersbox;

  /// Raw dance elements from the most recent [discover], in order, so [fetch]
  /// can re-serialize a single dance by index. [parse] never consults this.
  final List<Object?> _records = [];

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    // Reset up front so a failed attempt never leaves stale records fetchable
    // from a prior successful discover on this instance.
    _records.clear();

    final payload = request.payload;
    if (payload == null || payload.trim().isEmpty) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'No Caller\'s Box payload provided to import.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (e) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'Payload is not valid JSON: ${e.message}',
        cause: e,
      );
    }

    final elements = _extractDanceElements(decoded);
    if (elements == null) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'Payload is not a Caller\'s Box dance export: expected a TCB dance '
            'object (with "ID"/"Name"), an array of dances, or an object with '
            'a "dances"/"records" array.',
      );
    }
    // Keep only dance-like elements so a mixed array/wrapper never surfaces a
    // record with a null id/label that would only fail later in parse().
    final dances = elements.where(_looksLikeTcbDance).toList();
    if (dances.isEmpty) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'Payload does not contain a Caller\'s Box dance: no element has an '
            '"ID" or "Name".',
      );
    }

    _records.addAll(dances);
    return [
      for (var i = 0; i < dances.length; i++)
        DiscoveredRecord(
          source: source,
          externalId: _externalIdOf(dances[i]),
          label: _nameOf(dances[i]),
          locator: {'index': i},
        ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final index = record.locator['index'];
    if (index is! int || index < 0 || index >= _records.length) {
      throw fetchError(
        source,
        'Record locator is missing a valid "index"; re-run discover.',
        externalId: record.externalId,
      );
    }
    final element = _records[index];
    return RawRecord(
      source: source,
      externalId: record.externalId,
      sourceVersion: _sourceVersionOf(element),
      payload: jsonEncode(element),
      contentType: 'application/json',
      permission: _permissionOf(element),
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.payload);
    } on FormatException catch (e) {
      throw parseError(
        source,
        'Payload is not valid JSON: ${e.message}',
        externalId: raw.externalId,
        cause: e,
      );
    }
    if (decoded is! Map) {
      throw parseError(
        source,
        'Payload is not a Caller\'s Box dance object.',
        externalId: raw.externalId,
      );
    }
    final dance = Map<String, Object?>.from(decoded);

    final title = _asString(dance['Name'])?.trim();
    final id = _asString(dance['ID'])?.trim();
    if ((title == null || title.isEmpty) && (id == null || id.isEmpty)) {
      throw parseError(
        source,
        'Caller\'s Box record has no "ID" or "Name".',
        externalId: raw.externalId,
      );
    }
    // A dance with an id but no name is still importable (metadata stub).
    final effectiveTitle = (title != null && title.isNotEmpty)
        ? title
        : 'Caller\'s Box dance $id';

    final issues = <ImportIssue>[];
    final formation = _parseFormation(dance, issues);
    final progression = _parseProgression(dance['Progression'], issues);
    final phraseStructure = _parsePhraseStructure(
      dance['PhraseStructure'],
      issues,
    );

    final permission = (_asString(dance['Permission'])?.trim() ?? '')
        .toLowerCase();
    final isFull = permission == 'full';
    final figures = isFull
        ? _parseFigures(dance['phrases'], issues)
        : const <Figure>[];
    if (!isFull) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'callersbox_search_tier',
          message: permission.isEmpty
              ? 'Dance has no "full" permission tier; The Caller\'s Box '
                    'serves only metadata (no figures). Imported as a '
                    'metadata-only stub.'
              : 'Dance permission tier is "$permission" (not "full"); The '
                    'Caller\'s Box serves only metadata (no figures). '
                    'Imported as a metadata-only stub.',
        ),
      );
    }

    return StructuredDraft(
      dance: Dance(
        id: 'callersbox-import',
        title: effectiveTitle,
        formation: formation,
        progression: progression,
        phraseStructure: phraseStructure,
        figures: figures,
        callingNotes: _buildNotes(dance, issues),
        tunes: _asStringList(dance['Tunes']),
        // The pipeline attaches provenance at commit, derived from `raw`.
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
      raw: raw,
      issues: issues,
    );
  }

  // --- Figures ---------------------------------------------------------------

  /// TCB `phrases` is an array of `{name, figures:[line, ...]}`. Figures are
  /// concatenated across phrases in order; each line becomes a [customFigure].
  /// Parse-never-fails: any odd line is still imported as custom.
  List<Figure> _parseFigures(Object? phrases, List<ImportIssue> issues) {
    if (phrases is! List) return const [];
    final figures = <Figure>[];
    var index = 0;
    for (final phrase in phrases) {
      if (phrase is! Map) continue;
      final lines = phrase['figures'];
      if (lines is! List) continue;
      for (final line in lines) {
        final text = _asString(line);
        if (text == null) continue;
        final figure = _parseFigureLine(text, index, issues);
        if (figure != null) {
          figures.add(figure);
          index++;
        }
      }
    }
    return figures;
  }

  /// Parses one TCB figure line `(beats) text`. A missing prefix or `(0)` means
  /// a 0-beat line (a formation label). Returns `null` only for a line that is
  /// empty after scrubbing (nothing to store).
  Figure? _parseFigureLine(String line, int index, List<ImportIssue> issues) {
    final match = _beatsPrefix.firstMatch(line);
    int beats = 0;
    String text = line.trim();
    if (match != null) {
      beats = int.tryParse(match.group(1)!) ?? 0;
      text = match.group(2)!.trim();
    }
    final scrubbed = _scrub(text).trim();
    if (scrubbed.isEmpty) return null;
    return customFigure(scrubbed, beats: beats);
  }

  /// Applies the dialect chokepoint (gendered role terms → canonical tokens)
  /// after the `gypsy` → `shoulder round` legacy-move safety net.
  String _scrub(String text) {
    final degypsied = text
        .replaceAllMapped(_gypsiesTerm, (_) => 'shoulder rounds')
        .replaceAllMapped(_gypsyTerm, (_) => 'shoulder round');
    return canonicalizeText(degypsied, Dialect.canonical);
  }

  // --- Formation -------------------------------------------------------------

  Formation _parseFormation(
    Map<String, Object?> dance,
    List<ImportIssue> issues,
  ) {
    final base = _asString(dance['FormationBase'])?.trim() ?? '';
    final extra = _asString(dance['FormationDetail'])?.trim() ?? '';
    final combined = [base, extra].where((s) => s.isNotEmpty).join(' — ');
    final detail = combined.isEmpty ? null : combined;

    if (base.isEmpty && extra.isEmpty) {
      return const Formation(FormationShape.dupleImproper);
    }

    final lower = '$base $extra'.toLowerCase();
    FormationShape? shape;
    if (lower.contains('becket')) {
      shape = (lower.contains('ccw') || lower.contains('counter'))
          ? FormationShape.becketCcw
          : FormationShape.becketCw;
    } else if (lower.contains('improper')) {
      shape = FormationShape.dupleImproper;
    } else if (lower.contains('indecent')) {
      shape = FormationShape.dupleIndecent;
    } else if (lower.contains('proper')) {
      shape = FormationShape.dupleProper;
    } else if (lower.contains('triple')) {
      shape = FormationShape.tripleMinor;
    } else if (lower.contains('triplet')) {
      shape = FormationShape.triplet;
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
          code: 'callersbox_formation_unclassified',
          message:
              'Formation "${detail ?? base}" did not classify to a known '
              'shape; kept as detail on "other".',
        ),
      );
      return Formation(FormationShape.other, detail: detail);
    }
    return Formation(shape, detail: detail);
  }

  // --- Progression -----------------------------------------------------------

  Progression _parseProgression(Object? raw, List<ImportIssue> issues) {
    final text = _asString(raw)?.trim();
    if (text == null || text.isEmpty) return Progression.single;
    switch (text.toLowerCase()) {
      case 'none':
        return Progression.none;
      case 'single':
        return Progression.single;
      case 'double':
        return Progression.double;
      case 'triple':
        return Progression.triple;
      case 'quadruple':
        return Progression.quadruple;
    }
    issues.add(
      ImportIssue(
        severity: ImportIssueSeverity.info,
        code: 'callersbox_progression_unmapped',
        message:
            'Progression "$text" is not a standard tier; recorded as "other".',
      ),
    );
    return Progression.other;
  }

  // --- Phrase structure ------------------------------------------------------

  String _parsePhraseStructure(Object? raw, List<ImportIssue> issues) {
    final text = _asString(raw)?.trim();
    if (text == null || text.isEmpty) return '';
    try {
      // Validate against the model's grammar; keep the raw form when valid.
      PhraseStructure.parse(text);
      return text;
    } on FormatException {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'callersbox_phrase_structure_unreadable',
          message:
              'PhraseStructure "$text" is not "phrases*bars*beatsPerBar"; '
              'default structure used.',
        ),
      );
      return '';
    }
  }

  // --- Notes -----------------------------------------------------------------

  String _buildNotes(Map<String, Object?> dance, List<ImportIssue> issues) {
    final parts = <String>[];

    final authors = _asStringList(dance['Authors']);
    if (authors.isNotEmpty) {
      parts.add('By: ${authors.join(', ')}');
      for (final author in authors) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'callersbox_author_unresolved',
            message:
                'Author "$author" recorded in notes; author linking is '
                'resolved by the import pipeline (no id fabricated).',
          ),
        );
      }
    }

    final interpretedBy = _asStringList(dance['InterpretedBy']);
    if (interpretedBy.isNotEmpty) {
      parts.add('Interpreted by: ${interpretedBy.join(', ')}');
    }

    final callingNotes = _asStringList(dance['CallingNotes']);
    if (callingNotes.isNotEmpty) {
      parts.add(callingNotes.join('\n'));
    }

    final otherNames = _asStringList(dance['OtherNames']);
    if (otherNames.isNotEmpty) {
      parts.add('Other names: ${otherNames.join(', ')}');
    }

    final music = _asStringList(dance['Music']);
    if (music.isNotEmpty) {
      parts.add('Music: ${music.join(', ')}');
    }

    final appearances = _formatAppearances(dance['Appearances']);
    if (appearances.isNotEmpty) {
      parts.add('Appears in: $appearances');
    }

    parts.add('Imported from The Caller\'s Box.');
    return parts.join('\n\n');
  }

  String _formatAppearances(Object? raw) {
    if (raw is! List) return '';
    final entries = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final source = _asString(item['source'])?.trim();
      if (source == null || source.isEmpty) continue;
      final page = _asString(item['p'])?.trim();
      entries.add(
        page != null && page.isNotEmpty ? '$source (p. $page)' : source,
      );
    }
    return entries.join('; ');
  }

  // --- Top-level shape helpers ----------------------------------------------

  /// Normalizes the decoded payload to a flat list of dance elements, or `null`
  /// when the root is not a recognizable Caller's Box shape.
  static List<Object?>? _extractDanceElements(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final dances = decoded['dances'];
      if (dances is List) return dances;
      final records = decoded['records'];
      if (records is List) return records;
      // A bare object is a single dance only when it looks like a TCB dance.
      if (_looksLikeTcbDance(decoded)) return [decoded];
      return null;
    }
    return null;
  }

  static bool _looksLikeTcbDance(Object? element) {
    if (element is! Map) return false;
    final id = _asString(element['ID'])?.trim();
    final name = _asString(element['Name'])?.trim();
    return (id != null && id.isNotEmpty) || (name != null && name.isNotEmpty);
  }

  static String? _externalIdOf(Object? element) {
    if (element is! Map) return null;
    final id = _asString(element['ID'])?.trim();
    if (id != null && id.isNotEmpty) return id;
    final name = _asString(element['Name'])?.trim();
    if (name != null && name.isNotEmpty) {
      return 'name:${name.toLowerCase()}';
    }
    return null;
  }

  static String? _nameOf(Object? element) {
    if (element is! Map) return null;
    return _asString(element['Name'])?.trim();
  }

  static String? _permissionOf(Object? element) {
    if (element is! Map) return null;
    return _asString(element['Permission'])?.trim();
  }

  static String _sourceVersionOf(Object? element) {
    if (element is Map) {
      final downloaded = _asString(element['download_date'])?.trim();
      if (downloaded != null && downloaded.isNotEmpty) return downloaded;
    }
    return 'thecallersbox-json';
  }

  static String? _asString(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final item in value) {
      final s = _asString(item)?.trim();
      if (s != null && s.isNotEmpty) out.add(s);
    }
    return out;
  }

  static final RegExp _beatsPrefix = RegExp(
    r'^\s*\((\d+)\)\s*(.*)$',
    dotAll: true,
  );
  static final RegExp _gypsyTerm = RegExp(r'\bgypsy\b', caseSensitive: false);
  static final RegExp _gypsiesTerm = RegExp(
    r'\bgypsies\b',
    caseSensitive: false,
  );

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
}
