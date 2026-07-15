import 'package:flutter/material.dart';

/// A user-authored theme that lives only on-device
/// (`docs/design/ux-modernization.md` §4B). Rather than juggle the ~30 named
/// [ColorScheme] getters/setters, a custom theme stores an editable map of
/// role key → packed ARGB int; [toScheme] layers those over the M3 default
/// scheme for the theme's [brightness] so any role the user didn't touch keeps
/// a sensible default and the result is always a valid [ColorScheme].
@immutable
class CustomTheme {
  const CustomTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.roles,
  });

  /// Stable local identifier (never shown to the user).
  final String id;

  /// User-facing name shown in the gallery and editor.
  final String name;

  /// Light or dark — picks the base scheme and drives [ThemeMode].
  final Brightness brightness;

  /// Role key (see [CustomThemeRoles.keys]) → packed ARGB int
  /// ([Color.toARGB32]). Only edited/known roles are stored.
  final Map<String, int> roles;

  bool get isDark => brightness == Brightness.dark;

  /// The [ThemeMode] to pin when this theme is active (both MaterialApp slots
  /// are set to the same theme, so mode just follows the brightness).
  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  /// The color currently assigned to [key], or `null` if unset.
  Color? color(String key) {
    final v = roles[key];
    return v == null ? null : Color(v);
  }

  /// Builds a full [ColorScheme] by overlaying the stored roles onto the M3
  /// default scheme for [brightness]. Unset roles keep their default.
  ColorScheme toScheme() {
    final base = isDark ? const ColorScheme.dark() : const ColorScheme.light();
    Color? c(String key) => color(key);
    return base.copyWith(
      brightness: brightness,
      primary: c('primary'),
      onPrimary: c('onPrimary'),
      primaryContainer: c('primaryContainer'),
      onPrimaryContainer: c('onPrimaryContainer'),
      secondary: c('secondary'),
      onSecondary: c('onSecondary'),
      secondaryContainer: c('secondaryContainer'),
      onSecondaryContainer: c('onSecondaryContainer'),
      tertiary: c('tertiary'),
      onTertiary: c('onTertiary'),
      tertiaryContainer: c('tertiaryContainer'),
      onTertiaryContainer: c('onTertiaryContainer'),
      error: c('error'),
      onError: c('onError'),
      errorContainer: c('errorContainer'),
      onErrorContainer: c('onErrorContainer'),
      surface: c('surface'),
      onSurface: c('onSurface'),
      onSurfaceVariant: c('onSurfaceVariant'),
      surfaceContainerHighest: c('surfaceContainerHighest'),
      surfaceContainerHigh: c('surfaceContainerHigh'),
      surfaceContainer: c('surfaceContainer'),
      surfaceContainerLow: c('surfaceContainerLow'),
      surfaceContainerLowest: c('surfaceContainerLowest'),
      inverseSurface: c('inverseSurface'),
      onInverseSurface: c('onInverseSurface'),
      inversePrimary: c('inversePrimary'),
      outline: c('outline'),
      outlineVariant: c('outlineVariant'),
      surfaceTint: c('surfaceTint'),
      shadow: c('shadow'),
      scrim: c('scrim'),
    );
  }

  CustomTheme copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    Map<String, int>? roles,
  }) {
    return CustomTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      brightness: brightness ?? this.brightness,
      roles: roles ?? this.roles,
    );
  }

  /// Returns a copy with [key] set to [color].
  CustomTheme withColor(String key, Color color) {
    return copyWith(roles: {...roles, key: color.toARGB32()});
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'brightness': brightness == Brightness.dark ? 'dark' : 'light',
    'roles': roles,
  };

  static CustomTheme fromJson(Map<String, Object?> json) {
    final rawRoles = (json['roles'] as Map).cast<String, Object?>();
    return CustomTheme(
      id: json['id'] as String,
      name: json['name'] as String,
      brightness: (json['brightness'] as String) == 'dark'
          ? Brightness.dark
          : Brightness.light,
      roles: {
        for (final entry in rawRoles.entries)
          if (CustomThemeRoles.keys.contains(entry.key))
            entry.key: (entry.value as num).toInt(),
      },
    );
  }

  /// Captures every editable role from an existing [scheme] into a role map —
  /// used when copying a built-in (or another custom) theme to seed the editor.
  static Map<String, int> rolesFromScheme(ColorScheme scheme) => {
    'primary': scheme.primary.toARGB32(),
    'onPrimary': scheme.onPrimary.toARGB32(),
    'primaryContainer': scheme.primaryContainer.toARGB32(),
    'onPrimaryContainer': scheme.onPrimaryContainer.toARGB32(),
    'secondary': scheme.secondary.toARGB32(),
    'onSecondary': scheme.onSecondary.toARGB32(),
    'secondaryContainer': scheme.secondaryContainer.toARGB32(),
    'onSecondaryContainer': scheme.onSecondaryContainer.toARGB32(),
    'tertiary': scheme.tertiary.toARGB32(),
    'onTertiary': scheme.onTertiary.toARGB32(),
    'tertiaryContainer': scheme.tertiaryContainer.toARGB32(),
    'onTertiaryContainer': scheme.onTertiaryContainer.toARGB32(),
    'error': scheme.error.toARGB32(),
    'onError': scheme.onError.toARGB32(),
    'errorContainer': scheme.errorContainer.toARGB32(),
    'onErrorContainer': scheme.onErrorContainer.toARGB32(),
    'surface': scheme.surface.toARGB32(),
    'onSurface': scheme.onSurface.toARGB32(),
    'onSurfaceVariant': scheme.onSurfaceVariant.toARGB32(),
    'surfaceContainerHighest': scheme.surfaceContainerHighest.toARGB32(),
    'surfaceContainerHigh': scheme.surfaceContainerHigh.toARGB32(),
    'surfaceContainer': scheme.surfaceContainer.toARGB32(),
    'surfaceContainerLow': scheme.surfaceContainerLow.toARGB32(),
    'surfaceContainerLowest': scheme.surfaceContainerLowest.toARGB32(),
    'inverseSurface': scheme.inverseSurface.toARGB32(),
    'onInverseSurface': scheme.onInverseSurface.toARGB32(),
    'inversePrimary': scheme.inversePrimary.toARGB32(),
    'outline': scheme.outline.toARGB32(),
    'outlineVariant': scheme.outlineVariant.toARGB32(),
    'surfaceTint': scheme.surfaceTint.toARGB32(),
    'shadow': scheme.shadow.toARGB32(),
    'scrim': scheme.scrim.toARGB32(),
  };
}

/// A single editable color role, with a human label for the editor.
@immutable
class ColorRole {
  const ColorRole(this.key, this.label);
  final String key;
  final String label;
}

/// A foreground/background pair whose WCAG contrast the editor badges live.
@immutable
class ContrastPair {
  const ContrastPair({
    required this.foreground,
    required this.background,
    required this.label,
    this.largeOrNonText = false,
  });

  final String foreground;
  final String background;
  final String label;

  /// True for non-text UI (e.g. outlines) checked at 3:1 instead of 4.5:1.
  final bool largeOrNonText;
}

/// A labeled group of roles shown together in the editor.
@immutable
class RoleGroup {
  const RoleGroup({
    required this.label,
    required this.roles,
    this.pairs = const [],
  });

  final String label;
  final List<ColorRole> roles;
  final List<ContrastPair> pairs;
}

/// The single source of truth for every editable role, how they group in the
/// editor, and which pairs get a live contrast badge. Keeps [CustomTheme] JSON,
/// the editor UI, and the tests in lockstep.
class CustomThemeRoles {
  const CustomThemeRoles._();

  static final List<RoleGroup> groups = [
    const RoleGroup(
      label: 'Primary',
      roles: [
        ColorRole('primary', 'Primary'),
        ColorRole('onPrimary', 'On primary'),
        ColorRole('primaryContainer', 'Primary container'),
        ColorRole('onPrimaryContainer', 'On primary container'),
      ],
      pairs: [
        ContrastPair(
          foreground: 'onPrimary',
          background: 'primary',
          label: 'Text on primary',
        ),
        ContrastPair(
          foreground: 'onPrimaryContainer',
          background: 'primaryContainer',
          label: 'Text on primary container',
        ),
      ],
    ),
    const RoleGroup(
      label: 'Secondary',
      roles: [
        ColorRole('secondary', 'Secondary'),
        ColorRole('onSecondary', 'On secondary'),
        ColorRole('secondaryContainer', 'Secondary container'),
        ColorRole('onSecondaryContainer', 'On secondary container'),
      ],
      pairs: [
        ContrastPair(
          foreground: 'onSecondary',
          background: 'secondary',
          label: 'Text on secondary',
        ),
        ContrastPair(
          foreground: 'onSecondaryContainer',
          background: 'secondaryContainer',
          label: 'Text on secondary container',
        ),
      ],
    ),
    const RoleGroup(
      label: 'Tertiary',
      roles: [
        ColorRole('tertiary', 'Tertiary'),
        ColorRole('onTertiary', 'On tertiary'),
        ColorRole('tertiaryContainer', 'Tertiary container'),
        ColorRole('onTertiaryContainer', 'On tertiary container'),
      ],
      pairs: [
        ContrastPair(
          foreground: 'onTertiary',
          background: 'tertiary',
          label: 'Text on tertiary',
        ),
        ContrastPair(
          foreground: 'onTertiaryContainer',
          background: 'tertiaryContainer',
          label: 'Text on tertiary container',
        ),
      ],
    ),
    const RoleGroup(
      label: 'Error',
      roles: [
        ColorRole('error', 'Error'),
        ColorRole('onError', 'On error'),
        ColorRole('errorContainer', 'Error container'),
        ColorRole('onErrorContainer', 'On error container'),
      ],
      pairs: [
        ContrastPair(
          foreground: 'onError',
          background: 'error',
          label: 'Text on error',
        ),
        ContrastPair(
          foreground: 'onErrorContainer',
          background: 'errorContainer',
          label: 'Text on error container',
        ),
      ],
    ),
    const RoleGroup(
      label: 'Surface & text',
      roles: [
        ColorRole('surface', 'Surface'),
        ColorRole('onSurface', 'On surface'),
        ColorRole('onSurfaceVariant', 'On surface variant'),
        ColorRole('inverseSurface', 'Inverse surface'),
        ColorRole('onInverseSurface', 'On inverse surface'),
        ColorRole('inversePrimary', 'Inverse primary'),
      ],
      pairs: [
        ContrastPair(
          foreground: 'onSurface',
          background: 'surface',
          label: 'Body text on surface',
        ),
        ContrastPair(
          foreground: 'onSurfaceVariant',
          background: 'surface',
          label: 'Secondary text on surface',
        ),
        ContrastPair(
          foreground: 'onInverseSurface',
          background: 'inverseSurface',
          label: 'Text on inverse surface',
        ),
      ],
    ),
    const RoleGroup(
      label: 'Surface containers',
      roles: [
        ColorRole('surfaceContainerLowest', 'Container lowest'),
        ColorRole('surfaceContainerLow', 'Container low'),
        ColorRole('surfaceContainer', 'Container'),
        ColorRole('surfaceContainerHigh', 'Container high'),
        ColorRole('surfaceContainerHighest', 'Container highest'),
      ],
    ),
    const RoleGroup(
      label: 'Outline & effects',
      roles: [
        ColorRole('outline', 'Outline'),
        ColorRole('outlineVariant', 'Outline variant'),
        ColorRole('surfaceTint', 'Surface tint'),
        ColorRole('shadow', 'Shadow'),
        ColorRole('scrim', 'Scrim'),
      ],
      pairs: [
        ContrastPair(
          foreground: 'outline',
          background: 'surface',
          label: 'Outline on surface',
          largeOrNonText: true,
        ),
      ],
    ),
  ];

  /// Every editable role in editor order.
  static final List<ColorRole> all = [for (final g in groups) ...g.roles];

  /// The set of valid role keys (used to filter unknown keys on load).
  static final Set<String> keys = {for (final r in all) r.key};

  /// Every badged contrast pair across all groups.
  static final List<ContrastPair> allPairs = [
    for (final g in groups) ...g.pairs,
  ];
}
