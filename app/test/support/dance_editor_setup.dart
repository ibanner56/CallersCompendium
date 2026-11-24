import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the dance editor's folded setup panel (Credits, formation and
/// music), so its fields are on stage and hittable. Does nothing when it is
/// already open, or while a dialog (such as the draft-restore prompt) covers
/// the editor, where a tap would land on the dialog's barrier instead.
Future<void> openDanceEditorSetup(WidgetTester tester) async {
  if (find.byType(Dialog).evaluate().isNotEmpty) return;
  final summary = find.byKey(const ValueKey('setup-summary'));
  if (summary.evaluate().isEmpty) return;
  await tester.ensureVisible(summary);
  await tester.tap(summary);
  await tester.pumpAndSettle();
}
