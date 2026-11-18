import 'package:flutter/material.dart';

import '../data/reduce_motion_scope.dart';

/// Motion tokens: the five animation durations the app
/// uses, named once so a new animation picks a step rather than a fresh
/// number. Debounce and polling intervals are timers, not motion, and stay
/// where they are.
///
/// Every animated site still checks Reduce motion itself (most snap with
/// `Duration.zero`); [styleFor] is the shared answer for dialogs, sheets and
/// expansion tiles, whose motion is set per call through an [AnimationStyle].
abstract final class AppMotion {
  /// Small UI feedback: a hover glyph fading in, a list scrolling one row.
  static const Duration quick = Duration(milliseconds: 120);

  /// Scrolling a field or error into view.
  static const Duration short = Duration(milliseconds: 200);

  /// Scrolling to a heading in a long document.
  static const Duration medium = Duration(milliseconds: 250);

  /// One beat of a repeating pulse (the tap-tempo metronome).
  static const Duration long = Duration(milliseconds: 500);

  /// One sweep of the loading-skeleton shimmer.
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// [AnimationStyle.noAnimation] when Reduce motion is in effect at
  /// [context] (the in-app switch, else the OS setting), otherwise `null` so
  /// the component keeps its Material default. Pass it as `animationStyle:`
  /// to `showDialog` and `ExpansionTile`, and as `sheetAnimationStyle:` to
  /// `showModalBottomSheet`.
  ///
  /// Reads without registering a dependency, so it is safe in the event
  /// handlers that open dialogs and sheets.
  static AnimationStyle? styleFor(BuildContext context) =>
      ReduceMotionScope.read(context) ? AnimationStyle.noAnimation : null;
}
