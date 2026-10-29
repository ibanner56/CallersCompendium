import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/program_list_tile.dart';
import '../support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program(List<ProgramSlot> slots) => Program(
  id: 'p1',
  title: 'Spring Fling',
  status: ProgramStatus.draft,
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpTile(WidgetTester tester, Program program) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(body: ProgramListTile(program: program)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('slot count excludes alternates and the break but keeps stubs', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      _program([
        ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's1', position: 1, danceId: 'd2', isAlt: true),
        ProgramSlot(id: 's2', position: 2, text: 'bouncy'),
        ProgramSlot(id: 's3', position: 3, text: 'Break'),
        ProgramSlot(id: 's4', position: 4, danceId: 'd3'),
        ProgramSlot(id: 's5', position: 5, text: 'alt stub', isAlt: true),
      ]),
    );

    // Six rows, but only three planned dances.
    expect(find.text('3 slots'), findsOneWidget);
  });

  testWidgets('a single planned dance reads "1 slot"', (tester) async {
    await _pumpTile(
      tester,
      _program([
        ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's1', position: 1, danceId: 'd2', isAlt: true),
        ProgramSlot(id: 's2', position: 2, text: 'Break'),
      ]),
    );

    expect(find.text('1 slot'), findsOneWidget);
  });
}
