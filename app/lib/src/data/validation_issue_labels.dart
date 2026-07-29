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
  switch (issue.code) {
    case 'phrase_overflow':
    case 'phrase_underflow':
      return l10n.validationPhraseBeatMismatch(
        (issue.data['actual'] as int?) ?? 0,
        (issue.data['expected'] as int?) ?? 0,
      );
    case 'orphaned_alt':
      final position = (issue.data['position'] as int?) ?? 0;
      final text = issue.data['text'] as String?;
      return text == null
          ? l10n.validationOrphanedAlt(position)
          : l10n.validationOrphanedAltNamed(position, text);
    case 'empty_substitution':
      return l10n.validationEmptySubstitution(
        (issue.data['source'] as String?) ?? '',
      );
    case 'dialect_collision':
      return l10n.validationDialectCollision(
        (issue.data['source'] as String?) ?? '',
        (issue.data['existing'] as String?) ?? '',
        (issue.data['substitution'] as String?) ?? '',
      );
    default:
      // Generic, non-leaking fallback. The diagnostic English is appended only
      // in debug builds to aid development — never in a release UI (CWE-209).
      return kDebugMode
          ? '${l10n.validationGeneric} [${issue.code}: ${issue.message}]'
          : l10n.validationGeneric;
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
