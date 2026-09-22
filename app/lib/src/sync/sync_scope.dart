import 'package:flutter/widgets.dart';

import 'sync_controller.dart';

/// Exposes the [SyncController] to the widget tree, mirroring `UpdateScope`.
class SyncScope extends InheritedNotifier<SyncController> {
  const SyncScope({
    super.key,
    required SyncController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering a rebuild dependency.
  static SyncController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SyncScope>();
    if (scope == null) {
      throw FlutterError(
        'SyncScope.of() called with a context that has no SyncScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// The controller, registering a rebuild dependency, or `null` if this
  /// context has no [SyncScope] ancestor. For a surface that only needs Device
  /// Sync state for an optional feature (the §6.13 partial-venue hint) rather
  /// than requiring the whole app to be wired for sync — including a screen
  /// test harness that has no reason to set one up.
  static SyncController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()?.notifier;
}
