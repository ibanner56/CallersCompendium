import 'dart:convert';

import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../util/text_sanitizer.dart';
import 'import_error.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// A [SourceAdapter] that imports dances from **ContraDB** JSON
/// (`docs/design/imports.md` §"ContraDB (6.4)"; model surveyed in
/// `docs/research/contradb.md`). ContraDB is the strongest structured prior art
/// for figures + dialect, so its `figures_json` move/parameter model maps
/// move-for-move onto our taxonomy via a **positional→named** parameter
/// conversion table per move, plus term migrations (gyre → `shoulder_round`)
/// and aliases (see saw, swat the flea, meltdown swing).
///
/// **No real ContraDB export exists** — the site is grey-code with no committed
/// sample, and the primary path is user-supplied dumps rather than a live API.
/// The input shape and the per-move positional parameter orders below are
/// therefore *assumed* from the documented `defineFigure(name, params[])` model
/// and are validated against **synthetic** fixtures. When a real dump becomes
/// available this table should be revisited (the orders are the only guesswork;
/// the vocabulary mapping is factual).
///
/// ## Assumed input shape (tolerant)
/// [ImportRequest.payload] carries inline JSON text that is **one of**:
/// - a single dance object,
/// - an array of dance objects, or
/// - an object with a `dances` (or `records`) array.
///
/// Each dance object: `{id?, title, choreographer|choreographer_name?,
/// start_type?, hook?, preamble?, notes?, figures_json[], publish?}`. Each
/// `figures_json` element: `{move, parameter_values[] (positional), note?,
/// progression?, custom_figure?, beats?}`.
///
/// ## Contract
/// - [discover] decodes the payload once and emits one [DiscoveredRecord] per
///   dance (`externalId` = ContraDB `id` when present, else a stable id derived
///   from the title; `label` = title). A payload that is not decodable JSON, or
///   whose root is neither an object nor an array, throws a discover
///   [ImportError] — there is nothing to import.
/// - [fetch] re-serializes the single dance element into a self-contained
///   single-dance JSON [RawRecord] (source contradb, contentType
///   `application/json`) so [parse] works from the record alone.
/// - [parse] maps one dance JSON → [StructuredDraft]. It throws a parse
///   [ImportError] only when the payload is not a valid ContraDB dance record
///   at all (undecodable / not an object / no title). **It never fails on
///   figure content** (the parse-never-fails invariant): an unmapped move, a
///   `custom` move, or a parameter that will not convert falls back to
///   [customFigure] and/or the move's taxonomy default, recording a non-fatal
///   [ImportIssue].
///
/// ## Choreographer / metadata
/// The ContraDB choreographer name is carried on the draft's `authorNames`; the
/// import pipeline resolves it to a real [Choreographer] association
/// ([Dance.authorIds]) at commit (match-or-create). It is no longer folded into
/// [Dance.callingNotes]. ContraDB `hook` → [Dance.hook]; `preamble` +
/// `notes` → [Dance.callingNotes]. `start_type` free text is classified to a
/// [FormationShape] best-effort (its original text preserved in
/// [Formation.detail]); an unclassifiable string yields a warning and
/// [FormationShape.other].
class ContraDbAdapter implements SourceAdapter {
  ContraDbAdapter();

  @override
  ProvenanceSource get source => ProvenanceSource.contradb;

  /// Raw dance elements discovered from the most recent [discover] call, in
  /// order, so [fetch] can re-serialize a single dance by index. [parse] never
  /// consults this — it works from the [RawRecord] alone.
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
        message: 'No ContraDB payload provided to import.',
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
            'Payload is not a ContraDB export: expected a dance object, an '
            'array of dances, or an object with a "dances"/"records" array.',
      );
    }

    _records.addAll(elements);
    return [
      for (var i = 0; i < elements.length; i++)
        DiscoveredRecord(
          source: source,
          externalId: _externalIdOf(elements[i]),
          label: _titleOf(elements[i]),
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
    return RawRecord(
      source: source,
      externalId: record.externalId,
      payload: jsonEncode(_records[index]),
      contentType: 'application/json',
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
        'Payload is not a ContraDB dance object.',
        externalId: raw.externalId,
      );
    }
    final dance = Map<String, Object?>.from(decoded);

    final title = _sanitizeLine(_asString(dance['title']));
    if (title == null || title.isEmpty) {
      throw parseError(
        source,
        'ContraDB dance record has no title.',
        externalId: raw.externalId,
      );
    }

    final issues = <ImportIssue>[];
    final figures = _parseFigures(dance['figures_json'], issues);
    final formation = _parseFormation(dance['start_type'], issues);
    final choreographer = _sanitizeLine(_choreographerName(dance));

    return StructuredDraft(
      dance: Dance(
        id: 'contradb-import',
        title: title,
        formation: formation,
        figures: figures,
        // `Dance.hook` is a one-line description, so sanitize single-line
        // (allowLineBreaks: false) — strips embedded tab/newline/CR too (#444).
        hook: sanitizeImportedText(
          _asString(dance['hook'])?.trim() ?? '',
          allowLineBreaks: false,
        ),
        callingNotes: _buildNotes(dance),
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

  List<Figure> _parseFigures(Object? figuresJson, List<ImportIssue> issues) {
    if (figuresJson == null) return const [];
    // ContraDB stores figures_json as an embedded JSON string in some dumps and
    // as an inline array in others — accept both.
    Object? decoded = figuresJson;
    if (decoded is String) {
      final trimmed = decoded.trim();
      if (trimmed.isEmpty) return const [];
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        issues.add(
          const ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: 'contradb_figures_unreadable',
            message:
                'figures_json was a string that is not valid JSON; '
                'no figures imported.',
          ),
        );
        return const [];
      }
    }
    if (decoded is! List) {
      issues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'contradb_figures_unreadable',
          message: 'figures_json is not an array; no figures imported.',
        ),
      );
      return const [];
    }

    final figures = <Figure>[];
    for (var i = 0; i < decoded.length; i++) {
      figures.add(_parseFigure(decoded[i], i, issues));
    }
    return figures;
  }

  Figure _parseFigure(Object? raw, int index, List<ImportIssue> issues) {
    if (raw is! Map) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'contradb_move_fallback',
          message: 'Figure $index is not an object; imported as custom.',
          figureIndex: index,
        ),
      );
      return customFigure(
        '(unreadable figure)',
        origin: CustomOrigin.importGap,
      );
    }
    final fig = Map<String, Object?>.from(raw);
    final moveName = _asString(fig['move'])?.trim() ?? '';
    final params = fig['parameter_values'];
    final paramList = params is List ? params : const <Object?>[];
    final note = _asString(fig['note'])?.trim();
    final progression = _asFlag(fig['progression']) ?? false;
    final explicitBeats = _asBeats(fig['beats']);

    // ContraDB `custom` move: free-text `custom_figure` + beats, mapped
    // directly to our custom figure (parse-never-fails). Provenance splits by
    // condition: an explicit `custom` move is source-authored intent
    // (userEntered), while a MISSING move is a genuine data gap (importGap).
    if (moveName == 'custom' || moveName.isEmpty) {
      final text = _asString(fig['custom_figure'])?.trim();
      final reconstructed = (text != null && text.isNotEmpty)
          ? text
          : _reconstructText(
              moveName.isEmpty ? 'figure' : moveName,
              paramList,
              note,
            );
      return customFigure(
        sanitizeImportedText(reconstructed),
        beats: explicitBeats ?? _trailingBeats(paramList) ?? 0,
        progression: progression,
        origin: moveName.isEmpty
            ? CustomOrigin.importGap
            : CustomOrigin.userEntered,
      );
    }

    final mapping = _moveMappings[_normalizeMove(moveName)];
    if (mapping == null) {
      // Unknown move: reconstruct readable text, never throw.
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'contradb_move_fallback',
          message:
              'Move "$moveName" has no taxonomy mapping; '
              'imported as custom.',
          figureIndex: index,
        ),
      );
      return customFigure(
        sanitizeImportedText(_reconstructText(moveName, paramList, note)),
        beats: explicitBeats ?? _trailingBeats(paramList) ?? 0,
        progression: progression,
        origin: CustomOrigin.importGap,
      );
    }

    return _buildMappedFigure(
      mapping,
      moveName: moveName,
      paramList: paramList,
      note: note,
      progression: progression,
      explicitBeats: explicitBeats,
      // ContraDB embeds a `custom_figure` sub-field on contra corners / turn
      // alone; carry it onto our matching `custom` text param.
      customFigureField: _sanitizeLine(_asString(fig['custom_figure'])),
      index: index,
      issues: issues,
    );
  }

  Figure _buildMappedFigure(
    _MoveMap mapping, {
    required String moveName,
    required List<Object?> paramList,
    required String? note,
    required bool progression,
    required int? explicitBeats,
    required String? customFigureField,
    required int index,
    required List<ImportIssue> issues,
  }) {
    final params = <String, Object?>{};
    final specs = mapping.positional;

    for (var p = 0; p < specs.length; p++) {
      final spec = specs[p];
      if (p >= paramList.length) continue; // too few → taxonomy default applies
      final raw = paramList[p];
      if (raw == null) continue;
      final converted = spec.convert(raw);
      if (converted == null) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'contradb_param_unmapped',
            message:
                'Move "$moveName" parameter "${spec.name}" value '
                '"$raw" did not convert; taxonomy default used.',
            figureIndex: index,
          ),
        );
        continue;
      }
      params[spec.name] = converted;
    }

    if (paramList.length > specs.length) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.info,
          code: 'contradb_param_unmapped',
          message:
              'Move "$moveName" had ${paramList.length} positional '
              'values but only ${specs.length} are mapped; extras ignored.',
          figureIndex: index,
        ),
      );
    }

    // Aliases / term migrations pin fixed params (e.g. see saw → left shoulder).
    params.addAll(mapping.pinned);

    // A `custom_figure` sub-field fills the `custom` text param when the
    // positional table declares one and it was not already set positionally.
    // Guard the cast so the adapter stays parse-never-fails even if a future
    // mapping ever populates `custom` with a non-String value.
    final existingCustom = params['custom'];
    if (customFigureField != null &&
        customFigureField.isNotEmpty &&
        mapping.positional.any((p) => p.name == 'custom') &&
        (existingCustom is! String || existingCustom.isEmpty)) {
      params['custom'] = customFigureField;
    }

    // An explicit figure-level beats overrides any positional value.
    if (explicitBeats != null) params['beats'] = explicitBeats;

    return Figure(
      move: mapping.move,
      params: params,
      note: (note != null && note.isNotEmpty) ? note : null,
      progression: progression,
    );
  }

  // --- Formation -------------------------------------------------------------

  Formation _parseFormation(Object? startType, List<ImportIssue> issues) {
    final text = _sanitizeLine(_asString(startType));
    if (text == null || text.isEmpty) {
      return const Formation(FormationShape.dupleImproper);
    }
    final lower = text.toLowerCase();
    final detail = text;

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
    } else if (lower.contains('sicilian')) {
      shape = FormationShape.sicilianCircle;
    } else if (lower.contains('scatter')) {
      shape = FormationShape.scatterMixer;
    } else if (lower.contains('circle')) {
      shape = FormationShape.circleMixer;
    } else if (lower.contains('longways')) {
      shape = FormationShape.longways;
    }

    if (shape == null) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'contradb_formation_unclassified',
          message:
              'start_type "$text" did not classify to a known '
              'formation; kept as detail on "other".',
        ),
      );
      return Formation(FormationShape.other, detail: detail);
    }
    return Formation(shape, detail: detail);
  }

  // --- Notes -----------------------------------------------------------------

  String _buildNotes(Map<String, Object?> dance) {
    final parts = <String>[];
    // The choreographer name is resolved to a Choreographer association by the
    // import pipeline (Dance.authorIds) via the draft's authorNames, so it is
    // no longer folded into the notes.
    final preamble = _asString(dance['preamble'])?.trim();
    if (preamble != null && preamble.isNotEmpty) {
      parts.add('Preamble: $preamble');
    }
    final notes = _asString(dance['notes'])?.trim();
    if (notes != null && notes.isNotEmpty) {
      parts.add(notes);
    }
    // Multi-line sanitize: strip control/bidi/format spoofing characters from
    // the assembled free-text notes while keeping legitimate line breaks
    // (issue #444).
    return sanitizeImportedText(parts.join('\n\n')).trim();
  }

  String? _choreographerName(Map<String, Object?> dance) {
    final c = dance['choreographer'];
    if (c is String) return c.trim();
    if (c is Map) {
      final name = _asString(c['name']);
      if (name != null) return name.trim();
    }
    return _asString(dance['choreographer_name'])?.trim();
  }

  // --- Top-level shape helpers ----------------------------------------------

  /// Normalizes the decoded payload to a flat list of dance elements, or
  /// `null` when the root is not a recognizable ContraDB shape.
  static List<Object?>? _extractDanceElements(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final dances = decoded['dances'];
      if (dances is List) return dances;
      final records = decoded['records'];
      if (records is List) return records;
      // A bare object is treated as a single dance (tolerant).
      return [decoded];
    }
    return null;
  }

  static String? _externalIdOf(Object? element) {
    if (element is! Map) return null;
    final id = element['id'];
    if (id != null) return id.toString();
    final title = _sanitizeLine(_asString(element['title']));
    if (title != null && title.isNotEmpty) {
      return 'title:${title.toLowerCase()}';
    }
    return null;
  }

  static String? _titleOf(Object? element) {
    if (element is! Map) return null;
    return _sanitizeLine(_asString(element['title']));
  }

  static String _reconstructText(
    String move,
    List<Object?> paramValues,
    String? note,
  ) {
    final parts = <String>[move];
    for (final v in paramValues) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) parts.add(s);
    }
    if (note != null && note.isNotEmpty) parts.add('($note)');
    return parts.join(' ');
  }

  /// The last positional value that looks like a beat count, if any.
  static int? _trailingBeats(List<Object?> paramValues) {
    for (final v in paramValues.reversed) {
      final b = _asBeats(v);
      if (b != null) return b;
    }
    return null;
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
}

// --- Value converters --------------------------------------------------------

typedef _Conv = Object? Function(Object? raw);

/// One positional parameter in a ContraDB move's `parameter_values`: our
/// named [name] and a [convert] that maps the ContraDB value into our
/// vocabulary (returning `null` when it cannot convert cleanly).
class _PosParam {
  const _PosParam(this.name, this.convert);
  final String name;
  final _Conv convert;
}

/// A ContraDB move's mapping onto our taxonomy: the target [move] id, the
/// ordered [positional] parameter conversion table, and any [pinned] params
/// (aliases / term migrations, e.g. see saw → do si do left shoulder).
class _MoveMap {
  const _MoveMap(this.move, this.positional, {this.pinned = const {}});
  final String move;
  final List<_PosParam> positional;
  final Map<String, Object?> pinned;
}

String _normalizeMove(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'[\s_&-]+'), ' ');

String? _asString(Object? v) => v is String ? v : (v == null ? null : '$v');

/// Sanitizes a single-line imported string (title, author, formation detail),
/// stripping control, bidi-override and invisible/format characters plus any
/// embedded tab/newline/CR (issue #444). The title also feeds external-id
/// derivation (`title:<lowercased title>`), so removing line breaks keeps those
/// ids stable. Returns null for null/blank/all-stripped input.
String? _sanitizeLine(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final clean = sanitizeImportedText(trimmed, allowLineBreaks: false).trim();
  return clean.isEmpty ? null : clean;
}

bool? _asFlag(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == 'yes' || s == '1') return true;
    if (s == 'false' || s == 'no' || s == '0') return false;
  }
  return null;
}

int? _asBeats(Object? v) {
  final n = _asNum(v);
  if (n == null) return null;
  final b = n.round();
  if (b < 0 || b > 64) return null;
  return b;
}

num? _asNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

/// ContraDB dancer-set vocabulary → our canonical tokens. Roles migrate from
/// ContraDB gentlespoons/ladles to our role1/role2 (`docs/research/contradb.md`).
const Map<String, String> _dancerVocab = {
  'everyone': 'everyone',
  'all': 'everyone',
  'gentlespoons': 'role1s',
  'gentlespoon': 'role1s',
  'gents': 'role1s',
  'larks': 'role1s',
  'ladles': 'role2s',
  'ladle': 'role2s',
  'ravens': 'role2s',
  'robins': 'role2s',
  'role1s': 'role1s',
  'role2s': 'role2s',
  'ones': 'ones',
  'twos': 'twos',
  'partners': 'partners',
  'partner': 'partners',
  'neighbors': 'neighbors',
  'neighbor': 'neighbors',
  'same roles': 'sameRoles',
  'first corners': 'firstCorners',
  'second corners': 'secondCorners',
  'shadows': 'shadows',
  'second shadows': 'secondShadows',
  'previous neighbors': 'prevNeighbors',
  'next neighbors': 'nextNeighbors',
  'third neighbors': 'thirdNeighbors',
  'fourth neighbors': 'fourthNeighbors',
  'centers': 'centers',
  'first gentlespoon': 'onesRole1',
  'first ladle': 'onesRole2',
  'second gentlespoon': 'twosRole1',
  'second ladle': 'twosRole2',
};

Object? _dancers(Object? raw) {
  final s = _asString(raw);
  if (s == null) return null;
  return _dancerVocab[s.trim().toLowerCase()];
}

Object? _hand(Object? raw) {
  final s = _asString(raw)?.trim().toLowerCase();
  if (s == 'right' || s == 'left') return s;
  return null;
}

Object? _shoulder(Object? raw) => _hand(raw);

Object? _spin(Object? raw) {
  final s = _asString(raw);
  if (s == null) return null;
  final n = _stripSeparators(s);
  if (n == 'clockwise' || n == 'cw') return 'clockwise';
  if (n == 'counterclockwise' || n == 'ccw') return 'counterclockwise';
  return null;
}

/// ContraDB rotations are stored in degrees (90–900). Convert to our turns
/// (0.25–2.5), snapped to a quarter turn. Values already in the turn range
/// (≤2.5) are treated as turns.
Object? _turns(Object? raw) {
  final n = _asNum(raw);
  if (n == null) return null;
  final turns = n > 2.5 ? n / 360.0 : n.toDouble();
  final snapped = (turns * 4).round() / 4;
  if (snapped < 0.25 || snapped > 2.5) return null;
  return snapped;
}

/// ContraDB "places" travel. Large values (>10) are read as degrees
/// (one place ≈ 90°); otherwise taken as a place count. Clamped to 1..10.
Object? _places(Object? raw) {
  final n = _asNum(raw);
  if (n == null) return null;
  final places = n > 10 ? (n / 90).round() : n.round();
  if (places < 1) return 1;
  if (places > 10) return 10;
  return places;
}

Object? _fraction(Object? raw) {
  final n = _asNum(raw);
  if (n != null) {
    if (n == 0.25) return 'quarter';
    if (n == 0.5) return 'half';
    if (n == 0.75) return 'threeQuarter';
    if (n == 1 || n == 1.0) return 'full';
    return 'other';
  }
  final s = _asString(raw)?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  switch (s) {
    case 'quarter':
      return 'quarter';
    case 'half':
      return 'half';
    case 'threequarter':
    case 'threequarters':
      return 'threeQuarter';
    case 'full':
    case 'whole':
      return 'full';
    case 'other':
      return 'other';
  }
  return null;
}

Object? _direction(Object? raw) {
  final s = _asString(raw)?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  switch (s) {
    case 'along':
      return 'along';
    case 'across':
      return 'across';
    case 'rightdiagonal':
      return 'rightDiagonal';
    case 'leftdiagonal':
      return 'leftDiagonal';
    case 'in':
      return 'in';
    case 'out':
      return 'out';
    case 'up':
      return 'up';
    case 'down':
      return 'down';
  }
  return null;
}

Object? Function(Object?) _flag() =>
    (raw) => _asFlag(raw);

Object? Function(Object?) _beatsConv() =>
    (raw) => _asBeats(raw);

/// A choice converter over a fixed allowed set, with optional ContraDB→ours
/// [aliases]. Matching is case- and separator-insensitive (spaces, `_`, and
/// `-` are all ignored), so `forward_then_backward` and `forward then
/// backward` both match.
_Conv _choice(Set<String> allowed, {Map<String, String> aliases = const {}}) {
  final norm = <String, String>{
    for (final a in allowed) _stripSeparators(a): a,
    for (final e in aliases.entries) _stripSeparators(e.key): e.value,
  };
  return (raw) {
    final s = _asString(raw);
    if (s == null) return null;
    return norm[_stripSeparators(s)];
  };
}

/// Lowercases and removes separators (whitespace, `_`, `-`) for
/// separator-insensitive vocabulary matching.
String _stripSeparators(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

/// The positional→named conversion table per ContraDB move (keys normalized by
/// [_normalizeMove]). Positional order is the **assumed** `defineFigure` order;
/// `beats` is taken as the trailing positional value. Aliases / term migrations
/// pin fixed params. See the class doc-comment for the no-real-fixture caveat.
final Map<String, _MoveMap> _moveMappings = {
  'swing': _MoveMap('swing', [
    _PosParam('who', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  'meltdown swing': _MoveMap(
    'swing',
    [_PosParam('who', _dancers), _PosParam('beats', _beatsConv())],
    pinned: {'prefix': 'meltdown'},
  ),
  'balance': _MoveMap('balance', [
    _PosParam('who', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  'balance the ring': _MoveMap('balance_the_ring', [
    _PosParam('beats', _beatsConv()),
  ]),
  'allemande': _MoveMap('allemande', [
    _PosParam('who', _dancers),
    _PosParam('hand', _hand),
    _PosParam('turn', _turns),
    _PosParam('beats', _beatsConv()),
  ]),
  'allemande orbit': _MoveMap('allemande_orbit', [
    _PosParam('who', _dancers),
    _PosParam('hand', _hand),
    _PosParam('inner', _turns),
    _PosParam('outer', _turns),
    _PosParam('beats', _beatsConv()),
  ]),
  'do si do': _MoveMap('do_si_do', [
    _PosParam('who', _dancers),
    _PosParam('turn', _turns),
    _PosParam('beats', _beatsConv()),
  ]),
  'see saw': _MoveMap(
    'do_si_do',
    [
      _PosParam('who', _dancers),
      _PosParam('turn', _turns),
      _PosParam('beats', _beatsConv()),
    ],
    pinned: {'shoulder': 'left'},
  ),
  'box the gnat': _MoveMap('box_the_gnat', [
    _PosParam('who', _dancers),
    _PosParam('hand', _hand),
    _PosParam('beats', _beatsConv()),
  ]),
  'swat the flea': _MoveMap(
    'box_the_gnat',
    [_PosParam('who', _dancers), _PosParam('beats', _beatsConv())],
    pinned: {'hand': 'left'},
  ),
  // Term migration: gyre → shoulder_round (community/TCB usage post-2022).
  'gyre': _MoveMap('shoulder_round', [
    _PosParam('who', _dancers),
    _PosParam('shoulder', _shoulder),
    _PosParam('turn', _turns),
    _PosParam('beats', _beatsConv()),
  ]),
  'gypsy': _MoveMap('shoulder_round', [
    _PosParam('who', _dancers),
    _PosParam('shoulder', _shoulder),
    _PosParam('turn', _turns),
    _PosParam('beats', _beatsConv()),
  ]),
  'petronella': _MoveMap('petronella', [
    _PosParam('balance', _flag()),
    _PosParam('beats', _beatsConv()),
  ]),
  'long lines': _MoveMap('long_lines', [
    _PosParam('goBack', _flag()),
    _PosParam('beats', _beatsConv()),
  ]),
  'pass through': _MoveMap('pass_through', [
    _PosParam('dir', _direction),
    _PosParam('shoulder', _shoulder),
    _PosParam('beats', _beatsConv()),
  ]),
  'pass by': _MoveMap('pass_by', [
    _PosParam('who', _dancers),
    _PosParam('shoulder', _shoulder),
    _PosParam('beats', _beatsConv()),
  ]),
  'right left through': _MoveMap('right_left_through', [
    _PosParam('dir', _direction),
    _PosParam('beats', _beatsConv()),
  ]),
  'chain': _MoveMap('chain', [
    _PosParam('who', _dancers),
    _PosParam('dir', _direction),
    _PosParam('beats', _beatsConv()),
  ]),
  'promenade': _MoveMap('promenade', [
    _PosParam('who', _dancers),
    _PosParam('dir', _direction),
    _PosParam('beats', _beatsConv()),
  ]),
  'star promenade': _MoveMap('star_promenade', [
    _PosParam('who', _dancers),
    _PosParam('hand', _hand),
    _PosParam('turn', _turns),
    _PosParam('beats', _beatsConv()),
  ]),
  'roll away': _MoveMap('roll_away', [
    _PosParam('who', _dancers),
    _PosParam('whom', _dancers),
    _PosParam('halfSashay', _flag()),
    _PosParam('beats', _beatsConv()),
  ]),
  'butterfly whirl': _MoveMap('butterfly_whirl', [
    _PosParam('beats', _beatsConv()),
  ]),
  'arch and dive': _MoveMap('arch_and_dive', [
    _PosParam('who', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  'california twirl': _MoveMap('california_twirl', [
    _PosParam('who', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  'stand still': _MoveMap('stand_still', [_PosParam('beats', _beatsConv())]),
  'slide along set': _MoveMap('slide_along_set', [
    _PosParam('slide', _choice({'left', 'right'})),
    _PosParam('beats', _beatsConv()),
  ]),
  'mad robin': _MoveMap('mad_robin', [
    _PosParam('who', _dancers),
    _PosParam('turn', _turns),
    _PosParam('beats', _beatsConv()),
  ]),
  'revolving door': _MoveMap('revolving_door', [
    _PosParam('who', _dancers),
    _PosParam('hand', _hand),
    _PosParam('whom', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  'gate': _MoveMap('gate', [
    _PosParam('who', _dancers),
    _PosParam('whom', _dancers),
    _PosParam('face', _choice({'up', 'down', 'in', 'out'})),
    _PosParam('beats', _beatsConv()),
  ]),
  'give and take': _MoveMap('give_and_take', [
    _PosParam('who', _dancers),
    _PosParam('whom', _dancers),
    _PosParam('give', _flag()),
    _PosParam('beats', _beatsConv()),
  ]),
  'pull by': _MoveMap('pull_by_dancers', [
    _PosParam('who', _dancers),
    _PosParam('balance', _flag()),
    _PosParam('hand', _hand),
    _PosParam('beats', _beatsConv()),
  ]),
  'cross trails': _MoveMap('cross_trails', [
    _PosParam('who', _dancers),
    _PosParam('dir', _direction),
    _PosParam('who2', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  'down the hall': _MoveMap('down_the_hall', [
    _PosParam('who', _dancers),
    _PosParam(
      'facing',
      _choice(
        {'forward', 'forwardThenBackward', 'backward'},
        aliases: {'forwardthenbackward': 'forwardThenBackward'},
      ),
    ),
    _PosParam('ender', _choice(_downTheHallEnders)),
    _PosParam('beats', _beatsConv()),
  ]),
  'up the hall': _MoveMap('up_the_hall', [
    _PosParam('who', _dancers),
    _PosParam(
      'facing',
      _choice(
        {'forward', 'forwardThenBackward', 'backward'},
        aliases: {'forwardthenbackward': 'forwardThenBackward'},
      ),
    ),
    _PosParam('ender', _choice(_downTheHallEnders)),
    _PosParam('beats', _beatsConv()),
  ]),
  'zig zag': _MoveMap('zig_zag', [
    _PosParam('who', _dancers),
    _PosParam('turn', _choice({'left', 'right'})),
    _PosParam('ender', _choice({'none', 'ring', 'allemande'})),
    _PosParam('beats', _beatsConv()),
  ]),
  'slice': _MoveMap('slice', [
    _PosParam('slice', _choice({'left', 'right'})),
    _PosParam('by', _choice({'couple', 'dancer'})),
    _PosParam('return', _choice({'straight', 'diagonal', 'none'})),
    _PosParam('beats', _beatsConv()),
  ]),
  'contra corners': _MoveMap('contra_corners', [
    _PosParam('who', _dancers),
    _PosParam('custom', (raw) => _asString(raw)),
    _PosParam('beats', _beatsConv()),
  ]),
  'turn alone': _MoveMap('turn_alone', [
    _PosParam('who', _dancers),
    _PosParam('custom', (raw) => _asString(raw)),
    _PosParam('beats', _beatsConv()),
  ]),
  'figure 8': _MoveMap('figure_8', [
    _PosParam('who', _dancers),
    _PosParam('half', _fraction),
    _PosParam('beats', _beatsConv()),
  ]),
  'rory o more': _MoveMap('rory_o_more', [
    _PosParam('who', _dancers),
    _PosParam('balance', _flag()),
    _PosParam('slide', _choice({'left', 'right'})),
    _PosParam('beats', _beatsConv()),
  ]),
  'poussette': _MoveMap('poussette', [
    _PosParam('who', _dancers),
    _PosParam('whom', _dancers),
    _PosParam('half', _fraction),
    _PosParam('turn', _spin),
    _PosParam('beats', _beatsConv()),
  ]),
  'circle': _MoveMap('circle', [
    _PosParam('turn', _choice({'left', 'right'})),
    _PosParam('places', _places),
    _PosParam('beats', _beatsConv()),
  ]),
  'star': _MoveMap('star', [
    _PosParam('hand', _hand),
    _PosParam('places', _places),
    _PosParam('beats', _beatsConv()),
  ]),
  'facing star': _MoveMap('facing_star', [
    _PosParam('who', _dancers),
    _PosParam('turn', _spin),
    _PosParam('places', _places),
    _PosParam('beats', _beatsConv()),
  ]),
  'square through': _MoveMap('square_through', [
    _PosParam('who', _dancers),
    _PosParam('who2', _dancers),
    _PosParam('places', _places),
    _PosParam('beats', _beatsConv()),
  ]),
  'hey': _MoveMap('hey', [
    _PosParam('pass1', _dancers),
    _PosParam('shoulder', _shoulder),
    _PosParam(
      'length',
      _choice(
        {'lessThanHalf', 'half', 'betweenHalfAndFull', 'full'},
        aliases: {
          'lessthanhalf': 'lessThanHalf',
          'betweenhalfandfull': 'betweenHalfAndFull',
        },
      ),
    ),
    _PosParam('dir', _direction),
    _PosParam('beats', _beatsConv()),
  ]),
  'dolphin hey': _MoveMap('dolphin_hey', [
    _PosParam('who', _dancers),
    _PosParam('shoulder', _shoulder),
    _PosParam('beats', _beatsConv()),
  ]),
  'form long waves': _MoveMap('form_long_waves', [
    _PosParam('who', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  'form a long wave': _MoveMap('form_a_long_wave', [
    _PosParam('who', _dancers),
    _PosParam('beats', _beatsConv()),
  ]),
  // Issue #290: `form_an_ocean_wave` was removed from the taxonomy (v14).
  // ContraDB's "form an ocean wave" defaults to pass_through=true, so map it to
  // `pass_the_ocean` (carry beats) rather than letting it degrade to an
  // unknown-move custom figure. (The legacy minimal mapping only ever carried
  // beats; retargeting the id keeps that behavior while pointing at a live move.)
  'form an ocean wave': _MoveMap('pass_the_ocean', [
    _PosParam('beats', _beatsConv()),
  ]),
};

const Set<String> _downTheHallEnders = {
  'none',
  'turnCouple',
  'turnAlone',
  'circle',
  'cozy',
  'cloverleaf',
  'threadNeedle',
  'rightHandHigh',
  'slidingDoors',
};
