import 'dart:ui' show PlatformDispatcher;

import 'package:intl/intl.dart' show DateFormat;
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';

import '../support/l10n_harness.dart';

/// The System date format (PLAT-12): the device locale's numeric date.
String _systemDate(DateTime d) =>
    DateFormat.yMd(PlatformDispatcher.instance.locale.toString()).format(d);

final _now = DateTime.utc(2026, 1, 1);
final _eventDate = DateTime.utc(2026, 7, 15);

Program _program(DateTime eventDate) => Program(
  id: 'p1',
  title: 'Spring Fling',
  eventDate: eventDate,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpTile(WidgetTester tester, DateFormatSetting setting) async {
  final notifier = ValueNotifier<DateFormatSetting>(setting);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

      home: DateFormatScope(
        notifier: notifier,
        child: Scaffold(body: ProgramListTile(program: _program(_eventDate))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('program list tile renders the event date in the ymd format when '
      'the scope selects it', (tester) async {
    await _pumpTile(tester, DateFormatSetting(DateFormatPref.ymd));
    expect(find.textContaining('2026-07-15'), findsOneWidget);
    expect(find.textContaining('July'), findsNothing);
  });

  testWidgets('the tile renders a valid custom pattern from the scope', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      DateFormatSetting(DateFormatPref.custom, customPattern: 'MM.DD.YY'),
    );
    expect(find.textContaining('07.15.26'), findsOneWidget);
  });

  testWidgets('an invalid custom pattern falls back to the device-region '
      'date', (tester) async {
    await _pumpTile(
      tester,
      DateFormatSetting(DateFormatPref.custom, customPattern: 'bogus'),
    );
    final expected = _systemDate(_eventDate);
    expect(find.textContaining(expected), findsOneWidget);
    expect(find.textContaining('bogus'), findsNothing);
  });

  testWidgets('the same tile renders the device-region date under system', (
    tester,
  ) async {
    await _pumpTile(tester, DateFormatSetting(DateFormatPref.system));
    final expected = _systemDate(_eventDate);
    expect(find.textContaining(expected), findsOneWidget);
    // The fixed ymd pattern must NOT appear under the system default, and the
    // short date must genuinely differ from it for this locale.
    expect(find.textContaining('2026-07-15'), findsNothing);
    expect(expected, isNot('2026-07-15'));
  });
}
