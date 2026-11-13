import 'package:flutter_test/flutter_test.dart';

/// Pumps until [condition] holds, giving real (wall-clock) async work such as
/// file I/O time to finish between pumps.
///
/// `FakeAsync` never completes real I/O, so each round pumps the widget tree
/// and then yields to the real event loop via [WidgetTester.runAsync]. The wait
/// is bounded by a wall-clock [timeout] (generous, so a slow CI runner does not
/// flake), not by an iteration count; on expiry it fails with
/// "Timed out … waiting for [description]" instead of a bare finder mismatch.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 20),
}) async {
  final watch = Stopwatch()..start();
  while (true) {
    await tester.pump();
    if (condition()) return;
    if (watch.elapsed >= timeout) {
      fail(
        'Timed out after ${timeout.inSeconds}s of wall-clock time waiting for '
        '$description.',
      );
    }
    await tester.runAsync(() => Future<void>.delayed(interval));
  }
}

/// [pumpUntil] specialised to a [Finder] that must match at least one widget.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  description: finder.describeMatch(Plurality.one),
  timeout: timeout,
);
