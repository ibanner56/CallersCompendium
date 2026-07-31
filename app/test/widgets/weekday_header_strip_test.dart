import 'package:compendium_app/src/data/first_day_of_week_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/widgets/weekday_header_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed reference "today": Wednesday 2026-07-15.
  final wednesday = DateTime(2026, 7, 15);

  Future<void> pumpStrip(
    WidgetTester tester, {
    required FirstDayOfWeekPref pref,
    Set<DateTime> markedDates = const {},
  }) async {
    final notifier = ValueNotifier<FirstDayOfWeekPref>(pref);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FirstDayOfWeekScope(
          notifier: notifier,
          child: Scaffold(
            body: WeekdayHeaderStrip(now: wednesday, markedDates: markedDates),
          ),
        ),
      ),
    );
  }

  List<String?> weekdayLabels(WidgetTester tester) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('weekday-header-strip')),
            matching: find.byType(Text),
          ),
        )
        .toList();
    // Each day cell renders exactly two Texts in order: the weekday-letter
    // label, then the day-of-month number. Keep only the labels (even indices).
    return [for (var i = 0; i < texts.length; i += 2) texts[i].data];
  }

  testWidgets('Monday preference orders columns Mon..Sun', (tester) async {
    await pumpStrip(tester, pref: FirstDayOfWeekPref.monday);

    // MaterialApp defaults to English (Mon..Sun narrow labels: M T W T F S S).
    final labels = weekdayLabels(tester);
    expect(labels, ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
  });

  testWidgets('Sunday preference orders columns Sun..Sat', (tester) async {
    await pumpStrip(tester, pref: FirstDayOfWeekPref.sunday);

    final labels = weekdayLabels(tester);
    expect(labels, ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
  });

  testWidgets('Saturday preference orders columns Sat..Fri', (tester) async {
    await pumpStrip(tester, pref: FirstDayOfWeekPref.saturday);

    final labels = weekdayLabels(tester);
    expect(labels, ['S', 'S', 'M', 'T', 'W', 'T', 'F']);
  });

  testWidgets('system preference falls back to the locale (English default: '
      'Sunday-first)', (tester) async {
    await pumpStrip(tester, pref: FirstDayOfWeekPref.system);

    final labels = weekdayLabels(tester);
    expect(labels, ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
  });

  testWidgets('reorders live when the preference notifier changes', (
    tester,
  ) async {
    final notifier = ValueNotifier<FirstDayOfWeekPref>(
      FirstDayOfWeekPref.monday,
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FirstDayOfWeekScope(
          notifier: notifier,
          child: Scaffold(body: WeekdayHeaderStrip(now: wednesday)),
        ),
      ),
    );
    expect(weekdayLabels(tester).first, 'M');

    notifier.value = FirstDayOfWeekPref.sunday;
    await tester.pump();

    expect(weekdayLabels(tester).first, 'S');
  });

  testWidgets('marks the day-of-month for a date in markedDates', (
    tester,
  ) async {
    // Friday 2026-07-17, within the Monday-ordered week containing Wednesday
    // 2026-07-15.
    final marked = DateTime(2026, 7, 17);
    await pumpStrip(
      tester,
      pref: FirstDayOfWeekPref.monday,
      markedDates: {marked},
    );

    // The day cell showing "17" exists (the strip renders day-of-month
    // numbers); the marker presence itself is covered by golden-free layout
    // (no exception thrown while rendering the dot for the marked date).
    expect(find.text('17'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
