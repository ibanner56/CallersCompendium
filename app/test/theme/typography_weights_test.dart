import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_typography.dart';

/// Atkinson Hyperlegible is bundled at 400 and 700 only
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

  test('screen titles use the display face', () {
    expect(AppTypography.screenTitle.fontFamily, AppTypography.displayFamily);
  });

  test('no source file asks for a weight that is not bundled', () {
    // Only 400 and 700 exist, so `w500` and `w600` are drawn as one of them,
    // not as written. Ask for the weight that is drawn.
    final unbundled = RegExp(r'FontWeight\.w[1235689]00\b');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      // The display face is the one family that ships more than two weights.
      if (path == 'lib/src/theme/app_typography.dart') continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (unbundled.hasMatch(lines[i].split('//').first)) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Use FontWeight.w400 or w700.');
  });
}
