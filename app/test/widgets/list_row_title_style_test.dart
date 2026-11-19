import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/models/dance_list_entry.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';

import '../support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

void main() {
  testWidgets('dance and program rows title themselves in the same style', (
    tester,
  ) async {
    final dance = DanceListEntry(
      dance: Dance(
        id: 'd1',
        title: 'Dance Title',
        form: DanceForm.ecd,
        formation: const Formation(FormationShape.dupleImproper),
        createdAt: _now,
        updatedAt: _now,
      ),
      authorNames: const [],
      tagNames: const [],
      listCustomFields: const [],
      callCounts: const DanceCallCounts(all: 0, performed: 0),
    );
    final program = Program(
      id: 'p1',
      title: 'Program Title',
      status: ProgramStatus.draft,
      slots: const [],
      createdAt: _now,
      updatedAt: _now,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              DanceListTile(entry: dance, onTap: () {}),
              ProgramListTile(program: program),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    TextStyle titleStyle(String title) {
      final text = tester.widget<Text>(find.text(title));
      // The ListTile's title style is the one the Text inherits.
      final base = DefaultTextStyle.of(tester.element(find.text(title))).style;
      return base.merge(text.style);
    }

    final theme = Theme.of(tester.element(find.text('Dance Title')));
    final expected = theme.textTheme.titleMedium!;
    for (final title in ['Dance Title', 'Program Title']) {
      final style = titleStyle(title);
      expect(style.fontSize, expected.fontSize, reason: title);
      expect(style.fontWeight, expected.fontWeight, reason: title);
      expect(style.fontFamily, expected.fontFamily, reason: title);
    }
  });
}
