import 'package:flutter/widgets.dart';

/// Exposes the "Ignore leading articles when sorting" General setting as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true` (the default), the dance list alphabetizes titles with a leading
/// article ("the"/"a"/"an") ignored, so "The Nice Combination" files under
/// **N**. When `false`, titles sort by their literal text. Descendants that
/// call [SortIgnoreArticlesScope.of] rebuild automatically when the setting
/// changes (live update).
///
/// Use [SortIgnoreArticlesScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class SortIgnoreArticlesScope extends InheritedNotifier<ValueNotifier<bool>> {
  const SortIgnoreArticlesScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether leading articles are ignored when alphabetizing. Registers a
  /// rebuild dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `true` (the on-by-default behavior) when there is no
  /// [SortIgnoreArticlesScope] ancestor, so callers — and tests that don't
  /// wire the scope — get the product default of article-insensitive sorting.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SortIgnoreArticlesScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<SortIgnoreArticlesScope>();
    if (scope == null) {
      throw FlutterError(
        'SortIgnoreArticlesScope.notifierOf() called with a context that has '
        'no SortIgnoreArticlesScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
