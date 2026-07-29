import 'package:meta/meta.dart';

import 'enums.dart';

/// Soft length bound (OWASP) for a single `choice` option label. A choice value
/// is short user-entered text that is created interactively (the dance editor
/// and the custom-fields settings screen cap input at this length) and can also
/// arrive from an untrusted archive on import (where oversized values are
/// **clamped**, not rejected, mirroring the codec's partial-failure tolerance).
/// Shared so both entry paths agree on one bound.
const int kMaxCustomFieldChoiceLength = 100;

/// Normalizes a raw `choice` option value: trims surrounding whitespace and
/// soft-clamps to [kMaxCustomFieldChoiceLength]. Returns `null` when the value
/// is empty after trimming (nothing to add). Deduplication against existing
/// options is the caller's responsibility (case-sensitive, on the normalized
/// value), matching how choices are compared everywhere else.
String? normalizeChoiceOption(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length <= kMaxCustomFieldChoiceLength
      ? trimmed
      : trimmed.substring(0, kMaxCustomFieldChoiceLength);
}

/// Definition of a user-created custom field.
///
/// Typed ([CustomFieldType]) so search and sorting stay sane; `choice`
/// fields must declare their choices.
@immutable
class CustomFieldDef {
  CustomFieldDef({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    List<String>? choices,
    this.showInList = false,
    this.searchable = true,
  }) : choices = choices == null ? null : List.unmodifiable(choices) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', 'must be non-empty');
    }
    if (type == CustomFieldType.choice &&
        (choices == null || choices.isEmpty)) {
      throw ArgumentError(
        'choice fields must declare at least one choice',
        'choices',
      );
    }
  }

  final String id;

  /// Stable machine key (used in search syntax and storage).
  final String key;

  /// Display label (dialect does not apply to user-authored labels).
  final String label;
  final CustomFieldType type;
  final List<String>? choices;
  final bool showInList;
  final bool searchable;
}

/// A custom field value attached to a dance. The value's runtime type must
/// match the definition's [CustomFieldType].
@immutable
class CustomFieldValue {
  CustomFieldValue({required this.fieldId, required this.value});

  final String fieldId;
  final Object value;

  /// Checks this value against its definition's type (and choices).
  bool matchesType(CustomFieldDef def) {
    switch (def.type) {
      case CustomFieldType.text:
        return value is String;
      case CustomFieldType.number:
        return value is num;
      case CustomFieldType.boolean:
        return value is bool;
      case CustomFieldType.choice:
        return value is String && (def.choices?.contains(value) ?? false);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CustomFieldValue &&
      other.fieldId == fieldId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(fieldId, value);
}
