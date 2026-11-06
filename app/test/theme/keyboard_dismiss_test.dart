import 'package:compendium_app/src/theme/keyboard_dismiss.dart';
import 'package:compendium_app/src/widgets/readable_width.dart';
import 'package:flutter/gestures.dart';
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

Future<void> _focusFieldOffTheTop(WidgetTester tester) async {
  // Scroll off the top edge first: a clamped list at offset 0 emits no scroll
  // updates for a downward drag, so nothing could dismiss the keyboard.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
  await tester.pump();
  await tester.tap(find.byType(TextField));
  await tester.pump();
  expect(tester.testTextInput.isVisible, isTrue);
}

Future<void> _dragDown(WidgetTester tester) async {
  await _focusFieldOffTheTop(tester);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 50));
  await tester.pump();
}

/// A two-finger trackpad scroll down: pan-zoom events, which Flutter's drag
/// recognizers accept as a drag, and which raise no pointer-down that could
/// count as a tap outside the field.
Future<void> _trackpadScrollDown(WidgetTester tester) async {
  await _focusFieldOffTheTop(tester);
  final before = tester.getTopLeft(find.byType(TextField)).dy;
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(Scrollable).first),
    kind: PointerDeviceKind.trackpad,
  );
  for (var i = 0; i < 5; i++) {
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
  expect(
    tester.getTopLeft(find.byType(TextField)).dy,
    greaterThan(before),
    reason: 'the trackpad gesture must actually scroll the view',
  );
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

  final phones = TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  for (final e in fields.entries) {
    testWidgets('dragging dismisses the keyboard: ${e.key}', (tester) async {
      await _pump(tester, e.value());
      await _dragDown(tester);
      expect(tester.testTextInput.isVisible, isFalse);
    }, variant: phones);
  }

  // Flutter counts a trackpad as a drag device, so on a desktop the phone
  // default would unfocus the field being typed in. A desktop has no soft
  // keyboard to put away, so the field keeps focus.
  for (final e in fields.entries) {
    testWidgets(
      'a trackpad scroll keeps the field focused on a desktop: ${e.key}',
      (tester) async {
        await _pump(tester, e.value());
        await _trackpadScrollDown(tester);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );
      },
      variant: TargetPlatformVariant.desktop(),
    );
  }

  testWidgets('without AppScrollBehavior the keyboard stays (guard can fail)', (
    tester,
  ) async {
    await _pump(tester, fields['plain ListView']!(), app: false);
    await _dragDown(tester);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
