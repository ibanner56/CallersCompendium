import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  String title = 'Original',
  List<Figure> figures = const [],
  List<String> authorIds = const [],
  List<DanceLink> links = const [],
  List<CustomFieldValue> customFields = const [],
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  authorIds: authorIds,
  links: links,
  customFields: customFields,
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps a trivial home that pushes the editor, so the editor's Save/pop flow
/// returns to a real route (mirroring how it is reached in the app).
Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? danceId,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-editor'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<String>(
                builder: (_) => DanceEditorScreen(danceId: danceId),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
}

/// Types [typed] into figure [index]'s move field and taps the [optionId]
/// suggestion, mirroring the keyboard-first move picker.
Future<void> _selectMoveInEditor(
  WidgetTester tester,
  int index,
  String typed,
  String optionId,
) async {
  await tester.enterText(
    find.byKey(ValueKey('figure-$index-move-input')),
    typed,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('figure-$index-move-option-$optionId')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new dance: empty title blocks save', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(await repos.dances.listAll(), isEmpty);
  });

  testWidgets('new dance: save creates a dance', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'My New Dance',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dances = await repos.dances.listAll();
    expect(dances, hasLength(1));
    expect(dances.single.title, 'My New Dance');
    // Returned to the launching route.
    expect(find.byKey(const ValueKey('open-editor')), findsOneWidget);
  });

  testWidgets('edit existing: title round-trips', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      isNotNull,
    );
    expect(find.text('Original'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Renamed',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.title, 'Renamed');
    // createdAt preserved from the original.
    expect(saved.createdAt, _now);
  });

  testWidgets('invalid phrase structure blocks save', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'X');
    await tester.enterText(find.byKey(const ValueKey('phrase-field')), 'abc');
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    expect(find.textContaining('phrases*bars*beatsPerBar'), findsOneWidget);
    expect(await repos.dances.listAll(), isEmpty);
  });

  testWidgets('inline choreographer creation', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('author-input')),
      'Gene Hubert',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('author-option-create:Gene Hubert')),
    );
    await tester.pumpAndSettle();

    // Choreographer persisted immediately on creation.
    final choreographers = await repos.choreographers.listAll();
    expect(choreographers.map((c) => c.name), contains('Gene Hubert'));

    // Chip shown, then save and confirm it is attached to the dance.
    expect(find.widgetWithText(Chip, 'Gene Hubert'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'With Author',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.authorIds, hasLength(1));
    expect(dance.authorIds.single, choreographers.single.id);
  });

  testWidgets('surfaces non-blocking phrase warnings', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        figures: [
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 20}),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    expect(find.byKey(const ValueKey('warnings-card')), findsOneWidget);
    expect(find.textContaining('beats'), findsWidgets);
  });

  testWidgets('custom text field value round-trips', (tester) async {
    final repos = openTestRepositories();
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'extra',
        label: 'Extra',
        type: CustomFieldType.text,
      ),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'CF');
    await tester.enterText(
      find.byKey(const ValueKey('custom-f1')),
      'hello world',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.customFields, hasLength(1));
    expect(dance.customFields.single.fieldId, 'f1');
    expect(dance.customFields.single.value, 'hello world');
  });

  testWidgets('untouched boolean custom field is not persisted', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'b1',
        key: 'flag',
        label: 'Flag',
        type: CustomFieldType.boolean,
      ),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'B');
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    // The switch was never toggled: no spurious `false` value is written.
    final dance = (await repos.dances.listAll()).single;
    expect(dance.customFields, isEmpty);
  });

  testWidgets('toggled boolean custom field round-trips', (tester) async {
    final repos = openTestRepositories();
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'b1',
        key: 'flag',
        label: 'Flag',
        type: CustomFieldType.boolean,
      ),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'B');
    await tester.tap(find.byKey(const ValueKey('custom-b1')));
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.customFields, hasLength(1));
    expect(dance.customFields.single.value, true);
  });

  testWidgets('editing preserves relatedDance links', (tester) async {
    final repos = openTestRepositories();
    // FK target for the relatedDance link.
    await repos.dances.create(_dance(id: 'd2', title: 'Target'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Has related',
        links: [
          DanceLink(id: 'l1', kind: LinkKind.relatedDance, targetDanceId: 'd2'),
          DanceLink(
            id: 'l2',
            kind: LinkKind.source,
            url: 'https://example.com',
          ),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Has related (edited)',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    final kinds = saved!.links.map((l) => l.kind).toList();
    // The relatedDance link survives; the URL link is retained too.
    expect(kinds, containsAll([LinkKind.relatedDance, LinkKind.source]));
    final related = saved.links.firstWhere(
      (l) => l.kind == LinkKind.relatedDance,
    );
    expect(related.targetDanceId, 'd2');
  });

  testWidgets('autocomplete options are keyed by id, not display name', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Chris'));
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('author-input')), 'Chris');
    await tester.pumpAndSettle();

    // Existing options are keyed by id so two same-named entities (dedup is
    // deferred) can't produce a duplicate-key crash in the options list.
    expect(find.byKey(const ValueKey('author-option-c1')), findsOneWidget);
  });

  testWidgets('Collection New dance FAB opens the editor', (tester) async {
    final repos = openTestRepositories();
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const DanceListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('new-dance')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-dance')));
    await tester.pumpAndSettle();

    expect(find.text('New dance'), findsWidgets);
    expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
  });

  testWidgets('adding a figure via type-ahead persists on save', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'Swung');
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await _selectMoveInEditor(tester, 0, 'sw', 'swing');

    // Progression + note round-trip alongside the params.
    await tester.tap(find.byKey(const ValueKey('figure-0-progression')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-note')),
      'big swing',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.figures, hasLength(1));
    final figure = dance.figures.single;
    expect(figure.move, 'swing');
    expect(figure.params['who'], 'partners');
    expect(figure.params['beats'], 8);
    expect(figure.progression, isTrue);
    expect(figure.note, 'big swing');
  });

  testWidgets('a custom figure persists on save', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'Custom');
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'scoop them up',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.figures.single.isCustom, isTrue);
    expect(dance.figures.single.params['text'], 'scoop them up');
  });

  testWidgets('editing an existing figure round-trips', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        figures: [
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    // The existing figure loads into an editable row.
    expect(find.byKey(const ValueKey('figure-0-beats')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.figures.single.params['beats'], 16);
  });

  testWidgets('deleting a figure removes it on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        figures: [
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
          Figure(move: 'balance', params: {'who': 'neighbors', 'beats': 4}),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.figures, hasLength(1));
    expect(saved.figures.single.move, 'balance');
  });
}
