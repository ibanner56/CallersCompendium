import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Mark all performed sets the status" Calling
/// history setting. Stored as a `bool`; **unset means on** (`true`), the
/// product default (GIG-12).
const String kMarkAllSetsStatusKey = 'mark_all_sets_status';

/// Exposes the "Mark all performed sets the status" setting as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true` (the default), Mark all performed — in the program editor and
/// the program view — also sets the program's status to Performed, and its Undo
/// puts the marks and the status back together. When `false`, Mark all
/// performed leaves the status alone. Descendants that call
/// [MarkAllSetsStatusScope.of] rebuild automatically when the setting changes.
///
/// Use [MarkAllSetsStatusScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class MarkAllSetsStatusScope extends InheritedNotifier<ValueNotifier<bool>> {
  const MarkAllSetsStatusScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether Mark all performed also sets the program's status. Registers a
  /// rebuild dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `true` (the on-by-default behaviour) when there is no
  /// [MarkAllSetsStatusScope] ancestor, so callers — and tests that don't wire
  /// the scope — get the product default.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MarkAllSetsStatusScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Reads the setting without registering a rebuild dependency, for action
  /// handlers that run outside `build`. Same default as [of].
  static bool read(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<MarkAllSetsStatusScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<MarkAllSetsStatusScope>();
    if (scope == null) {
      throw FlutterError(
        'MarkAllSetsStatusScope.notifierOf() called with a context that has '
        'no MarkAllSetsStatusScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
