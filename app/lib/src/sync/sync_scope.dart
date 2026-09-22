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
}
