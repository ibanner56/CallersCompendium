import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/app_theme_extension.dart';
import 'package:compendium_app/src/theme/color_schemes.dart';
import 'package:compendium_app/src/theme/palette_schemes.dart';
import 'package:compendium_app/src/theme/set_list_accents.dart';

/// WCAG 2.x relative-luminance contrast ratio (mirrors the derivation helper
/// and `high_contrast_theme_test.dart`).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The gallery palettes under test, keyed by their selection name. Includes
/// the Default-group "Soft dark" so its dimmed canvas is held to the same AA bar.
final Map<String, ColorScheme> _galleryPalettes = {
  'softDark': AppColorSchemes.softDark,
  'blulocoLight': GalleryPalettes.blulocoLight,
  'oneDarkPro': GalleryPalettes.oneDarkPro,
  'monokai': GalleryPalettes.monokai,
  'noctis': GalleryPalettes.noctis,
  'githubLight': GalleryPalettes.githubLight,
  'catppuccinLatte': GalleryPalettes.catppuccinLatte,
  'gruvboxLight': GalleryPalettes.gruvboxLight,
  'everforestLight': GalleryPalettes.everforestLight,
  'rosePineDawn': GalleryPalettes.rosePineDawn,
  'ayuLight': GalleryPalettes.ayuLight,
  'tokyoNightLight': GalleryPalettes.tokyoNightLight,
  'nordLight': GalleryPalettes.nordLight,
  'kanagawaLotus': GalleryPalettes.kanagawaLotus,
  'dracula': GalleryPalettes.dracula,
  'nord': GalleryPalettes.nord,
  'tokyoNight': GalleryPalettes.tokyoNight,
  'gruvboxDark': GalleryPalettes.gruvboxDark,
  'catppuccinMocha': GalleryPalettes.catppuccinMocha,
  'githubDark': GalleryPalettes.githubDark,
  'everforestDark': GalleryPalettes.everforestDark,
  'rosePine': GalleryPalettes.rosePine,
  'ayuMirage': GalleryPalettes.ayuMirage,
  'cutiePro': GalleryPalettes.cutiePro,
  'pinkAsHeck': GalleryPalettes.pinkAsHeck,
  'vitesseLight': GalleryPalettes.vitesseLight,
  'zenburn': GalleryPalettes.zenburn,
  'shadesOfPurple': GalleryPalettes.shadesOfPurple,
  'catppuccinFrappe': GalleryPalettes.catppuccinFrappe,
  'synthwave84': GalleryPalettes.synthwave84,
  'noctisLilac': GalleryPalettes.noctisLilac,
};

/// Every selectable scheme: the gallery plus the three built-ins that are not
/// in it (Blue Hour light/dark and High contrast). 34 in all; the last test in
/// this file pins that to [AppThemeSelection] so a new palette cannot be left
/// out.
final Map<String, ColorScheme> _allSchemes = {
  'light': AppColorSchemes.light,
  'dark': AppColorSchemes.dark,
  'highContrast': AppColorSchemes.highContrast,
  ..._galleryPalettes,
};

ThemeData _themeFor(String name, ColorScheme scheme) => name == 'highContrast'
    ? AppTheme.highContrast
    : AppTheme.fromScheme(scheme);

void main() {
  const double aaText = 4.5; // body text & icons
  const double aaNonText = 3.0; // large text & non-text UI

  group('Every selectable scheme — contrast and tier pairs', () {
    _allSchemes.forEach((name, scheme) {
      group(name, () {
        void expectRatio(String role, Color fg, Color bg, double target) {
          expect(
            _contrast(fg, bg),
            greaterThanOrEqualTo(target),
            reason: '$name: $role must clear $target:1',
          );
        }

        test('surface-container tiers are distinct from surface', () {
          expect(
            scheme.surfaceContainerLow,
            isNot(scheme.surface),
            reason: '$name: cards would sit flat on the canvas',
          );
          expect(scheme.surfaceContainer, isNot(scheme.surfaceContainerLow));
          expect(scheme.surfaceContainerHigh, isNot(scheme.surfaceContainer));
          expect(
            scheme.surfaceContainerHighest,
            isNot(scheme.surfaceContainerHigh),
          );
          // Dim and Bright straddle the canvas in Material 3's direction.
          final dark = scheme.brightness == Brightness.dark;
          expect(
            dark ? scheme.surfaceBright : scheme.surfaceDim,
            isNot(scheme.surface),
            reason: '$name: surfaceDim/surfaceBright left at default',
          );
        });

        // Every tier something is drawn on: the canvas, cards (Low), menus
        // (default), dialogs (High), filled inputs (Highest), and Material's
        // Lowest, Dim and Bright.
        final tiers = <(String, Color)>[
          ('surface', scheme.surface),
          ('surfaceContainerLowest', scheme.surfaceContainerLowest),
          ('surfaceContainerLow', scheme.surfaceContainerLow),
          ('surfaceContainer', scheme.surfaceContainer),
          ('surfaceContainerHigh', scheme.surfaceContainerHigh),
          ('surfaceContainerHighest', scheme.surfaceContainerHighest),
          ('surfaceDim', scheme.surfaceDim),
          ('surfaceBright', scheme.surfaceBright),
        ];

        // Dim and Bright are left out of the checks below: neither the app
        // nor Flutter's Material widgets draw anything on them.
        final drawnTiers = tiers.where(
          (t) => t.$1 != 'surfaceDim' && t.$1 != 'surfaceBright',
        );

        test('text and accents clear AA on the canvas and every container '
            'tier', () {
          for (final (role, tier) in drawnTiers) {
            for (final (fgRole, fg) in [
              ('onSurface', scheme.onSurface),
              ('onSurfaceVariant', scheme.onSurfaceVariant),
              ('primary', scheme.primary),
              ('secondary', scheme.secondary),
              ('tertiary', scheme.tertiary),
              ('error', scheme.error),
            ]) {
              expectRatio('$fgRole/$role', fg, tier, aaText);
            }
          }
        });

        test('outline (input and chip borders) clears 3:1 on every '
            'container tier', () {
          for (final (role, tier) in drawnTiers) {
            expectRatio('outline/$role', scheme.outline, tier, aaNonText);
          }
        });

        test('SnackBar action reads on inverseSurface', () {
          expectRatio(
            'inversePrimary/inverseSurface',
            scheme.inversePrimary,
            scheme.inverseSurface,
            aaText,
          );
        });

        test('chip border is a visible boundary', () {
          final side =
              _themeFor(name, scheme).chipTheme.shape as RoundedRectangleBorder;
          expectRatio(
            'chip border/surface',
            side.side.color,
            scheme.surface,
            aaNonText,
          );
        });

        test('set-list accents clear 3:1 on the canvas', () {
          for (final family in FormationFamily.values) {
            final accent = setListAccent(
              family,
              brightPalette: scheme.brightness == Brightness.dark,
            )!;
            for (final (role, bg) in [
              ('surface', scheme.surface),
              ('surfaceContainerLow', scheme.surfaceContainerLow),
            ]) {
              expectRatio('${family.name} accent/$role', accent, bg, aaNonText);
            }
          }
        });

        test('focus ring clears 3:1 on every surface tier', () {
          // FocusRingLayer draws the ring outside the focused widget, over
          // whatever tier the widget sits on, so it must stand out from all.
          final ext = _themeFor(name, scheme).extension<AppThemeExtension>()!;
          for (final (role, tier) in drawnTiers) {
            expectRatio('focusRing/$role', ext.focusRing, tier, aaNonText);
          }
          expect(ext.focusRingWidth, greaterThanOrEqualTo(2));
        });

        test('the inverse accent clears 3:1 on the inverse surface', () {
          // A snackbar is drawn on inverseSurface; FocusRingLayer rings a
          // control inside one in inversePrimary.
          final theme = _themeFor(name, scheme);
          expectRatio(
            'inversePrimary/inverseSurface',
            theme.colorScheme.inversePrimary,
            theme.colorScheme.inverseSurface,
            aaNonText,
          );
        });

        test('status chips: label and icon on tint, full-alpha border', () {
          final ext = _themeFor(name, scheme).extension<AppThemeExtension>()!;
          for (final (role, token) in [
            ('statusDraft', ext.statusDraft),
            ('statusFinalized', ext.statusFinalized),
            ('statusPerformed', ext.statusPerformed),
            ('statusDeprecated', ext.statusDeprecated),
            ('statusBroken', ext.statusBroken),
            // The "Archived" chip (ProgramArchivedChip) is neutral.
            ('archived (outline)', scheme.outline),
          ]) {
            // A chip sits on the canvas, or on a card or bottom sheet (Low).
            for (final (tierRole, tier) in [
              ('surface', scheme.surface),
              ('surfaceContainerLow', scheme.surfaceContainerLow),
            ]) {
              final tint = Color.alphaBlend(
                token.withValues(alpha: AppThemeExtension.statusTintAlpha),
                tier,
              );
              expectRatio(
                'onSurface/$role tint on $tierRole',
                scheme.onSurface,
                tint,
                aaText,
              );
              // The chip's icon is drawn on that same tint.
              expectRatio(
                '$role icon/$role tint on $tierRole',
                AppThemeExtension.statusIconColor(token, scheme),
                tint,
                aaNonText,
              );
            }
            for (final (tierRole, tier) in [
              ('surface', scheme.surface),
              ('surfaceContainerLow', scheme.surfaceContainerLow),
            ]) {
              expectRatio('$role border/$tierRole', token, tier, aaNonText);
            }
          }
          // The ContraDB import's numbered markers use the same tint behind
          // an onSurface number, over primary or onSurfaceVariant.
          for (final (role, token) in [
            ('primary', scheme.primary),
            ('onSurfaceVariant', scheme.onSurfaceVariant),
          ]) {
            final tint = Color.alphaBlend(
              token.withValues(alpha: AppThemeExtension.statusTintAlpha),
              scheme.surface,
            );
            expectRatio('onSurface/$role tint', scheme.onSurface, tint, aaText);
          }
        });
      });
    });
  });

  group('Gallery palettes — WCAG 2.2 AA (§4A / §7 UX-6)', () {
    _galleryPalettes.forEach((name, scheme) {
      group(name, () {
        void expectText(String role, Color fg, Color bg) {
          expect(
            _contrast(fg, bg),
            greaterThanOrEqualTo(aaText),
            reason: '$name: $role must clear AA text 4.5:1',
          );
        }

        test('body & variant text on surface', () {
          expectText('onSurface/surface', scheme.onSurface, scheme.surface);
          expectText(
            'onSurfaceVariant/surface',
            scheme.onSurfaceVariant,
            scheme.surface,
          );
        });

        test('primary and error read as text on surface', () {
          expectText('primary/surface', scheme.primary, scheme.surface);
          expectText('error/surface', scheme.error, scheme.surface);
        });

        test('accent on-colors', () {
          expectText('onPrimary/primary', scheme.onPrimary, scheme.primary);
          expectText(
            'onSecondary/secondary',
            scheme.onSecondary,
            scheme.secondary,
          );
          expectText('onTertiary/tertiary', scheme.onTertiary, scheme.tertiary);
          expectText('onError/error', scheme.onError, scheme.error);
        });

        test('container on-colors', () {
          expectText(
            'onPrimaryContainer/primaryContainer',
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          );
          expectText(
            'onSecondaryContainer/secondaryContainer',
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          );
          expectText(
            'onTertiaryContainer/tertiaryContainer',
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          );
          expectText(
            'onErrorContainer/errorContainer',
            scheme.onErrorContainer,
            scheme.errorContainer,
          );
        });

        test('non-text UI (borders, focus ring) clears 3:1', () {
          expect(
            _contrast(scheme.outline, scheme.surface),
            greaterThanOrEqualTo(aaNonText),
            reason: '$name: outline/surface must clear 3:1',
          );
          // The focus ring is scheme.primary (AppThemeExtension); it must be a
          // visible non-text UI element against the surface.
          expect(
            _contrast(scheme.primary, scheme.surface),
            greaterThanOrEqualTo(aaNonText),
            reason: '$name: primary (focus ring) vs surface must clear 3:1',
          );
        });

        test('Perform mode stays >=7:1 regardless of palette (§4A.4)', () {
          final theme = AppTheme.fromScheme(scheme);
          final ext = theme.extension<AppThemeExtension>();
          expect(ext, isNotNull, reason: '$name: missing AppThemeExtension');
          expect(
            _contrast(ext!.performOnSurface, ext.performSurface),
            greaterThanOrEqualTo(7.0),
            reason: '$name: Perform text must stay >=7:1',
          );
          expect(
            _contrast(ext.performAccent, ext.performSurface),
            greaterThanOrEqualTo(4.5),
            reason: '$name: Perform accent must stay legible',
          );
        });
      });
    });
  });

  test('these pairs cover every selectable scheme', () {
    final pinned = AppThemeSelection.values
        .where((s) => s.isPinned)
        .map((s) => s.scheme)
        .toSet();
    expect(_allSchemes.values.toSet(), pinned);
    expect(_allSchemes, hasLength(34));
  });

  test('every non-system selection resolves to a scheme', () {
    for (final selection in AppThemeSelection.values) {
      if (selection == AppThemeSelection.system) {
        expect(selection.scheme, isNull);
        expect(selection.isPinned, isFalse);
      } else {
        expect(
          selection.scheme,
          isNotNull,
          reason: '${selection.name} must pin a ColorScheme',
        );
        expect(selection.isPinned, isTrue);
        expect(selection.scheme!.brightness, selection.brightness);
      }
    }
  });
}
