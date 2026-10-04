import 'package:compendium_app/src/widgets/settings_dropdown_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/screen_size.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  await setScreenSize(tester, Size(width, 800));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsDropdownRow(
          title: const Text('Label', key: ValueKey('row-title')),
          subtitle: const Text('Subtitle'),
          dropdownBuilder: (expanded) => DropdownButton<int>(
            key: const ValueKey('row-dropdown'),
            isExpanded: expanded,
            value: 1,
            onChanged: (_) {},
            items: const [
              DropdownMenuItem(value: 1, child: Text('One')),
              DropdownMenuItem(value: 2, child: Text('Two')),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with room, the dropdown is the ListTile trailing', (
    tester,
  ) async {
    await _pump(tester, 800);

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.trailing, isNotNull);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('row-dropdown')),
          )
          .isExpanded,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('without room, the expanded dropdown sits below the label', (
    tester,
  ) async {
    await _pump(tester, 320);

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.trailing, isNull);
    final dropdown = find.byKey(const ValueKey('row-dropdown'));
    expect(tester.widget<DropdownButton<int>>(dropdown).isExpanded, isTrue);
    expect(
      tester.getTopLeft(dropdown).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const ValueKey('row-title'))).dy,
      ),
    );
    expect(find.text('Subtitle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide surface still wraps once the text scale is large', (
    tester,
  ) async {
    await setScreenSize(tester, const Size(700, 800));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsDropdownRow(
            title: const Text('Label'),
            dropdownBuilder: (expanded) => DropdownButton<int>(
              key: const ValueKey('row-dropdown'),
              isExpanded: expanded,
              value: 1,
              onChanged: (_) {},
              items: const [DropdownMenuItem(value: 1, child: Text('One'))],
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('row-dropdown')),
          )
          .isExpanded,
      isTrue,
    );
  });
}
