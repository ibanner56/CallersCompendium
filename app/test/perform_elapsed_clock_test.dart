import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/perform_elapsed_clock.dart';

void main() {
  late DateTime now;
  PerformElapsedClock make({int initialSeconds = 0, bool paused = false}) =>
      withClock(
        Clock(() => now),
        () =>
            PerformElapsedClock(initialSeconds: initialSeconds, paused: paused),
      );

  setUp(() => now = DateTime.utc(2026, 1, 1, 20));

  test('counts the time between samples, however long the gap', () {
    final clock = make(initialSeconds: 10);
    now = now.add(const Duration(minutes: 5, milliseconds: 400));
    expect(clock.seconds, 310);
    expect(clock.untilNextSecond, const Duration(milliseconds: 600));
  });

  test('time between pause and resume is not counted', () {
    final clock = make();
    now = now.add(const Duration(seconds: 3));
    clock.pause();
    expect(clock.isRunning, isFalse);
    now = now.add(const Duration(hours: 1));
    expect(clock.seconds, 3);
    clock.resume();
    now = now.add(const Duration(seconds: 2));
    expect(clock.seconds, 5);
  });

  test('starting paused counts nothing until resumed', () {
    final clock = make(initialSeconds: 42, paused: true);
    now = now.add(const Duration(minutes: 1));
    expect(clock.seconds, 42);
  });

  test('a system clock set back neither subtracts nor freezes', () {
    final clock = make();
    now = now.add(const Duration(seconds: 30));
    expect(clock.seconds, 30);
    now = now.subtract(const Duration(hours: 1));
    expect(clock.seconds, 30);
    now = now.add(const Duration(seconds: 4));
    expect(clock.seconds, 34);
  });
}
