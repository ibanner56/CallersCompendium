import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/app_theme_extension.dart';
import 'package:compendium_app/src/theme/palette_schemes.dart';

/// WCAG 2.x relative-luminance contrast ratio (mirrors the derivation helper
/// and `high_contrast_theme_test.dart`).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The gallery palettes under test, keyed by their selection name.
final Map<String, ColorScheme> _galleryPalettes = {
  'solarizedLight': GalleryPalettes.solarizedLight,
  'atomOneLight': GalleryPalettes.atomOneLight,
  'noctisLux': GalleryPalettes.noctisLux,
  'solarizedDark': GalleryPalettes.solarizedDark,
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
  'materialLight': GalleryPalettes.materialLight,
  'zenburn': GalleryPalettes.zenburn,
  'shadesOfPurple': GalleryPalettes.shadesOfPurple,
  'palenight': GalleryPalettes.palenight,
  'synthwave84': GalleryPalettes.synthwave84,
  'noctisAzureus': GalleryPalettes.noctisAzureus,
  'noctisBordo': GalleryPalettes.noctisBordo,
  'noctisHibernus': GalleryPalettes.noctisHibernus,
  'noctisLilac': GalleryPalettes.noctisLilac,
  'noctisMinimus': GalleryPalettes.noctisMinimus,
  'noctisObscuro': GalleryPalettes.noctisObscuro,
  'noctisSereno': GalleryPalettes.noctisSereno,
  'noctisUva': GalleryPalettes.noctisUva,
  'noctisViola': GalleryPalettes.noctisViola,
};

void main() {
  const double aaText = 4.5; // body text & icons
  const double aaNonText = 3.0; // large text & non-text UI

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
