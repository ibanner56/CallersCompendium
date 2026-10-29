import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Show mark-performed toggles" Calling history
/// setting. Stored as a `bool`; **unset means on** (`true`), the product
/// default.
const String kShowPerformedTogglesKey = 'show_performed_toggles';

/// Exposes the "Show mark-performed toggles" setting as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true` (the default), each dance row in the program view carries a
/// toggle that marks that dance performed or not without opening the editor.
/// When `false`, rows show their performed state as a read-only check and offer
/// no toggle. Descendants that call [ShowPerformedTogglesScope.of] rebuild
/// automatically when the setting changes (live update).
///
/// Use [ShowPerformedTogglesScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class ShowPerformedTogglesScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ShowPerformedTogglesScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether program rows should offer a mark-performed toggle. Registers a
  /// rebuild dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `true` (the on-by-default behaviour) when there is no
  /// [ShowPerformedTogglesScope] ancestor, so callers — and tests that don't
  /// wire the scope — get the product default.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShowPerformedTogglesScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ShowPerformedTogglesScope>();
    if (scope == null) {
      throw FlutterError(
        'ShowPerformedTogglesScope.notifierOf() called with a context that has '
        'no ShowPerformedTogglesScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
