import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/models/dance_list_entry.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

final _now = DateTime.utc(2026, 1, 1);

DanceListEntry _entry({int? rating}) => DanceListEntry(
  dance: Dance(
    id: 'd1',
    title: 'Test Dance',
    rating: rating,
    createdAt: _now,
    updatedAt: _now,
  ),
  authorNames: const [],
  tagNames: const [],
  listCustomFields: const [],
);

Future<void> _pump(WidgetTester tester, DanceListEntry entry) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DanceListTile(entry: entry, onTap: () {}),
      ),
    ),
  );
}

void main() {
  testWidgets('rating indicator shows the value with a semantic label', (
    tester,
  ) async {
    await _pump(tester, _entry(rating: 4));

    final indicator = find.byKey(const ValueKey('rating-indicator'));
    expect(indicator, findsOneWidget);
    expect(
      find.descendant(of: indicator, matching: find.text('4')),
      findsOneWidget,
    );

    final label = tester.widget<Text>(
      find.descendant(of: indicator, matching: find.byType(Text)),
    );
    expect(label.semanticsLabel, 'Rating: 4 of 5 stars');
  });

  testWidgets('no rating indicator is shown for an unrated dance', (
    tester,
  ) async {
    await _pump(tester, _entry());
    expect(find.byKey(const ValueKey('rating-indicator')), findsNothing);
  });
}
