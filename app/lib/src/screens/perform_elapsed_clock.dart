import 'package:clock/clock.dart';

/// Elapsed time for the Perform timing readouts, measured from the clock
/// rather than counted from timer ticks (post-audit integrity-6).
///
/// The Perform screens used to add one second per `Timer.periodic` tick. Dart
/// timers do not fire while an iOS app is suspended in the background, while a
/// desktop is asleep, or while the UI thread is janking, so every such interval
/// was silently lost from the program clock. This class instead accumulates
/// the time that passed between samples, so a sample taken after any gap
/// includes the whole gap. The screens keep a timer, but only to call
/// [seconds] and refresh the display about once a second.
///
/// **Time source.** Samples come from `package:clock`'s [clock], captured when
/// the instance is created. In the app that is the system wall clock, which
/// keeps advancing while the device sleeps. Dart's `Stopwatch` was rejected
/// because its monotonic source pauses during device sleep on iOS, macOS,
/// Linux and Android, which is one of the gaps this class exists to cover. In
/// tests, `fake_async` (and so `tester.pump`) controls [clock], so readouts
/// still advance deterministically.
///
/// **Clock changes.** A sample earlier than the previous one (the system clock
/// was set back) adds nothing and re-bases on the new time, so the readout
/// never runs backwards or freezes. A clock set forward is indistinguishable
/// from time spent asleep and is counted.
///
/// **Pause.** Time between [pause] and [resume] is not counted.
class PerformElapsedClock {
  /// Starts at [initialSeconds], running unless [paused].
  PerformElapsedClock({int initialSeconds = 0, bool paused = false})
    : _accumulated = Duration(seconds: initialSeconds) {
    if (!paused) _lastSample = _clock.now();
  }

  final Clock _clock = clock;
  Duration _accumulated;

  /// When time was last added to [_accumulated]; `null` while paused.
  DateTime? _lastSample;

  /// Whether time is currently being counted.
  bool get isRunning => _lastSample != null;

  /// Whole seconds counted so far, sampled now.
  int get seconds {
    _sample();
    return _accumulated.inSeconds;
  }

  /// How long until [seconds] next changes, sampled now; one second while
  /// paused. The screens schedule their display refresh with this, so the
  /// readout turns over on the second rather than up to a second late after a
  /// pause or a resume left a fraction of a second on the count.
  Duration get untilNextSecond {
    _sample();
    const second = Duration(seconds: 1);
    if (!isRunning) return second;
    return second -
        Duration(microseconds: _accumulated.inMicroseconds % 1000000);
  }

  /// Stops counting; the time up to now is kept.
  void pause() {
    _sample();
    _lastSample = null;
  }

  /// Starts counting again from now. A no-op while already running.
  void resume() {
    _lastSample ??= _clock.now();
  }

  void _sample() {
    final last = _lastSample;
    if (last == null) return;
    final now = _clock.now();
    final delta = now.difference(last);
    if (!delta.isNegative) _accumulated += delta;
    _lastSample = now;
  }
}
