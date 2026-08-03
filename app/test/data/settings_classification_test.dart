import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage ratchet for settings-key classification.
///
/// The database half of the catalogue is enforced by reflecting over the drift
/// schema (`packages/compendium_core/test/privacy/`). Settings keys have no
/// schema to reflect over — they are string constants declared across
/// `app/lib` — so this walks the source for their declarations instead, in the
/// manner of `test/l10n/no_hardcoded_ui_strings_test.dart`.
///
/// Adding a settings key without classifying it fails here.
void main() {
  /// Matches `const String kSomethingKey = 'some_key';`, the declaration form
  /// every settings key in this app uses. Deliberately anchored to the whole
  /// declaration rather than grepping for bare string literals, so an unrelated
  /// constant that happens to look like a key is not swept in.
  final declaration = RegExp(
    r"""^const\s+String\s+(k[A-Za-z0-9]*Key)\s*=\s*(['"])([^'"]+)\2\s*;""",
    multiLine: true,
  );

  /// Constants whose names end in `Key` but which are not settings keys.
  ///
  /// Kept as an explicit, named exclusion rather than narrowing the regex, so
  /// that a newly added non-settings `…Key` constant fails this test and has to
  /// be justified here — the alternative, a cleverer pattern, would drop it
  /// silently. Mirrors the allowlist precedent in
  /// `test/l10n/no_hardcoded_ui_strings_test.dart`.
  const notSettingsKeys = <String>{
    // The Ed25519 public key that update manifests are verified against — the
    // root of trust for update authenticity (ADR-002 §6), not a preference.
    'kUpdateManifestPublicKey',
  };

  /// Replaces comment bodies with blanks so a commented-out declaration is not
  /// counted. Mirrors the comment-stripping in the i18n ratchet.
  String blankComments(String source) {
    source = source.replaceAllMapped(
      RegExp(r'/\*.*?\*/', dotAll: true),
      (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
    );
    return source.replaceAllMapped(
      RegExp(r'//[^\n]*'),
      (m) => ' ' * m[0]!.length,
    );
  }

  Map<String, String> declaredKeys() {
    final root = Directory('lib/src');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'Run this from the app/ directory (flutter test).',
    );

    final found = <String, String>{};
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = blankComments(entity.readAsStringSync());
      for (final match in declaration.allMatches(source)) {
        if (notSettingsKeys.contains(match.group(1))) continue;
        found[match.group(3)!] = entity.path;
      }
    }
    return found;
  }

  test('every declared settings key is classified', () {
    final declared = declaredKeys();

    expect(
      declared,
      isNotEmpty,
      reason:
          'Found no settings-key declarations at all — the detection regex has '
          'probably drifted from the declaration style, which would make this '
          'ratchet silently vacuous.',
    );

    final missing = declared.keys.toSet()
      ..removeAll(settingsClassifications.keys);

    expect(
      missing.toList()..sort(),
      isEmpty,
      reason:
          'These settings keys have no classification. Add them to\n'
          'packages/compendium_core/lib/src/privacy/settings_registry.dart;\n'
          'see docs/dev/data-classification.md for how to choose:\n\n'
          '${(missing.toList()..sort()).map((k) => "  '$k': ,  // ${declared[k]}").join('\n')}\n',
    );
  });

  test('no classification refers to a settings key that is not declared', () {
    final stale = settingsClassifications.keys.toSet()
      ..removeAll(declaredKeys().keys);

    expect(
      stale.toList()..sort(),
      isEmpty,
      reason:
          'These entries in settingsClassifications name keys no longer '
          'declared in app/lib. Remove them, or the catalogue documents '
          'settings that do not exist.',
    );
  });
}
