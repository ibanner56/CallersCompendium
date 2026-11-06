import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'hardcoded_ui_strings_allowlist.dart';

/// Ratchet guard against hardcoded user-facing UI strings (L5 i18n).
///
/// Walks every `lib/**.dart` file except the generated `lib/l10n/` and flags
/// string literals passed to a curated set of user-facing widget
/// constructors/arguments (`Text('…')`, `tooltip:`, `labelText:`,
/// `Semantics(label:/hint:)`, `InputDecoration` texts, `Tooltip` `message:`, …).
/// Prose in a localized app must come from `AppLocalizations` (`l10n.*`), so any
/// such literal is a leak.
///
/// A `Text(...)` is judged on every string literal at the top level of its
/// argument list, not only one directly after the paren, so
/// `Text(cond ? 'a' : 'b')` is caught, grouping parentheses included. Literals
/// nested in another call's arguments (`Text(l10n.x('a'))`) are not: that is a
/// call the guard cannot see into. Nor can it see prose stored in a `String`
/// and shown later; keep such messages typed (an enum mapped through `l10n` at
/// display time) instead.
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
  // (Widgets whose text is wrapped in `Text(...)` are caught by
  // [textArgumentLiterals] instead, so this stays deliberately narrow to avoid
  // matching non-UI maps/records that happen to use these key names.)
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
    // One of the user-facing named args followed by a string literal. `Text(`
    // is handled separately, by walking its arguments.
    r'''\b(?:'''
    '${namedArgs.join('|')}'
    r''')\s*:\s*(['"])''',
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

  /// Returns the index just past the string literal whose opening quote is at
  /// [q], skipping `${…}` interpolations (which may hold their own quotes).
  int literalEnd(String src, int q) {
    final quote = src[q];
    if (q + 2 < src.length && src[q + 1] == quote && src[q + 2] == quote) {
      final end = src.indexOf(quote * 3, q + 3);
      return end < 0 ? src.length : end + 3;
    }
    var i = q + 1;
    while (i < src.length) {
      final c = src[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == r'$' && i + 1 < src.length && src[i + 1] == '{') {
        var braces = 1;
        i += 2;
        while (i < src.length && braces > 0) {
          final d = src[i];
          if (d == "'" || d == '"') {
            i = literalEnd(src, i);
            continue;
          }
          if (d == '{') braces++;
          if (d == '}') braces--;
          i++;
        }
        continue;
      }
      if (c == quote || c == '\n') return i + 1;
      i++;
    }
    return src.length;
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
    final end = literalEnd(src, quoteIndex);
    // Unterminated on this line (or at end of file).
    if (end > src.length || src[end - 1] != quote) return null;
    return src.substring(quoteIndex + 1, end - 1);
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

  /// Offsets of the opening quote of every string literal at the top level of a
  /// `Text(...)` argument list. Delimiters are walked, so a literal behind a
  /// conditional or a `+` is found, including inside grouping parentheses
  /// (`Text((a ? 'x' : 'y'))`). One nested in another call's arguments, or in a
  /// list/map literal, is not. A grouping `(` is told from a call's `(` by the
  /// character before it: an identifier, `>`, `)` or `]` means a call.
  List<int> textArgumentLiterals(String src) {
    bool opensCall(int paren) {
      var j = paren - 1;
      while (j >= 0 && ' \t\r\n'.contains(src[j])) {
        j--;
      }
      return j >= 0 && RegExp(r'[A-Za-z0-9_$>)\]]').hasMatch(src[j]);
    }

    final quotes = <int>[];
    for (final m in RegExp(r'\bText\(').allMatches(src)) {
      // One entry per open delimiter; true when it is only a grouping paren.
      final open = <bool>[];
      var nested = 0; // open delimiters that are not grouping parens
      var i = m.end;
      while (i < src.length) {
        final c = src[i];
        if (c == "'" || c == '"') {
          if (nested == 0) quotes.add(i);
          i = literalEnd(src, i);
          continue;
        }
        if (c == '(' || c == '[' || c == '{') {
          final grouping = c == '(' && !opensCall(i);
          open.add(grouping);
          if (!grouping) nested++;
        }
        if (c == ')' || c == ']' || c == '}') {
          if (open.isEmpty) break;
          if (!open.removeLast()) nested--;
        }
        i++;
      }
    }
    return quotes;
  }

  int lineOf(String src, int offset) =>
      '\n'.allMatches(src.substring(0, offset)).length + 1;

  final libDir = Directory('lib');

  /// Scans Dart source, returning `(line, literal)` pairs for flagged prose
  /// that is not suppressed by `// i18n-ignore` on its line.
  List<(int, String)> scanSource(String raw) {
    final ignoredLines = <int>{};
    final rawLines = raw.split('\n');
    for (var i = 0; i < rawLines.length; i++) {
      if (rawLines[i].contains('i18n-ignore')) ignoredLines.add(i + 1);
    }
    final src = blankComments(raw);
    final hits = <(int, String)>[];
    final quoteIndexes = <int>[
      for (final m in trigger.allMatches(src)) m.start + m[0]!.length - 1,
      ...textArgumentLiterals(src),
    ]..sort();
    for (final quoteIndex in quoteIndexes) {
      final literal = readLiteral(src, quoteIndex);
      if (literal == null || !isProse(literal)) continue;
      final line = lineOf(src, quoteIndex);
      if (ignoredLines.contains(line)) continue;
      hits.add((line, literal));
    }
    return hits;
  }

  List<(int, String)> scan(File file) => scanSource(file.readAsStringSync());

  test('lib exists (guard runs from the app package root)', () {
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'Run this test from the app/ package (flutter test cwd).',
    );
  });

  /// Every file the guard judges, keyed by its `lib/`-relative POSIX path: all
  /// of `lib/` except the generated `lib/l10n/`.
  Map<String, File> guardedFiles() {
    final files = <String, File>{};
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path
          .replaceFirst(RegExp(r'^lib[/\\]'), 'lib/')
          .replaceAll('\\', '/');
      final relFromLib = rel.substring('lib/'.length);
      // Generated localizations are the translation source, not a leak.
      if (relFromLib.startsWith('l10n/')) continue;
      files[relFromLib] = entity;
    }
    return files;
  }

  test('the walk covers main.dart and lib/src but not generated l10n', () {
    // main.dart hid the integrity banner from this guard while it only walked
    // lib/src (#1396); losing it from the walk again must fail loudly.
    final files = guardedFiles().keys;
    expect(files, contains('main.dart'));
    expect(files, contains('src/update/update_banner.dart'));
    expect(files.where((f) => f.startsWith('l10n/')), isEmpty);
  });

  test('no hardcoded user-facing strings outside the allow-list', () {
    final offenders = <String, List<(int, String)>>{};
    for (final entry in guardedFiles().entries) {
      if (hardcodedUiStringAllowlist.contains(entry.key)) continue;
      final hits = scan(entry.value);
      if (hits.isNotEmpty) offenders[entry.key] = hits;
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

  group('scanner', () {
    test('flags a literal behind a conditional inside Text(...)', () {
      final hits = scanSource(
        'Widget w() => Text(\n'
        "  threw ? 'A check failed to complete.' : 'A check failed.',\n"
        ');\n',
      );
      expect(hits.map((h) => h.$2), [
        'A check failed to complete.',
        'A check failed.',
      ]);
    });

    test('flags a literal beside a localized value', () {
      expect(scanSource("Text(l10n.title + 'Suffix');"), hasLength(1));
    });

    test('flags a literal in a conditional whose first branch is l10n', () {
      expect(scanSource("Text(ok ? l10n.done : 'Not done');"), hasLength(1));
    });

    test('ignores localized text, interpolations and nested call args', () {
      expect(scanSource('Text(l10n.title);'), isEmpty);
      expect(scanSource("Text(l10n.count('items'));"), isEmpty);
      expect(scanSource(r"Text('$count');"), isEmpty);
      expect(scanSource(r"Text('${a ? 'x' : 'y'}');"), isEmpty);
      expect(
        scanSource("Text(l10n.x, style: TextStyle(fontFamily: 'Mono'));"),
        isEmpty,
      );
    });

    test('flags literals in a grouped (parenthesised) conditional', () {
      // A grouping paren is not a call: nothing is being passed to a function
      // the guard cannot see into, so the branches are still Text's own.
      expect(
        scanSource(
          "Text((failed ? 'English failure' : 'English fallback'));",
        ).map((h) => h.$2),
        ['English failure', 'English fallback'],
      );
      expect(
        scanSource("Text(a ? (b ? 'First one' : 'Second one') : l10n.q);"),
        hasLength(2),
      );
    });

    test('ignores a grouped conditional passed to another call', () {
      expect(scanSource("Text((l10n.count('items')));"), isEmpty);
      expect(scanSource("Text(l10n.x((y ? 'no way' : 'yes way')));"), isEmpty);
    });

    test('honours // i18n-ignore on the literal line', () {
      expect(scanSource("Text('Aa'); // i18n-ignore"), isEmpty);
    });
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
      'src/screens/settings/appearance_section.dart',
      'src/screens/settings/defaults_section.dart',
      'src/screens/settings/about_section.dart',
      'src/screens/settings/updates_section.dart',
      'src/screens/settings/dialect_section.dart',
      'src/widgets/import_gap_badge.dart',
      // Small global/shared chrome fully localized in L5.
      'src/screens/app_shell.dart',
      'src/utils/confirm_delete.dart',
      'src/utils/launch_external_url.dart',
      'src/widgets/app_bootstrap.dart',
      'src/widgets/color_edit_dialog.dart',
      // Formation-colours screen: prose localized in L5 (its formationShapeLabel
      // helper-swap was already in place).
      'src/screens/formation_colors_screen.dart',
    };
    final leaked = l5Targets.intersection(hardcodedUiStringAllowlist);
    expect(
      leaked,
      isEmpty,
      reason: 'L5 target files must not be allow-listed: $leaked',
    );
  });
}
