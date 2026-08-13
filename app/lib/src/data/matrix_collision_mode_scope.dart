import 'package:flutter/widgets.dart';

import '../screens/settings/settings_keys.dart'
    show kMatrixExactBeatCollisionKey;

/// Exposes the Programs "flag exact beat overlap only" setting
/// ([kMatrixExactBeatCollisionKey], issue #962) as a live [ValueNotifier] to
/// the widget tree.
///
/// When `true` (the default), the programming matrix's same-figure collision
/// check ([ProgramMatrix.isCollision] /
/// `MatrixCollisionMode.exactBeats`) flags a strictly-adjacent repeat only
/// when the move's beat span actually overlaps between the two dances. When
/// `false`, the matrix falls back to the original (#582) phrase-bucket check
/// (`MatrixCollisionMode.phrase`) — the move merely starting in the same named
/// phrase (A1/A2/B1/B2…). Descendants that call [MatrixCollisionModeScope.of]
/// rebuild automatically when the setting changes (live update — the #948
/// lesson: read the notifier's current value on every dependency change, not
/// just once at first load).
///
/// Use [MatrixCollisionModeScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class MatrixCollisionModeScope extends InheritedNotifier<ValueNotifier<bool>> {
  const MatrixCollisionModeScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether the matrix should use exact-beat-overlap collision detection.
  /// Registers a rebuild dependency so the caller rebuilds whenever the
  /// setting changes.
  ///
  /// Returns `true` (the on-by-default product behaviour, issue #962) when
  /// there is no [MatrixCollisionModeScope] ancestor, so callers — and tests
  /// that don't wire the scope — get the product default.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MatrixCollisionModeScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<MatrixCollisionModeScope>();
    if (scope == null) {
      throw FlutterError(
        'MatrixCollisionModeScope.notifierOf() called with a context that '
        'has no MatrixCollisionModeScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
