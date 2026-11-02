import 'package:compendium_app/src/theme/keyboard_dismiss.dart';
import 'package:compendium_app/src/widgets/readable_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget body, {bool app = true}) {
  return tester.pumpWidget(
    MaterialApp(
      scrollBehavior: app ? const AppScrollBehavior() : null,
      home: Scaffold(body: body),
    ),
  );
}

Future<void> _dragDown(WidgetTester tester) async {
  // Scroll off the top edge first: a clamped list at offset 0 emits no scroll
  // updates for a downward drag, so nothing could dismiss the keyboard.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
  await tester.pump();
  await tester.tap(find.byType(TextField));
  await tester.pump();
  expect(tester.testTextInput.isVisible, isTrue);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 50));
  await tester.pump();
}

void main() {
  final fields = <String, Widget Function()>{
    'plain ListView': () => ListView(
      children: [
        for (var i = 0; i < 12; i++) Text('$i'),
        const TextField(),
        for (var i = 0; i < 40; i++) Text('$i'),
      ],
    ),
    'SingleChildScrollView': () => SingleChildScrollView(
      child: Column(
        children: [
          for (var i = 0; i < 12; i++) Text('$i'),
          const TextField(),
          for (var i = 0; i < 40; i++) Text('$i'),
        ],
      ),
    ),
    'ReadableListView': () => ReadableListView(
      children: [
        for (var i = 0; i < 12; i++) Text('$i'),
        const TextField(),
        for (var i = 0; i < 40; i++) Text('$i'),
      ],
    ),
  };

  for (final e in fields.entries) {
    testWidgets('dragging dismisses the keyboard: ${e.key}', (tester) async {
      await _pump(tester, e.value());
      await _dragDown(tester);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  }

  testWidgets('without AppScrollBehavior the keyboard stays (guard can fail)', (
    tester,
  ) async {
    await _pump(tester, fields['plain ListView']!(), app: false);
    await _dragDown(tester);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
