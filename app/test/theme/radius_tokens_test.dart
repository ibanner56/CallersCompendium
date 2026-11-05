import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Corner radii come from `AppShapes` (8 / 12 / 16, dialogs 28), so a card, a
/// field and a badge round alike across the app (U11).
///
/// A `BorderRadius.circular(<number>)` literal in a screen or widget is a
/// radius nobody chose. The files below keep theirs on purpose, each for a
/// shape that is not a control: a miniature of a theme, a skeleton bone or a
/// pill. A new literal fails this test until it either uses a
/// token or is justified here.
const Set<String> _allowed = {
  // Miniatures of a theme's own cards, chips and focus ring: they mimic what
  // the theme draws, so they scale with its look, not the app's.
  'lib/src/screens/settings/appearance_section.dart',
  // A pill-shaped colour swatch.
  'lib/src/screens/theme_editor_screen.dart',
  // A placeholder bone is sized to the content it stands in for; its default
  // radius is a placeholder's, not a control's.
  'lib/src/widgets/skeleton.dart',
};

void main() {
  test('screens and widgets round corners with AppShapes tokens', () {
    final literal = RegExp(r'(?:Border)?Radius\.circular\(\s*\d');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/') || path.startsWith('lib/src/theme/')) {
        continue;
      }
      if (_allowed.contains(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use AppShapes.borderRadiusSmall / Medium / Large, or add the file '
          'to the allow-list with the reason.',
    );
  });

  test('every allow-listed file still has a literal radius', () {
    final literal = RegExp(r'(?:Border)?Radius\.circular\(\s*\d');
    final stale = [
      for (final path in _allowed)
        if (!File(path).readAsStringSync().contains(literal)) path,
    ];
    expect(stale, isEmpty, reason: 'Remove them from the allow-list.');
  });
}
