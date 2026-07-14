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
    form: DanceForm.ecd,
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

  testWidgets('shows a form-type leading avatar with an icon + text label', (
    tester,
  ) async {
    await _pump(tester, _entry());

    // The avatar carries the form icon...
    final avatar = find.byType(CircleAvatar);
    expect(avatar, findsOneWidget);
    expect(
      find.descendant(of: avatar, matching: find.byIcon(Icons.groups_outlined)),
      findsOneWidget,
    );
    // ...and the meaning is not glyph-only: the form label is the tooltip.
    expect(
      find.ancestor(of: avatar, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: avatar, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, 'English (ECD)');
  });

  testWidgets('title uses the themed titleMedium style', (tester) async {
    await _pump(tester, _entry());
    final title = tester.widget<Text>(find.text('Test Dance'));
    final expected = Theme.of(
      tester.element(find.text('Test Dance')),
    ).textTheme.titleMedium;
    expect(title.style, expected);
  });
}
