import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/program_list_tile.dart';
import '../support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({String? venue, String? venueId}) => Program(
  id: 'p1',
  title: 'Spring Fling',
  venue: venue,
  venueId: venueId,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpTile(
  WidgetTester tester,
  Program program,
  Map<String, Venue> venuesById,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: ProgramListTile(program: program, venuesById: venuesById),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the linked venue name when venueId resolves', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      _program(venue: 'Old free text', venueId: 'grange-hall'),
      {'grange-hall': Venue(id: 'grange-hall', name: 'Grange Hall')},
    );

    expect(find.textContaining('Grange Hall'), findsOneWidget);
    expect(find.textContaining('Old free text'), findsNothing);
  });

  testWidgets('falls back to free text when the venue link does not resolve', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      _program(venue: 'The Barn', venueId: 'missing'),
      const {},
    );

    expect(find.textContaining('The Barn'), findsOneWidget);
  });

  testWidgets('shows free text when there is no link', (tester) async {
    await _pumpTile(tester, _program(venue: 'The Grange'), const {});
    expect(find.textContaining('The Grange'), findsOneWidget);
  });
}
