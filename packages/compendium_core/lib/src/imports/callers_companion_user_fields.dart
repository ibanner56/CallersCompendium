import 'package:meta/meta.dart';

import '../model/custom_field.dart';
import 'callers_companion_mapping.dart';
import 'structured_draft.dart';

/// Prefix of the placeholder [CustomFieldValue.fieldId] the mapper writes for a
/// Caller's Companion user field.
///
/// The mapper is pure and runs at plan time, before any definition exists, so it
/// cannot know the receiver's field id. The value instead carries
/// `cc-user-field:<key>:<label>` (a key never contains `:`, so the label is
/// whatever follows the second one), and `CallersCompanionUsrImporter.commit`
/// resolves each key to a real definition and rewrites the placeholder
/// **before** the dances are written. The label rides along because the archive
/// the importer holds at commit has had its dances dropped to save memory. A
/// placeholder that reaches the repository is refused (`unknown custom field`),
/// so a path that does not go through the importer fails closed rather than
/// storing a dangling value.
const String kCcUserFieldIdPrefix = 'cc-user-field:';

/// The placeholder field id for a CC user field with derived [key] and [label].
String ccUserFieldPlaceholderId(String key, String label) =>
    '$kCcUserFieldIdPrefix$key:$label';

/// The `(key, label)` behind a placeholder id, or `null` when [fieldId] is not
/// one.
({String key, String label})? ccUserFieldOfPlaceholder(String fieldId) {
  if (!fieldId.startsWith(kCcUserFieldIdPrefix)) return null;
  final rest = fieldId.substring(kCcUserFieldIdPrefix.length);
  final split = rest.indexOf(':');
  if (split < 0) return (key: rest, label: rest);
  return (key: rest.substring(0, split), label: rest.substring(split + 1));
}

/// Longest key [ccUserFieldKeyForLabel] produces before any collision suffix.
const int kCcUserFieldMaxKeyLength = 48;

/// Longest label kept as a definition's display name; a longer one is cut.
const int kCcUserFieldMaxLabelLength = 100;

/// One CC user field after key derivation: the [key] the definition is matched
/// or created under, the caller's original [label], and the trimmed [value].
@immutable
class PlannedCcUserField {
  const PlannedCcUserField({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final String value;
}

/// The result of [planCcUserFields]: the fields that carry a value, plus a
/// non-fatal [ImportIssue] for every label whose key had to differ from a plain
/// slug of it.
@immutable
class CcUserFieldPlan {
  const CcUserFieldPlan({required this.fields, required this.issues});

  final List<PlannedCcUserField> fields;
  final List<ImportIssue> issues;
}

/// Derives a valid, deterministic custom-field key from a free-text CC [label].
///
/// Lower-cases, collapses every run of characters outside `[a-z0-9]` to one
/// `_`, trims leading and trailing `_`, and prefixes `f_` when the result would
/// start with a digit (keys must match `^[a-zA-Z_][a-zA-Z0-9_]*$`). A label with
/// no such characters at all (blank, or wholly non-Latin) has no slug to take,
/// so it falls back to `cc_<hash>`, where the hash is a stable FNV-1a of the
/// label: the same label yields the same key in every dance and every import.
String ccUserFieldKeyForLabel(String label) {
  final slug = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) return 'cc_${_fnv1a32Hex(label.trim())}';
  final bounded = slug.length <= kCcUserFieldMaxKeyLength
      ? slug
      : slug
            .substring(0, kCcUserFieldMaxKeyLength)
            .replaceAll(RegExp(r'_+$'), '');
  final key = RegExp(r'^[0-9]').hasMatch(bounded) ? 'f_$bounded' : bounded;
  assert(isValidCustomFieldKey(key), 'derived key "$key" is not valid');
  return key;
}

String _fnv1a32Hex(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Assigns each non-empty CC user field of one dance a distinct key.
///
/// Two labels in the same dance that slug to the same key ("Tempo" and
/// "tempo!") get a numeric suffix (2, 3, …) so neither value is lost or
/// overwrites the other, each with a warning. A label that had no slug (the hash fallback) is reported
/// as well, because the key does not read like the label. The original label is
/// always kept as the definition's display label.
///
/// This is used by both the mapper and the importer (to recover the labels
/// behind the placeholders), so the two can never disagree on a key.
CcUserFieldPlan planCcUserFields(List<CcUserField> userFields) {
  final fields = <PlannedCcUserField>[];
  final issues = <ImportIssue>[];
  final taken = <String>{};
  for (final field in userFields) {
    final value = field.value.trim();
    if (value.isEmpty) continue;
    final trimmed = field.label.trim();
    final label = trimmed.isEmpty
        ? 'Note'
        : trimmed.length <= kCcUserFieldMaxLabelLength
        ? trimmed
        : trimmed.substring(0, kCcUserFieldMaxLabelLength).trim();
    final base = ccUserFieldKeyForLabel(label);
    var key = base;
    for (var n = 2; !taken.add(key); n++) {
      key = '${base}_$n';
    }
    if (key != base) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'cc_user_field_key_adjusted',
          message:
              'Caller\'s Companion field "$label" shares a key with another '
              'field on this dance; stored under "$key".',
        ),
      );
    } else if (base.startsWith('cc_') &&
        !RegExp('[a-zA-Z0-9]').hasMatch(label)) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.info,
          code: 'cc_user_field_key_adjusted',
          message:
              'Caller\'s Companion field "$label" has no Latin letters or '
              'digits to build a key from; stored under "$key".',
        ),
      );
    }
    fields.add(PlannedCcUserField(key: key, label: label, value: value));
  }
  return CcUserFieldPlan(fields: fields, issues: issues);
}
