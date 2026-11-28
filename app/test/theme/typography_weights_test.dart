import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_typography.dart';

import '../support/source_scan.dart';

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
    final offenders = <String>[];
    for (final (path, source) in dartSources('lib')) {
      // The display face is the one family that ships more than two weights.
      if (path == 'lib/src/theme/app_typography.dart') continue;
      for (final line in unbundledWeightLines(source)) {
        offenders.add('$path:$line');
      }
    }
    expect(offenders, isEmpty, reason: 'Use FontWeight.w400 or w700.');
  });

  test('the weight scan sees each way of asking for a weight', () {
    expect(unbundledWeightLines('s: TextStyle(fontWeight: FontWeight.w500)'), [
      1,
    ]);
    // By index into the list of weights: 4 is w500; 3 and 6 are the bundled
    // w400 and w700; an index that is not a literal cannot be checked.
    expect(unbundledWeightLines('x\nfontWeight: FontWeight.values[4],'), [2]);
    expect(unbundledWeightLines('a: FontWeight.values[ 3 ],'), isEmpty);
    expect(unbundledWeightLines('a: FontWeight.values[6],'), isEmpty);
    expect(unbundledWeightLines('a: FontWeight.values[i],'), [1]);
    // A variable-font axis, by tag or by the named constructor.
    expect(unbundledWeightLines("v: [FontVariation(\n  'wght',\n  500,\n)]"), [
      1,
    ]);
    expect(unbundledWeightLines('[FontVariation.weight(600)]'), [1]);
    // Bundled weights, other axes, comments and strings are not offenders.
    expect(
      unbundledWeightLines(
        'a: FontWeight.w700,\n'
        "b: FontVariation('wght', 400),\n"
        "c: FontVariation('wdth', 500),\n"
        'd: FontVariation.weight(700),\n'
        '// FontWeight.w500\n'
        "e: Text('FontWeight.values[4]'),\n",
      ),
      isEmpty,
    );
  });
}

final RegExp _unbundled = RegExp(r'(?<![\w.])FontWeight\s*\.\s*w[1235689]00\b');
final RegExp _byIndex = RegExp(
  r'(?<![\w.])FontWeight\s*\.\s*values\s*\[([^\]]*)\]',
);

/// `FontWeight.values` indices of the bundled weights: 3 is w400, 6 is w700.
const _bundledIndices = {'3', '6'};
final RegExp _variation = RegExp(
  r'(?<![\w.])FontVariation\s*(?:\.\s*(\w+)\s*)?\(',
);
final RegExp _weightTag = RegExp('^r?([\'"])wght\\1\$');
final RegExp _bundledValue = RegExp(r'^(?:400|700)(?:\.0+)?$');

/// The 1-based lines of [source] that ask for a font weight other than 400 or
/// 700: by name (`FontWeight.w500`), by index (`FontWeight.values[4]`; an
/// index that is not a literal 3 or 6, such as a variable, counts, since the
/// weight it picks cannot be read from the source), or on
/// a variable font's weight axis (`FontVariation('wght', 500)`,
/// `FontVariation.weight(500)`). Comments and strings are not code.
List<int> unbundledWeightLines(String source) {
  final code = codeOnly(source);
  final lines = <int>{
    for (final m in _unbundled.allMatches(code)) lineAt(source, m.start),
    for (final m in _byIndex.allMatches(code))
      if (!_bundledIndices.contains(m.group(1)!.trim()))
        lineAt(source, m.start),
  };
  for (final m in _variation.allMatches(code)) {
    final args = [
      for (final a in callArgs(source, m.end - 1, code: code))
        if (a.name == null) a.text,
    ];
    final String? value;
    if (m.group(1) == 'weight') {
      value = args.firstOrNull;
    } else if (m.group(1) == null &&
        args.length == 2 &&
        _weightTag.hasMatch(args[0])) {
      value = args[1];
    } else {
      value = null;
    }
    if (value != null && !_bundledValue.hasMatch(value)) {
      lines.add(lineAt(source, m.start));
    }
  }
  return lines.toList()..sort();
}
