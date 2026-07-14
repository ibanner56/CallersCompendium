import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_theme.dart';

/// UX-2 (`ux-modernization.md` §5, §7): the app-level component sub-themes are
/// present and satisfy the interactive-target and shape acceptance criteria.
void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'highContrast': AppTheme.highContrast,
  };

  themes.forEach((name, theme) {
    group('Component themes are wired ($name)', () {
      test('every component sub-theme is set (no bare defaults)', () {
        expect(theme.cardTheme.shape, isNotNull);
        expect(theme.dialogTheme.shape, isNotNull);
        expect(theme.inputDecorationTheme.border, isNotNull);
        expect(theme.dividerTheme.color, isNotNull);
        expect(theme.filledButtonTheme.style, isNotNull);
        expect(theme.outlinedButtonTheme.style, isNotNull);
        expect(theme.textButtonTheme.style, isNotNull);
        expect(theme.chipTheme.shape, isNotNull);
        expect(theme.listTileTheme.shape, isNotNull);
        expect(theme.navigationRailTheme.indicatorColor, isNotNull);
        expect(theme.navigationBarTheme.indicatorColor, isNotNull);
      });

      test('interactive targets are ≥24px (UX-2 AC)', () {
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
        ]) {
          final min = style.minimumSize!.resolve(<WidgetState>{})!;
          expect(min.height, greaterThanOrEqualTo(24.0));
        }
      });

      test('dialogs use the 28dp dialog radius (§1d)', () {
        final shape = theme.dialogTheme.shape as RoundedRectangleBorder;
        expect(shape.borderRadius, const BorderRadius.all(Radius.circular(28)));
      });

      test('navigation uses a pill (stadium) selected indicator', () {
        expect(theme.navigationBarTheme.indicatorShape, isA<StadiumBorder>());
        expect(theme.navigationRailTheme.useIndicator, isTrue);
        expect(theme.navigationRailTheme.indicatorShape, isA<StadiumBorder>());
      });
    });
  });

  group('Standard (light/dark) treatment specifics', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      test('inputs are filled with rounded borders', () {
        expect(theme.inputDecorationTheme.filled, isTrue);
        final border = theme.inputDecorationTheme.border as OutlineInputBorder;
        expect(
          border.borderRadius,
          const BorderRadius.all(Radius.circular(12)),
        );
      });
    }
  });
}
