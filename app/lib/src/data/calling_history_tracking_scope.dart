import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import 'require_performed_for_history_scope.dart';

/// The four performance-tracking toggles. They decide which slots date a
/// recency window and which date the history order; they never change what
/// counts as called (that is the two global gates). [callingHistoryTrackingOf]
/// folds the four into the value the repositories take.

/// "Recency only counts dated programs" (on by default).
class RecencyRequireEventDateScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const RecencyRequireEventDateScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The live value, registering a rebuild dependency. `true` with no scope
  /// above, so a test that does not wire it sees the default behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RecencyRequireEventDateScope>()
          ?.notifier
          ?.value ??
      true;

  /// The notifier, for the settings screen to change. Registers no rebuild
  /// dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<RecencyRequireEventDateScope>();
    if (scope == null) {
      throw FlutterError(
        'RecencyRequireEventDateScope.notifierOf() called with a context that has no '
        'RecencyRequireEventDateScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// "Recency only counts slots marked performed". `null` means the caller has not chosen, so it follows the global "require performed" setting; a stored value, either way, wins.
class RecencyRequirePerformedScope
    extends InheritedNotifier<ValueNotifier<bool?>> {
  const RecencyRequirePerformedScope({
    super.key,
    required ValueNotifier<bool?> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The live value, registering a rebuild dependency. `null` with no scope
  /// above, so a test that does not wire it sees the default behaviour.
  static bool? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RecencyRequirePerformedScope>()
      ?.notifier
      ?.value;

  /// The notifier, for the settings screen to change. Registers no rebuild
  /// dependency.
  static ValueNotifier<bool?> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<RecencyRequirePerformedScope>();
    if (scope == null) {
      throw FlutterError(
        'RecencyRequirePerformedScope.notifierOf() called with a context that has no '
        'RecencyRequirePerformedScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// "History order and Last called ignore undated programs" (off by default).
class HistoryOrderIgnoreUndatedScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const HistoryOrderIgnoreUndatedScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The live value, registering a rebuild dependency. `false` with no scope
  /// above, so a test that does not wire it sees the default behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<HistoryOrderIgnoreUndatedScope>()
          ?.notifier
          ?.value ??
      false;

  /// The notifier, for the settings screen to change. Registers no rebuild
  /// dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<HistoryOrderIgnoreUndatedScope>();
    if (scope == null) {
      throw FlutterError(
        'HistoryOrderIgnoreUndatedScope.notifierOf() called with a context that has no '
        'HistoryOrderIgnoreUndatedScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// "History order and Last called ignore slots not marked performed" (off by default).
class HistoryOrderIgnoreUnperformedScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const HistoryOrderIgnoreUnperformedScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The live value, registering a rebuild dependency. `false` with no scope
  /// above, so a test that does not wire it sees the default behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            HistoryOrderIgnoreUnperformedScope
          >()
          ?.notifier
          ?.value ??
      false;

  /// The notifier, for the settings screen to change. Registers no rebuild
  /// dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<HistoryOrderIgnoreUnperformedScope>();
    if (scope == null) {
      throw FlutterError(
        'HistoryOrderIgnoreUnperformedScope.notifierOf() called with a context that has no '
        'HistoryOrderIgnoreUnperformedScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// The resolved toggles, registering a rebuild dependency on each input and on
/// the global "require performed" setting while the second toggle follows it.
CallingHistoryTracking callingHistoryTrackingOf(BuildContext context) =>
    CallingHistoryTracking(
      recencyRequireEventDate: RecencyRequireEventDateScope.of(context),
      recencyRequirePerformed:
          RecencyRequirePerformedScope.of(context) ??
          RequirePerformedForHistoryScope.of(context),
      orderIgnoreUndated: HistoryOrderIgnoreUndatedScope.of(context),
      orderIgnoreUnperformed: HistoryOrderIgnoreUnperformedScope.of(context),
    );
