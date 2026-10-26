/// Spacing tokens on a 4px base grid (§1d). Use these instead of ad-hoc
/// magic numbers so density stays consistent across screens.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Trailing space a scrollable leaves below its last item when its screen
  /// floats an extended FAB over it (56dp button + 16dp margin + 16dp gap), so
  /// the last row's content and trailing actions can always be scrolled clear.
  static const double fabClearance = 88;
}
