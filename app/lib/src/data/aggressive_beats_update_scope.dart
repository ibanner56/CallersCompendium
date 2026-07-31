import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Aggressively recompute figure beats"
/// dance-authoring toggle (issue #689). Stored as a `bool`; unset means off
/// (the default), preserving today's behavior.
const String kAggressiveBeatsUpdateKey = 'aggressive_beats_update';

/// Exposes the "Aggressively recompute figure beats" setting (#689) as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true`, the dance editor re-derives a figure's `beats` from the move's
/// canonical default on EVERY beats-affecting param change — even overriding a
/// value the user has already taken ownership of (see
/// `FigureDraft.beatsTouched`), such as one typed in manually or seeded from a
/// saved per-move default (DD.3). This mirrors ContraDB's more aggressive
/// behavior and is an explicit, deliberate opt-in trade-off: the setting's UI
/// copy makes the overwrite risk explicit so a caller isn't surprised.
///
/// When `false` (the default), behavior is byte-identical to today: `beats`
/// auto-fills from the default only while untouched, and a manual override is
/// never overwritten. Descendants that call [AggressiveBeatsUpdateScope.of]
/// rebuild automatically when the setting changes (live update).
///
/// Use [AggressiveBeatsUpdateScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class AggressiveBeatsUpdateScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const AggressiveBeatsUpdateScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether aggressive beats recomputation is enabled. Registers a rebuild
  /// dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [AggressiveBeatsUpdateScope] ancestor, so callers — and tests that don't
  /// wire the scope — get today's product default.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AggressiveBeatsUpdateScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<AggressiveBeatsUpdateScope>();
    if (scope == null) {
      throw FlutterError(
        'AggressiveBeatsUpdateScope.notifierOf() called with a context that '
        'has no AggressiveBeatsUpdateScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
