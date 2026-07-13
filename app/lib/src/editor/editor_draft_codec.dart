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
const _kDraftVersion = 2;

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

/// Serialises [snapshot] to a JSON string suitable for storage in
/// [SettingsRepository].
///
/// Schema (v2):
/// ```jsonc
/// {
///   "v": 2,
///   "title": "...", "hook": "...", "notes": "...",
///   "phrase": "...", "formationDetail": "...",
///   "form": "contra", "formationShape": "dupleImproper",
///   "progression": "single", "status": "active",
///   "authorIds": ["..."], "tagIds": ["..."], "tunes": ["..."],
///   "links": [
///     {"id":"...", "kind":"source", "url":"...", "label":"..."},
///     {"id":"...", "kind":"relatedDance", "targetDanceId":"...", "label":"..."}
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
/// Throws [FormatException] when the value is not a valid v2 draft.
/// Unknown top-level keys are silently ignored (forward-compat).
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
  if (v is! int || v != _kDraftVersion) {
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
    authorIds: _strList(json, 'authorIds'),
    tagIds: _strList(json, 'tagIds'),
    tunes: _strList(json, 'tunes'),
    links: _parseLinks(json['links']),
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
