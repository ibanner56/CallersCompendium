import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Always show verbose figure text"
/// accessibility toggle (ROADMAP G.7). Stored as a `bool`; unset means off.
const String kVerboseFigureRenderingKey = 'verbose_figure_rendering';

/// Exposes the "Always-verbose figure rendering" accessibility setting
/// (ROADMAP G.7) as a live [ValueNotifier] to the widget tree.
///
/// When `true`, the dance view renders the verbose (screen-reader-friendly,
/// ROADMAP 5.4) figure text as the *visible* text, not only in the assistive
/// technology label. When `false` (the default) the visible text stays terse
/// and the verbose form is spoken only to AT. Descendants that call
/// [VerboseFigureRenderingScope.of] rebuild automatically when the setting
/// changes (live update).
///
/// Use [VerboseFigureRenderingScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class VerboseFigureRenderingScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const VerboseFigureRenderingScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether verbose figure text is shown on screen. Registers a rebuild
  /// dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [VerboseFigureRenderingScope] ancestor, so callers — and tests that don't
  /// wire the scope — get the product default of terse visible text.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<VerboseFigureRenderingScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<VerboseFigureRenderingScope>();
    if (scope == null) {
      throw FlutterError(
        'VerboseFigureRenderingScope.notifierOf() called with a context that '
        'has no VerboseFigureRenderingScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
