import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/app_theme_extension.dart';
import 'package:compendium_app/src/theme/color_schemes.dart';

/// WCAG 2.x relative-contrast ratio between two opaque colors.
///
/// Uses Flutter's [Color.computeLuminance], which already implements the sRGB
/// relative-luminance formula, then applies the standard
/// `(L_lighter + 0.05) / (L_darker + 0.05)` ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('High-contrast color scheme — WCAG (ux-modernization §1b, UX-1 AC)', () {
    const hc = AppColorSchemes.highContrast;

    test('text pairings meet the ≥7:1 (AAA) target', () {
      // Each pairing below carries text/icon foregrounds, so it must clear 7:1.
      expect(
        _contrast(hc.onSurface, hc.surface),
        greaterThanOrEqualTo(7.0),
        reason: 'body text (onSurface on surface)',
      );
      expect(
        _contrast(hc.onPrimary, hc.primary),
        greaterThanOrEqualTo(7.0),
        reason: 'primary actions',
      );
      expect(
        _contrast(hc.onSecondary, hc.secondary),
        greaterThanOrEqualTo(7.0),
        reason: 'secondary accents',
      );
      expect(
        _contrast(hc.onTertiary, hc.tertiary),
        greaterThanOrEqualTo(7.0),
        reason: 'tertiary / performed status',
      );
      expect(
        _contrast(hc.error, hc.surface),
        greaterThanOrEqualTo(7.0),
        reason: 'error alerts on surface',
      );
      expect(
        _contrast(hc.onSurfaceVariant, hc.surface),
        greaterThanOrEqualTo(7.0),
        reason: 'secondary text (onSurfaceVariant on surface)',
      );
    });

    test('non-text UI (outline, focus ring) meets the ≥3:1 target', () {
      expect(
        _contrast(hc.outline, hc.surface),
        greaterThanOrEqualTo(3.0),
        reason: 'component borders',
      );
      // The high-visibility focus ring (#FFD54A) must be distinguishable on
      // the stage-dark surface.
      expect(
        _contrast(const Color(0xFFFFD54A), hc.surface),
        greaterThanOrEqualTo(3.0),
        reason: 'focus ring on surface',
      );
    });
  });

  group('High-contrast theme — outline-driven + focus ring (UX-1)', () {
    final theme = AppTheme.highContrast;
    final ext = theme.extension<AppThemeExtension>()!;

    test('focus-ring token is the high-visibility ochre at ≥3px', () {
      expect(ext.focusRing, const Color(0xFFFFD54A));
      expect(ext.focusRingWidth, greaterThanOrEqualTo(3.0));
    });

    test('input fields are outlined with a ≥3px focus ring', () {
      final decoration = theme.inputDecorationTheme;
      final enabled = decoration.enabledBorder as OutlineInputBorder;
      final focused = decoration.focusedBorder as OutlineInputBorder;

      expect(
        enabled.borderSide.width,
        greaterThan(0),
        reason: 'fields must always show a real border at HC',
      );
      expect(focused.borderSide.width, greaterThanOrEqualTo(3.0));
      expect(focused.borderSide.color, ext.focusRing);
    });

    test('cards and dialogs are defined by an outline, not elevation', () {
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.side.width, greaterThan(0));
      expect(cardShape.side.color, theme.colorScheme.outline);
      expect(theme.cardTheme.elevation, 0);

      final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
      expect(dialogShape.side.width, greaterThan(0));
    });

    test('buttons thicken to the focus ring when focused', () {
      final side = theme.outlinedButtonTheme.style!.side!;
      final focusedSide = side.resolve({WidgetState.focused})!;
      final restingSide = side.resolve(<WidgetState>{})!;

      expect(focusedSide.width, greaterThanOrEqualTo(3.0));
      expect(focusedSide.color, ext.focusRing);
      expect(
        restingSide.width,
        greaterThan(0),
        reason: 'buttons carry a real border even when not focused',
      );
    });
  });

  group('Light / dark themes are unaffected by the HC sub-themes', () {
    test('focus ring is the 2px primary ring, not the HC ochre', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final ext = theme.extension<AppThemeExtension>()!;
        expect(ext.focusRingWidth, 2.0);
        expect(ext.focusRing, theme.colorScheme.primary);
      }
    });

    test('no HC outline sub-themes leak into light/dark', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        // These stay at M3 defaults until UX-2 — the HC overrides must not
        // apply to the default themes.
        expect(theme.cardTheme.shape, isNull);
        expect(theme.outlinedButtonTheme.style, isNull);
        expect(theme.filledButtonTheme.style, isNull);
        // No outlined-input override leaked: the default has no forced borders.
        expect(theme.inputDecorationTheme.enabledBorder, isNull);
        expect(theme.inputDecorationTheme.focusedBorder, isNull);
        expect(theme.dividerTheme.color, isNull);
      }
    });
  });
}
