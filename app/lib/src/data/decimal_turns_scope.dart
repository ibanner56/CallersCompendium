import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Show turns as decimals" display toggle
/// (issue #368). Stored as a `bool`; unset means off (the default).
const String kDecimalTurnsKey = 'decimal_turns';

/// Exposes the "Show turns as decimals" display setting (#368) as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true`, figure turn/rotation amounts render as decimals (`0.75`, `1.5`)
/// instead of fraction glyphs (`¾`, `1½`). This is a *display-only* preference:
/// the core renderer's canonical text (which feeds search/FTS/dedupe) is never
/// affected, and the spoken/verbose accessibility rendering keeps natural word
/// fractions. When `false` (the default) turns keep the fraction glyphs.
/// Descendants that call [DecimalTurnsScope.of] rebuild automatically when the
/// setting changes (live update).
///
/// Use [DecimalTurnsScope.notifierOf] when you need to *change* the setting
/// (e.g. from the settings screen).
class DecimalTurnsScope extends InheritedNotifier<ValueNotifier<bool>> {
  const DecimalTurnsScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether turn amounts are shown as decimals. Registers a rebuild dependency
  /// so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [DecimalTurnsScope] ancestor, so callers — and tests that don't wire the
  /// scope — get the product default of fraction glyphs.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DecimalTurnsScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DecimalTurnsScope>();
    if (scope == null) {
      throw FlutterError(
        'DecimalTurnsScope.notifierOf() called with a context that has no '
        'DecimalTurnsScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
