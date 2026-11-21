import 'package:compendium_app/src/widgets/notice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, NoticeKind kind, {String? title}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light()),
        home: Scaffold(
          body: NoticeCard(
            key: const ValueKey('notice'),
            kind: kind,
            title: title,
            child: const Text('body'),
          ),
        ),
      ),
    );
  }

  Color? fill(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('notice')),
        matching: find.byType(Container),
      ),
    );
    return (box.decoration! as BoxDecoration).color;
  }

  testWidgets('each kind uses its own container colour and icon', (
    tester,
  ) async {
    const scheme = ColorScheme.light();
    await pump(tester, NoticeKind.warning);
    expect(fill(tester), scheme.tertiaryContainer);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);

    await pump(tester, NoticeKind.error);
    expect(fill(tester), scheme.errorContainer);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await pump(tester, NoticeKind.info);
    expect(fill(tester), scheme.secondaryContainer);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('is flat: no Card, and the title shows above the body', (
    tester,
  ) async {
    await pump(tester, NoticeKind.warning, title: 'Heads up');
    expect(find.byType(Card), findsNothing);
    expect(find.text('Heads up'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });
}
