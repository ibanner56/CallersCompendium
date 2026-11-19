import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spacing comes from `AppSpacing` (2 / 4 / 8 / 12 / 16 / 24 / 32 / 48), so a
/// gap between two controls is the same size wherever it appears and tracks one
/// edit to the scale.
///
/// A number written inside an `EdgeInsets` / `EdgeInsetsDirectional` call is a
/// spacing nobody chose. `0` is allowed (no space at all is not a magnitude).
/// There is no allow-list and no ceiling above zero: a count that rises fails
/// the build, and the baseline is zero. `tools/codemod/spacing_tokens.py`
/// rewrites the mechanical cases. (`pw.EdgeInsets` in the PDF export is in PDF
/// points and is out of scope.)
final RegExp _call = RegExp(r'(?<![\w.])EdgeInsets(?:Directional)?\.\w+\(');
final RegExp _magnitude = RegExp(
  r'(?<![\w.$])(?:0*[1-9]\d*(?:\.\d+)?|0\.\d*[1-9]\d*)(?![\w.])',
);

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// The 1-based lines of [source] holding an `EdgeInsets` call that carries a
/// non-zero number literal.
List<int> literalSpacingLines(String source) {
  final code = _stripComments(source);
  final lines = <int>[];
  for (final m in _call.allMatches(code)) {
    var depth = 1;
    var i = m.end;
    while (depth > 0 && i < code.length) {
      final c = code[i];
      if (c == "'" || c == '"') {
        i++;
        while (i < code.length && code[i] != c) {
          i += code[i] == r'\' ? 2 : 1;
        }
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
      i++;
    }
    if (_magnitude.hasMatch(code.substring(m.end, i - 1))) {
      lines.add('\n'.allMatches(code.substring(0, m.start)).length + 1);
    }
  }
  return lines;
}

void main() {
  test('screens and widgets space with AppSpacing tokens', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/')) continue;
      for (final line in literalSpacingLines(entity.readAsStringSync())) {
        offenders.add('$path:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use an AppSpacing token (xxxs 2, xxs 4, xs 8, sm 12, md 16, lg 24, '
          'xl 32, xxl 48), or AppSpacing.fabClearance under a floating button.',
    );
  });

  test('the scan sees a literal and ignores tokens, zero and comments', () {
    expect(literalSpacingLines('p: EdgeInsets.all(16),'), [1]);
    expect(literalSpacingLines('p: const EdgeInsets.only(left: 6),'), [1]);
    expect(
      literalSpacingLines(
        'x\np: EdgeInsets.fromLTRB(AppSpacing.md, 0, 0, 24),',
      ),
      [2],
    );
    expect(literalSpacingLines('p: EdgeInsets.all(AppSpacing.md + 4),'), [1]);
    expect(
      literalSpacingLines(
        'p: EdgeInsets.symmetric(\n'
        '  horizontal: AppSpacing.md, // 16\n'
        '  vertical: 0,\n'
        '),\n'
        'q: pw.EdgeInsets.all(8),\n'
        'r: EdgeInsets.zero,\n',
      ),
      isEmpty,
    );
  });
}
