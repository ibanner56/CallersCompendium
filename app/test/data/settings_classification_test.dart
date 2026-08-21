import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage ratchet for settings-key classification.
///
/// The database half of the catalogue is enforced by reflecting over the drift
/// schema (`packages/compendium_core/test/privacy/`). Settings keys have no
/// schema to reflect over — they are string constants declared across
/// `app/lib` and `packages/*/lib` — so this walks the source for their
/// declarations instead, in the manner of
/// `test/l10n/no_hardcoded_ui_strings_test.dart`.
///
/// Two declaration shapes are matched, because both exist in this codebase and
/// each escapes the *other*'s regex (issue #923):
/// - `const String kSomethingKey = '...';` — an exact settings key, resolved
///   against [settingsClassifications].
/// - `const String kSomethingKeyPrefix = '...';` — a settings-key *prefix*,
///   for keys built at runtime per-entity (`editor_draft:<id>`), resolved
///   against [settingsPrefixClassifications].
///
/// Adding either without classifying it fails here.
void main() {
  /// Matches `const String kSomethingKey = 'some_key';` — deliberately
  /// anchored to the whole declaration rather than grepping for bare string
  /// literals, so an unrelated constant that happens to look like a key is
  /// not swept in.
  ///
  /// Does not match `k…KeyPrefix` declarations: `Key` must be immediately
  /// followed by `=`, and in a `KeyPrefix` name it is followed by `Prefix`
  /// instead. [prefixDeclaration] matches that shape; the two patterns never
  /// match the same declaration.
  final declaration = RegExp(
    r"""^const\s+String\s+(k[A-Za-z0-9]*Key)\s*=\s*(['"])([^'"]+)\2\s*;""",
    multiLine: true,
  );

  /// Matches `const String kSomethingKeyPrefix = 'some_prefix:';` — the
  /// runtime-built-key declaration shape this issue is about. See
  /// [declaration] for why the two patterns don't overlap.
  final prefixDeclaration = RegExp(
    r"""^const\s+String\s+(k[A-Za-z0-9]*KeyPrefix)\s*=\s*(['"])([^'"]+)\2\s*;""",
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
    // This is a trust anchor, not a persisted user setting.
    'kPublishedCollectionPublicKey',
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

  /// Source roots to walk: `app/lib/src`, plus every `packages/*/lib/src`.
  ///
  /// The declaration-shape gap (`k…KeyPrefix`) is issue #923's headline defect;
  /// this location widening closes a second blind spot in the same ratchet:
  /// before this change it only scanned `app/lib/src`, so a settings key
  /// declared in a `packages/*` library — for example, a shared class used by
  /// a second client — would never be checked at all. No settings key is
  /// declared outside `app/lib/src` today — verified by running this test's
  /// own walk before widening it — but the walk should cover the shape of the
  /// risk, not just today's instances of it.
  List<Directory> sourceRoots() {
    final appLibSrc = Directory('lib/src');
    expect(
      appLibSrc.existsSync(),
      isTrue,
      reason: 'Run this from the app/ directory (flutter test).',
    );

    final roots = [appLibSrc];
    final packagesDir = Directory('../packages');
    if (packagesDir.existsSync()) {
      for (final entity in packagesDir.listSync()) {
        if (entity is! Directory) continue;
        final libSrc = Directory('${entity.path}/lib/src');
        if (libSrc.existsSync()) roots.add(libSrc);
      }
    }
    return roots;
  }

  /// Every declared exact settings key, mapped to the file it was found in.
  Map<String, String> declaredKeys() {
    final found = <String, String>{};
    for (final root in sourceRoots()) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = blankComments(entity.readAsStringSync());
        for (final match in declaration.allMatches(source)) {
          if (notSettingsKeys.contains(match.group(1))) continue;
          found[match.group(3)!] = entity.path;
        }
      }
    }
    return found;
  }

  /// Every declared settings-key *prefix*, mapped to the file it was found in.
  Map<String, String> declaredPrefixes() {
    final found = <String, String>{};
    for (final root in sourceRoots()) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = blankComments(entity.readAsStringSync());
        for (final match in prefixDeclaration.allMatches(source)) {
          found[match.group(3)!] = entity.path;
        }
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

  test('every declared settings-key prefix is classified', () {
    final declared = declaredPrefixes();

    expect(
      declared,
      isNotEmpty,
      reason:
          'Found no k…KeyPrefix declarations at all. If the last one was just '
          'removed, also delete its entry from settingsPrefixClassifications; '
          'if this is unexpected, the detection regex has probably drifted, '
          'which would make this ratchet arm silently vacuous.',
    );

    final missing = declared.keys.toSet()
      ..removeAll(settingsPrefixClassifications.keys);

    expect(
      missing.toList()..sort(),
      isEmpty,
      reason:
          'These settings-key prefixes have no classification. Add them to\n'
          'packages/compendium_core/lib/src/privacy/settings_registry.dart\n'
          '(settingsPrefixClassifications); see docs/dev/data-classification.md\n'
          'for how to choose:\n\n'
          '${(missing.toList()..sort()).map((k) => "  '$k': ,  // ${declared[k]}").join('\n')}\n',
    );
  });

  test('no prefix classification refers to a prefix that is not declared', () {
    final stale = settingsPrefixClassifications.keys.toSet()
      ..removeAll(declaredPrefixes().keys);

    expect(
      stale.toList()..sort(),
      isEmpty,
      reason:
          'These entries in settingsPrefixClassifications name prefixes no '
          'longer declared as a k…KeyPrefix constant. Remove them, or the '
          'catalogue documents settings that do not exist.',
    );
  });
}
