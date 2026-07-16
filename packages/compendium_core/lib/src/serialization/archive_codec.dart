import 'dart:convert';

import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/dance_link.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../model/partial_date.dart';
import '../model/program.dart';
import '../model/provenance.dart';
import '../model/published_source.dart';
import '../model/source_citation.dart';
import '../model/tag.dart';
import 'compendium_archive.dart';
import 'figure_codec.dart';

/// Canonical JSON (de)serialization for a [CompendiumArchive] — the versioned
/// backup/exchange format (`docs/design/imports.md` §"Generic JSON (6.6)").
///
/// [encodeArchive] produces a deterministic string: entities are ordered by id
/// and keys are emitted in a stable order, so the design's round-trip identity
/// property holds — `encodeArchive(decodeArchive(s).archive) == s` for any
/// string `s` this encoder produced.
///
/// [decodeArchive] is forward-compatible: unknown keys are ignored (files
/// written by newer app versions still load), a missing `schemaVersion` is
/// treated as the current version, and a newer `schemaVersion` is read on a
/// best-effort basis with a warning rather than an error. Recoverable problems
/// never throw: a malformed entity is skipped and recorded as an
/// [ArchiveError] while the rest of the archive still loads.

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

/// Serializes [archive] to a canonical JSON string.
String encodeArchive(CompendiumArchive archive) =>
    jsonEncode(archiveToJson(archive));

/// The canonical JSON object for [archive] (entities sorted by id).
Map<String, Object?> archiveToJson(CompendiumArchive archive) => {
  'schemaVersion': archive.schemaVersion,
  'exportedAt': _iso(archive.exportedAt),
  'choreographers': [
    for (final c in _sortedById(archive.choreographers, (c) => c.id))
      _choreographerToJson(c),
  ],
  'publishedSources': [
    for (final s in _sortedById(archive.publishedSources, (s) => s.id))
      _publishedSourceToJson(s),
  ],
  'tags': [
    for (final t in _sortedById(archive.tags, (t) => t.id)) _tagToJson(t),
  ],
  'customFields': [
    for (final f in _sortedById(archive.customFields, (f) => f.id))
      _customFieldDefToJson(f),
  ],
  'dances': [
    for (final d in _sortedById(archive.dances, (d) => d.id)) _danceToJson(d),
  ],
  'programs': [
    for (final p in _sortedById(archive.programs, (p) => p.id))
      _programToJson(p),
  ],
};

List<T> _sortedById<T>(List<T> items, String Function(T) id) =>
    [...items]..sort((a, b) => id(a).compareTo(id(b)));

String _iso(DateTime dt) => dt.toUtc().toIso8601String();

Map<String, Object?> _choreographerToJson(Choreographer c) => {
  'id': c.id,
  'name': c.name,
  if (c.website != null) 'website': c.website,
  if (c.notes != null) 'notes': c.notes,
  if (c.email != null) 'email': c.email,
  if (c.location != null) 'location': c.location,
  'deceased': c.deceased,
};

Map<String, Object?> _publishedSourceToJson(PublishedSource s) => {
  'id': s.id,
  'title': s.title,
  if (s.author != null) 'author': s.author,
  if (s.year != null) 'year': s.year,
  if (s.url != null) 'url': s.url,
  if (s.notes != null) 'notes': s.notes,
};

Map<String, Object?> _tagToJson(Tag t) => {
  'id': t.id,
  'name': t.name,
  if (t.color != null) 'color': t.color,
};

Map<String, Object?> _customFieldDefToJson(CustomFieldDef f) => {
  'id': f.id,
  'key': f.key,
  'label': f.label,
  'type': f.type.name,
  if (f.choices != null) 'choices': f.choices,
  'showInList': f.showInList,
  'searchable': f.searchable,
};

Map<String, Object?> _danceToJson(Dance d) => {
  'id': d.id,
  'title': d.title,
  'authorIds': d.authorIds,
  'form': d.form.name,
  'formation': _formationToJson(d.formation),
  'progression': d.progression.name,
  'phraseStructure': d.phraseStructure.raw,
  'figures': [for (final f in d.figures) figureToJson(f)],
  'hook': d.hook,
  'callingNotes': d.callingNotes,
  'status': d.status.name,
  if (d.level != null) 'level': d.level!.name,
  'mixedLevel': d.mixedLevel,
  if (d.rating != null) 'rating': d.rating,
  'tunes': d.tunes,
  'customFields': [for (final v in d.customFields) _customFieldValueToJson(v)],
  'tagIds': d.tagIds,
  'links': [for (final l in d.links) _danceLinkToJson(l)],
  'sourceCitations': [
    for (final s in d.sourceCitations) _sourceCitationToJson(s),
  ],
  if (d.provenance != null) 'provenance': _provenanceToJson(d.provenance!),
  if (d.composedOn != null) 'composedOn': d.composedOn!.serialize(),
  if (d.revisedOn != null) 'revisedOn': d.revisedOn!.serialize(),
  'createdAt': _iso(d.createdAt),
  'updatedAt': _iso(d.updatedAt),
  if (d.deletedAt != null) 'deletedAt': _iso(d.deletedAt!),
};

Map<String, Object?> _formationToJson(Formation f) => {
  'shape': f.shape.name,
  if (f.detail != null) 'detail': f.detail,
};

Map<String, Object?> _customFieldValueToJson(CustomFieldValue v) => {
  'fieldId': v.fieldId,
  'value': v.value,
};

Map<String, Object?> _danceLinkToJson(DanceLink l) => {
  'id': l.id,
  'kind': l.kind.name,
  if (l.url != null) 'url': l.url,
  if (l.targetDanceId != null) 'targetDanceId': l.targetDanceId,
  if (l.label != null) 'label': l.label,
};

Map<String, Object?> _sourceCitationToJson(SourceCitation s) => {
  'sourceId': s.sourceId,
  if (s.page != null) 'page': s.page,
  if (s.number != null) 'number': s.number,
};

Map<String, Object?> _provenanceToJson(Provenance p) => {
  'source': p.source.name,
  if (p.externalId != null) 'externalId': p.externalId,
  'importedAt': _iso(p.importedAt),
  if (p.permission != null) 'permission': p.permission,
  if (p.license != null) 'license': p.license,
  if (p.rawPayload != null) 'rawPayload': p.rawPayload,
  if (p.sourceVersion != null) 'sourceVersion': p.sourceVersion,
};

Map<String, Object?> _programToJson(Program p) => {
  'id': p.id,
  'title': p.title,
  if (p.eventDate != null) 'eventDate': _iso(p.eventDate!),
  if (p.venue != null) 'venue': p.venue,
  if (p.band != null) 'band': p.band,
  if (p.caller != null) 'caller': p.caller,
  if (p.dancerLevel != null) 'dancerLevel': p.dancerLevel,
  'notes': p.notes,
  'status': p.status.name,
  'slots': [for (final s in p.slots) _programSlotToJson(s)],
  'createdAt': _iso(p.createdAt),
  'updatedAt': _iso(p.updatedAt),
  if (p.deletedAt != null) 'deletedAt': _iso(p.deletedAt!),
};

Map<String, Object?> _programSlotToJson(ProgramSlot s) => {
  'id': s.id,
  'position': s.position,
  if (s.danceId != null) 'danceId': s.danceId,
  if (s.text != null) 'text': s.text,
  'isAlt': s.isAlt,
  if (s.guestCaller != null) 'guestCaller': s.guestCaller,
  if (s.plannedMinutes != null) 'plannedMinutes': s.plannedMinutes,
  if (s.performedAt != null) 'performedAt': _iso(s.performedAt!),
};

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/// Decodes a canonical archive JSON string. Never throws for recoverable
/// problems: an unreadable root or malformed entity is reported in the result's
/// [ArchiveReadResult.errors] and the rest still loads.
ArchiveReadResult decodeArchive(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException catch (e) {
    return ArchiveReadResult(
      archive: CompendiumArchive(exportedAt: _epoch),
      errors: [
        ArchiveError(
          kind: ArchiveErrorKind.read,
          entityType: 'archive',
          message: 'not valid JSON: ${e.message}',
          cause: e,
        ),
      ],
    );
  }
  if (root is! Map) {
    return ArchiveReadResult(
      archive: CompendiumArchive(exportedAt: _epoch),
      errors: const [
        ArchiveError(
          kind: ArchiveErrorKind.read,
          entityType: 'archive',
          message: 'root must be a JSON object',
        ),
      ],
    );
  }
  return archiveFromJson(root.cast<String, Object?>());
}

/// Decodes an already-parsed archive object. See [decodeArchive].
ArchiveReadResult archiveFromJson(Map<String, Object?> root) {
  final errors = <ArchiveError>[];
  final warnings = <String>[];

  var schemaVersion = archiveSchemaVersion;
  final rawVersion = root['schemaVersion'];
  if (rawVersion is int) {
    schemaVersion = rawVersion;
    if (rawVersion > archiveSchemaVersion) {
      warnings.add(
        'archive schemaVersion $rawVersion is newer than supported '
        '$archiveSchemaVersion; reading known fields only',
      );
    }
  } else if (rawVersion != null) {
    warnings.add(
      'ignoring non-integer schemaVersion; assuming '
      '$archiveSchemaVersion',
    );
  }

  DateTime exportedAt = _epoch;
  final rawExportedAt = root['exportedAt'];
  if (rawExportedAt is String) {
    final parsed = DateTime.tryParse(rawExportedAt);
    if (parsed != null) {
      exportedAt = parsed.toUtc();
    } else {
      warnings.add('ignoring unparseable exportedAt "$rawExportedAt"');
    }
  } else if (rawExportedAt != null) {
    warnings.add('ignoring non-string exportedAt');
  }

  final choreographers = _decodeList(
    root['choreographers'],
    'choreographer',
    _choreographerFromJson,
    errors,
  );
  final publishedSources = _decodeList(
    root['publishedSources'],
    'publishedSource',
    _publishedSourceFromJson,
    errors,
  );
  final tags = _decodeList(root['tags'], 'tag', _tagFromJson, errors);
  final customFields = _decodeList(
    root['customFields'],
    'customField',
    _customFieldDefFromJson,
    errors,
  );
  final dances = _decodeList(root['dances'], 'dance', _danceFromJson, errors);
  final programs = _decodeList(
    root['programs'],
    'program',
    _programFromJson,
    errors,
  );

  return ArchiveReadResult(
    archive: CompendiumArchive(
      schemaVersion: schemaVersion,
      exportedAt: exportedAt,
      dances: dances,
      programs: programs,
      choreographers: choreographers,
      publishedSources: publishedSources,
      customFields: customFields,
      tags: tags,
    ),
    errors: errors,
    warnings: warnings,
  );
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Decodes a JSON list field into models, skipping (and recording) any entry
/// that is not an object or fails to decode. A missing/non-list field yields an
/// empty list.
List<T> _decodeList<T>(
  Object? raw,
  String entityType,
  T Function(Map<String, Object?>) decode,
  List<ArchiveError> errors,
) {
  if (raw == null) return const [];
  if (raw is! List) {
    errors.add(
      ArchiveError(
        kind: ArchiveErrorKind.read,
        entityType: entityType,
        message: 'expected a JSON array; ignoring',
      ),
    );
    return const [];
  }
  final result = <T>[];
  for (final entry in raw) {
    if (entry is! Map) {
      errors.add(
        ArchiveError(
          kind: ArchiveErrorKind.read,
          entityType: entityType,
          message: 'entry is not a JSON object; skipped',
        ),
      );
      continue;
    }
    final map = entry.cast<String, Object?>();
    try {
      result.add(decode(map));
    } on Exception catch (e) {
      // Catch only Exceptions (the decode helpers throw FormatException for
      // malformed input): Dart Errors signal genuine bugs and should surface
      // during development rather than being recorded as data-quality errors.
      errors.add(
        ArchiveError(
          kind: ArchiveErrorKind.read,
          entityType: entityType,
          entityId: map['id'] is String ? map['id'] as String : null,
          message: 'could not be read: $e',
          cause: e,
        ),
      );
    }
  }
  return result;
}

Choreographer _choreographerFromJson(Map<String, Object?> m) => Choreographer(
  id: _str(m, 'id'),
  name: _str(m, 'name'),
  website: _strOrNull(m, 'website'),
  notes: _strOrNull(m, 'notes'),
  email: _strOrNull(m, 'email'),
  location: _strOrNull(m, 'location'),
  deceased: _boolOr(m, 'deceased', false),
);

PublishedSource _publishedSourceFromJson(Map<String, Object?> m) =>
    PublishedSource(
      id: _str(m, 'id'),
      title: _str(m, 'title'),
      author: _strOrNull(m, 'author'),
      year: _intOrNull(m, 'year'),
      url: _strOrNull(m, 'url'),
      notes: _strOrNull(m, 'notes'),
    );

Tag _tagFromJson(Map<String, Object?> m) => Tag(
  id: _str(m, 'id'),
  name: _str(m, 'name'),
  color: _intOrNull(m, 'color'),
);

CustomFieldDef _customFieldDefFromJson(Map<String, Object?> m) =>
    CustomFieldDef(
      id: _str(m, 'id'),
      key: _str(m, 'key'),
      label: _str(m, 'label'),
      type: _enumByName(CustomFieldType.values, _str(m, 'type'), 'type'),
      choices: _stringListOrNull(m, 'choices'),
      showInList: _boolOr(m, 'showInList', false),
      searchable: _boolOr(m, 'searchable', true),
    );

Dance _danceFromJson(Map<String, Object?> m) => Dance(
  id: _str(m, 'id'),
  title: _str(m, 'title'),
  authorIds: _stringList(m, 'authorIds'),
  form: _enumByNameOr(DanceForm.values, m['form'], DanceForm.contra, 'form'),
  formation: _formationFromJson(m['formation']),
  progression: _enumByNameOr(
    Progression.values,
    m['progression'],
    Progression.single,
    'progression',
  ),
  phraseStructure: _strOr(m, 'phraseStructure', ''),
  figures: _figuresFromJson(m['figures']),
  hook: _strOr(m, 'hook', ''),
  callingNotes: _strOr(m, 'callingNotes', ''),
  status: _enumByNameOr(
    DanceStatus.values,
    m['status'],
    DanceStatus.active,
    'status',
  ),
  level: m['level'] == null
      ? null
      : _enumByName(DanceLevel.values, _str(m, 'level'), 'level'),
  mixedLevel: _boolOr(m, 'mixedLevel', false),
  rating: _intOrNull(m, 'rating'),
  tunes: _stringList(m, 'tunes'),
  customFields: _customFieldValuesFromJson(m['customFields']),
  tagIds: _stringList(m, 'tagIds'),
  links: _danceLinksFromJson(m['links']),
  sourceCitations: _sourceCitationsFromJson(m['sourceCitations']),
  provenance: m['provenance'] == null
      ? null
      : _provenanceFromJson(_asMap(m['provenance'], 'provenance')),
  composedOn: _partialDateOrNull(m, 'composedOn'),
  revisedOn: _partialDateOrNull(m, 'revisedOn'),
  createdAt: _dt(m, 'createdAt'),
  updatedAt: _dt(m, 'updatedAt'),
  deletedAt: _dtOrNull(m, 'deletedAt'),
);

Formation _formationFromJson(Object? raw) {
  if (raw == null) return const Formation(FormationShape.dupleImproper);
  final m = _asMap(raw, 'formation');
  return Formation(
    _enumByName(FormationShape.values, _str(m, 'shape'), 'shape'),
    detail: _strOrNull(m, 'detail'),
  );
}

List<Figure> _figuresFromJson(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) throw FormatException('"figures" must be an array');
  return [
    for (final e in raw)
      if (e is Map)
        figureFromJson(e.cast<String, Object?>())
      else
        throw FormatException('figure entries must be objects: $e'),
  ];
}

List<CustomFieldValue> _customFieldValuesFromJson(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) throw FormatException('"customFields" must be an array');
  return [
    for (final e in raw)
      CustomFieldValue(
        fieldId: _str(_asMap(e, 'customField'), 'fieldId'),
        value: _requireValue(_asMap(e, 'customField')),
      ),
  ];
}

Object _requireValue(Map<String, Object?> m) {
  final v = m['value'];
  if (v == null) throw FormatException('custom field value is missing "value"');
  return v;
}

List<DanceLink> _danceLinksFromJson(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) throw FormatException('"links" must be an array');
  return [
    for (final e in raw)
      () {
        final m = _asMap(e, 'link');
        return DanceLink(
          id: _str(m, 'id'),
          kind: _enumByName(LinkKind.values, _str(m, 'kind'), 'kind'),
          url: _strOrNull(m, 'url'),
          targetDanceId: _strOrNull(m, 'targetDanceId'),
          label: _strOrNull(m, 'label'),
        );
      }(),
  ];
}

List<SourceCitation> _sourceCitationsFromJson(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) throw FormatException('"sourceCitations" must be an array');
  return [
    for (final e in raw)
      () {
        final m = _asMap(e, 'sourceCitation');
        return SourceCitation(
          sourceId: _str(m, 'sourceId'),
          page: _strOrNull(m, 'page'),
          number: _strOrNull(m, 'number'),
        );
      }(),
  ];
}

Provenance _provenanceFromJson(Map<String, Object?> m) => Provenance(
  source: _enumByName(ProvenanceSource.values, _str(m, 'source'), 'source'),
  externalId: _strOrNull(m, 'externalId'),
  importedAt: _dt(m, 'importedAt'),
  permission: _strOrNull(m, 'permission'),
  license: _strOrNull(m, 'license'),
  rawPayload: _strOrNull(m, 'rawPayload'),
  sourceVersion: _strOrNull(m, 'sourceVersion'),
);

Program _programFromJson(Map<String, Object?> m) => Program(
  id: _str(m, 'id'),
  title: _str(m, 'title'),
  eventDate: _dtOrNull(m, 'eventDate'),
  venue: _strOrNull(m, 'venue'),
  band: _strOrNull(m, 'band'),
  caller: _strOrNull(m, 'caller'),
  dancerLevel: _strOrNull(m, 'dancerLevel'),
  notes: _strOr(m, 'notes', ''),
  status: _enumByNameOr(
    ProgramStatus.values,
    m['status'],
    ProgramStatus.draft,
    'status',
  ),
  slots: _programSlotsFromJson(m['slots']),
  createdAt: _dt(m, 'createdAt'),
  updatedAt: _dt(m, 'updatedAt'),
  deletedAt: _dtOrNull(m, 'deletedAt'),
);

List<ProgramSlot> _programSlotsFromJson(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) throw FormatException('"slots" must be an array');
  return [
    for (final e in raw)
      () {
        final m = _asMap(e, 'slot');
        return ProgramSlot(
          id: _str(m, 'id'),
          position: _int(m, 'position'),
          danceId: _strOrNull(m, 'danceId'),
          text: _strOrNull(m, 'text'),
          isAlt: _boolOr(m, 'isAlt', false),
          guestCaller: _strOrNull(m, 'guestCaller'),
          plannedMinutes: _intOrNull(m, 'plannedMinutes'),
          performedAt: _dtOrNull(m, 'performedAt'),
        );
      }(),
  ];
}

// ---------------------------------------------------------------------------
// Typed field accessors (throw FormatException; caught per-entity on decode)
// ---------------------------------------------------------------------------

Map<String, Object?> _asMap(Object? v, String what) {
  if (v is! Map) throw FormatException('$what must be a JSON object');
  return v.cast<String, Object?>();
}

String _str(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! String) throw FormatException('missing or non-string "$key"');
  return v;
}

String _strOr(Map<String, Object?> m, String key, String fallback) {
  final v = m[key];
  if (v == null) return fallback;
  if (v is! String) throw FormatException('"$key" must be a string');
  return v;
}

String? _strOrNull(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! String) throw FormatException('"$key" must be a string');
  return v;
}

int _int(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! int) throw FormatException('missing or non-integer "$key"');
  return v;
}

int? _intOrNull(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! int) throw FormatException('"$key" must be an integer');
  return v;
}

bool _boolOr(Map<String, Object?> m, String key, bool fallback) {
  final v = m[key];
  if (v == null) return fallback;
  if (v is! bool) throw FormatException('"$key" must be a boolean');
  return v;
}

List<String> _stringList(Map<String, Object?> m, String key) =>
    _stringListOrNull(m, key) ?? const [];

List<String>? _stringListOrNull(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! List) throw FormatException('"$key" must be an array');
  return [
    for (final e in v)
      if (e is String) e else throw FormatException('"$key" must be strings'),
  ];
}

DateTime _dt(Map<String, Object?> m, String key) {
  final parsed = _dtOrNull(m, key);
  if (parsed == null) throw FormatException('missing datetime "$key"');
  return parsed;
}

DateTime? _dtOrNull(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! String) throw FormatException('"$key" must be an ISO-8601 string');
  final parsed = DateTime.tryParse(v);
  if (parsed == null) throw FormatException('"$key" is not a valid datetime');
  return parsed.toUtc();
}

PartialDate? _partialDateOrNull(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! String) throw FormatException('"$key" must be a string');
  return PartialDate.parse(v);
}

T _enumByName<T extends Enum>(List<T> values, String name, String field) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('unknown $field: "$name"');
}

T _enumByNameOr<T extends Enum>(
  List<T> values,
  Object? raw,
  T fallback,
  String field,
) {
  if (raw == null) return fallback;
  if (raw is! String) throw FormatException('"$field" must be a string');
  return _enumByName(values, raw, field);
}
