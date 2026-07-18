import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Colour-code set-list rows" Appearance
/// toggle (issue #270). Stored as a `bool`; **unset means on** (`true`), the
/// product default — the accent is redundant with row text and toggleable.
const String kSetListColorCodingKey = 'set_list_color_coding';

/// Exposes the "Colour-code set-list rows" Appearance setting (issue #270) as a
/// live [ValueNotifier] to the widget tree.
///
/// When `true` (the default), set-list rows in the program summary and builder
/// carry a redundant formation-family accent colour alongside their formation
/// text. When `false`, the accent is suppressed and rows render exactly as
/// before. Descendants that call [SetListColorCodingScope.of] rebuild
/// automatically when the setting changes (live update).
///
/// Use [SetListColorCodingScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class SetListColorCodingScope extends InheritedNotifier<ValueNotifier<bool>> {
  const SetListColorCodingScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether set-list rows should carry the formation accent. Registers a
  /// rebuild dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `true` (the on-by-default behaviour) when there is no
  /// [SetListColorCodingScope] ancestor, so callers — and tests that don't wire
  /// the scope — get the product default.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SetListColorCodingScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<SetListColorCodingScope>();
    if (scope == null) {
      throw FlutterError(
        'SetListColorCodingScope.notifierOf() called with a context that has '
        'no SetListColorCodingScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
