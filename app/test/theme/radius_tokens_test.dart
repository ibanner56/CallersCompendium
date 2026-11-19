import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Corner radii come from `AppShapes` (8 / 12 / 16, dialogs 28, pills), so a
/// card, a field and a badge round alike across the app.
///
/// A `BorderRadius.circular(<number>)` or `Radius.circular(<number>)` literal
/// in a screen or widget is a radius nobody chose. There is no allow-list:
/// even the theme picker's miniatures and the skeleton bones use the tokens.
/// `tools/codemod/spacing_tokens.py` rewrites the mechanical cases.
final RegExp _literalRadius = RegExp(r'(?:Border)?Radius\.circular\(\s*\d');

/// The lines of [source] that write a literal radius, ignoring comments.
List<int> literalRadiusLines(String source) {
  final lines = source.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_literalRadius.hasMatch(lines[i].split('//').first)) i + 1,
  ];
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
        '// BorderRadius.circular(14)\n',
      ),
      isEmpty,
    );
  });
}
