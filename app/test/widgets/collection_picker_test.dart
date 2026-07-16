import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

import '../support/test_repositories.dart';

Dance _dance({
  required String id,
  required String title,
  List<Figure> figures = const [],
}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: figures,
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// The standard four-phrase skeleton (A1/A2/B1/B2), each a 16-beat move, so
/// section-aware figure queries resolve to the expected phrase.
List<Figure> _phrases({
  required String a1,
  required String a2,
  required String b1,
  required String b2,
}) => [
  Figure(move: a1, params: const {'beats': 16}),
  Figure(move: a2, params: const {'beats': 16}),
  Figure(move: b1, params: const {'beats': 16}),
  Figure(move: b2, params: const {'beats': 16}),
];

Future<void> _pumpPicker(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required void Function(String danceId) onAddDance,
}) async {
  // A tall surface so the search bar, filter/by-phrase/advanced panels and the
  // results list all lay out without scrolling, keeping control taps stable.
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final data = await CollectionData.load(repos);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RepositoriesScope(
          repositories: repos,
          child: CollectionPicker(
            data: data,
            dialect: Dialect.larksRobins,
            onAddDance: onAddDance,
          ),
        ),
      ),
    ),
  );
}

List<String> _titles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(find.byType(DanceListTile))
    .map((t) => t.entry.title)
    .toList();

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Types [text] into the keyed By-Phrase move input and picks [option] from the
/// type-ahead overlay.
Future<void> _addPhraseMove(
  WidgetTester tester,
  String inputKey,
  String text,
  String option,
) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(inputKey)),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('by phrase: figure-in-A1 query filters the picker results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // petronella in A1.
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'A1 Petronella',
        figures: _phrases(
          a1: 'petronella',
          a2: 'swing',
          b1: 'balance',
          b2: 'long_lines',
        ),
      ),
    );
    // petronella in B1, not A1 → filtered out.
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'B1 Petronella',
        figures: _phrases(
          a1: 'swing',
          a2: 'swing',
          b1: 'petronella',
          b2: 'long_lines',
        ),
      ),
    );

    await _pumpPicker(tester, repos, onAddDance: (_) {});
    await tester.pumpAndSettle();

    // Both dances show before any query is applied.
    expect(_titles(tester), containsAll(['A1 Petronella', 'B1 Petronella']));

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-by-phrase-panel')),
    );
    await _addPhraseMove(tester, 'match-A1-input-0', 'petro', 'petronella');

    expect(_titles(tester), ['A1 Petronella']);
  });

  testWidgets('by phrase: add-in-one-tap still works on a filtered result', (
    tester,
  ) async {
    final added = <String>[];
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'A1 Petronella',
        figures: _phrases(
          a1: 'petronella',
          a2: 'swing',
          b1: 'balance',
          b2: 'long_lines',
        ),
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'B1 Petronella',
        figures: _phrases(
          a1: 'swing',
          a2: 'swing',
          b1: 'petronella',
          b2: 'long_lines',
        ),
      ),
    );

    await _pumpPicker(tester, repos, onAddDance: added.add);
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-by-phrase-panel')),
    );
    await _addPhraseMove(tester, 'match-A1-input-0', 'petro', 'petronella');

    // Only the A1 match survives; its one-tap add affordance still fires.
    expect(_titles(tester), ['A1 Petronella']);
    await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));
    expect(added, ['a']);
  });

  testWidgets('advanced builder: add a figure row filters the picker results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'Has Petronella',
        figures: [
          Figure(move: 'petronella', params: const {'beats': 16}),
        ],
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'Just Swing',
        figures: [
          Figure(move: 'swing', params: const {'beats': 16}),
        ],
      ),
    );

    await _pumpPicker(tester, repos, onAddDance: (_) {});
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-enable')),
    );
    await _tapVisible(tester, find.text('Add'));
    await _tapVisible(tester, find.text('Has figure'));

    final moveField = find.byType(TextField).last;
    await tester.ensureVisible(moveField);
    await tester.enterText(moveField, 'petro');
    await tester.pumpAndSettle();
    await tester.tap(find.text('petronella').last);
    await tester.pumpAndSettle();

    // The advanced tree compiles through buildCollectionFilter and re-runs the
    // search, so only the dance with the figure survives.
    expect(_titles(tester), ['Has Petronella']);
  });
}
