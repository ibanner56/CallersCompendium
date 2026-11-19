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

/// Sets a phone-sized screen [width] wide, the text scale to [scale] and, when
/// [keyboard] is true, a 300 dp on-screen keyboard inset.
Future<void> atPhoneSize(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool keyboard = false,
}) async {
  final size = Size(width, 844);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  if (keyboard) {
    // View insets are physical pixels.
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
  }
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetViewInsets();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    return tester.binding.setSurfaceSize(null);
  });
}

/// The phone conditions [expectFabClearsLastRow] is checked under: the
/// default text, large text, large text with the keyboard open, and the same
/// on a small phone.
const fabClearanceCases =
    <({String name, double width, double scale, bool keyboard})>[
      (name: 'default text', width: 390, scale: 1, keyboard: false),
      (name: '2x text', width: 390, scale: 2, keyboard: false),
      (
        name: '2x text with the keyboard open',
        width: 390,
        scale: 2,
        keyboard: true,
      ),
      (
        name: '320 wide, 2x text, keyboard open',
        width: 320,
        scale: 2,
        keyboard: true,
      ),
    ];
