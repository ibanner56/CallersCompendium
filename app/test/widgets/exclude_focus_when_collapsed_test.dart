import 'package:compendium_app/src/widgets/exclude_focus_when_collapsed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tile built like the Dance editor's and Program builder's "More details":
/// collapsed to begin with, and keeping its children's state while collapsed.
Widget _tile(ExpansibleController controller, FocusNode inside) => MaterialApp(
  home: Scaffold(
    body: ExpansionTile(
      controller: controller,
      title: const Text('More details'),
      maintainState: true,
      children: [
        ExcludeFocusWhenCollapsed(
          controller: controller,
          builder: (_) =>
              TextField(key: const ValueKey('inside'), focusNode: inside),
        ),
      ],
    ),
  ),
);

void main() {
  late ExpansibleController controller;
  late FocusNode inside;

  setUp(() {
    controller = ExpansibleController();
    inside = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    inside.dispose();
  });

  testWidgets('a collapsed tile keeps its children, and Tab does not enter '
      'them', (tester) async {
    await tester.pumpWidget(_tile(controller, inside));
    // The state is kept (the field is in the tree) ...
    expect(find.byKey(const ValueKey('inside'), skipOffstage: false), findsOne);
    // ... but it cannot take focus, and Tab never lands on it.
    inside.requestFocus();
    await tester.pump();
    expect(inside.hasFocus, isFalse, reason: 'a collapsed field took focus');
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(inside.hasFocus, isFalse, reason: 'Tab reached a hidden field');
    }
  });

  testWidgets('an expanded tile joins the focus order, and collapsing it '
      'takes focus back out', (tester) async {
    await tester.pumpWidget(_tile(controller, inside));
    controller.expand();
    await tester.pumpAndSettle();

    inside.requestFocus();
    await tester.pump();
    expect(inside.hasFocus, isTrue, reason: 'an open field could not focus');

    controller.collapse();
    await tester.pumpAndSettle();
    expect(
      inside.hasFocus,
      isFalse,
      reason: 'focus stayed in a field that was collapsed away',
    );
  });

  testWidgets('a DropdownMenu built while collapsed can take focus once the '
      'tile opens', (tester) async {
    // DropdownMenu reads its focus node's effective canRequestFocus when it
    // builds, and its text field writes what it read onto the node. Built under
    // a collapsed tile that is false. The wrapper must build the field again
    // when the tile opens, or the field stays unfocusable and typing in it does
    // nothing (the Program builder's dialect picker did exactly that).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExpansionTile(
              controller: controller,
              title: const Text('More details'),
              maintainState: true,
              children: [
                ExcludeFocusWhenCollapsed(
                  controller: controller,
                  builder: (_) => DropdownMenu<int>(
                    focusNode: inside,
                    enableFilter: true,
                    requestFocusOnTap: true,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 1, label: 'One'),
                      DropdownMenuEntry(value: 2, label: 'Two'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.expand();
    await tester.pumpAndSettle();

    expect(inside.canRequestFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'Tw');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Tw',
      reason: 'typing did not reach the field',
    );
  });
}
