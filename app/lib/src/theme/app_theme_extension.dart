import 'package:flutter/material.dart';

/// Semantic color tokens that Material 3's [ColorScheme] does not model
/// directly (§2). Each token is derived from the active [ColorScheme] so it
/// adapts automatically across light / dark / high-contrast.
///
/// **Every token is only ever paired with an icon + text label** by its
/// consuming widget — color alone never conveys meaning
/// (`docs/research/accessibility-baseline.md`). The presentation helpers that
/// pick the icon + label already live next to each widget (e.g.
/// `programStatusPresentation`); this extension supplies only the themed color.
///
/// Keyed to the real domain enums:
/// - `ProgramStatus { draft, finalized, performed }`
/// - `DanceStatus { active, deprecated, broken }`
@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.statusDraft,
    required this.statusFinalized,
    required this.statusPerformed,
    required this.statusDeprecated,
    required this.statusBroken,
    required this.dialectAccent,
    required this.performSurface,
    required this.performOnSurface,
    required this.performAccent,
    required this.performFocus,
  });

  // ProgramStatus tokens.
  final Color statusDraft;
  final Color statusFinalized;
  final Color statusPerformed;

  // DanceStatus tokens (active renders no chip → no token needed).
  final Color statusDeprecated;
  final Color statusBroken;

  /// Accent for dialect-scoped terms (leading border/underline), always shown
  /// with a small "dialect" badge.
  final Color dialectAccent;

  // Perform-mode / high-contrast tokens (§1b), shared with Phase 5.
  final Color performSurface;
  final Color performOnSurface;
  final Color performAccent;
  final Color performFocus;

  /// Derives semantic tokens from a [ColorScheme] so they track the theme.
  /// Perform tokens are fixed to the dark-stage high-contrast values (§1b)
  /// regardless of the active brightness — Perform is always high-contrast.
  factory AppThemeExtension.fromColorScheme(ColorScheme scheme) {
    return AppThemeExtension(
      statusDraft: scheme.onSurfaceVariant,
      statusFinalized: scheme.secondary,
      statusPerformed: scheme.tertiary,
      statusDeprecated: scheme.onSurfaceVariant,
      statusBroken: scheme.error,
      dialectAccent: scheme.tertiary,
      performSurface: const Color(0xFF0A0705),
      performOnSurface: const Color(0xFFFFF3EC),
      performAccent: const Color(0xFFFFD9C9),
      performFocus: const Color(0xFFFFD54A),
    );
  }

  @override
  AppThemeExtension copyWith({
    Color? statusDraft,
    Color? statusFinalized,
    Color? statusPerformed,
    Color? statusDeprecated,
    Color? statusBroken,
    Color? dialectAccent,
    Color? performSurface,
    Color? performOnSurface,
    Color? performAccent,
    Color? performFocus,
  }) {
    return AppThemeExtension(
      statusDraft: statusDraft ?? this.statusDraft,
      statusFinalized: statusFinalized ?? this.statusFinalized,
      statusPerformed: statusPerformed ?? this.statusPerformed,
      statusDeprecated: statusDeprecated ?? this.statusDeprecated,
      statusBroken: statusBroken ?? this.statusBroken,
      dialectAccent: dialectAccent ?? this.dialectAccent,
      performSurface: performSurface ?? this.performSurface,
      performOnSurface: performOnSurface ?? this.performOnSurface,
      performAccent: performAccent ?? this.performAccent,
      performFocus: performFocus ?? this.performFocus,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      statusDraft: Color.lerp(statusDraft, other.statusDraft, t)!,
      statusFinalized: Color.lerp(statusFinalized, other.statusFinalized, t)!,
      statusPerformed: Color.lerp(statusPerformed, other.statusPerformed, t)!,
      statusDeprecated: Color.lerp(
        statusDeprecated,
        other.statusDeprecated,
        t,
      )!,
      statusBroken: Color.lerp(statusBroken, other.statusBroken, t)!,
      dialectAccent: Color.lerp(dialectAccent, other.dialectAccent, t)!,
      performSurface: Color.lerp(performSurface, other.performSurface, t)!,
      performOnSurface: Color.lerp(
        performOnSurface,
        other.performOnSurface,
        t,
      )!,
      performAccent: Color.lerp(performAccent, other.performAccent, t)!,
      performFocus: Color.lerp(performFocus, other.performFocus, t)!,
    );
  }

  /// Convenience accessor: the [AppThemeExtension] registered on the current
  /// theme. Falls back to a scheme-derived default if none is registered.
  static AppThemeExtension of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppThemeExtension>() ??
        AppThemeExtension.fromColorScheme(theme.colorScheme);
  }
}
