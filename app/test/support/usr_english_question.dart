import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the question a Caller's Companion `.USR` import asks before it
/// plans a file, whether its dances are English country dances (ADR-006 W6),
/// and fails when the question is not showing. [english] taps Yes, else No.
/// [settle] pumps until the screen settles after; a plan running on a real
/// isolate passes false and waits on its own condition instead.
Future<void> answerUsrEnglishQuestion(
  WidgetTester tester, {
  bool english = false,
  bool settle = true,
}) async {
  expect(
    find.byKey(const ValueKey('import-usr-english-question')),
    findsOneWidget,
  );
  await tester.tap(
    find.byKey(
      ValueKey(english ? 'import-usr-english-yes' : 'import-usr-english-no'),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
