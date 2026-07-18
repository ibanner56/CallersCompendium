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
/// §4 / §4A). Persistence stores the enum [name] and [forName] resolves it, so
/// backward compatibility relies on *name stability*, not enum ordering — new
/// values can be declared wherever they read best (built-in defaults are kept
/// grouped together) without affecting persisted selections or the gallery,
/// which orders sections explicitly via [inGroup].
enum AppThemeSelection {
  system,
  light,
  dark,
  softDark,
  highContrast,
  // Gallery palettes (§4A) — light.
  blulocoLight,
  githubLight,
  catppuccinLatte,
  gruvboxLight,
  everforestLight,
  rosePineDawn,
  ayuLight,
  tokyoNightLight,
  nordLight,
  kanagawaLotus,
  noctisLilac,
  vitesseLight,
  // Gallery palettes (§4A) — dark.
  oneDarkPro,
  monokai,
  noctis,
  dracula,
  nord,
  tokyoNight,
  gruvboxDark,
  catppuccinMocha,
  githubDark,
  everforestDark,
  rosePine,
  ayuMirage,
  cutiePro,
  pinkAsHeck,
  zenburn,
  shadesOfPurple,
  catppuccinFrappe,
  synthwave84;

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
    AppThemeSelection.softDark => AppColorSchemes.softDark,
    AppThemeSelection.highContrast => AppColorSchemes.highContrast,
    AppThemeSelection.blulocoLight => GalleryPalettes.blulocoLight,
    AppThemeSelection.githubLight => GalleryPalettes.githubLight,
    AppThemeSelection.catppuccinLatte => GalleryPalettes.catppuccinLatte,
    AppThemeSelection.gruvboxLight => GalleryPalettes.gruvboxLight,
    AppThemeSelection.everforestLight => GalleryPalettes.everforestLight,
    AppThemeSelection.rosePineDawn => GalleryPalettes.rosePineDawn,
    AppThemeSelection.ayuLight => GalleryPalettes.ayuLight,
    AppThemeSelection.tokyoNightLight => GalleryPalettes.tokyoNightLight,
    AppThemeSelection.nordLight => GalleryPalettes.nordLight,
    AppThemeSelection.kanagawaLotus => GalleryPalettes.kanagawaLotus,
    AppThemeSelection.noctisLilac => GalleryPalettes.noctisLilac,
    AppThemeSelection.oneDarkPro => GalleryPalettes.oneDarkPro,
    AppThemeSelection.monokai => GalleryPalettes.monokai,
    AppThemeSelection.noctis => GalleryPalettes.noctis,
    AppThemeSelection.dracula => GalleryPalettes.dracula,
    AppThemeSelection.nord => GalleryPalettes.nord,
    AppThemeSelection.tokyoNight => GalleryPalettes.tokyoNight,
    AppThemeSelection.gruvboxDark => GalleryPalettes.gruvboxDark,
    AppThemeSelection.catppuccinMocha => GalleryPalettes.catppuccinMocha,
    AppThemeSelection.githubDark => GalleryPalettes.githubDark,
    AppThemeSelection.everforestDark => GalleryPalettes.everforestDark,
    AppThemeSelection.rosePine => GalleryPalettes.rosePine,
    AppThemeSelection.ayuMirage => GalleryPalettes.ayuMirage,
    AppThemeSelection.cutiePro => GalleryPalettes.cutiePro,
    AppThemeSelection.pinkAsHeck => GalleryPalettes.pinkAsHeck,
    AppThemeSelection.vitesseLight => GalleryPalettes.vitesseLight,
    AppThemeSelection.zenburn => GalleryPalettes.zenburn,
    AppThemeSelection.shadesOfPurple => GalleryPalettes.shadesOfPurple,
    AppThemeSelection.catppuccinFrappe => GalleryPalettes.catppuccinFrappe,
    AppThemeSelection.synthwave84 => GalleryPalettes.synthwave84,
  };

  /// Brightness of a pinned selection (defaults to light for [system], which
  /// follows the platform and is wired via [themeMode] instead).
  Brightness get brightness => scheme?.brightness ?? Brightness.light;

  /// The gallery section this selection belongs to.
  AppThemeGroup get group => switch (this) {
    AppThemeSelection.system => AppThemeGroup.system,
    AppThemeSelection.light ||
    AppThemeSelection.dark ||
    AppThemeSelection.softDark ||
    AppThemeSelection.highContrast => AppThemeGroup.defaultHearth,
    AppThemeSelection.blulocoLight ||
    AppThemeSelection.githubLight ||
    AppThemeSelection.catppuccinLatte ||
    AppThemeSelection.gruvboxLight ||
    AppThemeSelection.everforestLight ||
    AppThemeSelection.rosePineDawn ||
    AppThemeSelection.vitesseLight ||
    AppThemeSelection.tokyoNightLight ||
    AppThemeSelection.nordLight ||
    AppThemeSelection.kanagawaLotus ||
    AppThemeSelection.noctisLilac ||
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
    AppThemeSelection.softDark => 'Soft Dark',
    AppThemeSelection.highContrast => 'High contrast',
    AppThemeSelection.blulocoLight => 'Bluloco Light',
    AppThemeSelection.oneDarkPro => 'One Dark Pro',
    AppThemeSelection.monokai => 'Monokai',
    AppThemeSelection.noctis => 'Noctis',
    AppThemeSelection.githubLight => 'GitHub Light',
    AppThemeSelection.catppuccinLatte => 'Catppuccin Latte',
    AppThemeSelection.gruvboxLight => 'Gruvbox Light',
    AppThemeSelection.everforestLight => 'Everforest Light',
    AppThemeSelection.rosePineDawn => 'Rosé Pine Dawn',
    AppThemeSelection.ayuLight => 'Ayu Light',
    AppThemeSelection.tokyoNightLight => 'Tokyo Night Light',
    AppThemeSelection.nordLight => 'Nord Light',
    AppThemeSelection.kanagawaLotus => 'Kanagawa Lotus',
    AppThemeSelection.dracula => 'Dracula',
    AppThemeSelection.nord => 'Nord',
    AppThemeSelection.tokyoNight => 'Tokyo Night',
    AppThemeSelection.gruvboxDark => 'Gruvbox Dark',
    AppThemeSelection.catppuccinMocha => 'Catppuccin Mocha',
    AppThemeSelection.githubDark => 'GitHub Dark',
    AppThemeSelection.everforestDark => 'Everforest Dark',
    AppThemeSelection.rosePine => 'Rosé Pine',
    AppThemeSelection.ayuMirage => 'Ayu Mirage',
    AppThemeSelection.cutiePro => 'Cutie Pro',
    AppThemeSelection.pinkAsHeck => 'Pink as Heck',
    AppThemeSelection.vitesseLight => 'Vitesse Light',
    AppThemeSelection.zenburn => 'Zenburn',
    AppThemeSelection.shadesOfPurple => 'Shades of Purple',
    AppThemeSelection.catppuccinFrappe => 'Catppuccin Frappé',
    AppThemeSelection.synthwave84 => 'Synthwave ’84',
    AppThemeSelection.noctisLilac => 'Noctis Lilac',
  };

  /// One-line description shown under each option.
  String get description => switch (this) {
    AppThemeSelection.system => 'Match the device light/dark setting',
    AppThemeSelection.light => 'Warm light palette',
    AppThemeSelection.dark => 'Warm dark palette',
    AppThemeSelection.softDark => 'Warm dark on a softer, lighter canvas',
    AppThemeSelection.highContrast =>
      'Maximum contrast for dim rooms and low vision',
    AppThemeSelection.blulocoLight =>
      'Crisp cool-neutral canvas with vivid jewel tones',
    AppThemeSelection.oneDarkPro => 'One Dark Pro, the popular editor theme',
    AppThemeSelection.monokai => 'One Monokai — Monokai syntax on charcoal',
    AppThemeSelection.noctis => 'The original deep teal Noctis night',
    AppThemeSelection.githubLight => 'GitHub’s clean neutral light',
    AppThemeSelection.catppuccinLatte =>
      'Soft pastel light, community favorite',
    AppThemeSelection.gruvboxLight => 'Warm retro cream and earth tones',
    AppThemeSelection.everforestLight => 'Gentle green, easy on the eyes',
    AppThemeSelection.rosePineDawn => 'Muted rose and iris on warm paper',
    AppThemeSelection.ayuLight => 'Bright, minimal light with amber accents',
    AppThemeSelection.tokyoNightLight =>
      'Crisp indigo daylight, Tokyo Night’s day',
    AppThemeSelection.nordLight => 'Cool arctic snow-storm neutrals',
    AppThemeSelection.kanagawaLotus => 'Warm sumi-e paper with ink accents',
    AppThemeSelection.dracula => 'The classic purple-on-charcoal favorite',
    AppThemeSelection.nord => 'Cool arctic blues, understated',
    AppThemeSelection.tokyoNight => 'Neon indigo city-at-night palette',
    AppThemeSelection.gruvboxDark => 'Warm retro amber on charcoal',
    AppThemeSelection.catppuccinMocha => 'Cozy pastel dark, community favorite',
    AppThemeSelection.githubDark => 'GitHub’s neutral dark',
    AppThemeSelection.everforestDark => 'Soft forest green, low fatigue',
    AppThemeSelection.rosePine => 'Muted rose and iris in the dark',
    AppThemeSelection.ayuMirage => 'Smooth slate with amber accents',
    AppThemeSelection.cutiePro => 'Cute af dark pastel, pink-forward',
    AppThemeSelection.pinkAsHeck => 'Unapologetic hot pink on berry',
    AppThemeSelection.vitesseLight => 'Modern muted sage, teal and rose',
    AppThemeSelection.zenburn => 'The classic low-contrast warm grey',
    AppThemeSelection.shadesOfPurple => 'Bold gold on deep indigo',
    AppThemeSelection.catppuccinFrappe => 'Lighter blue-gray pastel Catppuccin',
    AppThemeSelection.synthwave84 => 'Glowing neon on retro purple',
    AppThemeSelection.noctisLilac => 'Gentle lilac Noctis daylight',
  };

  /// Resolves a persisted name back to a selection, or `null` if unknown.
  static AppThemeSelection? forName(String? name) {
    for (final s in AppThemeSelection.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// A curated display order for the Default group. Unlike the gallery
  /// sections (sorted A→Z), the built-in Default themes read more intuitively
  /// grouped by canvas darkness — Dark, its dimmed Soft Dark sibling, then the
  /// high-contrast and light options — rather than alphabetically.
  static const List<AppThemeSelection> _defaultGroupOrder = [
    AppThemeSelection.dark,
    AppThemeSelection.softDark,
    AppThemeSelection.highContrast,
    AppThemeSelection.light,
  ];

  /// The selections belonging to [group].
  ///
  /// Gallery sections (Light/Dark) are sorted alphabetically by [label]
  /// (case-insensitive) so built-in palettes list A→Z. The Default group uses
  /// the curated [_defaultGroupOrder] instead, which reads more naturally in
  /// the Settings pane than alphabetical ordering.
  static List<AppThemeSelection> inGroup(AppThemeGroup group) {
    final members = AppThemeSelection.values
        .where((s) => s.group == group)
        .toList();
    if (group == AppThemeGroup.defaultHearth) {
      members.sort(
        (a, b) => _defaultGroupOrder
            .indexOf(a)
            .compareTo(_defaultGroupOrder.indexOf(b)),
      );
      return members;
    }
    return members
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

  /// The current selection, or `null` when there is no [AppThemeScope] ancestor.
  /// Registers a rebuild dependency. Use this from widgets that may render
  /// outside the app shell (e.g. reused in tests) so a missing scope degrades
  /// gracefully instead of throwing.
  static AppThemeSelection? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return scope?.notifier?.value;
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
