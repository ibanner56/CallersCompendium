import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Horizontal navigation bar" Appearance
/// setting. Stored as a `bool`; **unset means off** (`false`), the long-standing
/// layout — a vertical navigation rail down the left.
///
/// Only a desktop window wider than the rail breakpoint reads it: at narrow
/// widths the bottom bar already spans the screen, and a phone or tablet has no
/// rail to move. The setting is offered on desktop only for the same reason.
const String kHorizontalTopNavKey = 'horizontal_top_nav';

/// Whether [platform] is a desktop with a window whose chrome this setting can
/// rearrange.
///
/// The check is deliberately a plain function over a [TargetPlatform] rather
/// than `Platform.is…`: the value comes from the ambient theme, so a test can
/// override the target platform like the rest of the UI does.
bool isDesktopNavPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => false,
};

/// Exposes the "Horizontal navigation bar" Appearance setting as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true`, a wide desktop window lays its main destinations out in a bar
/// across the top instead of the left rail. When `false` — the default — the
/// rail is unchanged. Descendants that call [HorizontalTopNavScope.of] rebuild
/// automatically when the setting changes (live update), so flipping it in
/// Settings rearranges the shell immediately.
///
/// Use [HorizontalTopNavScope.notifierOf] when you need to *change* the setting
/// (e.g. from the settings screen).
class HorizontalTopNavScope extends InheritedNotifier<ValueNotifier<bool>> {
  const HorizontalTopNavScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether a wide desktop layout should put its navigation across the top.
  /// Registers a rebuild dependency so the caller rebuilds whenever the setting
  /// changes.
  ///
  /// Returns `false` (the rail default) when there is no
  /// [HorizontalTopNavScope] ancestor, so callers — and tests that don't wire
  /// the scope — get the product default.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<HorizontalTopNavScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<HorizontalTopNavScope>();
    if (scope == null) {
      throw FlutterError(
        'HorizontalTopNavScope.notifierOf() called with a context that has '
        'no HorizontalTopNavScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
