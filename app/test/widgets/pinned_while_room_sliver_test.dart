import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/pinned_while_room_sliver.dart';

/// Opaque, so a hit test stops on it rather than on a row behind it.
Widget _header(String key, double height) => ColoredBox(
  key: ValueKey(key),
  color: Colors.blue,
  child: SizedBox(height: height),
);

/// A 600-high scroll view: header A, a 200-high gap, header B, then 50 rows.
Future<ScrollController> _pump(
  WidgetTester tester, {
  double a = 50,
  double b = 30,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: CustomScrollView(
            controller: controller,
            slivers: [
              PinnedWhileRoomSliver(child: _header('a', a)),
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
              PinnedWhileRoomSliver(child: _header('b', b)),
              SliverList.builder(
                itemCount: 50,
                itemBuilder: (context, i) => SizedBox(
                  key: ValueKey('row-$i'),
                  height: 40,
                  child: Text('Row $i'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return controller;
}

/// Top of [key] relative to the top of the 600-high viewport.
double _top(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key))).dy -
    tester.getTopLeft(find.byType(CustomScrollView)).dy;

/// The render object of the [PinnedWhileRoomSliver] around [key]: a
/// stateless widget reports the first render object below it.
bool _pinned(WidgetTester tester, String key) => tester
    .renderObject<RenderPinnedWhileRoomSliver>(
      find.ancestor(
        of: find.byKey(ValueKey(key), skipOffstage: false),
        matching: find.byType(PinnedWhileRoomSliver, skipOffstage: false),
      ),
    )
    .pinned;

void main() {
  testWidgets('headers that fit stack at the top as the list scrolls', (
    tester,
  ) async {
    final controller = await _pump(tester);
    expect(_top(tester, 'b'), 250);

    controller.jumpTo(1000);
    await tester.pump();

    expect(_top(tester, 'a'), 0);
    expect(_top(tester, 'b'), 50);
    expect(find.byKey(const ValueKey('a')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('b')).hitTestable(), findsOneWidget);
  });

  testWidgets('a header that would cover more than half the viewport scrolls '
      'away instead', (tester) async {
    final controller = await _pump(tester, a: 320);
    expect(_pinned(tester, 'a'), isFalse);

    controller.jumpTo(1000);
    await tester.pump();

    expect(find.byKey(const ValueKey('a')).hitTestable(), findsNothing);
    // B still fits on its own, and pins at the very top.
    expect(_top(tester, 'b'), 0);
  });

  testWidgets('a second header pins only while both together fit', (
    tester,
  ) async {
    // 200 + 150 = 350, more than half of 600: A stays, B scrolls under it.
    final controller = await _pump(tester, a: 200, b: 150);

    controller.jumpTo(1000);
    await tester.pump();

    expect(_top(tester, 'a'), 0);
    expect(_pinned(tester, 'a'), isTrue);
    expect(_pinned(tester, 'b'), isFalse);
    expect(find.byKey(const ValueKey('b')).hitTestable(), findsNothing);
  });

  testWidgets('a second header that cannot pin slides smoothly under the '
      'first, rather than sticking and then jumping', (tester) async {
    // 200 + 150 is more than half of 600, so B must never pin; it reaches
    // A's bottom edge at scroll 200 and is under A from scroll 350.
    final controller = await _pump(tester, a: 200, b: 150);
    double? previous;
    for (var offset = 150.0; offset <= 400; offset++) {
      controller.jumpTo(offset);
      await tester.pump();
      expect(_pinned(tester, 'b'), isFalse, reason: 'at scroll $offset');
      final top = _top(tester, 'b');
      expect(top, 400 - offset, reason: 'at scroll $offset');
      if (previous != null) expect(previous - top, 1);
      previous = top;
    }
  });

  testWidgets('revealing a row scrolls it clear of the pinned headers', (
    tester,
  ) async {
    final controller = await _pump(tester);
    controller.jumpTo(1000);
    await tester.pump();

    // Row 20 now lies under the headers or above the viewport.
    await tester.ensureVisible(find.byKey(const ValueKey('row-20')));
    await tester.pump();

    expect(_top(tester, 'row-20'), 80);
  });
}
