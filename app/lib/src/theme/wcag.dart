import 'dart:ui';

/// WCAG 2.2 contrast helpers, shared by the custom-theme editor so it can show
/// live AA pass/fail badges as the user edits colors
/// (`docs/design/ux-modernization.md` §4B). Kept dependency-free and pure so it
/// is trivially unit-testable.
class Wcag {
  const Wcag._();

  /// Minimum contrast for normal body text and icons.
  static const double aaText = 4.5;

  /// Minimum contrast for large text and non-text UI (borders, component
  /// boundaries, focus rings).
  static const double aaNonText = 3.0;

  /// The WCAG relative-luminance contrast ratio between two colors, in the
  /// range 1.0 (identical) … 21.0 (black vs white). Order-independent.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Whether [foreground] on [background] clears the AA threshold — 4.5:1 for
  /// normal text (default) or 3.0:1 for [largeOrNonText] content.
  static bool meetsAA(
    Color foreground,
    Color background, {
    bool largeOrNonText = false,
  }) {
    final target = largeOrNonText ? aaNonText : aaText;
    return contrastRatio(foreground, background) >= target;
  }
}
