import 'package:flutter/material.dart';

import 'app_shapes.dart';
import 'app_theme_extension.dart';
import 'app_typography.dart';

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
    required this.snackBar,
    this.bottomSheet = const BottomSheetThemeData(),
    this.popupMenu = const PopupMenuThemeData(),
    this.menu = const MenuThemeData(),
    this.appBar = const AppBarTheme(),
    this.floatingActionButton = const FloatingActionButtonThemeData(),
    this.iconButton = const IconButtonThemeData(),
    this.segmentedButton = const SegmentedButtonThemeData(),
    this.expansionTile = const ExpansionTileThemeData(),
    this.tooltip = const TooltipThemeData(),
    this.dropdownMenu = const DropdownMenuThemeData(),
    this.progressIndicator = const ProgressIndicatorThemeData(),
    this.switchTheme = const SwitchThemeData(),
    this.checkbox = const CheckboxThemeData(),
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
  final SnackBarThemeData snackBar;

  // The components below are themed alike in both treatments by
  // [_withSharedComponents]: AppShapes radii everywhere, plus an outline in
  // High contrast where the component is a container or control boundary.
  // Sheets and menus sit on distinct surface tiers, and High contrast
  // outlines them, as it does cards and dialogs.
  final BottomSheetThemeData bottomSheet;
  final PopupMenuThemeData popupMenu;
  final MenuThemeData menu;
  final AppBarTheme appBar;
  final FloatingActionButtonThemeData floatingActionButton;
  final IconButtonThemeData iconButton;
  final SegmentedButtonThemeData segmentedButton;
  final ExpansionTileThemeData expansionTile;
  final TooltipThemeData tooltip;
  final DropdownMenuThemeData dropdownMenu;
  final ProgressIndicatorThemeData progressIndicator;
  final SwitchThemeData switchTheme;
  final CheckboxThemeData checkbox;

  /// Every snackbar floats, as the Undo snackbar already does (#463), instead of
  /// docking to the bottom edge and covering the controls beneath it. The theme
  /// cannot set a duration, so those still differ by call site.
  static const SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
  );

  /// Minimum visual button height, in logical pixels. Comfortably clears the
  /// UX-2 AC of ≥24px while staying below Material's 48px padded tap target
  /// (which continues to govern hit-testing regardless of this value).
  static const double _minTarget = 40;

  factory ComponentThemes.forScheme(
    ColorScheme scheme,
    AppThemeExtension ext, {
    bool highContrast = false,
  }) {
    final base = highContrast
        ? ComponentThemes._highContrast(scheme, ext)
        : ComponentThemes._standard(scheme, ext);
    return base._withSharedComponents(scheme, highContrast: highContrast);
  }

  // --- Both treatments: components Material otherwise leaves unthemed ----

  ComponentThemes _withSharedComponents(
    ColorScheme scheme, {
    required bool highContrast,
  }) {
    // The one outline High contrast adds; none elsewhere.
    final side = highContrast
        ? BorderSide(color: scheme.outline, width: 1.5)
        : BorderSide.none;
    final menuStyle = MenuStyle(
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppShapes.borderRadiusSmall),
      ),
      side: highContrast ? WidgetStatePropertyAll(side) : null,
    );
    final tileShape = RoundedRectangleBorder(
      borderRadius: AppShapes.borderRadiusMedium,
      side: side,
    );

    return ComponentThemes(
      card: card,
      dialog: dialog.copyWith(
        // Set here rather than left to Material's default so dialog titles
        // stay in the display face if that default changes.
        titleTextStyle: AppTypography.textTheme.headlineSmall!.copyWith(
          color: scheme.onSurface,
        ),
      ),
      input: input,
      divider: divider,
      filledButton: filledButton,
      outlinedButton: outlinedButton,
      textButton: textButton,
      chip: chip,
      listTile: listTile,
      navigationRail: navigationRail,
      navigationBar: navigationBar,
      snackBar: snackBar,
      bottomSheet: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppShapes.radiusDialog),
          ),
          side: side,
        ),
      ),
      popupMenu: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusSmall,
          side: side,
        ),
      ),
      menu: MenuThemeData(style: menuStyle),
      dropdownMenu: DropdownMenuThemeData(menuStyle: menuStyle),
      appBar: AppBarTheme(
        // Leading titles on every platform.
        centerTitle: false,
        // No Material scrolled-under tint: the bar keeps the
        // canvas colour whatever scrolls beneath it.
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: AppTypography.screenTitle.copyWith(
          color: scheme.onSurface,
        ),
        // High contrast separates the bar from the page with a rule, since
        // the bar and page share one colour.
        shape: highContrast ? Border(bottom: side) : null,
      ),
      floatingActionButton: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusLarge,
          side: side,
        ),
      ),
      // Icon buttons share the buttons' small radius, so their hover and press
      // highlights match the focus ring drawn round them.
      iconButton: const IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppShapes.borderRadiusSmall),
          ),
        ),
      ),
      segmentedButton: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppShapes.borderRadiusSmall),
          ),
          side: highContrast ? WidgetStatePropertyAll(side) : null,
        ),
      ),
      expansionTile: ExpansionTileThemeData(
        shape: tileShape,
        collapsedShape: tileShape,
      ),
      tooltip: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppShapes.borderRadiusSmall,
        ),
        textStyle: AppTypography.textTheme.bodySmall!.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      progressIndicator: const ProgressIndicatorThemeData(
        borderRadius: AppShapes.borderRadiusSmall,
      ),
      // High contrast keeps a visible track outline on a switch that is on
      // (Material drops it), and a box outline on a ticked checkbox.
      switchTheme: highContrast
          ? SwitchThemeData(
              trackOutlineColor: WidgetStatePropertyAll(scheme.outline),
              trackOutlineWidth: const WidgetStatePropertyAll(1.5),
            )
          : const SwitchThemeData(),
      checkbox: highContrast
          ? CheckboxThemeData(
              // A state-aware side, because a plain BorderSide is drawn only
              // while the box is unticked.
              side: WidgetStateBorderSide.resolveWith(
                (_) => BorderSide(color: scheme.outline, width: 2),
              ),
            )
          : const CheckboxThemeData(),
    );
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
      dialog: const DialogThemeData(
        shape: AppShapes.dialogShape,
        constraints: AppShapes.dialogConstraints,
      ),
      input: InputDecorationThemeData(
        filled: true,
        border: inputBorder(scheme.outline, 1),
        enabledBorder: inputBorder(scheme.outline, 1),
        // Focus reuses the semantic focus-ring token (primary, 2px here).
        focusedBorder: inputBorder(ext.focusRing, ext.focusRingWidth),
        errorBorder: inputBorder(scheme.error, 1),
        focusedErrorBorder: inputBorder(scheme.error, ext.focusRingWidth),
        // Without this a disabled field falls back to its decoration's own
        // `border`, so the many local `OutlineInputBorder()`s drew square 4px
        // corners on a disabled field beside rounded enabled ones. M3 dims a
        // disabled outline to onSurface at 12%.
        disabledBorder: inputBorder(
          scheme.onSurface.withValues(alpha: 0.12),
          1,
        ),
      ),
      divider: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
      filledButton: FilledButtonThemeData(style: buttonStyle),
      outlinedButton: OutlinedButtonThemeData(style: buttonStyle),
      textButton: TextButtonThemeData(style: buttonStyle),
      chip: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.borderRadiusSmall,
          // outline, not outlineVariant: a chip's border is its boundary and
          // needs 3:1 on the surface; outlineVariant was ~1.5:1.
          side: BorderSide(color: scheme.outline),
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
      snackBar: _snackBarTheme,
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
        constraints: AppShapes.dialogConstraints,
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
        // Still outlined (HC never relies on fill alone), but in the quieter
        // outline role so a disabled field reads differently from an enabled one.
        disabledBorder: inputBorder(scheme.outline, 1.5),
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
      snackBar: _snackBarTheme,
    );
  }
}
