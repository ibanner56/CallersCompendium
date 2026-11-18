import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_typography.dart';

/// Audit B-05: Atkinson Hyperlegible is bundled at 400 and 700 only
/// (`app/pubspec.yaml`), so every Atkinson style must ask for one of those.
/// A weight with no file behind it is drawn by the engine's fallback, not as
/// written.
void main() {
  final bundled = {FontWeight.w400, FontWeight.w700};

  final styles = <String, TextStyle?>{
    'displayLarge': AppTypography.textTheme.displayLarge,
    'displayMedium': AppTypography.textTheme.displayMedium,
    'displaySmall': AppTypography.textTheme.displaySmall,
    'headlineLarge': AppTypography.textTheme.headlineLarge,
    'headlineMedium': AppTypography.textTheme.headlineMedium,
    'headlineSmall': AppTypography.textTheme.headlineSmall,
    'titleLarge': AppTypography.textTheme.titleLarge,
    'titleMedium': AppTypography.textTheme.titleMedium,
    'titleSmall': AppTypography.textTheme.titleSmall,
    'bodyLarge': AppTypography.textTheme.bodyLarge,
    'bodyMedium': AppTypography.textTheme.bodyMedium,
    'bodySmall': AppTypography.textTheme.bodySmall,
    'labelLarge': AppTypography.textTheme.labelLarge,
    'labelMedium': AppTypography.textTheme.labelMedium,
    'labelSmall': AppTypography.textTheme.labelSmall,
    'performSectionHeader': AppTypography.performSectionHeader,
    'performBody': AppTypography.performBody,
    'screenTitle': AppTypography.screenTitle,
  };

  test('every Atkinson style asks for a bundled weight', () {
    final atkinson = styles.entries.where(
      (e) => e.value?.fontFamily == AppTypography.bodyFamily,
    );
    expect(atkinson, isNotEmpty);
    for (final MapEntry(:key, :value) in atkinson) {
      expect(
        bundled,
        contains(value!.fontWeight ?? FontWeight.w400),
        reason: '$key asks for ${value.fontWeight}, which is not bundled',
      );
    }
  });

  test('screen titles use the display face (B-04)', () {
    expect(AppTypography.screenTitle.fontFamily, AppTypography.displayFamily);
  });
}
