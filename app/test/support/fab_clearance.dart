import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scrolls [list] to its end and expects [lastRow] to sit wholly above the
/// screen's floating button, so the button never covers the last row.
///
/// Fails, rather than passing vacuously, when the list is too short to scroll:
/// a list that fits on the screen proves nothing about the end of a long one.
Future<void> expectFabClearsLastRow(
  WidgetTester tester, {
  required Finder list,
  required Finder lastRow,
}) async {
  final fab = find.byType(FloatingActionButton);
  expect(fab, findsOneWidget, reason: 'the screen floats one button');
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(
    position.maxScrollExtent,
    greaterThan(0),
    reason: 'the list must be long enough to reach under the button',
  );
  // A lazily built list learns its full extent as it builds, so jump until
  // the end stops moving.
  for (var i = 0; i < 20; i++) {
    final end = position.maxScrollExtent;
    position.jumpTo(end);
    await tester.pump();
    if (position.maxScrollExtent == end) break;
  }
  expect(lastRow, findsOneWidget);
  expect(
    tester.getRect(lastRow).bottom,
    lessThanOrEqualTo(tester.getRect(fab).top),
    reason: 'the floating button covers the last row',
  );
}

/// Runs [body] at phone width with the text scale at [scale] and, when
/// [keyboard] is true, the on-screen keyboard's inset applied.
Future<void> atPhoneSize(
  WidgetTester tester, {
  double scale = 1,
  bool keyboard = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  tester.view.physicalSize =
      const Size(390, 844) * tester.view.devicePixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetViewInsets();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    return tester.binding.setSurfaceSize(null);
  });
}

/// The phone conditions [expectFabClearsLastRow] is checked under: the
/// default text, large text, and large text with the keyboard open.
const fabClearanceCases = <({String name, double scale, bool keyboard})>[
  (name: 'default text', scale: 1, keyboard: false),
  (name: '2x text', scale: 2, keyboard: false),
  (name: '2x text with the keyboard open', scale: 2, keyboard: true),
];
