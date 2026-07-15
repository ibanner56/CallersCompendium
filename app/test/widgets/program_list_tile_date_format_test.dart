import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program(DateTime eventDate) => Program(
  id: 'p1',
  title: 'Spring Fling',
  eventDate: eventDate,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpTile(WidgetTester tester, DateFormatPref pref) async {
  final notifier = ValueNotifier<DateFormatPref>(pref);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: DateFormatScope(
        notifier: notifier,
        child: Scaffold(
          body: ProgramListTile(program: _program(DateTime.utc(2026, 7, 15))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('program list tile renders the event date in the ymd format when '
      'the scope selects it', (tester) async {
    await _pumpTile(tester, DateFormatPref.ymd);
    expect(find.textContaining('2026-07-15'), findsOneWidget);
  });

  testWidgets('the same tile renders differently under the system default', (
    tester,
  ) async {
    await _pumpTile(tester, DateFormatPref.system);
    // The system/medium format is not the fixed ymd pattern.
    expect(find.textContaining('2026-07-15'), findsNothing);
  });
}
