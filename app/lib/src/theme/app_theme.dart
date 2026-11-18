import 'package:flutter/material.dart';

import 'app_theme_extension.dart';
import 'app_typography.dart';
import 'color_schemes.dart';
import 'component_themes.dart';

/// Assembles the app's [ThemeData] from the design-system foundation:
/// palette "Hearth" [ColorScheme]s, the Fraunces/Atkinson [TextTheme],
/// adaptive density, a visible keyboard-focus color, the shared component
/// sub-themes ([ComponentThemes]), and the semantic [AppThemeExtension] (which
/// carries the spacing/shape/status/focus-ring tokens for widgets to read).
///
/// This replaces the two inline seed lines that previously lived in
/// `main.dart`. Component treatments (buttons, chips, cards, list tiles, the
/// shared `InputDecorationTheme`, dialogs, nav) are defined once in
/// [ComponentThemes] and driven from the tokens (UX-2, §5).
///
/// The **high-contrast** theme is a special case: because HC deliberately
/// defeats tonal/elevation cues, its components are *outline-driven* (real
/// borders) with a high-visibility ≥3px focus ring (`#FFD54A`) per UX-1
/// (`ux-modernization.md` §1b, §7). That variation lives in [ComponentThemes].
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppColorSchemes.light);
  static ThemeData get dark => _build(AppColorSchemes.dark);
  static ThemeData get highContrast =>
      _build(AppColorSchemes.highContrast, highContrast: true);

  /// Builds the app [ThemeData] for any [scheme] — used by the UX-6 theme
  /// gallery, whose palettes each pin a concrete [ColorScheme]
  /// (`docs/design/ux-modernization.md` §4A). Gallery palettes are standard
  /// (non-high-contrast) themes; only the built-in "High contrast" selection
  /// uses the outline-driven variation via [highContrast].
  static ThemeData fromScheme(ColorScheme scheme) => _build(scheme);

  /// [theme] with page transitions and the [ExpansionTile] animation turned
  /// off, for the in-app Reduce motion switch. Dialogs and
  /// bottom sheets have no theme hook for their animation, so each call site
  /// passes `AppMotion.styleFor(context)` instead.
  static ThemeData withoutMotion(ThemeData theme) => theme.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _NoTransitionsBuilder(),
        TargetPlatform.iOS: _NoTransitionsBuilder(),
        TargetPlatform.macOS: _NoTransitionsBuilder(),
        TargetPlatform.windows: _NoTransitionsBuilder(),
        TargetPlatform.linux: _NoTransitionsBuilder(),
        TargetPlatform.fuchsia: _NoTransitionsBuilder(),
      },
    ),
    expansionTileTheme: theme.expansionTileTheme.copyWith(
      expansionAnimationStyle: AnimationStyle.noAnimation,
    ),
  );

  static ThemeData _build(ColorScheme scheme, {bool highContrast = false}) {
    final textTheme = AppTypography.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      decorationColor: scheme.onSurface,
    );

    final extension = AppThemeExtension.fromColorScheme(
      scheme,
      highContrast: highContrast,
    );

    final components = ComponentThemes.forScheme(
      scheme,
      extension,
      highContrast: highContrast,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      // Compact on desktop, comfortable on touch — chosen per platform.
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Keyboard focus must be visible on every interactive element
      // (accessibility-baseline). A tinted focus overlay makes traversal clear;
      // high-contrast uses a stronger, high-visibility tint of the focus ring.
      focusColor: highContrast
          ? extension.focusRing.withValues(alpha: 0.30)
          : scheme.primary.withValues(alpha: 0.14),
      cardTheme: components.card,
      dialogTheme: components.dialog,
      inputDecorationTheme: components.input,
      dividerTheme: components.divider,
      filledButtonTheme: components.filledButton,
      outlinedButtonTheme: components.outlinedButton,
      textButtonTheme: components.textButton,
      chipTheme: components.chip,
      listTileTheme: components.listTile,
      navigationRailTheme: components.navigationRail,
      navigationBarTheme: components.navigationBar,
      snackBarTheme: components.snackBar,
      bottomSheetTheme: components.bottomSheet,
      popupMenuTheme: components.popupMenu,
      menuTheme: components.menu,
      appBarTheme: components.appBar,
      floatingActionButtonTheme: components.floatingActionButton,
      iconButtonTheme: components.iconButton,
      segmentedButtonTheme: components.segmentedButton,
      expansionTileTheme: components.expansionTile,
      tooltipTheme: components.tooltip,
      dropdownMenuTheme: components.dropdownMenu,
      progressIndicatorTheme: components.progressIndicator,
      switchTheme: components.switchTheme,
      checkboxTheme: components.checkbox,
      extensions: <ThemeExtension<dynamic>>[extension],
    );
  }
}

/// A page transition that shows the new route at once.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
