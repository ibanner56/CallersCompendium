import 'package:flutter/widgets.dart';

/// Persisted-settings key for the Experimental "Custom Figures" toggle (#709).
/// Stored as a `bool`; unset means off (the default).
const String kShowCustomFiguresKey = 'show_custom_figures';

/// Exposes the "Custom Figures" setting as a live [ValueNotifier] to the
/// widget tree.
///
/// When `true` the user's own figures can be added and edited from the Custom
/// Figures screen in the Experimental settings, and from the Glossary while it
/// is shown, and the dance editor offers them as a figure's move. It does not
/// depend on "Show Glossary". When `false`
/// they are hidden, never deleted: turning it back on shows them again. A
/// dance-editor row that already holds one still expands when the dance is
/// saved (#709).
///
/// Use [ShowCustomFiguresScope.notifierOf] to change the setting.
class ShowCustomFiguresScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ShowCustomFiguresScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether the setting is on. Registers a rebuild dependency. Returns
  /// `false`, the default, when there is no [ShowCustomFiguresScope]
  /// ancestor.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShowCustomFiguresScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ShowCustomFiguresScope>();
    if (scope == null) {
      throw FlutterError(
        'ShowCustomFiguresScope.notifierOf() called with a context that has no '
        'ShowCustomFiguresScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Whether the user's own figures are shown: "Custom Figures" is on, whether
/// or not the Glossary is. Registers a rebuild dependency.
bool customFiguresShown(BuildContext context) =>
    ShowCustomFiguresScope.of(context);
