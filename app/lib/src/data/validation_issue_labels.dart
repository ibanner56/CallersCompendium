import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';

/// Localized presentation of core [ValidationIssue]s (and the phrase-structure
/// [FormatException]) rendered in the editors.
///
/// The core layer keeps a stable `code` discriminator plus typed [data] on each
/// issue; its `message` is an internal English diagnostic that is **not**
/// displayed in a localized UI. This mapper turns `code` (+ `data`) into a
/// localized string at the presentation boundary, mirroring
/// `import_error_labels.dart`.
///
/// Security: user-entered dialect/program text carried in [data] is rendered as
/// plain text through gen-l10n placeholders (safe in Flutter). Any raw
/// lower-layer/parser detail is surfaced only under [kDebugMode] — never in a
/// release build (CWE-209).

/// The [ValidationIssue] codes this mapper localizes explicitly. Any other code
/// falls back to [AppLocalizations.validationGeneric]. Exposed for the coverage
/// test that guards against a silent English leak.
const Set<String> mappedValidationCodes = {
  'phrase_overflow',
  'phrase_underflow',
  'orphaned_alt',
  'empty_substitution',
  'dialect_collision',
};

/// Localized message for a [ValidationIssue] surfaced in an editor.
String validationIssueMessage(AppLocalizations l10n, ValidationIssue issue) {
  final localized = _localizedValidation(l10n, issue);
  if (localized != null) return localized;
  // No specific localization (unknown code, or expected structured data
  // missing/ill-typed): generic, non-leaking fallback. The diagnostic English
  // is appended only in debug builds — never in a release UI (CWE-209).
  return kDebugMode
      ? '${l10n.validationGeneric} [${issue.code}: ${issue.message}]'
      : l10n.validationGeneric;
}

/// Returns the specific localized message for [issue], or `null` when the code
/// is unmapped or its required safe structured data is absent/ill-typed (so the
/// caller can fall back to the generic message rather than render a misleading
/// value such as "0 beats").
String? _localizedValidation(AppLocalizations l10n, ValidationIssue issue) {
  final data = issue.data;
  switch (issue.code) {
    case 'phrase_overflow':
    case 'phrase_underflow':
      final actual = data['actual'];
      final expected = data['expected'];
      return (actual is int && expected is int)
          ? l10n.validationPhraseBeatMismatch(actual, expected)
          : null;
    case 'orphaned_alt':
      final position = data['position'];
      if (position is! int) return null;
      final text = data['text'] as String?;
      return text == null
          ? l10n.validationOrphanedAlt(position)
          : l10n.validationOrphanedAltNamed(position, text);
    case 'empty_substitution':
      final source = data['source'];
      return source is String ? l10n.validationEmptySubstitution(source) : null;
    case 'dialect_collision':
      final source = data['source'];
      final existing = data['existing'];
      final substitution = data['substitution'];
      return (source is String && existing is String && substitution is String)
          ? l10n.validationDialectCollision(source, existing, substitution)
          : null;
    default:
      return null;
  }
}

/// Localized field error for an invalid phrase-structure string. The raw
/// [FormatException] message is opaque parser text, so it is shown only under
/// [kDebugMode]; release builds get the generic localized message (CWE-209).
String phraseStructureErrorMessage(
  AppLocalizations l10n,
  FormatException error,
) => kDebugMode
    ? '${l10n.validationPhraseInvalid} [${error.message}]'
    : l10n.validationPhraseInvalid;
