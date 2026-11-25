import 'package:flutter/widgets.dart';

export 'settings_keys.dart' show kShowRepertoireDashboardKey;

/// Exposes the Experimental "Repertoire" switch (#2357) as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true`, Collection's More actions menu offers a Repertoire item that
/// opens the read-only Repertoire page. When `false` (the default) the item is
/// absent. Either way no navigation destination is added.
///
/// Use [ShowRepertoireScope.notifierOf] to change the setting.
class ShowRepertoireScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ShowRepertoireScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether the switch is on. Registers a rebuild dependency. Returns
  /// `false`, the default, when there is no [ShowRepertoireScope] ancestor.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShowRepertoireScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ShowRepertoireScope>();
    if (scope == null) {
      throw FlutterError(
        'ShowRepertoireScope.notifierOf() called with a context that has no '
        'ShowRepertoireScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
