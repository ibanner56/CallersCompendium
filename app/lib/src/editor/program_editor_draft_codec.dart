import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// Settings-table key prefix for the program editor's transient autosave drafts.
///
/// Draft keys are dynamic (`program_editor_draft:<programId|new>`) and hold
/// unsaved, device-local in-progress edits — not user content or preferences.
/// They must never travel in a backup, so `backup_service.dart` excludes this
/// prefix from both export and restore (see `kBackupSettingsDenylistPrefixes`).
/// It lives in this non-UI module (mirroring [kDanceEditorDraftKeyPrefix]) so
/// both the editor screen and `BackupService` can share it without a data→UI
/// dependency.
const String kProgramEditorDraftKeyPrefix = 'program_editor_draft:';

/// Draft schema version. Increment if the JSON shape changes in a
/// backward-incompatible way; [decodeProgramDraft] checks this and rejects
/// unrecognised future versions gracefully.
const int _kProgramDraftVersion = 1;

// ---------------------------------------------------------------------------
// ProgramEditorDraft — immutable snapshot of the program editor's working state
// ---------------------------------------------------------------------------

/// An immutable snapshot of the program editor's full working state (title,
/// event metadata, notes, status, hide-alternates flag, and the slot list).
///
/// Distinct from a domain [Program]: the title may be **empty** (a still-titled
/// in-progress build), and there are no `createdAt`/`updatedAt`/`id` — those are
/// carried by the editor's `_existing` program (for an edit) or minted on save
/// (for a new one). `venueId`/`provenance` are not part of the editable working
/// state, so they are deliberately omitted (preserved on `_existing` and
/// reapplied via `copyWith` on save).
@immutable
class ProgramEditorDraft {
  const ProgramEditorDraft({
    required this.title,
    this.eventDate,
    this.venue,
    this.band,
    this.caller,
    this.dancerLevel,
    required this.notes,
    required this.status,
    required this.hideAlternates,
    required this.slots,
  });

  /// The program title as typed; may be empty for an in-progress draft.
  final String title;

  /// Event date; `null` when unset.
  final DateTime? eventDate;

  /// Free-text venue label; `null` when blank.
  final String? venue;

  /// Band playing the event; `null` when blank.
  final String? band;

  /// Host caller; `null` when blank.
  final String? caller;

  /// Event dancer level (free text); `null` when blank.
  final String? dancerLevel;

  /// Program notes (may be empty).
  final String notes;

  /// Program status.
  final ProgramStatus status;

  /// Whether alternates are hidden from output.
  final bool hideAlternates;

  /// The in-progress slot list (position-ordered).
  final List<ProgramSlot> slots;
}

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

/// Serialises [draft] to a JSON string suitable for storage in
/// [SettingsRepository].
///
/// Schema (v1):
/// ```jsonc
/// {
///   "v": 1,
///   "title": "...",          // may be ""
///   "eventDate": "2026-01-01T00:00:00.000Z", // omitted when null
///   "venue": "...", "band": "...", "caller": "...", "dancerLevel": "...",
///   "notes": "...",
///   "status": "draft",
///   "hideAlternates": false,
///   "slots": [
///     {"id":"...", "position":0, "danceId":"...", "isAlt":false},
///     {"id":"...", "position":1, "text":"Break", "isAlt":false}
///   ]
/// }
/// ```
/// Nullable metadata (`eventDate`/`venue`/`band`/`caller`/`dancerLevel`) and
/// nullable per-slot fields (`danceId`/`text`/`guestCaller`/`plannedMinutes`/
/// `performedAt`) are omitted when unset.
String encodeProgramDraft(ProgramEditorDraft draft) {
  return jsonEncode({
    'v': _kProgramDraftVersion,
    'title': draft.title,
    if (draft.eventDate != null)
      'eventDate': draft.eventDate!.toUtc().toIso8601String(),
    if (draft.venue != null) 'venue': draft.venue,
    if (draft.band != null) 'band': draft.band,
    if (draft.caller != null) 'caller': draft.caller,
    if (draft.dancerLevel != null) 'dancerLevel': draft.dancerLevel,
    'notes': draft.notes,
    'status': draft.status.name,
    'hideAlternates': draft.hideAlternates,
    'slots': [for (final s in draft.slots) _slotToJson(s)],
  });
}

Map<String, Object?> _slotToJson(ProgramSlot s) => {
  'id': s.id,
  'position': s.position,
  if (s.danceId != null) 'danceId': s.danceId,
  if (s.text != null) 'text': s.text,
  'isAlt': s.isAlt,
  if (s.guestCaller != null) 'guestCaller': s.guestCaller,
  if (s.plannedMinutes != null) 'plannedMinutes': s.plannedMinutes,
  if (s.performedAt != null)
    'performedAt': s.performedAt!.toUtc().toIso8601String(),
};

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

/// Deserialises a draft JSON value (as returned by [SettingsRepository.get],
/// which round-trips through `jsonDecode` and so is normally a `Map`, but may
/// be the raw JSON string) back into a [ProgramEditorDraft].
///
/// Hardened against malformed input (OWASP input-validation posture — the
/// source is device-local, but we still verify every field rather than trust
/// it): the version must be in `[1, _kProgramDraftVersion]`, every field is
/// type-checked, the status is resolved by name, dates must be valid ISO-8601,
/// and each slot is validated (a slot with neither `danceId` nor `text`, a
/// negative position, or negative planned minutes throws). Unknown top-level
/// keys are ignored (forward-compat). Any structural problem throws a
/// [FormatException] so the caller can silently discard the corrupt draft.
ProgramEditorDraft decodeProgramDraft(Object? value) {
  final Map<String, Object?> json;
  if (value is String) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('program draft root must be a JSON object');
    }
    json = decoded.cast();
  } else if (value is Map) {
    json = value.cast();
  } else {
    throw FormatException(
      'unexpected program draft type: ${value.runtimeType}',
    );
  }

  final v = json['v'];
  // Accept any version in the range [1, _kProgramDraftVersion]. Versions below
  // 1 or above the current version are unknown and must be rejected so we never
  // silently mangle data from a future schema we don't understand.
  if (v is! int || v < 1 || v > _kProgramDraftVersion) {
    throw FormatException('unsupported program draft schema version: $v');
  }

  return ProgramEditorDraft(
    title: _str(json, 'title'),
    eventDate: _dateOrNull(json['eventDate'], 'eventDate'),
    venue: _strOrNull(json, 'venue'),
    band: _strOrNull(json, 'band'),
    caller: _strOrNull(json, 'caller'),
    dancerLevel: _strOrNull(json, 'dancerLevel'),
    notes: _str(json, 'notes'),
    status: _parseEnum(ProgramStatus.values, _str(json, 'status')),
    hideAlternates: _bool(json, 'hideAlternates'),
    slots: _parseSlots(json['slots']),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _str(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return '';
  if (v is! String) {
    throw FormatException('program draft.$key must be a string: $v');
  }
  return v;
}

String? _strOrNull(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is! String) {
    throw FormatException('program draft.$key must be a string: $v');
  }
  return v;
}

bool _bool(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return false;
  if (v is! bool) {
    throw FormatException('program draft.$key must be a bool: $v');
  }
  return v;
}

DateTime? _dateOrNull(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! String) {
    throw FormatException(
      'program draft.$field must be an ISO-8601 string: $raw',
    );
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('program draft.$field is not a valid date: $raw');
  }
  return parsed.toUtc();
}

T _parseEnum<T extends Enum>(List<T> values, String name) {
  return values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw FormatException(
      'unknown enum value "$name" for ${values.first.runtimeType}',
    ),
  );
}

List<ProgramSlot> _parseSlots(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('program draft.slots must be an array');
  }
  return [for (final e in raw) _parseSlot(e)];
}

ProgramSlot _parseSlot(Object? e) {
  if (e is! Map) {
    throw const FormatException('program draft slot must be an object');
  }
  final m = e.cast<String, Object?>();
  final id = _str(m, 'id');
  if (id.isEmpty) {
    throw const FormatException('program draft slot.id is required');
  }
  final position = m['position'];
  if (position is! int) {
    throw FormatException(
      'program draft slot.position must be an int: $position',
    );
  }
  final planned = m['plannedMinutes'];
  if (planned != null && planned is! int) {
    throw FormatException(
      'program draft slot.plannedMinutes must be an int: $planned',
    );
  }
  try {
    return ProgramSlot(
      id: id,
      position: position,
      danceId: _strOrNull(m, 'danceId'),
      text: _strOrNull(m, 'text'),
      isAlt: _bool(m, 'isAlt'),
      guestCaller: _strOrNull(m, 'guestCaller'),
      plannedMinutes: planned as int?,
      performedAt: _dateOrNull(m['performedAt'], 'slot.performedAt'),
    );
  } on ArgumentError catch (err) {
    // The ProgramSlot constructor throws ArgumentError (a Dart Error, not an
    // Exception) for a slot with neither danceId nor text, a negative position,
    // or negative plannedMinutes. Surface it as a FormatException so the load
    // path's discard-on-error handling treats the whole draft as corrupt rather
    // than letting an Error escape and abort the editor load.
    throw FormatException('invalid program draft slot: ${err.message}');
  }
}
