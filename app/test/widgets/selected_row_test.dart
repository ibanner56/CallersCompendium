import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/models/dance_list_entry.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/selected_row.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';

import '../support/l10n_harness.dart';

/// Issue #2156: the split-pane row open in the detail pane must be visibly
/// marked. `ListTile.selected` alone paints no background in this theme, and
/// the dance row's own title style hid the selected colour, so the selected
/// dance looked like every other row. These read what the tile actually hands
/// to its `Ink` and what colour its title text renders in, not the widget's
/// parameters.

final _now = DateTime.utc(2026, 1, 1);

DanceListEntry _dance(String id) => DanceListEntry(
  dance: Dance(
    id: id,
    title: 'Dance $id',
    form: DanceForm.contra,
    formation: const Formation(FormationShape.dupleImproper),
    createdAt: _now,
    updatedAt: _now,
  ),
  authorNames: const ['Someone'],
  tagNames: const [],
  listCustomFields: const [],
  callCounts: const DanceCallCounts(all: 0, performed: 0),
);

Program _program(String id) => Program(
  id: id,
  title: 'Program $id',
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

OnlineSearchResultRow _online(String id) => OnlineSearchResultRow(
  source: OnlineSource.callersBox,
  id: id,
  name: 'Online $id',
  author: 'Someone',
  formation: 'Becket',
);

Future<void> _pump(WidgetTester tester, ThemeData theme, List<Widget> rows) =>
    tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(body: ListView(children: rows)),
      ),
    );

/// The left side of the border the row's [ListTile] paints, or null when it
/// paints none.
BorderSide? _bar(WidgetTester tester, Finder row) {
  final ink = tester.widget<Ink>(
    find.descendant(of: row, matching: find.byType(Ink)).first,
  );
  final shape = (ink.decoration! as ShapeDecoration).shape;
  if (shape is! Border) return null;
  return shape.left == BorderSide.none ? null : shape.left;
}

Color? _textColor(WidgetTester tester, Finder row, String text) {
  final rich = tester.widget<RichText>(
    find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == text,
      ),
    ),
  );
  return rich.text.style?.color;
}

void main() {
  final themes = {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'highContrast': AppTheme.highContrast,
  };

  themes.forEach((name, theme) {
    final scheme = theme.colorScheme;
    final expectedBar = BorderSide(
      color: scheme.primary,
      width: selectedRowBarWidth,
    );

    group('selected split-pane row ($name)', () {
      testWidgets('a dance row: primary bar and primary title, the others '
          'neither', (tester) async {
        await _pump(tester, theme, [
          DanceListTile(
            key: const ValueKey('a'),
            entry: _dance('a'),
            onTap: () {},
          ),
          DanceListTile(
            key: const ValueKey('b'),
            entry: _dance('b'),
            onTap: () {},
            selected: true,
          ),
        ]);
        final unselected = find.byKey(const ValueKey('a'));
        final selected = find.byKey(const ValueKey('b'));

        expect(_bar(tester, selected), expectedBar);
        expect(_bar(tester, unselected), isNull);
        expect(_textColor(tester, selected, 'Dance b'), scheme.primary);
        expect(
          _textColor(tester, unselected, 'Dance a'),
          isNot(scheme.primary),
        );
      });

      testWidgets('a checked row in batch selection mode has the bar as well '
          'as its checkbox', (tester) async {
        await _pump(tester, theme, [
          DanceListTile(
            key: const ValueKey('a'),
            entry: _dance('a'),
            onTap: () {},
            selectionMode: true,
          ),
          DanceListTile(
            key: const ValueKey('b'),
            entry: _dance('b'),
            onTap: () {},
            selectionMode: true,
            selected: true,
            selectedForBatch: true,
          ),
        ]);
        expect(_bar(tester, find.byKey(const ValueKey('b'))), expectedBar);
        expect(_bar(tester, find.byKey(const ValueKey('a'))), isNull);
      });

      testWidgets('a program row', (tester) async {
        await _pump(tester, theme, [
          ProgramListTile(key: const ValueKey('a'), program: _program('a')),
          ProgramListTile(
            key: const ValueKey('b'),
            program: _program('b'),
            selected: true,
          ),
        ]);
        expect(_bar(tester, find.byKey(const ValueKey('b'))), expectedBar);
        expect(_bar(tester, find.byKey(const ValueKey('a'))), isNull);
      });

      testWidgets('an online result row', (tester) async {
        await _pump(tester, theme, [
          OnlineResultTile(key: const ValueKey('a'), result: _online('a')),
          OnlineResultTile(
            key: const ValueKey('b'),
            result: _online('b'),
            selected: true,
          ),
        ]);
        expect(_bar(tester, find.byKey(const ValueKey('b'))), expectedBar);
        expect(_bar(tester, find.byKey(const ValueKey('a'))), isNull);
      });
    });
  });

  test('an unselected row keeps the theme shape', () {
    expect(selectedRowShape(AppTheme.light.colorScheme, selected: false), null);
  });
}
