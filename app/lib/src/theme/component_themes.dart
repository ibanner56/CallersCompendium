import 'package:flutter/material.dart';

import 'app_shapes.dart';
import 'app_theme_extension.dart';

/// App-level component sub-themes (UX-2, `ux-modernization.md` §5).
///
/// One place assembles every Material component treatment from the Hearth
/// [ColorScheme] and the semantic [AppThemeExtension] focus-ring tokens, so
/// buttons, chips, cards, list tiles, inputs, dialogs, and navigation all share
/// a single themed look instead of ~20 scattered local `InputDecoration`s and
/// default-styled widgets.
///
/// Two treatments:
/// - **Light / dark** — the Material 3 idiom: filled inputs (12dp radius),
///   rounded cards, shaped buttons with ≥24px targets, subtle outline dividers,
///   and a pill nav indicator.
/// - **High-contrast** — *outline-driven* (real borders, elevation 0) with a
///   ≥3px high-visibility focus ring, exactly as UX-1 defined. HC deliberately
///   defeats tonal/elevation cues, so borders carry the structure.
@immutable
class ComponentThemes {
  const ComponentThemes({
    required this.card,
    required this.dialog,
    required this.input,
    required this.divider,
    required this.filledButton,
    required this.outlinedButton,
    required this.textButton,
    required this.chip,
    required this.listTile,
    required this.navigationRail,
    required this.navigationBar,
  });

  final CardThemeData card;
  final DialogThemeData dialog;
  final InputDecorationThemeData input;
  final DividerThemeData divider;
  final FilledButtonThemeData filledButton;
  final OutlinedButtonThemeData outlinedButton;
  final TextButtonThemeData textButton;
  final ChipThemeData chip;
  final ListTileThemeData listTile;
  final NavigationRailThemeData navigationRail;
  final NavigationBarThemeData navigationBar;

  /// Minimum interactive height. Material's padded tap target already lifts hit
  /// testing to 48px, but a ≥24px visual minimum satisfies the UX-2 AC directly.
  static const double _minTarget = 40;

  factory ComponentThemes.forScheme(
    ColorScheme scheme,
    AppThemeExtension ext, {
    bool highContrast = false,
  }) {
    return highContrast
        ? ComponentThemes._highContrast(scheme, ext)
        : ComponentThemes._standard(scheme, ext);
  }

  // --- Light / dark: Material 3 filled / tonal treatment (UX-2) -------------

  factory ComponentThemes._standard(ColorScheme scheme, AppThemeExtension ext) {
    OutlineInputBorder inputBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: AppShapes.borderRadiusMedium,
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, _minTarget)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppShapes.borderRadiusSmall),
      ),
    );

    return ComponentThemes(
      card: CardThemeData(
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusMedium,
        ),
      ),
      dialog: const DialogThemeData(shape: AppShapes.dialogShape),
      input: InputDecorationThemeData(
        filled: true,
        border: inputBorder(scheme.outline, 1),
        enabledBorder: inputBorder(scheme.outline, 1),
        // Focus reuses the semantic focus-ring token (primary, 2px here).
        focusedBorder: inputBorder(ext.focusRing, ext.focusRingWidth),
        errorBorder: inputBorder(scheme.error, 1),
        focusedErrorBorder: inputBorder(scheme.error, ext.focusRingWidth),
      ),
      divider: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
      filledButton: FilledButtonThemeData(style: buttonStyle),
      outlinedButton: OutlinedButtonThemeData(style: buttonStyle),
      textButton: TextButtonThemeData(style: buttonStyle),
      chip: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusSmall,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTile: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusMedium,
        ),
      ),
      navigationRail: NavigationRailThemeData(
        useIndicator: true,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
      ),
      navigationBar: NavigationBarThemeData(
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }

  // --- High-contrast: outline-driven treatment (UX-1, unchanged) ------------

  factory ComponentThemes._highContrast(
    ColorScheme scheme,
    AppThemeExtension ext,
  ) {
    OutlineInputBorder inputBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: AppShapes.borderRadiusSmall,
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, _minTarget)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppShapes.borderRadiusSmall),
      ),
      // A real border always, thickening into the high-visibility focus ring
      // when focused so keyboard focus is unmistakable (≥3px, UX-1 AC).
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: ext.focusRing, width: ext.focusRingWidth);
        }
        return BorderSide(color: scheme.outline, width: 1.5);
      }),
    );

    return ComponentThemes(
      card: CardThemeData(
        // Tonal elevation is invisible at HC, so cards are defined by an outline.
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusMedium,
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      dialog: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppShapes.radiusDialog),
          ),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      input: InputDecorationThemeData(
        // Fields are always outlined at HC; focus swaps to a thick focus ring.
        border: inputBorder(ext.performOnSurface, 1.5),
        enabledBorder: inputBorder(ext.performOnSurface, 1.5),
        focusedBorder: inputBorder(ext.focusRing, ext.focusRingWidth),
        errorBorder: inputBorder(ext.statusBroken, 1.5),
        focusedErrorBorder: inputBorder(ext.focusRing, ext.focusRingWidth),
      ),
      divider: DividerThemeData(color: scheme.outline, thickness: 1.5),
      filledButton: FilledButtonThemeData(style: buttonStyle),
      outlinedButton: OutlinedButtonThemeData(style: buttonStyle),
      textButton: TextButtonThemeData(style: buttonStyle),
      chip: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusSmall,
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      listTile: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusMedium,
        ),
      ),
      navigationRail: NavigationRailThemeData(
        useIndicator: true,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
      ),
      navigationBar: NavigationBarThemeData(
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
