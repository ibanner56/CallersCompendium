import 'package:flutter/widgets.dart';

/// Exposes the "venue entity mode" General setting as a live [ValueNotifier] to
/// the widget tree.
///
/// When `true`, the program editor swaps its free-text venue field for a picker
/// over reusable [Venue] records (address/contacts/schedule); when `false` (the
/// default) the editor uses the simple free-text `Program.venue` field. The
/// setting governs the editor's ENTRY mode only.
///
/// Display resolution is independent of this setting: wherever a program links a
/// reusable [Venue] (`venueId`), screens show that venue's display name
/// regardless of the toggle (see `resolveVenueLabel`), because both columns
/// persist independently.
///
/// The toggle is entry/display-mode only — `Program.venue` and
/// `Program.venueId` persist independently, so flipping it is lossless and
/// reversible and never clears the other mode's value. Descendants that call
/// [VenueEntityModeScope.of] rebuild automatically when the setting changes.
///
/// Use [VenueEntityModeScope.notifierOf] when you need to *change* the setting
/// (e.g. from the settings screen).
class VenueEntityModeScope extends InheritedNotifier<ValueNotifier<bool>> {
  const VenueEntityModeScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether the reusable-venue entity mode is on. Registers a rebuild
  /// dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [VenueEntityModeScope] ancestor, so callers — and tests that don't wire
  /// the scope — safely fall back to the simple free-text venue field.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<VenueEntityModeScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<VenueEntityModeScope>();
    if (scope == null) {
      throw FlutterError(
        'VenueEntityModeScope.notifierOf() called with a context that has no '
        'VenueEntityModeScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
