import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'wcag.dart';

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
/// - `DanceStatus { active, deprecated, broken, draft, variation }`
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
    required this.focusRing,
    required this.focusRingWidth,
  });

  /// The alpha of the tinted fill behind a status token — the status chip and
  /// the dance-status banner on the detail screen and Perform card — and, for
  /// one look, behind the numbered markers in the ContraDB import (tinted
  /// with primary or onSurfaceVariant). [_chipSafe] eases each status token
  /// until an `onSurface` label clears AA on this tint, so a site that uses a
  /// stronger alpha loses that guarantee; `palette_contrast_test.dart` checks
  /// the marker tints at this alpha too.
  static const double statusTintAlpha = 0.10;

  // ProgramStatus tokens.
  final Color statusDraft;
  final Color statusFinalized;
  final Color statusPerformed;

  // DanceStatus tokens (active renders no chip; draft and variation reuse the
  // neutral deprecated token).
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

  /// The keyboard-focus ring color for the *active* theme. In high-contrast
  /// this is the high-visibility ochre (`#FFD54A`, ≥3:1 on surface, §1b); in
  /// light/dark it is the scheme primary. Widgets that draw their own focus
  /// affordance (and Phase 5 Perform mode) read this so focus is consistent.
  final Color focusRing;

  /// The focus-ring stroke width in logical px. High-contrast uses ≥3px per the
  /// UX-1 acceptance criteria; other themes use a 2px ring.
  final double focusRingWidth;

  /// Derives semantic tokens from a [ColorScheme] so they track the theme.
  /// Perform tokens are fixed to the dark-stage high-contrast values (§1b)
  /// regardless of the active brightness — Perform is always high-contrast.
  ///
  /// [highContrast] selects the high-visibility focus ring (≥3px ochre) used by
  /// the high-contrast theme; light/dark themes get a 2px primary ring.
  factory AppThemeExtension.fromColorScheme(
    ColorScheme scheme, {
    bool highContrast = false,
  }) {
    return AppThemeExtension(
      statusDraft: _chipSafe(scheme.onSurfaceVariant, scheme),
      statusFinalized: _doneColor(scheme),
      statusPerformed: _chipSafe(scheme.tertiary, scheme),
      statusDeprecated: _chipSafe(scheme.onSurfaceVariant, scheme),
      statusBroken: _chipSafe(scheme.error, scheme),
      dialectAccent: scheme.tertiary,
      performSurface: const Color(0xFF0A0705),
      performOnSurface: const Color(0xFFFFF3EC),
      performAccent: const Color(0xFFFFD9C9),
      performFocus: const Color(0xFFFFD54A),
      focusRing: highContrast ? const Color(0xFFFFD54A) : scheme.primary,
      focusRingWidth: highContrast ? 3.0 : 2.0,
    );
  }

  /// The "done" green for the Finalized status (§2: green means ready).
  ///
  /// A palette's secondary when it is already green-to-cyan (hue 90–180°), as
  /// its designer chose it; otherwise a green at hue 140° with the primary's
  /// saturation and lightness. Either way it is then moved away from the
  /// surface until it clears 3:1 as an icon on the canvas and on the container
  /// tiers (a chip can sit on a card or sheet). Neither secondary nor
  /// primary works for every palette: in Blue Hour secondary is a dusty rose,
  /// and in High contrast, Monokai and Gruvbox primary is red or orange — both
  /// read as a warning beside Broken.
  static Color _doneColor(ColorScheme scheme) {
    final secondary = HSLColor.fromColor(scheme.secondary);
    final primary = HSLColor.fromColor(scheme.primary);
    var green = secondary.hue >= 90 && secondary.hue <= 180
        ? secondary
        : HSLColor.fromAHSL(
            1,
            140,
            primary.saturation.clamp(0.35, 0.75),
            primary.lightness,
          );
    final towardContrast = scheme.surface.computeLuminance() > 0.5
        ? -0.02
        : 0.02;
    for (var step = 0; step < 50; step++) {
      if (Wcag.contrastRatio(green.toColor(), scheme.surface) >=
              Wcag.aaNonText &&
          Wcag.contrastRatio(green.toColor(), scheme.surfaceContainerHighest) >=
              Wcag.aaNonText) {
        break;
      }
      green = green.withLightness(
        (green.lightness + towardContrast).clamp(0.0, 1.0),
      );
    }
    return _chipSafe(green.toColor(), scheme);
  }

  /// [token] eased toward the surface only as far as needed for the status
  /// chip's `onSurface` label to clear AA against the [statusTintAlpha] tint
  /// (see `StatusChip`), laid over the canvas or over `surfaceContainerLow`,
  /// the tier of the cards and bottom sheets a chip can sit on. `scheme.error`
  /// is derived to read as text on the surface, which can darken (or, on dark
  /// themes, lighten) the tint enough to pull the label below 4.5:1, and the
  /// same holds for onSurfaceVariant and tertiary behind Draft, Deprecated and
  /// Performed. The status token is only an icon, border and tint, so it is
  /// relaxed independently and leaves the scheme's own roles untouched.
  static Color _chipSafe(Color token, ColorScheme scheme) {
    for (var step = 0; step <= 20; step++) {
      final c = Color.lerp(token, scheme.surface, step / 20)!;
      final tint = c.withValues(alpha: statusTintAlpha);
      if (Wcag.meetsAA(
            scheme.onSurface,
            Color.alphaBlend(tint, scheme.surface),
          ) &&
          Wcag.meetsAA(
            scheme.onSurface,
            Color.alphaBlend(tint, scheme.surfaceContainerLow),
          )) {
        return c;
      }
    }
    // No candidate can pass (e.g. a custom theme whose onSurface already
    // fails against its surface): keep the original token rather than fading
    // the icon into the surface.
    return token;
  }

  /// The colour to draw a status icon in, for a status chip or banner tinted
  /// with [token] (one of the status tokens above) at [statusTintAlpha].
  ///
  /// [_chipSafe] can only ease a token toward the surface, which lightens the
  /// icon along with the tint; in a few palettes (Everforest Light's Broken,
  /// for one) no single colour then gives both the label 4.5:1 and the icon
  /// 3:1 on the tint. The icon is therefore moved apart from the token, toward
  /// `onSurface`, only as far as it needs to clear 3:1 on the tint laid over
  /// the canvas and over `surfaceContainerLow`. The tint and the border keep
  /// [token], so the label and border guarantees are untouched; where the
  /// token already clears 3:1, the icon is the token.
  static Color statusIconColor(Color token, ColorScheme scheme) {
    final tints = [
      for (final tier in [scheme.surface, scheme.surfaceContainerLow])
        Color.alphaBlend(token.withValues(alpha: statusTintAlpha), tier),
    ];
    for (var step = 0; step <= 20; step++) {
      final c = Color.lerp(token, scheme.onSurface, step / 20)!;
      if (tints.every((tint) => Wcag.contrastRatio(c, tint) >= 3)) return c;
    }
    return scheme.onSurface;
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
    Color? focusRing,
    double? focusRingWidth,
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
      focusRing: focusRing ?? this.focusRing,
      focusRingWidth: focusRingWidth ?? this.focusRingWidth,
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
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      focusRingWidth: lerpDouble(focusRingWidth, other.focusRingWidth, t)!,
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
