import 'package:flutter/widgets.dart';

/// Persisted-settings key for the Experimental "Show Glossary" toggle (issue
/// #695). Stored as a `bool`; unset means off (the default).
const String kShowGlossaryKey = 'show_glossary';

/// Exposes the Experimental "Show Glossary" setting as a live [ValueNotifier]
/// to the widget tree.
///
/// When `true`, the app shell shows a Glossary destination between Programs
/// and Settings. When `false` (the default) the destination is absent. Hiding
/// it removes only the navigation entry: the glossary's content is shipped
/// with the app and nothing is stored or deleted. Descendants that call
/// [ShowGlossaryScope.of] rebuild automatically when the setting changes
/// (live update).
///
/// Use [ShowGlossaryScope.notifierOf] when you need to *change* the setting
/// (e.g. from the settings screen).
class ShowGlossaryScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ShowGlossaryScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether the Glossary destination is shown. Registers a rebuild dependency
  /// so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [ShowGlossaryScope] ancestor, so callers — and tests that don't wire the
  /// scope — get the product default: no Glossary destination.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShowGlossaryScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ShowGlossaryScope>();
    if (scope == null) {
      throw FlutterError(
        'ShowGlossaryScope.notifierOf() called with a context that has no '
        'ShowGlossaryScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
