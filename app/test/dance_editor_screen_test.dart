import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  authorIds: authorIds,
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
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
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

  testWidgets('Collection New dance FAB opens the editor', (tester) async {
    final repos = openTestRepositories();
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            RepositoriesScope(repositories: repos, child: child!),
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
}
