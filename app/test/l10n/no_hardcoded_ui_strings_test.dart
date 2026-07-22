import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'hardcoded_ui_strings_allowlist.dart';

/// Ratchet guard against hardcoded user-facing UI strings (L5 i18n).
///
/// Walks `lib/src/**.dart` and flags string literals passed to a curated set of
/// user-facing widget constructors/arguments (`Text('…')`, `tooltip:`,
/// `labelText:`, `Semantics(label:/hint:)`, `InputDecoration` texts, `Tooltip`
/// `message:`, …). Prose in a localized app must come from `AppLocalizations`
/// (`l10n.*`), so any such literal is a leak.
///
/// This mirrors the `dart:io` file-walking + comment-stripping precedent of
/// `test/data/migration_guard_test.dart` and the ADR-001 Flutter-import guard,
/// and runs inside the ordinary `flutter test` gate — no new CI step.
///
/// It is a **ratchet**: files that still contain leaks live in
/// [hardcodedUiStringAllowlist]. Every other file must be clean, so a newly
/// added or freshly localized file can never silently regress.
///
/// Escape hatch: append `// i18n-ignore` to a line whose literal is
/// intentionally not translatable (e.g. a single-glyph font specimen).
void main() {
  // Named arguments that render user-facing prose directly from a raw string.
  // (Widgets whose text is wrapped in `Text(...)` are caught by the `Text(`
  // trigger instead, so this stays deliberately narrow to avoid matching
  // non-UI maps/records that happen to use these key names.)
  const namedArgs = <String>[
    'tooltip',
    'labelText',
    'hintText',
    'helperText',
    'errorText',
    'semanticLabel',
    'message',
    'hint',
    'helpText',
  ];

  final trigger = RegExp(
    // `Text(` (optionally `const`) followed by a string literal, OR one of the
    // user-facing named args followed by a string literal.
    r'''(?:\bText\(\s*(?:const\s+)?|\b(?:'''
    '${namedArgs.join('|')}'
    r''')\s*:\s*)(['"])''',
  );

  /// Replaces comment bodies with same-length blanks (newlines preserved) so
  /// match offsets still map to the right source line for `// i18n-ignore`.
  String blankComments(String src) {
    src = src.replaceAllMapped(
      RegExp(r'/\*.*?\*/', dotAll: true),
      (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
    );
    src = src.replaceAllMapped(RegExp(r'//[^\n]*'), (m) => ' ' * m[0]!.length);
    return src;
  }

  /// Reads the string literal that starts at [quoteIndex] (the opening quote),
  /// honoring backslash escapes, and returns its raw inner text — or `null` if
  /// it is a triple-quoted or unterminated literal we shouldn't judge.
  String? readLiteral(String src, int quoteIndex) {
    final quote = src[quoteIndex];
    // Skip triple-quoted strings (multi-line blocks are rarely UI prose here).
    if (quoteIndex + 2 < src.length &&
        src[quoteIndex + 1] == quote &&
        src[quoteIndex + 2] == quote) {
      return null;
    }
    final buf = StringBuffer();
    var i = quoteIndex + 1;
    while (i < src.length) {
      final c = src[i];
      if (c == r'\') {
        if (i + 1 < src.length) buf.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (c == quote) return buf.toString();
      if (c == '\n') return null; // unterminated on this line
      buf.write(c);
      i++;
    }
    return null;
  }

  /// Whether [literal] carries translatable prose: it has a letter left over
  /// after stripping `$…`/`${…}` interpolations. Pure interpolations, numbers,
  /// punctuation, and symbols (e.g. `'• '`, `'$count'`, `'—'`) are ignored.
  bool isProse(String literal) {
    final withoutInterp = literal
        .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '');
    return RegExp(r'[A-Za-z]').hasMatch(withoutInterp);
  }

  int lineOf(String src, int offset) =>
      '\n'.allMatches(src.substring(0, offset)).length + 1;

  final libSrc = Directory('lib/src');

  /// Scans one file, returning `(line, literal)` pairs for flagged prose that
  /// is not suppressed by `// i18n-ignore` on its line.
  List<(int, String)> scan(File file) {
    final raw = file.readAsStringSync();
    final ignoredLines = <int>{};
    final rawLines = raw.split('\n');
    for (var i = 0; i < rawLines.length; i++) {
      if (rawLines[i].contains('i18n-ignore')) ignoredLines.add(i + 1);
    }
    final src = blankComments(raw);
    final hits = <(int, String)>[];
    for (final m in trigger.allMatches(src)) {
      final quoteIndex = m.start + m[0]!.length - 1;
      final literal = readLiteral(src, quoteIndex);
      if (literal == null || !isProse(literal)) continue;
      final line = lineOf(src, quoteIndex);
      if (ignoredLines.contains(line)) continue;
      hits.add((line, literal));
    }
    return hits;
  }

  test('lib/src exists (guard runs from the app package root)', () {
    expect(
      libSrc.existsSync(),
      isTrue,
      reason: 'Run this test from the app/ package (flutter test cwd).',
    );
  });

  test('no hardcoded user-facing strings outside the allow-list', () {
    final offenders = <String, List<(int, String)>>{};
    for (final entity in libSrc.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path
          .replaceFirst(RegExp(r'^lib[/\\]'), 'lib/')
          .replaceAll(r'\', '/');
      final relFromLib = rel.substring('lib/'.length);
      if (hardcodedUiStringAllowlist.contains(relFromLib)) continue;
      final hits = scan(entity);
      if (hits.isNotEmpty) offenders[relFromLib] = hits;
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Hardcoded user-facing strings found. Route them through '
          'AppLocalizations (l10n.*), or if a file is deferred to a later '
          'localization layer add it to hardcoded_ui_strings_allowlist.dart:\n'
          '${offenders.entries.map((e) => '  ${e.key}:\n'
              '${e.value.map((h) => '    L${h.$1}: ${h.$2}').join('\n')}').join('\n')}',
    );
  });

  test('allow-list has no stale or already-clean entries', () {
    final stale = <String>[];
    final clean = <String>[];
    for (final rel in hardcodedUiStringAllowlist) {
      final file = File('lib/$rel');
      if (!file.existsSync()) {
        stale.add(rel);
        continue;
      }
      if (scan(file).isEmpty) clean.add(rel);
    }
    expect(
      stale,
      isEmpty,
      reason:
          'These allow-listed files no longer exist — remove them:\n'
          '${stale.map((s) => '  $s').join('\n')}',
    );
    expect(
      clean,
      isEmpty,
      reason:
          'These allow-listed files no longer have any flagged literal — '
          'they are localized, so remove them from the allow-list to re-arm '
          'the guard:\n${clean.map((s) => '  $s').join('\n')}',
    );
  });

  test('no fully-localized L5 target file is allow-listed', () {
    // Files L5 fully localizes must never be parked on the allow-list — that
    // would let them regress silently. (Helper-swap-only files touched by L5
    // may legitimately be listed for L6.)
    const l5Targets = <String>{
      'src/screens/settings/general_section.dart',
      'src/screens/settings/appearance_section.dart',
      'src/screens/settings/defaults_section.dart',
      'src/screens/settings/about_section.dart',
      'src/screens/settings/updates_section.dart',
      'src/screens/settings/dialect_section.dart',
      'src/screens/formation_colors_screen.dart',
      'src/widgets/import_gap_badge.dart',
      // Small global/shared chrome fully localized in L5.
      'src/screens/app_shell.dart',
      'src/utils/confirm_delete.dart',
      'src/utils/launch_external_url.dart',
      'src/widgets/app_bootstrap.dart',
      'src/widgets/color_edit_dialog.dart',
    };
    final leaked = l5Targets.intersection(hardcodedUiStringAllowlist);
    expect(
      leaked,
      isEmpty,
      reason: 'L5 target files must not be allow-listed: $leaked',
    );
  });
}
