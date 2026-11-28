import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_scan.dart';

/// Corner radii come from `AppShapes` (8 / 12 / 16, dialogs 28, pills), so a
/// card, a field and a badge round alike across the app.
///
/// A number literal anywhere in the arguments of a `BorderRadius.circular`,
/// `BorderRadiusDirectional.circular`, `Radius.circular` or
/// `Radius.elliptical` call in a screen or widget is a radius nobody chose:
/// written on one line or across several, alone or behind a condition
/// (`wide ? 12 : 8`). There is no allow-list: even the theme picker's
/// miniatures and the skeleton bones use the tokens.
/// `tools/codemod/spacing_tokens.py` rewrites the mechanical cases.
///
/// Not caught: a number given a name first (`const r = 12.0;` then
/// `Radius.circular(r)`). Following a value through a variable is more than a
/// text scan can do reliably, and the name is at least a choice someone made
/// on purpose, where review can see it.
final RegExp _radiusCall = RegExp(
  r'(?<![\w.])(?:BorderRadius(?:Directional)?\.circular|'
  r'Radius\.(?:circular|elliptical))\s*\(',
);
final RegExp _number = RegExp(r'(?<![\w.$])\d');

/// The lines of [source] that write a literal radius, ignoring comments and
/// strings.
List<int> literalRadiusLines(String source) {
  final code = codeOnly(source);
  final lines = <int>{};
  for (final m in _radiusCall.allMatches(code)) {
    final close = closingDelimiter(code, m.end - 1);
    if (_number.hasMatch(code.substring(m.end, close))) {
      lines.add(lineAt(source, m.start));
    }
  }
  return lines.toList()..sort();
}

void main() {
  test('screens and widgets round corners with AppShapes tokens', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/') || path.startsWith('lib/src/theme/')) {
        continue;
      }
      for (final line in literalRadiusLines(entity.readAsStringSync())) {
        offenders.add('$path:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use AppShapes.borderRadiusSmall / Medium / Large, or '
          'BorderRadius.circular(AppShapes.radiusFull).',
    );
  });

  test('the scan sees a literal radius and ignores tokens and comments', () {
    expect(literalRadiusLines('a: BorderRadius.circular(14),'), [1]);
    expect(literalRadiusLines('a: const Radius.circular(6),'), [1]);
    expect(
      literalRadiusLines(
        'a: BorderRadius.circular(AppShapes.radiusSmall),\n'
        '// BorderRadius.circular(14)\n'
        "b: Text('Radius.circular(3)'),\n"
        '/* Radius.elliptical(2, 3) */\n',
      ),
      isEmpty,
    );
  });

  test('the scan sees a literal radius in other shapes', () {
    // Across lines, as `dart format` writes a long call.
    expect(literalRadiusLines('a: BorderRadius.circular(\n  12,\n),'), [1]);
    // Behind a condition, or beside a token.
    expect(
      literalRadiusLines(
        'a: BorderRadius.circular(wide ? AppShapes.radiusLarge : 8),',
      ),
      [1],
    );
    expect(literalRadiusLines('a: Radius.elliptical(4, AppShapes.x),'), [1]);
    expect(literalRadiusLines('a: BorderRadiusDirectional.circular(6),'), [1]);
    expect(
      literalRadiusLines('a: Radius.elliptical(AppShapes.a, AppShapes.b),'),
      isEmpty,
    );
  });
}
