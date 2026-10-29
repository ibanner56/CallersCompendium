import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts the search-tool chip [key] is in the row but greyed out: present,
/// not tappable, and not announced as an enabled button.
void expectPanelDisabled(WidgetTester tester, String key) {
  final chip = find.byKey(ValueKey(key));
  expect(chip, findsOneWidget, reason: '$key stays in the row');
  expect(
    tester.widget<ActionChip>(chip).onPressed,
    isNull,
    reason: '$key cannot be opened',
  );
}
