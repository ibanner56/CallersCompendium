import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

/// Resolves a persisted settings value into a [Dialect].
///
/// The active dialect is stored as a full dialect JSON map so fully-custom
/// dialects (custom role terms, move substitutions, discouraged terms) survive
/// a restart. For backward compatibility, a bare preset-name string is still
/// resolved via [Dialect.forName]. Returns `null` when there is nothing usable
/// stored (callers fall back to the default, [Dialect.larksRobins]).
Dialect? dialectFromStored(Object? stored) {
  if (stored is Map) {
    return Dialect.fromJson(stored.cast<String, Object?>());
  }
  if (stored is String) {
    return Dialect.forName(stored);
  }
  return null;
}

/// Exposes the user's active [Dialect] as a live [ValueNotifier] to the
/// widget tree.  Descendants that call [ActiveDialectScope.of] will rebuild
/// automatically when the dialect changes (live update).
///
/// Use [ActiveDialectScope.notifierOf] when you need to *change* the dialect
/// (e.g. from the settings screen).
class ActiveDialectScope extends InheritedNotifier<ValueNotifier<Dialect>> {
  const ActiveDialectScope({
    super.key,
    required ValueNotifier<Dialect> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The currently active dialect. Registers a rebuild dependency so the
  /// calling widget rebuilds whenever the dialect changes.
  static Dialect of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ActiveDialectScope>();
    if (scope == null) {
      throw FlutterError(
        'ActiveDialectScope.of() called with a context that has no '
        'ActiveDialectScope ancestor.',
      );
    }
    return scope.notifier!.value;
  }

  /// Returns the underlying notifier so callers can change the active dialect.
  /// Does *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<Dialect> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ActiveDialectScope>();
    if (scope == null) {
      throw FlutterError(
        'ActiveDialectScope.notifierOf() called with a context that has no '
        'ActiveDialectScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
