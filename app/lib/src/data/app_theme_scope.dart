import 'package:flutter/material.dart';

import '../theme/color_schemes.dart';
import '../theme/palette_schemes.dart';

/// The section a selection belongs to in the Settings theme gallery
/// (`docs/design/ux-modernization.md` §4A). Drives the labeled groups that
/// organize the swatch cards.
enum AppThemeGroup {
  system('System'),
  defaultHearth('Default'),
  light('Light'),
  dark('Dark');

  const AppThemeGroup(this.label);

  /// Section heading shown in the gallery.
  final String label;
}

/// The user's theme choice. High-contrast is not a [ThemeMode] value, and the
/// gallery palettes each pin a concrete scheme, so we model explicit selections
/// rather than reusing [ThemeMode] directly (`docs/design/ux-modernization.md`
/// §4 / §4A). Persistence stores the enum [name]; new values append to the end
/// so previously persisted names keep resolving.
enum AppThemeSelection {
  system,
  light,
  dark,
  highContrast,
  // Gallery palettes (§4A) — light.
  solarizedLight,
  atomOneLight,
  noctisLux,
  githubLight,
  catppuccinLatte,
  gruvboxLight,
  everforestLight,
  rosePineDawn,
  ayuLight,
  // Gallery palettes (§4A) — dark.
  solarizedDark,
  atomOneDark,
  oneDarkPro,
  oneDarkProDarker,
  monokai,
  noctis,
  dracula,
  nord,
  tokyoNight,
  gruvboxDark,
  catppuccinMocha,
  githubDark,
  nightOwl,
  everforestDark,
  rosePine,
  ayuMirage;

  bool get isHighContrast => this == AppThemeSelection.highContrast;

  /// True for every selection except [system], i.e. those that pin a concrete
  /// [ColorScheme] regardless of the OS brightness.
  bool get isPinned => this != AppThemeSelection.system;

  /// The concrete [ColorScheme] for a pinned selection, or `null` for [system]
  /// (which resolves at runtime from the platform brightness).
  ColorScheme? get scheme => switch (this) {
    AppThemeSelection.system => null,
    AppThemeSelection.light => AppColorSchemes.light,
    AppThemeSelection.dark => AppColorSchemes.dark,
    AppThemeSelection.highContrast => AppColorSchemes.highContrast,
    AppThemeSelection.solarizedLight => GalleryPalettes.solarizedLight,
    AppThemeSelection.atomOneLight => GalleryPalettes.atomOneLight,
    AppThemeSelection.noctisLux => GalleryPalettes.noctisLux,
    AppThemeSelection.githubLight => GalleryPalettes.githubLight,
    AppThemeSelection.catppuccinLatte => GalleryPalettes.catppuccinLatte,
    AppThemeSelection.gruvboxLight => GalleryPalettes.gruvboxLight,
    AppThemeSelection.everforestLight => GalleryPalettes.everforestLight,
    AppThemeSelection.rosePineDawn => GalleryPalettes.rosePineDawn,
    AppThemeSelection.ayuLight => GalleryPalettes.ayuLight,
    AppThemeSelection.solarizedDark => GalleryPalettes.solarizedDark,
    AppThemeSelection.atomOneDark => GalleryPalettes.atomOneDark,
    AppThemeSelection.oneDarkPro => GalleryPalettes.oneDarkPro,
    AppThemeSelection.oneDarkProDarker => GalleryPalettes.oneDarkProDarker,
    AppThemeSelection.monokai => GalleryPalettes.monokai,
    AppThemeSelection.noctis => GalleryPalettes.noctis,
    AppThemeSelection.dracula => GalleryPalettes.dracula,
    AppThemeSelection.nord => GalleryPalettes.nord,
    AppThemeSelection.tokyoNight => GalleryPalettes.tokyoNight,
    AppThemeSelection.gruvboxDark => GalleryPalettes.gruvboxDark,
    AppThemeSelection.catppuccinMocha => GalleryPalettes.catppuccinMocha,
    AppThemeSelection.githubDark => GalleryPalettes.githubDark,
    AppThemeSelection.nightOwl => GalleryPalettes.nightOwl,
    AppThemeSelection.everforestDark => GalleryPalettes.everforestDark,
    AppThemeSelection.rosePine => GalleryPalettes.rosePine,
    AppThemeSelection.ayuMirage => GalleryPalettes.ayuMirage,
  };

  /// Brightness of a pinned selection (defaults to light for [system], which
  /// follows the platform and is wired via [themeMode] instead).
  Brightness get brightness => scheme?.brightness ?? Brightness.light;

  /// The gallery section this selection belongs to.
  AppThemeGroup get group => switch (this) {
    AppThemeSelection.system => AppThemeGroup.system,
    AppThemeSelection.light ||
    AppThemeSelection.dark ||
    AppThemeSelection.highContrast => AppThemeGroup.defaultHearth,
    AppThemeSelection.solarizedLight ||
    AppThemeSelection.atomOneLight ||
    AppThemeSelection.noctisLux ||
    AppThemeSelection.githubLight ||
    AppThemeSelection.catppuccinLatte ||
    AppThemeSelection.gruvboxLight ||
    AppThemeSelection.everforestLight ||
    AppThemeSelection.rosePineDawn ||
    AppThemeSelection.ayuLight => AppThemeGroup.light,
    _ => AppThemeGroup.dark,
  };

  /// The [ThemeMode] used to pick between `theme` and `darkTheme` on
  /// [MaterialApp]. High-contrast forces the dark slot (both slots are set to
  /// the high-contrast theme by the caller). Pinned gallery palettes set both
  /// slots to the same theme, so their mode just follows the scheme brightness.
  ThemeMode get themeMode => switch (this) {
    AppThemeSelection.system => ThemeMode.system,
    AppThemeSelection.highContrast => ThemeMode.dark,
    _ => brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark,
  };

  /// Human-readable label for settings UI.
  String get label => switch (this) {
    AppThemeSelection.system => 'System',
    AppThemeSelection.light => 'Light',
    AppThemeSelection.dark => 'Dark',
    AppThemeSelection.highContrast => 'High contrast',
    AppThemeSelection.solarizedLight => 'Solarized Light',
    AppThemeSelection.atomOneLight => 'Atom One Light',
    AppThemeSelection.noctisLux => 'Noctis Lux',
    AppThemeSelection.solarizedDark => 'Solarized Dark',
    AppThemeSelection.atomOneDark => 'Atom One Dark',
    AppThemeSelection.oneDarkPro => 'One Dark Pro',
    AppThemeSelection.oneDarkProDarker => 'One Dark Pro Darker',
    AppThemeSelection.monokai => 'Monokai',
    AppThemeSelection.noctis => 'Noctis',
    AppThemeSelection.githubLight => 'GitHub Light',
    AppThemeSelection.catppuccinLatte => 'Catppuccin Latte',
    AppThemeSelection.gruvboxLight => 'Gruvbox Light',
    AppThemeSelection.everforestLight => 'Everforest Light',
    AppThemeSelection.rosePineDawn => 'Rosé Pine Dawn',
    AppThemeSelection.ayuLight => 'Ayu Light',
    AppThemeSelection.dracula => 'Dracula',
    AppThemeSelection.nord => 'Nord',
    AppThemeSelection.tokyoNight => 'Tokyo Night',
    AppThemeSelection.gruvboxDark => 'Gruvbox Dark',
    AppThemeSelection.catppuccinMocha => 'Catppuccin Mocha',
    AppThemeSelection.githubDark => 'GitHub Dark',
    AppThemeSelection.nightOwl => 'Night Owl',
    AppThemeSelection.everforestDark => 'Everforest Dark',
    AppThemeSelection.rosePine => 'Rosé Pine',
    AppThemeSelection.ayuMirage => 'Ayu Mirage',
  };

  /// One-line description shown under each option.
  String get description => switch (this) {
    AppThemeSelection.system => 'Match the device light/dark setting',
    AppThemeSelection.light => 'Warm light palette',
    AppThemeSelection.dark => 'Warm dark palette',
    AppThemeSelection.highContrast =>
      'Maximum contrast for dim rooms and low vision',
    AppThemeSelection.solarizedLight => 'Ethan Schoonover’s low-glare classic',
    AppThemeSelection.atomOneLight => 'Crisp editor light, inspired by Atom',
    AppThemeSelection.noctisLux => 'Soft warm light with teal accents',
    AppThemeSelection.solarizedDark => 'The Solarized base tuned for the dark',
    AppThemeSelection.atomOneDark => 'The familiar Atom / VS Code dark',
    AppThemeSelection.oneDarkPro => 'One Dark Pro, the popular editor theme',
    AppThemeSelection.oneDarkProDarker => 'One Dark Pro on a deeper surface',
    AppThemeSelection.monokai => 'Vivid Monokai on charcoal',
    AppThemeSelection.noctis => 'Deep blue night with mint accents',
    AppThemeSelection.githubLight => 'GitHub’s clean neutral light',
    AppThemeSelection.catppuccinLatte =>
      'Soft pastel light, community favorite',
    AppThemeSelection.gruvboxLight => 'Warm retro cream and earth tones',
    AppThemeSelection.everforestLight => 'Gentle green, easy on the eyes',
    AppThemeSelection.rosePineDawn => 'Muted rose and iris on warm paper',
    AppThemeSelection.ayuLight => 'Bright, minimal light with amber accents',
    AppThemeSelection.dracula => 'The classic purple-on-charcoal favorite',
    AppThemeSelection.nord => 'Cool arctic blues, understated',
    AppThemeSelection.tokyoNight => 'Neon indigo city-at-night palette',
    AppThemeSelection.gruvboxDark => 'Warm retro amber on charcoal',
    AppThemeSelection.catppuccinMocha => 'Cozy pastel dark, community favorite',
    AppThemeSelection.githubDark => 'GitHub’s neutral dark',
    AppThemeSelection.nightOwl => 'Deep blue tuned for late-night work',
    AppThemeSelection.everforestDark => 'Soft forest green, low fatigue',
    AppThemeSelection.rosePine => 'Muted rose and iris in the dark',
    AppThemeSelection.ayuMirage => 'Smooth slate with amber accents',
  };

  /// Resolves a persisted name back to a selection, or `null` if unknown.
  static AppThemeSelection? forName(String? name) {
    for (final s in AppThemeSelection.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// The selections belonging to [group], sorted alphabetically by [label]
  /// (case-insensitive) so the Settings gallery lists built-in themes A→Z
  /// within each section.
  static List<AppThemeSelection> inGroup(AppThemeGroup group) {
    return AppThemeSelection.values.where((s) => s.group == group).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }
}

/// Exposes the user's active [AppThemeSelection] as a live [ValueNotifier] to
/// the widget tree. Placed alongside `ActiveDialectScope` in `src/data/`
/// because it is runtime app state; the `src/theme/` layer stays
/// presentation-only.
///
/// Descendants that call [AppThemeScope.of] rebuild when the selection
/// changes; use [AppThemeScope.notifierOf] to *change* it (e.g. from Settings).
class AppThemeScope
    extends InheritedNotifier<ValueNotifier<AppThemeSelection>> {
  const AppThemeScope({
    super.key,
    required ValueNotifier<AppThemeSelection> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The current selection. Registers a rebuild dependency.
  static AppThemeSelection of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    if (scope == null) {
      throw FlutterError(
        'AppThemeScope.of() called with a context that has no '
        'AppThemeScope ancestor.',
      );
    }
    return scope.notifier!.value;
  }

  /// Returns the underlying notifier so callers can change the selection.
  /// Does *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<AppThemeSelection> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppThemeScope>();
    if (scope == null) {
      throw FlutterError(
        'AppThemeScope.notifierOf() called with a context that has no '
        'AppThemeScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
