import 'dart:convert';

import '../model/user_glossary.dart';
import '../storage/repositories/user_glossary_repository.dart';
import '../storage/shareable_text.dart';

/// The sync bodies of the user's own glossary (#709): the `glossaryEntry` and
/// `figureNote` record kinds.
///
/// Neither is in the compendium archive (an archive carries the collection;
/// the glossary travels in backups, in their `app.glossary` section, and by
/// sync), so unlike every other entity kind their bodies are not archive-codec
/// output. They are built and read here instead, and pass through the same
/// shareable projection and allow-list (`wire_mapping.dart`) as every other
/// body.
///
/// Every key is always present, null or empty when unset, so that two copies
/// of one record compare and hash alike whatever wrote them.

/// The sync body of [entry].
///
/// `payload` is the stored payload **text**, not the JSON value it encodes.
/// Carried as text so that an entry this build cannot read — a payload that
/// no longer decodes, or decodes to something only a newer build
/// understands — arrives byte for byte, and so that decoding and re-encoding
/// on the way (which sorts keys, as canonical JSON must) never rewrites what
/// the user's device stored. `kind` is the stored name, known here or not.
Map<String, Object?> syncGlossaryEntryBody(StoredUserGlossaryEntry entry) => {
  'id': entry.id,
  'kind': entry.kind,
  'name': entry.name,
  'definition': entry.definition,
  'description': entry.description,
  'keywords': [...entry.keywords],
  'notes': entry.notes,
  'payload': entry.payloadJson,
  'createdAt': _timestamp(entry.createdAt),
};

/// Reads a `glossaryEntry` body, throwing [FormatException] for one this
/// build cannot store as it came.
///
/// Refuses only what could not be written faithfully: a missing or mistyped
/// field, text over the bounds every build enforces, a creation time finer
/// than the second the column holds, and a payload that is JSON but not in
/// the normalised form storage would write (storing it would change the
/// record under its peer's wire hash). A kind this build does not know, and
/// a payload that does not decode at all, are accepted and kept as they are.
StoredUserGlossaryEntry decodeSyncGlossaryEntryBody(Map<String, Object?> body) {
  final keywords = body['keywords'] ?? const <Object?>[];
  if (keywords is! List ||
      keywords.length > maxUserGlossaryKeywords ||
      keywords.any(
        (k) =>
            k is! String || k.isEmpty || k.length > maxUserGlossaryNameLength,
      )) {
    throw const FormatException('glossary entry keywords are invalid');
  }
  final notes = body['notes'];
  if (notes != null &&
      (notes is! String || notes.length > maxUserGlossaryTextLength)) {
    throw const FormatException('glossary entry notes are invalid');
  }
  return StoredUserGlossaryEntry(
    id: _text(body, 'id', maxUserGlossaryNameLength),
    kind: _text(body, 'kind', maxUserGlossaryNameLength),
    name: _text(body, 'name', maxUserGlossaryNameLength),
    definition: _text(body, 'definition', maxUserGlossaryTextLength),
    description: _text(body, 'description', maxUserGlossaryTextLength),
    keywords: keywords.cast<String>(),
    notes: notes as String?,
    payloadJson: _payload(body['payload']),
    createdAt: _createdAt(body['createdAt']),
  );
}

/// The sync body of [note]: its record id is the shipped figure's id.
Map<String, Object?> syncFigureNoteBody(FigureNote note) => {
  'id': note.figureId,
  'notes': note.notes,
};

/// Reads a `figureNote` body, throwing [FormatException] for one this build
/// cannot store.
FigureNote decodeSyncFigureNoteBody(Map<String, Object?> body) => FigureNote(
  figureId: _text(body, 'id', maxUserGlossaryNameLength),
  notes: _text(body, 'notes', maxUserGlossaryTextLength),
);

String _text(Map<String, Object?> body, String key, int max) {
  final value = body[key];
  if (value is! String || value.isEmpty || value.length > max) {
    throw FormatException('glossary $key must be text of 1 to $max units');
  }
  return value;
}

String? _payload(Object? value) {
  if (value == null) return null;
  if (value is! String || value.length > maxUserGlossaryPayloadLength) {
    throw const FormatException('glossary entry payload is invalid');
  }
  if (!userGlossaryPayloadIsJson(value)) return value;
  if (userGlossaryPayloadDeeperThan(
    jsonDecode(value),
    maxUserGlossaryPayloadDepth,
  )) {
    throw const FormatException('glossary entry payload nests too deeply');
  }
  final String normalized;
  try {
    normalized = normalizeShareableJsonText(value);
  } on ShareableJsonKeyCollision {
    throw const FormatException('glossary entry payload keys collide');
  }
  if (normalized != value) {
    throw const FormatException('glossary entry payload is not normalised');
  }
  return value;
}

DateTime _createdAt(Object? value) {
  final parsed = value is String && value.endsWith('Z')
      ? DateTime.tryParse(value)
      : null;
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.millisecond != 0 ||
      parsed.microsecond != 0) {
    throw const FormatException(
      'glossary entry createdAt must be a UTC time to the second',
    );
  }
  return parsed;
}

/// [value] to the second, as the column stores it.
String _timestamp(DateTime value) {
  final micros = value.toUtc().microsecondsSinceEpoch;
  return DateTime.fromMicrosecondsSinceEpoch(
    micros - micros.remainder(Duration.microsecondsPerSecond),
    isUtc: true,
  ).toIso8601String();
}
