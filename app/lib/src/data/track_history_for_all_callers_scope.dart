import 'package:flutter/widgets.dart';

/// Exposes the "Track calling history for all callers" General setting
/// (issue #583) as a live [ValueNotifier] to the widget tree.
///
/// When `false` (the default) and a default caller is configured, a dance's
/// calling history and counts include programs whose host caller matches that
/// default caller **and** programs with a NULL or blank caller (treated as the
/// user's own; #850 supersedes the original #583 exclusion); when `true` — or
/// when no default caller is set — history tracks every program that contains
/// the dance, as it always has.
/// Descendants that call [TrackHistoryForAllCallersScope.of] rebuild
/// automatically when the setting changes (live update), so an open Collection
/// list or dance-detail screen re-derives its counts/history immediately.
///
/// Use [TrackHistoryForAllCallersScope.notifierOf] when you need to *change*
/// the setting (e.g. from the settings screen).
class TrackHistoryForAllCallersScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const TrackHistoryForAllCallersScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether calling history tracks all callers. Registers a rebuild dependency
  /// so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [TrackHistoryForAllCallersScope] ancestor, so callers — and tests that
  /// don't wire the scope — fall back to the scoped-to-default-caller behavior
  /// only when a default caller is actually configured (the resolver treats an
  /// absent default caller as "track all" regardless).
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TrackHistoryForAllCallersScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<TrackHistoryForAllCallersScope>();
    if (scope == null) {
      throw FlutterError(
        'TrackHistoryForAllCallersScope.notifierOf() called with a context '
        'that has no TrackHistoryForAllCallersScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
