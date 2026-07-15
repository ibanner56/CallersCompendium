import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

import 'editor_snapshot.dart';

/// Draft schema version. Increment if the JSON shape changes in a
/// backward-incompatible way; [decodeDraft] checks this and rejects
/// unrecognised future versions gracefully.
///
/// v1 → v2: `links` now supports relatedDance kind with `targetDanceId`;
/// the separate `preservedLinks` bucket is removed (all four LinkKinds live
/// in `links`).
///
/// v2 → v3: adds `level` (nullable [DanceLevel] name, omitted when unspecified)
/// and `mixedLevel` (bool). Older drafts decode with `level:null` /
/// `mixedLevel:false`.
///
/// v3 → v4: adds `composedOn` / `revisedOn` (nullable canonical [PartialDate]
/// strings, omitted when unspecified). Older drafts decode with both `null`.
///
/// v4 → v5: adds `rating` (nullable `int` star rating on the closed `1..5`
/// scale, omitted when unrated). Older drafts decode with `rating:null`.
///
/// v5 → v6: adds `sourceCitations` (ordered list of `{sourceId, page?, number?}`
/// citing reusable published sources; omitted entirely when empty). Older
/// drafts (v ≤ 5) decode with `sourceCitations: const []`.
const _kDraftVersion = 6;

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

/// Serialises [snapshot] to a JSON string suitable for storage in
/// [SettingsRepository].
///
/// Schema (v6):
/// ```jsonc
/// {
///   "v": 6,
///   "title": "...", "hook": "...", "notes": "...",
///   "phrase": "...", "formationDetail": "...",
///   "form": "contra", "formationShape": "dupleImproper",
///   "progression": "single", "status": "active",
///   "level": "intermediate", "mixedLevel": false,
///   "rating": 4,
///   "composedOn": "1989", "revisedOn": "2004-03-15",
///   "authorIds": ["..."], "tagIds": ["..."], "tunes": ["..."],
///   "links": [
///     {"id":"...", "kind":"source", "url":"...", "label":"..."},
///     {"id":"...", "kind":"relatedDance", "targetDanceId":"...", "label":"..."}
///   ],
///   "sourceCitations": [
///     {"sourceId":"...", "page":"12-14", "number":"A1"}
///   ],
///   "customValues": {"fieldId": <value>},
///   "figureDrafts": [
///     {"id":"...", "move":"swing",
///      "params":{"who":"partners","beats":16},
///      "note":"", "progression":false, "sv":1}
///   ]
/// }
/// ```
/// `move` may be `null` for an incomplete draft row.
/// `label`, `url`, and `targetDanceId` may be omitted when empty/null.
/// `level`, `rating`, `composedOn`, and `revisedOn` are omitted when unset.
/// `sourceCitations` is omitted when empty; per-citation `page`/`number` are
/// omitted when null.
String encodeDraft(EditorSnapshot snapshot) {
  return jsonEncode({
    'v': _kDraftVersion,
    'title': snapshot.title,
    'hook': snapshot.hook,
    'notes': snapshot.notes,
    'phrase': snapshot.phrase,
    'formationDetail': snapshot.formationDetail,
    'form': snapshot.form.name,
    'formationShape': snapshot.formationShape.name,
    'progression': snapshot.progression.name,
    'status': snapshot.status.name,
    if (snapshot.level != null) 'level': snapshot.level!.name,
    'mixedLevel': snapshot.mixedLevel,
    if (snapshot.rating != null) 'rating': snapshot.rating,
    if (snapshot.composedOn != null)
      'composedOn': snapshot.composedOn!.serialize(),
    if (snapshot.revisedOn != null)
      'revisedOn': snapshot.revisedOn!.serialize(),
    'authorIds': snapshot.authorIds,
    'tagIds': snapshot.tagIds,
    'tunes': snapshot.tunes,
    'links': [
      for (final l in snapshot.links)
        {
          'id': l.id,
          'kind': l.kind.name,
          if (l.url.isNotEmpty) 'url': l.url,
          if (l.label.isNotEmpty) 'label': l.label,
          if (l.targetDanceId != null) 'targetDanceId': l.targetDanceId,
        },
    ],
    if (snapshot.sourceCitations.isNotEmpty)
      'sourceCitations': [
        for (final c in snapshot.sourceCitations)
          {
            'sourceId': c.sourceId,
            if (c.page != null) 'page': c.page,
            if (c.number != null) 'number': c.number,
          },
      ],
    'customValues': snapshot.customValues,
    'figureDrafts': [
      for (final d in snapshot.figureDrafts)
        {
          'id': d.id,
          'move': d.move,
          'params': d.params,
          'note': d.note,
          'progression': d.progression,
          'sv': d.schemaVersion,
        },
    ],
  });
}

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

/// Deserialises a draft JSON value (as returned by [SettingsRepository.get])
/// back into an [EditorSnapshot].
///
/// Accepts **v1 and v2** drafts (forward-compatible read):
/// - v1 has URL-kind links only (no `targetDanceId`). Since v1 couldn't create
///   relatedDance links, missing `targetDanceId` fields decode as `null` —
///   a v1 draft loads intact as a valid draft with only URL-kind links.
/// - v2 added `targetDanceId` to links and removed the `preservedLinks` bucket.
///
/// Throws [FormatException] for unknown future versions (`v > _kDraftVersion`)
/// or for structurally invalid content. Unknown top-level keys are silently
/// ignored (forward-compat).
EditorSnapshot decodeDraft(Object? value) {
  final Map<String, Object?> json;
  if (value is String) {
    // SettingsRepository round-trips through jsonDecode, so we expect a Map.
    // Guard for the case where the stored value is the raw JSON string.
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('draft root must be a JSON object');
    }
    json = decoded.cast();
  } else if (value is Map) {
    json = value.cast();
  } else {
    throw FormatException('unexpected draft type: ${value.runtimeType}');
  }

  final v = json['v'];
  // Accept any version in the range [1, _kDraftVersion]. Versions below 1
  // or above the current version are unknown and must be rejected so we never
  // silently mangle data from a future schema we don't understand.
  if (v is! int || v < 1 || v > _kDraftVersion) {
    throw FormatException('unsupported draft schema version: $v');
  }

  return EditorSnapshot(
    title: _str(json, 'title'),
    hook: _str(json, 'hook'),
    notes: _str(json, 'notes'),
    phrase: _str(json, 'phrase'),
    formationDetail: _str(json, 'formationDetail'),
    form: _parseEnum(DanceForm.values, _str(json, 'form')),
    formationShape: _parseEnum(
      FormationShape.values,
      _str(json, 'formationShape'),
    ),
    progression: _parseEnum(Progression.values, _str(json, 'progression')),
    status: _parseEnum(DanceStatus.values, _str(json, 'status')),
    level: _parseNullableEnum(DanceLevel.values, json['level']),
    mixedLevel: _bool(json, 'mixedLevel'),
    rating: _parseNullableRating(json['rating']),
    composedOn: _parseNullablePartialDate(json['composedOn']),
    revisedOn: _parseNullablePartialDate(json['revisedOn']),
    authorIds: _strList(json, 'authorIds'),
    tagIds: _strList(json, 'tagIds'),
    tunes: _strList(json, 'tunes'),
    links: _parseLinks(json['links']),
    sourceCitations: _parseSourceCitations(json['sourceCitations']),
    customValues: _parseCustomValues(json['customValues']),
    figureDrafts: _parseFigureDrafts(json['figureDrafts']),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _str(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return '';
  if (v is! String) throw FormatException('draft.$key must be a string: $v');
  return v;
}

List<String> _strList(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return const [];
  if (v is! List) throw FormatException('draft.$key must be an array: $v');
  return [
    for (final e in v)
      if (e is String)
        e
      else
        throw FormatException('draft.$key entries must be strings: $e'),
  ];
}

T _parseEnum<T extends Enum>(List<T> values, String name) {
  return values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw FormatException(
      'unknown enum value "$name" for ${values.first.runtimeType}',
    ),
  );
}

/// Parses an optional enum name: `null`/absent → `null`; a string is resolved
/// against [values] (unknown names throw). Used for the nullable `level` field.
T? _parseNullableEnum<T extends Enum>(List<T> values, Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw FormatException('draft enum value must be a string: $raw');
  }
  return _parseEnum(values, raw);
}

/// Parses an optional canonical [PartialDate] string: `null`/absent → `null`;
/// a string is parsed (an unparseable/invalid value throws). Used for the
/// nullable `composedOn` / `revisedOn` fields.
PartialDate? _parseNullablePartialDate(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw FormatException('draft date value must be a string: $raw');
  }
  return PartialDate.parse(raw);
}

/// Parses an optional star rating: `null`/absent → `null`; otherwise an `int`
/// on the closed `1..5` scale (out-of-range or non-int values throw). Used for
/// the nullable `rating` field.
int? _parseNullableRating(Object? raw) {
  if (raw == null) return null;
  if (raw is! int) {
    throw FormatException('draft rating value must be an int: $raw');
  }
  if (raw < 1 || raw > 5) {
    throw FormatException('draft rating must be null or 1..5: $raw');
  }
  return raw;
}

bool _bool(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return false;
  if (v is! bool) throw FormatException('draft.$key must be a bool: $v');
  return v;
}

List<LinkSnapshot> _parseLinks(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) throw const FormatException('draft.links must be an array');
  return [for (final e in raw) _parseLinkSnapshot(e)];
}

LinkSnapshot _parseLinkSnapshot(Object? e) {
  if (e is! Map) throw const FormatException('link entry must be an object');
  final m = e.cast<String, Object?>();
  return LinkSnapshot(
    id: _str(m, 'id'),
    kind: _parseEnum(LinkKind.values, _str(m, 'kind')),
    url: _str(m, 'url'),
    label: _str(m, 'label'),
    targetDanceId: m['targetDanceId'] is String
        ? m['targetDanceId'] as String
        : null,
  );
}

SourceCitation _parseSourceCitation(Object? e) {
  if (e is! Map) {
    throw const FormatException('sourceCitation entry must be an object');
  }
  final m = e.cast<String, Object?>();
  final sourceId = _str(m, 'sourceId');
  if (sourceId.isEmpty) {
    throw const FormatException('sourceCitation.sourceId is required');
  }
  final page = m['page'];
  if (page != null && page is! String) {
    throw FormatException('sourceCitation.page must be a string: $page');
  }
  final number = m['number'];
  if (number != null && number is! String) {
    throw FormatException('sourceCitation.number must be a string: $number');
  }
  return SourceCitation(
    sourceId: sourceId,
    page: page as String?,
    number: number as String?,
  );
}

List<SourceCitation> _parseSourceCitations(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('draft.sourceCitations must be an array');
  }
  return [for (final e in raw) _parseSourceCitation(e)];
}

Map<String, Object?> _parseCustomValues(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw const FormatException('draft.customValues must be an object');
  }
  return Map<String, Object?>.unmodifiable(raw.cast());
}

List<FigureDraftSnapshot> _parseFigureDrafts(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('draft.figureDrafts must be an array');
  }
  return [for (final e in raw) _parseFigureDraftSnapshot(e)];
}

FigureDraftSnapshot _parseFigureDraftSnapshot(Object? e) {
  if (e is! Map) {
    throw const FormatException('figureDraft entry must be an object');
  }
  final m = e.cast<String, Object?>();
  final id = _str(m, 'id');
  if (id.isEmpty) throw const FormatException('figureDraft.id is required');

  final move = m['move'] as String?;
  final params = m['params'];
  final parsedParams = <String, Object?>{};
  if (params is Map) {
    for (final entry in params.entries) {
      parsedParams[entry.key.toString()] = entry.value;
    }
  }
  final note = _str(m, 'note');
  final progression = m['progression'];
  if (progression is! bool) {
    throw FormatException(
      'figureDraft.progression must be a bool: $progression',
    );
  }
  final sv = m['sv'] ?? figureSchemaVersion;
  if (sv is! int) {
    throw FormatException('figureDraft.sv must be an int: $sv');
  }

  return FigureDraftSnapshot(
    id: id,
    move: move,
    params: Map.unmodifiable(parsedParams),
    note: note,
    progression: progression,
    schemaVersion: sv,
  );
}
