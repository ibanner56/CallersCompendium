import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/theme/app_motion.dart';
import 'package:compendium_app/src/theme/app_theme.dart';

/// Reduce motion reaches page transitions, expansion tiles,
/// dialogs and bottom sheets.
void main() {
  group('AppTheme.withoutMotion', () {
    final theme = AppTheme.withoutMotion(AppTheme.light);

    test('every platform\'s page transition is instant', () {
      for (final platform in TargetPlatform.values) {
        final builder = theme.pageTransitionsTheme.builders[platform];
        expect(builder, isNotNull, reason: '$platform keeps its transition');
        expect(builder!.transitionDuration, Duration.zero);
        expect(builder.reverseTransitionDuration, Duration.zero);
      }
    });

    test('expansion tiles open without animating', () {
      expect(
        theme.expansionTileTheme.expansionAnimationStyle,
        AnimationStyle.noAnimation,
      );
      // The rest of the expansion-tile theme survives.
      expect(
        theme.expansionTileTheme.shape,
        AppTheme.light.expansionTileTheme.shape,
      );
    });
  });

  group('AppMotion.styleFor', () {
    Future<AnimationStyle?> styleUnder(
      WidgetTester tester, {
      required bool? override,
      required bool os,
    }) async {
      late AnimationStyle? style;
      final notifier = ValueNotifier<bool?>(override);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: os),
          child: ReduceMotionScope(
            notifier: notifier,
            child: Builder(
              builder: (context) {
                style = AppMotion.styleFor(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return style;
    }

    testWidgets('in-app "on" turns animation off', (tester) async {
      expect(
        await styleUnder(tester, override: true, os: false),
        AnimationStyle.noAnimation,
      );
    });

    testWidgets('in-app "off" beats the OS', (tester) async {
      expect(await styleUnder(tester, override: false, os: true), isNull);
    });

    testWidgets('unset follows the OS', (tester) async {
      expect(
        await styleUnder(tester, override: null, os: true),
        AnimationStyle.noAnimation,
      );
      expect(await styleUnder(tester, override: null, os: false), isNull);
    });
  });

  // There is no theme hook for a dialog's or sheet's animation, so the guard
  // is on the call sites: every one under lib/ passes the style.
  test('every showDialog / showModalBottomSheet passes AppMotion.styleFor', () {
    const required = {
      'showDialog': 'animationStyle',
      'showModalBottomSheet': 'sheetAnimationStyle',
    };
    final call = RegExp(
      r'(?<![\w.])(showDialog|showModalBottomSheet)\s*(<[^()]*?>)?\s*\(',
    );
    final missing = <String>[];
    var seen = 0;
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      for (final m in call.allMatches(src)) {
        final lineStart = src.lastIndexOf('\n', m.start) + 1;
        if (src.substring(lineStart, m.start).trimLeft().startsWith('//')) {
          continue;
        }
        seen++;
        final args = _topLevelArgs(src, m.end - 1);
        final name = required[m.group(1)]!;
        final value = args[name];
        if (value == null || !value.startsWith('AppMotion.styleFor(')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          missing.add('${file.path}:$line ${m.group(1)} without $name');
        }
      }
    }
    expect(seen, greaterThan(100), reason: 'the scan found too few calls');
    expect(missing, isEmpty);
  });
}

/// The named arguments of the call whose `(` is at [open], at the call's own
/// nesting depth only, mapped to their source text. Walks delimiters (and
/// skips string literals), so a multi-line or nested argument is read whole.
Map<String, String> _topLevelArgs(String src, int open) {
  final args = <String, String>{};
  var depth = 0;
  var argStart = open + 1;
  String? quote;
  void finish(int end) {
    final arg = src.substring(argStart, end).trim();
    final named = RegExp(r'^(\w+)\s*:\s*([\s\S]*)$').firstMatch(arg);
    if (named != null) args[named.group(1)!] = named.group(2)!.trim();
  }

  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      i = src.indexOf('\n', i);
    } else if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      depth--;
      if (depth == 0) {
        finish(i);
        return args;
      }
    } else if (c == ',' && depth == 1) {
      finish(i);
      argStart = i + 1;
    }
  }
  return args;
}
