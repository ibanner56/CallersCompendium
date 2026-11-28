import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/theme/app_motion.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/app_date_picker.dart';

import '../support/source_scan.dart';

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

    testWidgets('iOS keeps its edge swipe back', (tester) async {
      // The Cupertino back gesture lives in its page transition builder, so
      // an instant transition must still come from that builder.
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          theme: theme.copyWith(platform: TargetPlatform.iOS),
          home: const Scaffold(body: Text('first')),
        ),
      );
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('second')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(400, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsNothing);
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
  test('every dialog and sheet passes AppMotion.styleFor', () {
    final missing = <String>[];
    var seen = 0;
    for (final (path, source) in dartSources('lib')) {
      final found = motionProblems(source);
      seen += found.calls;
      missing.addAll([for (final p in found.problems) '$path:$p']);
    }
    expect(seen, greaterThan(100), reason: 'the scan found too few calls');
    expect(missing, isEmpty);
  });

  test('the motion scan reads each opener in any shape', () {
    expect(
      motionProblems(
        'showDialog<void>(\n'
        '  context: context,\n'
        "  builder: (_) => Text('animationStyle: AppMotion.styleFor('),\n"
        ');\n'
        '// showDialog(context: context)\n',
      ).problems,
      ['1 showDialog without animationStyle'],
    );
    expect(
      motionProblems(
        'showAdaptiveDialog(context: c, builder: b);\n'
        'Navigator.push(c, DialogRoute(context: c, builder: b));\n'
        'ModalBottomSheetRoute(builder: b, isScrollControlled: true);\n',
      ).problems,
      [
        '1 showAdaptiveDialog without animationStyle',
        '2 DialogRoute without animationStyle',
        '3 ModalBottomSheetRoute without sheetAnimationStyle',
      ],
    );
    expect(
      motionProblems(
        'showGeneralDialog(context: c, pageBuilder: p);\n'
        'showCupertinoModalPopup(context: c, builder: b);\n',
      ).problems,
      [
        '1 showGeneralDialog takes no AnimationStyle',
        '2 showCupertinoModalPopup takes no AnimationStyle',
      ],
    );
    final clean = motionProblems(
      'showModalBottomSheet(\n'
      '  context: c,\n'
      '  sheetAnimationStyle: AppMotion.styleFor(context),\n'
      '  builder: b,\n'
      ');\n'
      'showDialog(builder: b, animationStyle: AppMotion.styleFor(context));\n',
    );
    expect(clean.problems, isEmpty);
    expect(clean.calls, 2);
  });

  for (final (reduce, instant) in [(true, true), (false, false)]) {
    testWidgets('showAppDatePicker opens '
        '${instant ? 'at once' : 'animated'} with Reduce motion '
        '${reduce ? 'on' : 'off'}', (tester) async {
      final notifier = ValueNotifier<bool?>(reduce);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        ReduceMotionScope(
          notifier: notifier,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppDatePicker(
                  context: context,
                  initialDate: DateTime(2000, 6, 15),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2001),
                ),
                child: const Text('pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pump();
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(DatePickerDialog)),
      )!;
      expect(route.animation!.isCompleted, instant);
      await tester.pumpAndSettle();
    });
  }

  for (final (reduce, instant) in [(true, true), (false, false)]) {
    testWidgets('showAppTimePicker opens '
        '${instant ? 'at once' : 'animated'} with Reduce motion '
        '${reduce ? 'on' : 'off'}', (tester) async {
      final notifier = ValueNotifier<bool?>(reduce);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        ReduceMotionScope(
          notifier: notifier,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 19, minute: 30),
                ),
                child: const Text('pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pump();
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(TimePickerDialog)),
      )!;
      expect(route.animation!.isCompleted, instant);
      await tester.pumpAndSettle();
    });
  }

  // Flutter's picker helpers open their dialog with no AnimationStyle, so
  // the app opens the date picker through showAppDatePicker instead.
  test('no picker helper that ignores Reduce motion is called', () {
    final call = RegExp(
      r'(?<![\w.])(showDatePicker|showTimePicker|showDateRangePicker)\s*\(',
    );
    final found = <String>[];
    var helperCalls = 0;
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      helperCalls += RegExp(r'showAppDatePicker\(').allMatches(src).length;
      for (final m in call.allMatches(src)) {
        final lineStart = src.lastIndexOf('\n', m.start) + 1;
        if (src.substring(lineStart, m.start).trimLeft().startsWith('//')) {
          continue;
        }
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        found.add('${file.path}:$line ${m.group(1)}');
      }
    }
    // The positive control: the scan reads the files the pickers live in.
    expect(helperCalls, greaterThanOrEqualTo(3));
    expect(found, isEmpty);
  });
}

/// The openers that take a reduce-motion style, by the argument that carries
/// it.
const _styled = {
  'showDialog': 'animationStyle',
  'showAdaptiveDialog': 'animationStyle',
  'DialogRoute': 'animationStyle',
  'showModalBottomSheet': 'sheetAnimationStyle',
  'ModalBottomSheetRoute': 'sheetAnimationStyle',
};

/// Openers with no AnimationStyle at all: a dialog or sheet opened through one
/// animates whatever Reduce motion says, so the app does not call them.
const _unstyled = {
  'showGeneralDialog',
  'RawDialogRoute',
  'showCupertinoDialog',
  'showCupertinoModalPopup',
  'CupertinoDialogRoute',
  'CupertinoModalPopupRoute',
};

final RegExp _opener = RegExp(
  '(?<![\\w.])(${[..._styled.keys, ..._unstyled].join('|')})'
  r'\s*(<[^()]*?>)?\s*\(',
);

/// How many dialog and sheet openers [source] calls, and `line problem` for
/// each that does not pass `AppMotion.styleFor(...)` as its style (comments and
/// strings are not code).
({int calls, List<String> problems}) motionProblems(String source) {
  final code = codeOnly(source);
  final problems = <String>[];
  var calls = 0;
  for (final m in _opener.allMatches(code)) {
    calls++;
    final name = m.group(1)!;
    final line = lineAt(source, m.start);
    final arg = _styled[name];
    if (arg == null) {
      problems.add('$line $name takes no AnimationStyle');
      continue;
    }
    final value = namedArgs(source, m.end - 1, code: code)[arg];
    if (value == null || !value.startsWith('AppMotion.styleFor(')) {
      problems.add('$line $name without $arg');
    }
  }
  return (calls: calls, problems: problems);
}
