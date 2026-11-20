import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps a dance-detail secondary action (`duplicate-dance`, `reimport-dance`,
/// `delete-dance`) by its key, opening the `dance-actions-overflow` menu first.
///
/// On every width these actions live in the overflow menu, so a test that
/// taps them must open it; the menu entries carry the same keys the old icon
/// buttons did.
Future<void> tapDanceOverflowAction(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const ValueKey('dance-actions-overflow')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)).last);
  await tester.pumpAndSettle();
}
